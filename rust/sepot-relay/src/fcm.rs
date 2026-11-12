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

/// Tělo FCM budíčku. Vysokou prioritu dostane jen budíček zprávy: provozní
/// obálky nekončí notifikací a Google aplikacím, které vysokou prioritu
/// utrácejí bez ní, doručování zpomalí. Běžná priorita počká na okno údržby,
/// doručence to nevadí.
fn wake_message(device_token: &str, kind: crate::push::WakeKind) -> serde_json::Value {
    let (priority, collapse_key) = match kind {
        crate::push::WakeKind::Message => ("HIGH", "wake"),
        // Vlastní klíč: jinak by čekající tichý budíček přepsal budíček
        // zprávy (FCM drží na klíč jen poslední) a notifikace by zmizela.
        crate::push::WakeKind::Sync => ("NORMAL", "sync"),
    };
    serde_json::json!({
        "message": {
            "token": device_token,
            "data": { "v": "1", "k": kind.as_str() },
            "android": { "priority": priority, "collapse_key": collapse_key }
        }
    })
}

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
    /// stavový kód (nikdy token). Vrací `true`, když FCM token natrvalo
    /// odmítl (stejně i `send_call_wake`).
    pub async fn send_wake(
        &self,
        http: &reqwest::Client,
        device_token: &str,
        kind: crate::push::WakeKind,
    ) -> bool {
        self.send(http, wake_message(device_token, kind)).await
    }


    /// Budíček pro příchozí hovor: `k=call` spustí na telefonu zvonění
    /// a platnost je krátká — zmeškaný hovor po návratu do sítě nezvoní.
    pub async fn send_call_wake(&self, http: &reqwest::Client, device_token: &str) -> bool {
        let body = serde_json::json!({
            "message": {
                "token": device_token,
                "data": { "v": "1", "k": "call" },
                "android": {
                    "priority": "HIGH",
                    "ttl": format!("{}s", crate::apns::CALL_RING_SECONDS)
                }
            }
        });
        self.send(http, body).await
    }

    async fn send(&self, http: &reqwest::Client, body: serde_json::Value) -> bool {
        let Some(access) = self.access_token(http).await else {
            return false;
        };
        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );
        // warn, ne debug: relay běží na RUST_LOG=info, takže na debugu bylo
        // selhání pushe neviditelné a tiše se hromadila fronta. Protistranou
        // je Google, ne telefon uživatele — chyba tu znamená mrtvý token nebo
        // rozbitou konfiguraci projektu, obojí je provozní problém.
        match http.post(&url).bearer_auth(access).json(&body).send().await {
            Ok(resp) if resp.status().is_success() => false,
            Ok(resp) => {
                let status = resp.status();
                let dead = is_dead_token(status.as_u16(), &resp.text().await.unwrap_or_default());
                tracing::warn!(status = %status, dead_token = dead, "FCM budíček odmítnut");
                dead
            }
            Err(e) => {
                tracing::warn!("FCM budíček selhal: {}", e.without_url());
                false
            }
        }
    }
}

/// Odmítl FCM token natrvalo? Jen 404 s kódem `UNREGISTERED` (appka
/// odinstalovaná, token vyměněný). Holé 404 může znamenat i špatně
/// nastavený projekt a kvůli chybě v konfiguraci se tokeny mazat nesmí.
fn is_dead_token(status: u16, body: &str) -> bool {
    const NOT_FOUND: u16 = 404;
    if status != NOT_FOUND {
        return false;
    }
    serde_json::from_str::<serde_json::Value>(body).is_ok_and(|reply| {
        reply["error"]["details"]
            .as_array()
            .is_some_and(|details| details.iter().any(|d| d["errorCode"] == "UNREGISTERED"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::push::WakeKind;

    #[test]
    fn budicek_zpravy_ma_vysokou_prioritu_a_provozni_beznou() {
        let msg = wake_message("t", WakeKind::Message);
        assert_eq!(msg["message"]["data"]["k"], "msg");
        assert_eq!(msg["message"]["android"]["priority"], "HIGH");

        let sync = wake_message("t", WakeKind::Sync);
        assert_eq!(sync["message"]["data"]["k"], "sync");
        assert_eq!(sync["message"]["android"]["priority"], "NORMAL");
        assert_ne!(
            msg["message"]["android"]["collapse_key"], sync["message"]["android"]["collapse_key"],
            "tichý budíček nesmí ve frontě FCM přepsat budíček zprávy"
        );
    }

    #[test]
    fn mrtvy_token_pozna_jen_z_kodu_unregistered() {
        let unregistered = r#"{"error":{"code":404,"status":"NOT_FOUND","details":[
            {"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}"#;
        assert!(is_dead_token(404, unregistered));
        for (status, body) in [
            (404, r#"{"error":{"code":404,"status":"NOT_FOUND"}}"#),
            (404, "není JSON"),
            (400, r#"{"error":{"details":[{"errorCode":"INVALID_ARGUMENT"}]}}"#),
            (403, r#"{"error":{"details":[{"errorCode":"SENDER_ID_MISMATCH"}]}}"#),
            (429, r#"{"error":{"details":[{"errorCode":"QUOTA_EXCEEDED"}]}}"#),
            (503, unregistered),
        ] {
            assert!(!is_dead_token(status, body), "{status} {body}");
        }
    }

    #[test]
    fn budicek_nenese_nic_nez_verzi_a_druh() {
        let msg = wake_message("t", WakeKind::Message);
        let data = msg["message"]["data"].as_object().unwrap();
        assert_eq!(data.len(), 2);
        assert_eq!(data["v"], "1");
    }
}
