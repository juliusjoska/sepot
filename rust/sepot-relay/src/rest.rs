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

pub async fn server_info(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "frame_version": 1,
        "trust_root": BASE64_STANDARD.encode(&state.certs.trust_root_public),
        "capabilities": ["pqxdh", "sealed-sender"],
    }))
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
    Json(body): Json<RegisterIn>,
) -> ApiResult<(StatusCode, Json<RegisterOut>)> {
    if body.one_time_prekeys.len() > MAX_ONE_TIME_PREKEYS {
        return Err(bad("příliš mnoho one-time prekeys"));
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
    if inserted.rows_affected() == 0 {
        return Err((StatusCode::CONFLICT, "identita už existuje".into()));
    }

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

        // Spotřebuj jeden one-time prekey (DELETE ... RETURNING).
        let otp: Option<(i32, Vec<u8>)> = sqlx::query_as(
            "DELETE FROM one_time_prekeys
             WHERE (device_uuid, key_id) IN (
                 SELECT device_uuid, key_id FROM one_time_prekeys
                 WHERE device_uuid = $1 ORDER BY key_id LIMIT 1)
             RETURNING key_id, public_key",
        )
        .bind(&device_uuid)
        .fetch_optional(&state.pool)
        .await
        .map_err(internal)?;

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
    if (now_ms - ts).abs() > AUTH_WINDOW_MS {
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
    })
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
