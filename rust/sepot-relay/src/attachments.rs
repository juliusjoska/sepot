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
//!   - TTL 30 dní, pak hodinový úklid smaže řádek i soubor; plné úložiště
//!     vytlačuje nejstarší bloby dřív (`Limits::att_evict_min_age_hours`)
//!
//! Data leží na disku (`SEPOT_ATTACHMENTS_DIR`), v DB jen metadata pro
//! úklid (blob_id, velikost, expirace).

use std::path::{Path as FsPath, PathBuf};
use std::sync::Arc;
use std::time::Duration as StdDuration;

use axum::body::{Body, Bytes};
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::Response;
use axum::Json;
use chrono::{Duration, Utc};
use futures_util::{Stream, StreamExt};
use rand::RngCore;
use serde::Serialize;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncRead, AsyncWriteExt};
use tokio::sync::mpsc;

use crate::state::AppState;

/// TTL blobu — stejné okno jako offline fronta zpráv.
pub const ATTACHMENT_TTL_DAYS: i64 = 30;

/// Výchozí strop velikosti (šifrovaný blob). Přepis env `SEPOT_MAX_ATTACHMENT_BYTES`.
const DEFAULT_MAX_BYTES: u64 = 25 * 1024 * 1024;

/// Výchozí strop součtu všech živých příloh na disku. Přepis env
/// `SEPOT_ATTACHMENTS_TOTAL_BYTES`. Bez něj jeden registrovaný klient
/// zaplní celý filesystem (v produkci 16 GB sdílených s Postgresem) za
/// minuty a relay přestane zapisovat do DB.
const DEFAULT_TOTAL_BYTES: u64 = 4 * 1024 * 1024 * 1024;

/// Jak dlouho smí při stahování čekat přečtený blok, než si ho klient
/// vezme. Časový limit routy hlídá jen hlavičky odpovědi; tělo by klient,
/// který přestal číst, držel otevřené (soubor i spojení) bez konce.
const DOWNLOAD_STALL_TIMEOUT: StdDuration = StdDuration::from_secs(60);
/// Strop celého stahování: 25 MiB za půl hodiny je 14 KiB/s, pomaleji
/// nejede ani mobilní síť přes Tor.
const DOWNLOAD_MAX_DURATION: StdDuration = StdDuration::from_secs(30 * 60);

/// Osiřelé `.part` soubory (pád mezi zápisem a přejmenováním) starší než
/// tohle se při úklidu mažou.
const PART_MAX_AGE: StdDuration = StdDuration::from_secs(24 * 3600);

#[derive(Clone)]
pub struct Config {
    pub dir: PathBuf,
    pub max_bytes: u64,
    pub total_bytes: u64,
}

impl Config {
    pub fn from_env() -> Self {
        let dir = std::env::var("SEPOT_ATTACHMENTS_DIR")
            .unwrap_or_else(|_| "./attachments".into());
        let max_bytes = std::env::var("SEPOT_MAX_ATTACHMENT_BYTES")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(DEFAULT_MAX_BYTES);
        let total_bytes = std::env::var("SEPOT_ATTACHMENTS_TOTAL_BYTES")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(DEFAULT_TOTAL_BYTES);
        Self {
            dir: PathBuf::from(dir),
            max_bytes,
            total_bytes,
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

#[derive(Debug, Serialize)]
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
) -> Result<(StatusCode, Json<UploadOut>), crate::rest::ApiError> {
    let authed =
        crate::rest::authenticate_device(&state, &headers, "POST /v1/attachments").await?;

    let cfg = &state.attachments;

    // Rychlé odmítnutí podle Content-Length, než tečou data
    let declared = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok());
    if declared.is_some_and(|len| len > cfg.max_bytes) {
        return Err((
            StatusCode::PAYLOAD_TOO_LARGE,
            "příloha je příliš velká".to_string(),
        )
            .into());
    }

    // Místo na disku dřív než cokoli dalšího: přílohy a DB sdílí filesystém
    // a plný disk by zastavil i zprávy (disk.rs).
    if state
        .disk
        .below(state.limits.disk_min_free_pct_attachments)
    {
        return Err((
            StatusCode::INSUFFICIENT_STORAGE,
            "úložiště příloh je plné, zkus to později".to_string(),
        )
            .into());
    }

    // Kvóta účtu: rezervuje se ohlášená velikost (bez Content-Length strop
    // jedné přílohy) a po zápisu se nespotřebovaný zbytek vrátí. Jen
    // v paměti — vazba účet → blob se neukládá (viz hlavička modulu).
    let reserved = declared.unwrap_or(cfg.max_bytes);
    let account = authed.account_id;
    // Čerstvý účet má nižší denní i uložený příděl (limits.rs).
    let fresh = state.is_fresh_account(authed.registered_at);
    let fresh_cap = state.limits.att_fresh_bytes_per_day;
    let daily_cost = |bytes: u64| match fresh {
        true => crate::quota::scaled_cost(bytes, state.limits.att_account_bytes_per_day, fresh_cap),
        false => bytes,
    };
    let stored_cap = (fresh && fresh_cap > 0).then_some(fresh_cap);
    if !state
        .attachment_budget
        .try_take(&account, daily_cost(reserved))
    {
        return Err((
            StatusCode::TOO_MANY_REQUESTS,
            "denní limit příloh vyčerpán, zkus to později".to_string(),
        )
            .into());
    }
    if !state
        .attachment_stored
        .try_reserve(&account, reserved, stored_cap)
    {
        state
            .attachment_budget
            .refund(&account, daily_cost(reserved));
        // Čerstvému účtu místo neuvolní stažení ani čekání do zítřka:
        // strop mu zvedne až stáří účtu.
        let message = match stored_cap {
            Some(_) => "nový účet smí první dny nahrát jen omezený objem příloh, zkus to později",
            None => "příliš mnoho uložených příloh, počkej, až je příjemci stáhnou",
        };
        return Err((StatusCode::TOO_MANY_REQUESTS, message.to_string()).into());
    }
    let refund = |unused: u64| {
        state.attachment_budget.refund(&account, daily_cost(unused));
        state.attachment_stored.release(&account, unused);
    };
    let result = store_upload(&state, body, authed.body_claim).await;
    match &result {
        Ok(stored) => refund(reserved.saturating_sub(stored.size_bytes)),
        Err(_) => refund(reserved),
    }
    result
        .map(|stored| (StatusCode::CREATED, Json(stored.into())))
        .map_err(Into::into)
}

/// Výsledek zápisu včetně skutečné velikosti (pro vyúčtování kvóty).
struct Stored {
    blob_id: String,
    expires_at_ms: i64,
    max_bytes: u64,
    size_bytes: u64,
}

impl From<Stored> for UploadOut {
    fn from(s: Stored) -> Self {
        Self {
            blob_id: s.blob_id,
            expires_at_ms: s.expires_at_ms,
            max_bytes: s.max_bytes,
        }
    }
}

async fn store_upload(
    state: &AppState,
    body: Body,
    claim: crate::rest::BodyClaim,
) -> ApiResult<Stored> {
    let cfg = &state.attachments;

    // Globální strop: součet živých příloh + tahle nesmí přesáhnout
    // total_bytes. Jeden SELECT nad malou tabulkou; nic o zařízení se
    // k blobu neváže.
    let (used,): (i64,) =
        sqlx::query_as("SELECT coalesce(sum(size_bytes), 0)::bigint FROM attachments")
            .fetch_one(&state.pool)
            .await
            .map_err(internal)?;
    // Před přijetím těla se jen ověří, že by místo šlo uvolnit. Mazat se
    // smí až pro přílohu, která opravdu dorazila: nahrání, které pak selže
    // (přerušené, moc velké, s cizím podpisem), jinak cizí přílohy vytlačilo
    // zadarmo.
    let missing = (used.max(0) as u64)
        .saturating_add(cfg.max_bytes)
        .saturating_sub(cfg.total_bytes);
    if missing > 0 && evictable_bytes(state).await.map_err(internal)? < missing {
        return Err(storage_full());
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

    let written = match write_stream(body, &tmp_path, cfg.max_bytes, claim).await {
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
    match make_room(state, written).await {
        Ok(true) => {}
        Ok(false) => {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(storage_full());
        }
        Err(e) => {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(internal(e));
        }
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

    Ok(Stored {
        blob_id: blob_hex,
        expires_at_ms: expires_at.timestamp_millis(),
        max_bytes: cfg.max_bytes,
        size_bytes: written,
    })
}

fn storage_full() -> (StatusCode, String) {
    (
        StatusCode::INSUFFICIENT_STORAGE,
        "úložiště příloh je plné, zkus to později".into(),
    )
}

/// Udělá místo pro přijatou přílohu o `written` bajtech; `false` = místo
/// není a uvolnit ho nejde. Počítá se skutečnou velikostí, ne se stropem
/// jedné přílohy jako kontrola před přijetím těla. Souběžná nahrání můžou
/// strop úložiště krátce přetáhnout o to, co právě přijímají; hlídat to
/// zámkem by nahrávání seřadilo do fronty.
async fn make_room(state: &AppState, written: u64) -> sqlx::Result<bool> {
    let (used,): (i64,) =
        sqlx::query_as("SELECT coalesce(sum(size_bytes), 0)::bigint FROM attachments")
            .fetch_one(&state.pool)
            .await?;
    let missing = (used.max(0) as u64)
        .saturating_add(written)
        .saturating_sub(state.attachments.total_bytes);
    Ok(missing == 0 || evict_oldest(state, missing).await? >= missing)
}

/// Kolik bajtů by vytlačení nejstarších příloh nejvýš uvolnilo.
async fn evictable_bytes(state: &AppState) -> sqlx::Result<u64> {
    let min_age_hours = state.limits.att_evict_min_age_hours;
    if min_age_hours == 0 {
        return Ok(0);
    }
    let (evictable,): (i64,) = sqlx::query_as(
        "SELECT coalesce(sum(size_bytes), 0)::bigint FROM attachments
         WHERE created_at < now() - make_interval(hours => $1)",
    )
    .bind(min_age_hours)
    .fetch_one(&state.pool)
    .await?;
    Ok(evictable.max(0) as u64)
}

/// Plné úložiště: smaže nejstarší bloby starší než
/// `Limits::att_evict_min_age_hours`, dokud neuvolní `missing` bajtů, a vrátí,
/// kolik uvolnil. Mladší bloby nechá — jinak by nová příloha mazala tu,
/// kterou někdo nahrál před minutou a příjemce ji ještě nestihl stáhnout.
/// Stáří je jediné vodítko: zda blob někdo stáhl, relay neeviduje, a i kdyby
/// ano, stahování je bez přihlášení a „stažené“ by si útočník obstaral sám.
async fn evict_oldest(state: &AppState, missing: u64) -> sqlx::Result<u64> {
    let min_age_hours = state.limits.att_evict_min_age_hours;
    if min_age_hours == 0 {
        return Ok(0);
    }
    let evicted: Vec<(Vec<u8>, i64)> = sqlx::query_as(
        "DELETE FROM attachments WHERE blob_id IN (
             SELECT blob_id FROM (
                 SELECT blob_id,
                        coalesce(sum(size_bytes) OVER (ORDER BY created_at, blob_id
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS freed_before
                 FROM attachments
                 WHERE created_at < now() - make_interval(hours => $2)
             ) oldest WHERE freed_before < $1
         ) RETURNING blob_id, size_bytes",
    )
    .bind(i64::try_from(missing).unwrap_or(i64::MAX))
    .bind(min_age_hours)
    .fetch_all(&state.pool)
    .await?;
    let mut freed = 0u64;
    for (blob_id, size_bytes) in &evicted {
        let path = state.attachments.blob_path(&hex::encode(blob_id));
        let _ = tokio::fs::remove_file(path).await;
        freed = freed.saturating_add((*size_bytes).max(0) as u64);
    }
    if !evicted.is_empty() {
        // warn: plné úložiště příloh je buď málo místa, nebo útok; obojí
        // má provozovatel vidět. Bez blob_id — jen počet a objem.
        tracing::warn!(
            count = evicted.len(),
            freed,
            "úložiště příloh plné, nejstarší přílohy vytlačeny"
        );
    }
    Ok(freed)
}

/// Zapíše tělo do souboru a vrátí velikost. Když se podpis požadavku váže
/// k otisku těla, musí zapsané tělo sedět: jinak by šlo zachycený podpis
/// použít k nahrání jiného obsahu na účet oběti.
async fn write_stream(
    body: Body,
    path: &FsPath,
    max_bytes: u64,
    claim: crate::rest::BodyClaim,
) -> ApiResult<u64> {
    let mut file = tokio::fs::File::create(path).await.map_err(internal)?;
    let mut stream = body.into_data_stream();
    let mut written: u64 = 0;
    let mut digest = Sha256::new();
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
        digest.update(&chunk);
        file.write_all(&chunk).await.map_err(internal)?;
    }
    if !claim.matches(&digest.finalize().into()) {
        return Err((
            StatusCode::UNAUTHORIZED,
            crate::rest::TEXT_BODY_MISMATCH.into(),
        ));
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
    let stream = timed_stream(file, DOWNLOAD_STALL_TIMEOUT, DOWNLOAD_MAX_DURATION);

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(header::CONTENT_LENGTH, size)
        .header(header::CACHE_CONTROL, "no-store")
        // Blob je bearer URL na důvěryhodné doméně — prohlížeč ho nesmí
        // ani zkoušet vykreslit (nosniff + attachment).
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .header(header::CONTENT_DISPOSITION, "attachment")
        .body(Body::from_stream(stream))
        .map_err(internal)
}

/// Tělo odpovědi čtené ze souboru s lhůtou: blok, který si klient do
/// `stall` nevezme, nebo stahování delší než `total` čtení ukončí a soubor
/// zavře. Odpověď pak skončí dřív, než slibuje Content-Length, a HTTP
/// vrstva spojení zavře.
///
/// Čte vlastní úloha přes kanál o jednom bloku, ne stream sám: stream
/// u klienta, který nečte, nikdo nepolluje, takže by lhůtu nikdy nezjistil.
fn timed_stream<R>(
    reader: R,
    stall: StdDuration,
    total: StdDuration,
) -> impl Stream<Item = std::io::Result<Bytes>>
where
    R: AsyncRead + Send + Unpin + 'static,
{
    let (tx, rx) = mpsc::channel::<std::io::Result<Bytes>>(1);
    tokio::spawn(async move {
        let deadline = tokio::time::Instant::now() + total;
        let mut chunks = tokio_util::io::ReaderStream::new(reader);
        while let Some(chunk) = chunks.next().await {
            let failed = chunk.is_err();
            let hand_over = (tokio::time::Instant::now() + stall).min(deadline);
            let taken = tokio::time::timeout_at(hand_over, tx.send(chunk)).await;
            if failed || !matches!(taken, Ok(Ok(()))) {
                break;
            }
        }
    });
    futures_util::stream::unfold(rx, |mut rx| async move {
        rx.recv().await.map(|chunk| (chunk, rx))
    })
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
mod tests {
    use tokio::io::AsyncReadExt;

    use super::*;

    const SHORT: StdDuration = StdDuration::from_millis(50);
    const BLOB_BYTES: u64 = 4 * 1024 * 1024;

    fn blob() -> impl AsyncRead + Send + Unpin + 'static {
        tokio::io::repeat(0x42).take(BLOB_BYTES)
    }

    async fn drain(stream: impl Stream<Item = std::io::Result<Bytes>>) -> u64 {
        stream
            .fold(0u64, |total, chunk| async move {
                total + chunk.map_or(0, |bytes| bytes.len() as u64)
            })
            .await
    }

    #[tokio::test]
    async fn stahovani_ktere_cte_dostane_cely_blob() {
        let stream = timed_stream(blob(), SHORT, StdDuration::from_secs(60));
        assert_eq!(drain(stream).await, BLOB_BYTES);
    }

    /// Klient, který přestal číst, nesmí držet soubor otevřený bez konce:
    /// po lhůtě čtení skončí a zbytek blobu už nedostane.
    #[tokio::test]
    async fn stahovani_ktere_stoji_se_ukonci() {
        let stream = timed_stream(blob(), SHORT, StdDuration::from_secs(60));
        tokio::pin!(stream);
        let first = stream.next().await.expect("první blok").expect("čtení");
        tokio::time::sleep(SHORT * 4).await;
        let rest = drain(stream).await;
        assert!(
            first.len() as u64 + rest < BLOB_BYTES,
            "po lhůtě přišel celý blob"
        );
    }

    #[tokio::test]
    async fn stahovani_ma_strop_celkove_doby() {
        let stream = timed_stream(blob(), StdDuration::from_secs(60), SHORT);
        tokio::pin!(stream);
        let mut received = 0u64;
        while let Some(chunk) = stream.next().await {
            received += chunk.expect("čtení").len() as u64;
            // Pomalý klient: každý blok si vezme, ale celé to trvá moc dlouho.
            tokio::time::sleep(SHORT / 2).await;
        }
        assert!(received < BLOB_BYTES, "stahování přežilo celkový strop");
    }
}

#[cfg(test)]
mod db_tests {
    //! Integrace nad reálným Postgresem (dev DB) — spouštět
    //! `cargo test -p sepot-relay -- --ignored`. Uklízí po sobě.
    use super::*;
    use crate::testkit::{self, rand_bytes, TestIdentity};

    /// Strop jedné přílohy v testech.
    const TEST_MAX_BYTES: u64 = 1024;

    fn test_config(tag: &str, total_bytes: u64) -> Config {
        let dir = std::env::temp_dir().join(format!(
            "sepot-att-test-{}-{tag}",
            std::process::id()
        ));
        std::fs::create_dir_all(dir.join("tmp")).unwrap();
        Config {
            dir,
            max_bytes: TEST_MAX_BYTES,
            total_bytes,
        }
    }

    async fn test_state() -> AppState {
        let mut state = testkit::state().await;
        state.attachments = test_config("sdilene", 1 << 30);
        state
    }

    async fn upload_blob(
        state: &Arc<AppState>,
        identity: &TestIdentity,
        device_uuid: &[u8],
        size: usize,
    ) -> Result<UploadOut, crate::rest::ApiError> {
        let headers = identity.auth_headers(device_uuid, "POST /v1/attachments");
        upload(State(state.clone()), headers, Body::from(vec![0xC3u8; size]))
            .await
            .map(|(_, Json(out))| out)
    }

    async fn insert_blob(state: &AppState, size: i64, age_hours: i32) -> PathBuf {
        let blob_id = rand_blob_id();
        let path = state.attachments.blob_path(&hex::encode(&blob_id));
        std::fs::write(&path, b"ciphertext").unwrap();
        sqlx::query(
            "INSERT INTO attachments (blob_id, size_bytes, created_at, expires_at)
             VALUES ($1, $2, now() - make_interval(hours => $3), now() + interval '20 days')",
        )
        .bind(&blob_id)
        .bind(size)
        .bind(age_hours)
        .execute(&state.pool)
        .await
        .unwrap();
        path
    }

    /// Plné úložiště: nová příloha vytlačí nejstarší bloby za hranicí
    /// stáří, mladé nechá. Dřív stačilo úložiště jednou zaplnit a do
    /// vypršení TTL nešlo nahrát nic.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plne_uloziste_vytlaci_nejstarsi_prilohy() {
        /// Úložiště na tři největší přílohy.
        const TOTAL: u64 = 3 * TEST_MAX_BYTES;
        let isolated = testkit::Isolated::new().await;
        let mut state = isolated.state().await;
        state.attachments = test_config("vytlaceni", TOTAL);
        let min_age = state.limits.att_evict_min_age_hours;
        let state = Arc::new(state);
        let identity = TestIdentity::new();
        let registered = testkit::register(&state, &identity, &rand_bytes(32))
            .await
            .expect("registrace");

        let oldest = insert_blob(&state, TEST_MAX_BYTES as i64, min_age + 48).await;
        let old = insert_blob(&state, TEST_MAX_BYTES as i64, min_age + 24).await;
        let young = insert_blob(&state, TEST_MAX_BYTES as i64, 1).await;

        // Nahrání, které selže (tělo nad strop jedné přílohy), nesmí cizí
        // přílohy vytlačit: mazat se má až pro přílohu, která dorazila.
        let too_big = upload_blob(
            &state,
            &identity,
            &registered.device_uuid,
            TEST_MAX_BYTES as usize + 1,
        )
        .await
        .expect_err("nad strop jedné přílohy");
        assert_eq!(too_big.status, StatusCode::PAYLOAD_TOO_LARGE);
        assert!(oldest.exists(), "neúspěšné nahrání nic nevytlačilo");

        upload_blob(&state, &identity, &registered.device_uuid, 100)
            .await
            .expect("místo uvolnil nejstarší blob");
        assert!(!oldest.exists(), "nejstarší blob vytlačen i se souborem");
        assert!(old.exists(), "víc, než bylo potřeba, se nemaže");
        assert!(young.exists());

        // Místo po vytlačeném blobu stačí i na další malou přílohu.
        upload_blob(&state, &identity, &registered.device_uuid, 100)
            .await
            .expect("místo ještě je");
        assert!(old.exists(), "bez potřeby se nemaže");

        // Velká se už nevejde: padne další starý blob, mladý nikdy.
        upload_blob(&state, &identity, &registered.device_uuid, TEST_MAX_BYTES as usize)
            .await
            .expect("místo uvolnil další starý blob");
        assert!(!old.exists());
        assert!(young.exists(), "mladý blob zůstává");

        let _ = std::fs::remove_dir_all(&state.attachments.dir);
        isolated.remove().await;
    }

    /// Samé mladé bloby: vytlačit není co, úložiště odmítá jako dřív.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plne_uloziste_mlade_prilohy_nemaze() {
        const TOTAL: u64 = 2 * TEST_MAX_BYTES;
        let isolated = testkit::Isolated::new().await;
        let mut state = isolated.state().await;
        state.attachments = test_config("mlade", TOTAL);
        let state = Arc::new(state);
        let identity = TestIdentity::new();
        let registered = testkit::register(&state, &identity, &rand_bytes(32))
            .await
            .expect("registrace");
        let first = insert_blob(&state, TEST_MAX_BYTES as i64, 1).await;
        let second = insert_blob(&state, TEST_MAX_BYTES as i64, 2).await;

        let error = upload_blob(&state, &identity, &registered.device_uuid, 100)
            .await
            .expect_err("plné úložiště");
        assert_eq!(error.status, StatusCode::INSUFFICIENT_STORAGE);
        assert!(first.exists() && second.exists());

        let _ = std::fs::remove_dir_all(&state.attachments.dir);
        isolated.remove().await;
    }

    /// Podpis s otiskem těla nahraje jen to tělo; jiné relay odmítne a
    /// rozepsaný soubor po sobě nenechá.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn upload_s_otiskem_tela_odmitne_jine_telo() {
        const PATH: &str = "POST /v1/attachments";
        let isolated = testkit::Isolated::new().await;
        let mut state = isolated.state().await;
        state.attachments = test_config("otisk", 1 << 30);
        let state = Arc::new(state);
        let identity = TestIdentity::new();
        let device = testkit::register(&state, &identity, &rand_bytes(32))
            .await
            .expect("registrace")
            .device_uuid;
        let signed = vec![0xC3u8; 100];
        let digest: [u8; 32] = Sha256::digest(&signed).into();
        let headers = || identity.auth_headers_for_body(&device, PATH, &digest);

        let refused = upload(State(state.clone()), headers(), Body::from(vec![0x3Cu8; 100]))
            .await
            .expect_err("jiné tělo, než klient podepsal");
        assert_eq!(refused.status, StatusCode::UNAUTHORIZED);
        let leftovers = std::fs::read_dir(state.attachments.tmp_dir()).unwrap().count();
        assert_eq!(leftovers, 0, "rozepsaný soubor zůstal");
        let stored: i64 = sqlx::query_scalar("SELECT count(*) FROM attachments")
            .fetch_one(&state.pool)
            .await
            .unwrap();
        assert_eq!(stored, 0);

        upload(State(state.clone()), headers(), Body::from(signed))
            .await
            .map(|_| ())
            .expect("podepsané tělo");

        let _ = std::fs::remove_dir_all(&state.attachments.dir);
        isolated.remove().await;
    }

    /// Čerstvý účet má nižší příděl příloh, zavedený plný.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn cerstvy_ucet_ma_nizsi_pridel_priloh() {
        const UPLOAD: usize = 400;
        let mut state = test_state().await;
        // Čerstvý účet: dvě přílohy po 400 B, třetí už ne. Bez Content-Length
        // se napřed rezervuje strop jedné přílohy, proto příděl nad ním.
        state.limits.att_fresh_bytes_per_day = TEST_MAX_BYTES + UPLOAD as u64;
        let state = Arc::new(state);
        let (fresh, established) = (TestIdentity::new(), TestIdentity::new());
        let (fresh_address, established_address) = (rand_bytes(32), rand_bytes(32));
        let fresh_device = testkit::register(&state, &fresh, &fresh_address)
            .await
            .expect("registrace");
        let established_device = testkit::register(&state, &established, &established_address)
            .await
            .expect("registrace");
        sqlx::query(
            "UPDATE identities SET registered_at = now() - interval '30 days'
             WHERE account_id = $1",
        )
        .bind(&established_device.account_id)
        .execute(&state.pool)
        .await
        .unwrap();

        let mut blobs = Vec::new();
        for _ in 0..2 {
            let out = upload_blob(&state, &fresh, &fresh_device.device_uuid, UPLOAD)
                .await
                .expect("v přídělu čerstvého účtu");
            blobs.push(out.blob_id);
        }
        let error = upload_blob(&state, &fresh, &fresh_device.device_uuid, UPLOAD)
            .await
            .expect_err("nad příděl čerstvého účtu");
        assert_eq!(error.status, StatusCode::TOO_MANY_REQUESTS);
        for _ in 0..5 {
            let out = upload_blob(&state, &established, &established_device.device_uuid, UPLOAD)
                .await
                .expect("zavedený účet má plný příděl");
            blobs.push(out.blob_id);
        }

        for blob_hex in blobs {
            sqlx::query("DELETE FROM attachments WHERE blob_id = $1")
                .bind(hex::decode(&blob_hex).unwrap())
                .execute(&state.pool)
                .await
                .unwrap();
            let _ = std::fs::remove_file(state.attachments.blob_path(&blob_hex));
        }
        testkit::forget(&state.pool, &fresh, &[&fresh_address]).await;
        testkit::forget(&state.pool, &established, &[&established_address]).await;
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

        // úklid po testu; adresář sdílí další testy, mazat jen svůj soubor
        sqlx::query("DELETE FROM attachments WHERE blob_id = $1")
            .bind(&live)
            .execute(&state.pool)
            .await
            .unwrap();
        let _ = std::fs::remove_file(&live_path);
    }
}
