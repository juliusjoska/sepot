//! Přílohy — opaque šifrované bloby mimo message_queue.
//!
//! Model Signal: klient soubor zašifruje vlastním klíčem (AES-256-GCM),
//! sem nahraje UŽ ŠIFROVANÝ blob a klíč+digest pošle uvnitř E2E zprávy.
//! Relay proto vidí jen náhodné bajty a nikdy neví, ke které zprávě ani
//! komu blob patří:
//!
//!   - upload vyžaduje X-Sepot-Auth (anti-abuse), ale vazba zařízení→blob
//!     se NIKAM neukládá ani neloguje
//!   - download je bez auth — blob_id (128 bitů) je bearer capability,
//!     zná ho jen odesílatel a příjemce (dorazil E2E kanálem)
//!   - TTL 30 dní, pak hodinový úklid smaže řádek i soubor
//!
//! Data leží na disku (`SEPOT_ATTACHMENTS_DIR`), v DB jen metadata pro
//! úklid (blob_id, velikost, expirace).

use std::path::{Path as FsPath, PathBuf};
use std::sync::Arc;
use std::time::Duration as StdDuration;

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::Response;
use axum::Json;
use chrono::{Duration, Utc};
use futures_util::StreamExt;
use rand::RngCore;
use serde::Serialize;
use tokio::io::AsyncWriteExt;

use crate::state::AppState;

/// TTL blobu — stejné okno jako offline fronta zpráv.
pub const ATTACHMENT_TTL_DAYS: i64 = 30;

/// Výchozí strop velikosti (šifrovaný blob). Přepis env `SEPOT_MAX_ATTACHMENT_BYTES`.
const DEFAULT_MAX_BYTES: u64 = 25 * 1024 * 1024;

/// Osiřelé `.part` soubory (pád mezi zápisem a přejmenováním) starší než
/// tohle se při úklidu mažou.
const PART_MAX_AGE: StdDuration = StdDuration::from_secs(24 * 3600);

#[derive(Clone)]
pub struct Config {
    pub dir: PathBuf,
    pub max_bytes: u64,
}

impl Config {
    pub fn from_env() -> Self {
        let dir = std::env::var("SEPOT_ATTACHMENTS_DIR")
            .unwrap_or_else(|_| "./attachments".into());
        let max_bytes = std::env::var("SEPOT_MAX_ATTACHMENT_BYTES")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(DEFAULT_MAX_BYTES);
        Self {
            dir: PathBuf::from(dir),
            max_bytes,
        }
    }

    fn blob_path(&self, blob_hex: &str) -> PathBuf {
        self.dir.join(blob_hex)
    }

    fn tmp_dir(&self) -> PathBuf {
        self.dir.join("tmp")
    }
}

type ApiResult<T> = Result<T, (StatusCode, String)>;

fn internal<E: std::fmt::Display>(e: E) -> (StatusCode, String) {
    tracing::warn!("interní chyba (přílohy): {e}");
    (StatusCode::INTERNAL_SERVER_ERROR, "interní chyba".into())
}

/// Neexistence, expirace i špatný formát ID = stejná odpověď (nic neleakovat).
fn not_found() -> (StatusCode, String) {
    (StatusCode::NOT_FOUND, "neznámá příloha".into())
}

// ── POST /v1/attachments ───────────────────────────────────────────────

#[derive(Serialize)]
pub struct UploadOut {
    pub blob_id: String,
    pub expires_at_ms: i64,
    pub max_bytes: u64,
}

/// Streamuje tělo na disk (žádné buffrování celého blobu v RAM), strop
/// velikosti se vynucuje průběžně. Tělo = raw šifrované bajty
/// (application/octet-stream). Auth podpis: `"POST /v1/attachments\n<ts>"`.
pub async fn upload(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    body: Body,
) -> ApiResult<(StatusCode, Json<UploadOut>)> {
    crate::rest::authenticate_device(&state, &headers, "POST /v1/attachments").await?;

    let cfg = &state.attachments;

    // Rychlé odmítnutí podle Content-Length, než tečou data
    if let Some(len) = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
    {
        if len > cfg.max_bytes {
            return Err((
                StatusCode::PAYLOAD_TOO_LARGE,
                "příloha je příliš velká".into(),
            ));
        }
    }

    // ThreadRng je !Send — nesmí přežít přes await, proto vlastní scope.
    let blob_id = {
        let mut rng = rand::rng();
        let mut b = vec![0u8; 16];
        rng.fill_bytes(&mut b);
        b
    };
    let blob_hex = hex::encode(&blob_id);

    tokio::fs::create_dir_all(cfg.tmp_dir())
        .await
        .map_err(internal)?;
    let tmp_path = cfg.tmp_dir().join(format!("{blob_hex}.part"));

    let written = match write_stream(body, &tmp_path, cfg.max_bytes).await {
        Ok(n) => n,
        Err(e) => {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(e);
        }
    };
    if written == 0 {
        let _ = tokio::fs::remove_file(&tmp_path).await;
        return Err((StatusCode::BAD_REQUEST, "prázdné tělo".into()));
    }

    let expires_at = Utc::now() + Duration::days(ATTACHMENT_TTL_DAYS);
    let final_path = cfg.blob_path(&blob_hex);
    tokio::fs::rename(&tmp_path, &final_path)
        .await
        .map_err(internal)?;

    let inserted = sqlx::query(
        "INSERT INTO attachments (blob_id, size_bytes, expires_at) VALUES ($1, $2, $3)",
    )
    .bind(&blob_id)
    .bind(written as i64)
    .bind(expires_at)
    .execute(&state.pool)
    .await;
    if let Err(e) = inserted {
        let _ = tokio::fs::remove_file(&final_path).await;
        return Err(internal(e));
    }

    // Log bez blob_id — jen velikost (kapacitní metrika)
    tracing::debug!(size = written, "příloha uložena");

    Ok((
        StatusCode::CREATED,
        Json(UploadOut {
            blob_id: blob_hex,
            expires_at_ms: expires_at.timestamp_millis(),
            max_bytes: cfg.max_bytes,
        }),
    ))
}

async fn write_stream(body: Body, path: &FsPath, max_bytes: u64) -> ApiResult<u64> {
    let mut file = tokio::fs::File::create(path).await.map_err(internal)?;
    let mut stream = body.into_data_stream();
    let mut written: u64 = 0;
    while let Some(chunk) = stream.next().await {
        let chunk =
            chunk.map_err(|_| (StatusCode::BAD_REQUEST, "tělo se nepodařilo přečíst".into()))?;
        written += chunk.len() as u64;
        if written > max_bytes {
            return Err((
                StatusCode::PAYLOAD_TOO_LARGE,
                "příloha je příliš velká".into(),
            ));
        }
        file.write_all(&chunk).await.map_err(internal)?;
    }
    file.sync_all().await.map_err(internal)?;
    Ok(written)
}

// ── GET /v1/attachments/{blob_id} ──────────────────────────────────────

/// Bez auth (bearer capability), bez logování blob_id. Streamuje z disku.
pub async fn download(
    State(state): State<Arc<AppState>>,
    Path(blob_hex): Path<String>,
) -> Result<Response, (StatusCode, String)> {
    // 16 B hex + jen lowercase hex znaky, jinak jednotné 404
    if blob_hex.len() != 32 || !blob_hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(not_found());
    }
    let blob_id = hex::decode(&blob_hex).map_err(|_| not_found())?;

    let row: Option<(i64,)> = sqlx::query_as(
        "SELECT size_bytes FROM attachments WHERE blob_id = $1 AND expires_at > now()",
    )
    .bind(&blob_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(internal)?;
    let Some((size,)) = row else {
        return Err(not_found());
    };

    let file = tokio::fs::File::open(state.attachments.blob_path(&blob_hex))
        .await
        .map_err(|_| not_found())?;
    let stream = tokio_util::io::ReaderStream::new(file);

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(header::CONTENT_LENGTH, size)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::from_stream(stream))
        .map_err(internal)
}

// ── Úklid ──────────────────────────────────────────────────────────────

/// Hodinový úklid: expirované přílohy (řádek + soubor), expirovaná fronta
/// zpráv (dosud se jen filtrovala při čtení) a osiřelé `.part` soubory.
pub fn spawn_cleanup(state: Arc<AppState>) {
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(StdDuration::from_secs(3600));
        loop {
            tick.tick().await;
            if let Err(e) = sweep(&state).await {
                tracing::warn!("úklid příloh selhal: {e}");
            }
        }
    });
}

pub(crate) async fn sweep(state: &AppState) -> anyhow::Result<()> {
    let expired: Vec<(Vec<u8>,)> =
        sqlx::query_as("DELETE FROM attachments WHERE expires_at < now() RETURNING blob_id")
            .fetch_all(&state.pool)
            .await?;
    let count = expired.len();
    for (blob_id,) in expired {
        let path = state.attachments.blob_path(&hex::encode(blob_id));
        let _ = tokio::fs::remove_file(path).await;
    }
    if count > 0 {
        tracing::info!(count, "expirované přílohy smazány");
    }

    sqlx::query("DELETE FROM message_queue WHERE expires_at < now()")
        .execute(&state.pool)
        .await?;

    // Osiřelé .part (pád uprostřed uploadu) starší než PART_MAX_AGE
    if let Ok(mut entries) = tokio::fs::read_dir(state.attachments.tmp_dir()).await {
        while let Ok(Some(entry)) = entries.next_entry().await {
            let stale = entry
                .metadata()
                .await
                .ok()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.elapsed().ok())
                .is_some_and(|age| age > PART_MAX_AGE);
            if stale {
                let _ = tokio::fs::remove_file(entry.path()).await;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod db_tests {
    //! Integrace nad reálným Postgresem (dev DB) — spouštět
    //! `cargo test -p sepot-relay -- --ignored`. Uklízí po sobě.
    use super::*;

    async fn test_state() -> AppState {
        let url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://sepot:sepot_dev@127.0.0.1/sepot_relay".into());
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(2)
            .connect(&url)
            .await
            .expect("dev DB");
        let certs = crate::certs::CertAuthority::init(&pool).await.unwrap();
        let dir = std::env::temp_dir().join(format!("sepot-att-test-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("tmp")).unwrap();
        AppState::new(
            pool,
            certs,
            Config {
                dir,
                max_bytes: 1024,
            },
        )
    }

    fn rand_blob_id() -> Vec<u8> {
        let mut b = vec![0u8; 16];
        rand::rng().fill_bytes(&mut b);
        b
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn sweep_maze_expirovane_vcetne_souboru() {
        let state = test_state().await;

        // expirovaná příloha se souborem na disku
        let dead = rand_blob_id();
        let dead_path = state.attachments.blob_path(&hex::encode(&dead));
        std::fs::write(&dead_path, b"ciphertext").unwrap();
        sqlx::query(
            "INSERT INTO attachments (blob_id, size_bytes, expires_at)
             VALUES ($1, 10, now() - interval '1 hour')",
        )
        .bind(&dead)
        .execute(&state.pool)
        .await
        .unwrap();

        // živá příloha zůstává
        let live = rand_blob_id();
        let live_path = state.attachments.blob_path(&hex::encode(&live));
        std::fs::write(&live_path, b"ciphertext").unwrap();
        sqlx::query(
            "INSERT INTO attachments (blob_id, size_bytes, expires_at)
             VALUES ($1, 10, now() + interval '1 day')",
        )
        .bind(&live)
        .execute(&state.pool)
        .await
        .unwrap();

        sweep(&state).await.unwrap();

        assert!(!dead_path.exists(), "expirovaný soubor měl zmizet");
        assert!(live_path.exists(), "živý soubor musí zůstat");
        let remaining: i64 =
            sqlx::query_scalar("SELECT count(*) FROM attachments WHERE blob_id = $1")
                .bind(&live)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(remaining, 1);

        // úklid po testu
        sqlx::query("DELETE FROM attachments WHERE blob_id = $1")
            .bind(&live)
            .execute(&state.pool)
            .await
            .unwrap();
        let _ = std::fs::remove_dir_all(&state.attachments.dir);
    }
}
