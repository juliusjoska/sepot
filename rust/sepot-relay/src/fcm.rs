//! FCM HTTP v1 sender — opt-in „fast mode".
//!
//! Stejné tvrdé pravidlo jako u UnifiedPush: posílá se JEN konstantní
//! ťuk `{"v":1}` v data payloadu — žádný obsah, žádný odesílatel.
//! Uživatel si FCM vědomě zapíná (vystavuje svůj push token Googlu
//! výměnou za spolehlivé/rychlé buzení bez další aplikace).
//!
//! Credentials: `SEPOT_FCM_CREDENTIALS` = cesta k service account JSON
//! (Google SA s rolí Firebase Cloud Messaging Admin). Bez env proměnné
//! zůstává fast mode vypnutý a FCM registrace se tiše ignorují.
//!
//! OAuth2: RS256 JWT podepsaný SA klíčem → access token (cache do
//! expirace s 60s rezervou).

use std::sync::Arc;

use chrono::Utc;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

const FCM_SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";

#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
    token_uri: String,
}

#[derive(Serialize)]
struct Claims<'a> {
    iss: &'a str,
    scope: &'a str,
    aud: &'a str,
    iat: i64,
    exp: i64,
}

pub struct FcmSender {
    project_id: String,
    client_email: String,
    token_uri: String,
    key: EncodingKey,
    /// (access_token, expirace unix)
    cached: Mutex<Option<(String, i64)>>,
}

impl FcmSender {
    /// Načte SA credentials z `SEPOT_FCM_CREDENTIALS`. None = fast mode off.
    pub fn from_env() -> Option<Arc<FcmSender>> {
        let path = std::env::var("SEPOT_FCM_CREDENTIALS").ok()?;
        let raw = match std::fs::read(&path) {
            Ok(r) => r,
            Err(e) => {
                tracing::warn!("FCM credentials nejdou přečíst: {e}");
                return None;
            }
        };
        let sa: ServiceAccount = match serde_json::from_slice(&raw) {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!("FCM credentials nejdou parsovat: {e}");
                return None;
            }
        };
        let key = match EncodingKey::from_rsa_pem(sa.private_key.as_bytes()) {
            Ok(k) => k,
            Err(e) => {
                tracing::warn!("FCM privátní klíč nejde načíst: {e}");
                return None;
            }
        };
        tracing::info!("FCM fast mode aktivní (projekt nakonfigurován)");
        Some(Arc::new(FcmSender {
            project_id: sa.project_id,
            client_email: sa.client_email,
            token_uri: sa.token_uri,
            key,
            cached: Mutex::new(None),
        }))
    }

    async fn access_token(&self, http: &reqwest::Client) -> Option<String> {
        let now = Utc::now().timestamp();
        let mut cached = self.cached.lock().await;
        if let Some((token, exp)) = cached.as_ref() {
            if *exp > now + 60 {
                return Some(token.clone());
            }
        }

        let claims = Claims {
            iss: &self.client_email,
            scope: FCM_SCOPE,
            aud: &self.token_uri,
            iat: now,
            exp: now + 3600,
        };
        let jwt = jsonwebtoken::encode(&Header::new(Algorithm::RS256), &claims, &self.key)
            .map_err(|e| tracing::warn!("FCM JWT podpis selhal: {e}"))
            .ok()?;

        #[derive(Deserialize)]
        struct TokenOut {
            access_token: String,
            expires_in: i64,
        }
        let resp: TokenOut = http
            .post(&self.token_uri)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &jwt),
            ])
            .send()
            .await
            .ok()?
            .json()
            .await
            .map_err(|e| tracing::debug!("FCM token endpoint: {e}"))
            .ok()?;

        let token = resp.access_token.clone();
        *cached = Some((resp.access_token, now + resp.expires_in));
        Some(token)
    }

    /// Pošle budíček na FCM registrační token. Best-effort; loguje se jen
    /// stavový kód (nikdy token).
    pub async fn send_wake(&self, http: &reqwest::Client, device_token: &str) {
        let Some(access) = self.access_token(http).await else {
            return;
        };
        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );
        let body = serde_json::json!({
            "message": {
                "token": device_token,
                "data": { "v": "1" },
                "android": { "priority": "HIGH" }
            }
        });
        match http.post(&url).bearer_auth(access).json(&body).send().await {
            Ok(resp) if !resp.status().is_success() => {
                tracing::debug!(status = %resp.status(), "FCM budíček odmítnut");
            }
            Err(e) => tracing::debug!("FCM budíček selhal: {e}"),
            _ => {}
        }
    }
}
