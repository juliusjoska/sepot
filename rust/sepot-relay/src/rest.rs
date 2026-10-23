//! REST endpointy — registrace, prekey bundle, sender cert.
//! Chybové odpovědi nikdy neleakují interní detail; logy bez identifikátorů.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use base64::prelude::*;
use libsignal_protocol::PublicKey;
use rand::RngCore;
use serde::{Deserialize, Serialize};

use crate::state::AppState;

type ApiResult<T> = Result<T, (StatusCode, String)>;

fn internal<E: std::fmt::Display>(e: E) -> (StatusCode, String) {
    tracing::warn!("interní chyba: {e}");
    (StatusCode::INTERNAL_SERVER_ERROR, "interní chyba".into())
}

fn bad(msg: &str) -> (StatusCode, String) {
    (StatusCode::BAD_REQUEST, msg.into())
}

fn b64(name: &str, value: &str, expect_len: Option<usize>) -> ApiResult<Vec<u8>> {
    let bytes = BASE64_STANDARD
        .decode(value)
        .map_err(|_| bad(&format!("pole {name} není platný base64")))?;
    if let Some(len) = expect_len {
        if bytes.len() != len {
            return Err(bad(&format!("pole {name} má špatnou délku")));
        }
    }
    Ok(bytes)
}

pub async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "ok" }))
}

/// Readiness: health je jen „proces žije", tohle ověří i DB.
/// Pro sondy monitoringu — DB mimo provoz = 503, ne falešné 200.
pub async fn ready(State(state): State<Arc<AppState>>) -> ApiResult<Json<serde_json::Value>> {
    let probe = tokio::time::timeout(
        std::time::Duration::from_secs(1),
        sqlx::query("SELECT 1").execute(&state.pool),
    )
    .await;
    match probe {
        Ok(Ok(_)) => Ok(Json(serde_json::json!({ "status": "ready" }))),
        _ => Err((StatusCode::SERVICE_UNAVAILABLE, "databáze neodpovídá".into())),
    }
}

/// Veřejné informace o relayi. `source` + `revision` plní AGPL §13 — kdo
/// s relayem mluví, má vědět, který zdroj právě běží.
pub async fn server_info(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "frame_version": 1,
        "trust_root": BASE64_STANDARD.encode(&state.certs.trust_root_public),
        "capabilities": ["pqxdh", "sealed-sender", "prekey-upload", "identity-reclaim"],
        "source": state.source_url,
        "revision": state.revision,
    }))
}

/// Ověří hlavičku `X-Sepot-Identity-Proof: <ts_ms>.<sig_b64>` — podpis
/// identity klíčem nad `"<method_path>\n<ts_ms>"`, stejné okno jako
/// X-Sepot-Auth. Důkaz držení privátního klíče bez znalosti device_uuid:
/// obnova ze 24 slov na novém telefonu nemá nic jiného.
fn identity_proof_valid(headers: &HeaderMap, identity: &PublicKey, method_path: &str) -> bool {
    let Some(header) = headers
        .get("x-sepot-identity-proof")
        .and_then(|v| v.to_str().ok())
    else {
        return false;
    };
    let Some((ts_str, sig_b64)) = header.split_once('.') else {
        return false;
    };
    let Ok(ts) = ts_str.parse::<i64>() else {
        return false;
    };
    let Ok(signature) = BASE64_STANDARD.decode(sig_b64) else {
        return false;
    };
    let now_ms = chrono::Utc::now().timestamp_millis();
    if now_ms.abs_diff(ts) > AUTH_WINDOW_MS as u64 {
        return false;
    }
    let message = format!("{method_path}\n{ts}");
    identity.verify_signature(message.as_bytes(), &signature)
}

// ── POST /v1/register ──────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct PreKeyIn {
    pub key_id: i32,
    pub public_key: String,
    #[serde(default)]
    pub signature: Option<String>,
    #[serde(default)]
    pub is_last_resort: bool,
}

#[derive(Deserialize)]
pub struct RegisterIn {
    pub identity_key: String,
    pub device_id: i32,
    pub registration_id: i32,
    pub delivery_address: String,
    pub signed_prekey: PreKeyIn,
    pub kyber_prekey: PreKeyIn,
    #[serde(default)]
    pub one_time_prekeys: Vec<PreKeyIn>,
}

#[derive(Serialize)]
pub struct RegisterOut {
    pub account_id: String,
    pub device_uuid: String,
}

/// Strop OTP klíčů v jedné registraci (klient posílá 100).
const MAX_ONE_TIME_PREKEYS: usize = 100;

pub async fn register(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<RegisterIn>,
) -> ApiResult<(StatusCode, Json<RegisterOut>)> {
    if state.limits.registration_paused {
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "registrace jsou dočasně pozastavené, zkus to za pár minut".into(),
        ));
    }
    if body.one_time_prekeys.len() > MAX_ONE_TIME_PREKEYS {
        return Err(bad("příliš mnoho one-time prekeys"));
    }
    // libsignal DeviceId je 1..=127; registration_id kladné 14bitové číslo.
    // Mimo rozsah by registrace prošla a GET /v1/certificate pak padal na 500.
    if !(1..=127).contains(&body.device_id) || !(1..=16_383).contains(&body.registration_id) {
        return Err(bad("device_id nebo registration_id mimo rozsah"));
    }
    let identity_key = b64("identity_key", &body.identity_key, Some(33))?;
    let delivery_address = b64("delivery_address", &body.delivery_address, Some(32))?;
    let spk_pub = b64("signed_prekey.public_key", &body.signed_prekey.public_key, Some(33))?;
    let spk_sig = b64(
        "signed_prekey.signature",
        body.signed_prekey.signature.as_deref().ok_or_else(|| bad("chybí podpis signed prekey"))?,
        Some(64),
    )?;
    let kyber_pub = b64("kyber_prekey.public_key", &body.kyber_prekey.public_key, None)?;
    let kyber_sig = b64(
        "kyber_prekey.signature",
        body.kyber_prekey.signature.as_deref().ok_or_else(|| bad("chybí podpis kyber prekey"))?,
        Some(64),
    )?;

    // Hygiena: podpisy prekeys musí sedět k identity klíči už při uploadu.
    let identity = PublicKey::deserialize(&identity_key).map_err(|_| bad("neplatný identity klíč"))?;
    if !identity.verify_signature(&spk_pub, &spk_sig) {
        return Err(bad("podpis signed prekey nesedí"));
    }
    if !identity.verify_signature(&kyber_pub, &kyber_sig) {
        return Err(bad("podpis kyber prekey nesedí"));
    }

    // ThreadRng je !Send — nesmí přežít přes await, proto vlastní scope.
    let (account_id, device_uuid) = {
        let mut rng = rand::rng();
        let mut account_id = vec![0u8; 16];
        rng.fill_bytes(&mut account_id);
        let mut device_uuid = vec![0u8; 16];
        rng.fill_bytes(&mut device_uuid);
        (account_id, device_uuid)
    };

    let mut tx = state.pool.begin().await.map_err(internal)?;

    let inserted = sqlx::query(
        "INSERT INTO identities (account_id, identity_key) VALUES ($1, $2)
         ON CONFLICT (identity_key) DO NOTHING",
    )
    .bind(&account_id)
    .bind(&identity_key)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;
    // Identita už existuje = obnova ze 24 slov na novém telefonu (nebo
    // reinstalace). Bez důkazu držení klíče zůstává 409 (anti-squatting);
    // s důkazem účet převezme nové zařízení: stará zařízení, jejich
    // prekeys, push tokeny i nedoručená fronta pryč (nové zařízení staré
    // ratchet relace stejně nemá), account_id zůstává — kontakty ho znají.
    let account_id = if inserted.rows_affected() == 0 {
        if !identity_proof_valid(&headers, &identity, "POST /v1/register") {
            return Err((StatusCode::CONFLICT, "identita už existuje".into()));
        }
        let (existing,): (Vec<u8>,) =
            sqlx::query_as("SELECT account_id FROM identities WHERE identity_key = $1")
                .bind(&identity_key)
                .fetch_one(&mut *tx)
                .await
                .map_err(internal)?;
        sqlx::query(
            "DELETE FROM message_queue WHERE dst_address IN (
                 SELECT delivery_address FROM devices WHERE account_id = $1)",
        )
        .bind(&existing)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        sqlx::query("DELETE FROM devices WHERE account_id = $1")
            .bind(&existing)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        tracing::info!("identita převzata novým zařízením (obnova)");
        existing
    } else {
        account_id
    };

    sqlx::query(
        "INSERT INTO devices (device_uuid, account_id, device_id, registration_id, delivery_address)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&device_uuid)
    .bind(&account_id)
    .bind(body.device_id)
    .bind(body.registration_id)
    .bind(&delivery_address)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;

    sqlx::query(
        "INSERT INTO signed_prekeys (device_uuid, key_id, public_key, signature)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(&device_uuid)
    .bind(body.signed_prekey.key_id)
    .bind(&spk_pub)
    .bind(&spk_sig)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;

    sqlx::query(
        "INSERT INTO kyber_prekeys (device_uuid, key_id, public_key, signature, is_last_resort)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&device_uuid)
    .bind(body.kyber_prekey.key_id)
    .bind(&kyber_pub)
    .bind(&kyber_sig)
    .bind(body.kyber_prekey.is_last_resort)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;

    for otp in &body.one_time_prekeys {
        let otp_pub = b64("one_time_prekeys.public_key", &otp.public_key, Some(33))?;
        sqlx::query(
            "INSERT INTO one_time_prekeys (device_uuid, key_id, public_key) VALUES ($1, $2, $3)",
        )
        .bind(&device_uuid)
        .bind(otp.key_id)
        .bind(&otp_pub)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    }

    tx.commit().await.map_err(internal)?;
    tracing::info!("nová registrace zařízení");

    Ok((
        StatusCode::CREATED,
        Json(RegisterOut {
            account_id: hex::encode(account_id),
            device_uuid: hex::encode(device_uuid),
        }),
    ))
}

// ── GET /v1/keys/{delivery_address} ───────────────────────────────────

#[derive(Serialize)]
pub struct PreKeyOut {
    pub key_id: i32,
    pub public_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Serialize)]
pub struct DeviceBundleOut {
    pub device_id: i32,
    pub registration_id: i32,
    pub identity_key: String,
    pub signed_prekey: PreKeyOut,
    pub kyber_prekey: PreKeyOut,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub one_time_prekey: Option<PreKeyOut>,
}

#[derive(Serialize)]
pub struct BundlesOut {
    pub devices: Vec<DeviceBundleOut>,
}

pub async fn fetch_bundle(
    State(state): State<Arc<AppState>>,
    Path(delivery_address): Path<String>,
) -> ApiResult<Json<BundlesOut>> {
    let address = hex::decode(&delivery_address).map_err(|_| bad("neplatná adresa"))?;

    let account: Option<(Vec<u8>, Vec<u8>)> = sqlx::query_as(
        "SELECT d.account_id, i.identity_key
         FROM devices d JOIN identities i USING (account_id)
         WHERE d.delivery_address = $1",
    )
    .bind(&address)
    .fetch_optional(&state.pool)
    .await
    .map_err(internal)?;
    let Some((account_id, identity_key)) = account else {
        return Err((StatusCode::NOT_FOUND, "adresa neznámá".into()));
    };

    // Multi-device fanout: bundle pro všechna zařízení identity.
    let devices: Vec<(Vec<u8>, i32, i32)> = sqlx::query_as(
        "SELECT device_uuid, device_id, registration_id FROM devices WHERE account_id = $1",
    )
    .bind(&account_id)
    .fetch_all(&state.pool)
    .await
    .map_err(internal)?;

    let mut out = Vec::with_capacity(devices.len());
    for (device_uuid, device_id, registration_id) in devices {
        let spk: (i32, Vec<u8>, Vec<u8>) = sqlx::query_as(
            "SELECT key_id, public_key, signature FROM signed_prekeys
             WHERE device_uuid = $1 ORDER BY created_at DESC LIMIT 1",
        )
        .bind(&device_uuid)
        .fetch_one(&state.pool)
        .await
        .map_err(internal)?;

        let kyber: (i32, Vec<u8>, Vec<u8>) = sqlx::query_as(
            "SELECT key_id, public_key, signature FROM kyber_prekeys
             WHERE device_uuid = $1 ORDER BY is_last_resort ASC, created_at DESC LIMIT 1",
        )
        .bind(&device_uuid)
        .fetch_one(&state.pool)
        .await
        .map_err(internal)?;

        // Spotřebuj jeden one-time prekey (DELETE ... RETURNING) —
        // ale jen v mezích hodinového stropu na adresu: bundle bez OTP je
        // povolený fallback, vyčerpaná zásoba cizím ne.
        let otp: Option<(i32, Vec<u8>)> = if state.allow_otp_issue(&address) {
            sqlx::query_as(
                "DELETE FROM one_time_prekeys
                 WHERE (device_uuid, key_id) IN (
                     SELECT device_uuid, key_id FROM one_time_prekeys
                     WHERE device_uuid = $1 ORDER BY key_id
                     FOR UPDATE SKIP LOCKED LIMIT 1)
                 RETURNING key_id, public_key",
            )
            .bind(&device_uuid)
            .fetch_optional(&state.pool)
            .await
            .map_err(internal)?
        } else {
            None
        };

        out.push(DeviceBundleOut {
            device_id,
            registration_id,
            identity_key: BASE64_STANDARD.encode(&identity_key),
            signed_prekey: PreKeyOut {
                key_id: spk.0,
                public_key: BASE64_STANDARD.encode(spk.1),
                signature: Some(BASE64_STANDARD.encode(spk.2)),
            },
            kyber_prekey: PreKeyOut {
                key_id: kyber.0,
                public_key: BASE64_STANDARD.encode(kyber.1),
                signature: Some(BASE64_STANDARD.encode(kyber.2)),
            },
            one_time_prekey: otp.map(|(key_id, public_key)| PreKeyOut {
                key_id,
                public_key: BASE64_STANDARD.encode(public_key),
                signature: None,
            }),
        });
    }

    Ok(Json(BundlesOut { devices: out }))
}

// ── Autentizace zařízení (X-Sepot-Auth) ────────────────────────────────

/// Max stáří podepsaného timestampu v X-Sepot-Auth (replay okno).
const AUTH_WINDOW_MS: i64 = 300_000;

pub(crate) struct AuthedDevice {
    pub account_id: Vec<u8>,
    pub identity_key: Vec<u8>,
    pub device_id: i32,
    pub device_uuid: Vec<u8>,
}

/// Ověří hlavičku `X-Sepot-Auth: <device_uuid_hex>.<ts_ms>.<sig_b64>`,
/// kde sig = XEdDSA identity klíčem zařízení nad `"<method_path>\n<ts_ms>"`.
/// Sdílí ji sender certificate a upload příloh; do logů nejde nic.
pub(crate) async fn authenticate_device(
    state: &AppState,
    headers: &HeaderMap,
    method_path: &str,
) -> Result<AuthedDevice, (StatusCode, String)> {
    let unauthorized = || (StatusCode::UNAUTHORIZED, "neautorizováno".to_string());

    let header = headers
        .get("x-sepot-auth")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(unauthorized)?;
    let mut parts = header.splitn(3, '.');
    let (device_hex, ts_str, sig_b64) = (
        parts.next().ok_or_else(unauthorized)?,
        parts.next().ok_or_else(unauthorized)?,
        parts.next().ok_or_else(unauthorized)?,
    );

    let device_uuid = hex::decode(device_hex).map_err(|_| unauthorized())?;
    let ts: i64 = ts_str.parse().map_err(|_| unauthorized())?;
    let signature = BASE64_STANDARD.decode(sig_b64).map_err(|_| unauthorized())?;

    let now_ms = chrono::Utc::now().timestamp_millis();
    // abs_diff: `(now - ts).abs()` by u extrémního ts v release přetekl.
    if now_ms.abs_diff(ts) > AUTH_WINDOW_MS as u64 {
        return Err(unauthorized());
    }

    let row: Option<(Vec<u8>, Vec<u8>, i32)> = sqlx::query_as(
        "SELECT d.account_id, i.identity_key, d.device_id
         FROM devices d JOIN identities i USING (account_id)
         WHERE d.device_uuid = $1",
    )
    .bind(&device_uuid)
    .fetch_optional(&state.pool)
    .await
    .map_err(internal)?;
    let Some((account_id, identity_key, device_id)) = row else {
        return Err(unauthorized());
    };

    let message = format!("{method_path}\n{ts}");
    let identity = PublicKey::deserialize(&identity_key).map_err(|_| unauthorized())?;
    if !identity.verify_signature(message.as_bytes(), &signature) {
        return Err(unauthorized());
    }

    Ok(AuthedDevice {
        account_id,
        identity_key,
        device_id,
        device_uuid,
    })
}

// ── POST /v1/keys ──────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct UploadKeysIn {
    #[serde(default)]
    pub signed_prekey: Option<PreKeyIn>,
    #[serde(default)]
    pub kyber_prekey: Option<PreKeyIn>,
    #[serde(default)]
    pub one_time_prekeys: Vec<PreKeyIn>,
}

#[derive(Serialize)]
pub struct UploadKeysOut {
    /// Kolik OTP zařízení má po nahrání.
    pub one_time_prekeys: i64,
}


/// Po kolika dnech se starý signed prekey smaže (po rotaci ho relay ještě
/// drží, protože bundle s ním mohl někdo stáhnout těsně před výměnou).
const SIGNED_PREKEY_GRACE_DAYS: i64 = 30;

/// Doplnění one-time prekeys a rotace signed / Kyber prekey. Auth podpis: `"POST /v1/keys\n<ts>"`.
/// Podpisy nových prekeys se ověřují proti identity klíči zařízení.
pub async fn upload_keys(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<UploadKeysIn>,
) -> ApiResult<Json<UploadKeysOut>> {
    let authed = authenticate_device(&state, &headers, "POST /v1/keys").await?;
    if body.one_time_prekeys.len() > MAX_ONE_TIME_PREKEYS {
        return Err(bad("příliš mnoho one-time prekeys"));
    }
    let identity =
        PublicKey::deserialize(&authed.identity_key).map_err(|_| bad("neplatný identity klíč"))?;

    let mut tx = state.pool.begin().await.map_err(internal)?;

    if let Some(spk) = &body.signed_prekey {
        let public = b64("signed_prekey.public_key", &spk.public_key, Some(33))?;
        let sig = b64(
            "signed_prekey.signature",
            spk.signature.as_deref().ok_or_else(|| bad("chybí podpis signed prekey"))?,
            Some(64),
        )?;
        if !identity.verify_signature(&public, &sig) {
            return Err(bad("podpis signed prekey nesedí"));
        }
        sqlx::query(
            "INSERT INTO signed_prekeys (device_uuid, key_id, public_key, signature)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (device_uuid, key_id) DO NOTHING",
        )
        .bind(&authed.device_uuid)
        .bind(spk.key_id)
        .bind(&public)
        .bind(&sig)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        // Starší než grace a zároveň ne nejnovější → pryč.
        sqlx::query(
            "DELETE FROM signed_prekeys WHERE device_uuid = $1
               AND created_at < now() - make_interval(days => $2)
               AND key_id <> (SELECT key_id FROM signed_prekeys WHERE device_uuid = $1
                              ORDER BY created_at DESC LIMIT 1)",
        )
        .bind(&authed.device_uuid)
        .bind(SIGNED_PREKEY_GRACE_DAYS as i32)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    }

    if let Some(kyber) = &body.kyber_prekey {
        let public = b64("kyber_prekey.public_key", &kyber.public_key, None)?;
        if public.len() > 2048 {
            return Err(bad("kyber prekey je příliš dlouhý"));
        }
        let sig = b64(
            "kyber_prekey.signature",
            kyber.signature.as_deref().ok_or_else(|| bad("chybí podpis kyber prekey"))?,
            Some(64),
        )?;
        if !identity.verify_signature(&public, &sig) {
            return Err(bad("podpis kyber prekey nesedí"));
        }
        sqlx::query(
            "INSERT INTO kyber_prekeys (device_uuid, key_id, public_key, signature, is_last_resort)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (device_uuid, key_id) DO NOTHING",
        )
        .bind(&authed.device_uuid)
        .bind(kyber.key_id)
        .bind(&public)
        .bind(&sig)
        .bind(kyber.is_last_resort)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        sqlx::query(
            "DELETE FROM kyber_prekeys WHERE device_uuid = $1 AND is_last_resort
               AND created_at < now() - make_interval(days => $2)
               AND key_id <> (SELECT key_id FROM kyber_prekeys WHERE device_uuid = $1
                              AND is_last_resort ORDER BY created_at DESC LIMIT 1)",
        )
        .bind(&authed.device_uuid)
        .bind(SIGNED_PREKEY_GRACE_DAYS as i32)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    }

    let (mut stored,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM one_time_prekeys WHERE device_uuid = $1")
            .bind(&authed.device_uuid)
            .fetch_one(&mut *tx)
            .await
            .map_err(internal)?;
    for otp in &body.one_time_prekeys {
        // Strop zásoby OTP (`Limits::max_stored_otp`, výchozí 100) — nad něj se
        // další zahodí (klient posílá dávky po 50, jako při registraci sto).
        if stored >= state.limits.max_stored_otp {
            break;
        }
        let public = b64("one_time_prekeys.public_key", &otp.public_key, Some(33))?;
        let res = sqlx::query(
            "INSERT INTO one_time_prekeys (device_uuid, key_id, public_key) VALUES ($1, $2, $3)
             ON CONFLICT (device_uuid, key_id) DO NOTHING",
        )
        .bind(&authed.device_uuid)
        .bind(otp.key_id)
        .bind(&public)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        stored += res.rows_affected() as i64;
    }

    tx.commit().await.map_err(internal)?;
    Ok(Json(UploadKeysOut {
        one_time_prekeys: stored,
    }))
}

// ── DELETE /v1/identity ────────────────────────────────────────────────

/// Deregistrace účtu (GDPR čl. 17, store požadavek na smazání účtu).
/// Auth stejným podpisem jako sender certificate — smazat účet smí jen
/// držitel identity klíče. Kaskáda v DB odnese devices → prekeys +
/// push_tokens; fronta zpráv je vázaná na delivery_address bez FK,
/// maže se explicitně v téže transakci. Přílohy vazbu na účet nemají
/// (bearer capability) — dožijí TTL sweep.
pub async fn delete_identity(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> ApiResult<StatusCode> {
    let authed = authenticate_device(&state, &headers, "DELETE /v1/identity").await?;
    state
        .delete_identity(&authed.account_id)
        .await
        .map_err(internal)?;
    tracing::info!("identita smazána na žádost zařízení");
    Ok(StatusCode::NO_CONTENT)
}

// ── GET /v1/certificate/delivery ───────────────────────────────────────

#[derive(Serialize)]
pub struct CertificateOut {
    pub sender_certificate: String,
    pub trust_root: String,
    pub sender_uuid: String,
    pub expires_at_ms: u64,
}

pub async fn certificate_delivery(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> ApiResult<Json<CertificateOut>> {
    let authed =
        authenticate_device(&state, &headers, "GET /v1/certificate/delivery").await?;

    let now_ms = chrono::Utc::now().timestamp_millis();
    let sender_uuid = hex::encode(&authed.account_id);
    let (cert, expires_at_ms) = state
        .certs
        .issue(
            &sender_uuid,
            authed.device_id as u32,
            &authed.identity_key,
            now_ms as u64,
        )
        .map_err(internal)?;

    Ok(Json(CertificateOut {
        sender_certificate: BASE64_STANDARD.encode(cert),
        trust_root: BASE64_STANDARD.encode(&state.certs.trust_root_public),
        sender_uuid,
        expires_at_ms,
    }))
}
