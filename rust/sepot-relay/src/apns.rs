//! APNs sender — nativní iOS push, BEZ Googlu.
//!
//! Pro privacy messenger je na iOS správné buzení přímo přes Apple Push
//! Notification service, ne přes Firebase (žádný Google v cestě). Stejné
//! tvrdé pravidlo jako všude: posílá se JEN tichý „background" budíček
//! `{"aps":{"content-available":1}}` — žádný obsah, žádný odesílatel.
//! Klient se po probuzení sám připojí na WS a vyleje frontu.
//!
//! Credentials (env): `SEPOT_APNS_CREDENTIALS` = cesta k APNs auth key
//! (.p8, EC private key z Apple Developer → Keys), `SEPOT_APNS_KEY_ID`,
//! `SEPOT_APNS_TEAM_ID`, `SEPOT_APNS_TOPIC` (= bundle id cz.sepot.sepot).
//! `SEPOT_APNS_PRODUCTION` (default true; TestFlight i App Store =
//! production APNs, jen debug build z Xcode jede sandbox).
//! Bez env proměnných zůstává APNs vypnutý a registrace se tiše ignorují.
//!
//! Auth: ES256 JWT (iss=team, iat=now) podepsaný APNs klíčem, platný ~1 h,
//! sdílený přes všechny odeslání (cache, refresh po 50 min).

use std::sync::Arc;

use chrono::{DateTime, Utc};
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::Serialize;
use tokio::sync::Mutex;

const PROD_HOST: &str = "https://api.push.apple.com";
const SANDBOX_HOST: &str = "https://api.sandbox.push.apple.com";

/// Do kdy má APNs budíček držet, když telefon zrovna není v síti (tunel,
/// letadlo). S `apns-expiration: 0` ho APNs zkusí jen jednou a zahodí —
/// telefon po návratu do sítě pak o zprávě neví, dokud appku někdo neotevře.
/// Déle než obálka ve frontě relaye nemá budíček smysl; APNs sám drží
/// nejvýš 30 dní.
fn wake_expiration(now: DateTime<Utc>) -> i64 {
    (now + chrono::Duration::days(crate::state::QUEUE_TTL_DAYS)).timestamp()
}

/// Jak dlouho může zvonit hovor, který telefon nezastihl hned. Stejná mez
/// jako u klienta: nabídka starší než tohle se už nezvoní, jen zapíše jako
/// zmeškaná.
pub const CALL_RING_SECONDS: i64 = 45;

#[derive(Serialize)]
struct Claims<'a> {
    iss: &'a str,
    iat: i64,
}

pub struct ApnsSender {
    team_id: String,
    key_id: String,
    topic: String,
    host: &'static str,
    key: EncodingKey,
    /// (jwt, vydáno_unix)
    cached: Mutex<Option<(String, i64)>>,
}

impl ApnsSender {
    /// Načte APNs credentials z env. None = iOS nativní push vypnutý.
    pub fn from_env() -> Option<Arc<ApnsSender>> {
        let path = std::env::var("SEPOT_APNS_CREDENTIALS").ok()?;
        let key_id = std::env::var("SEPOT_APNS_KEY_ID").ok()?;
        let team_id = std::env::var("SEPOT_APNS_TEAM_ID").ok()?;
        let topic =
            std::env::var("SEPOT_APNS_TOPIC").unwrap_or_else(|_| "cz.sepot.sepot".into());
        let production = std::env::var("SEPOT_APNS_PRODUCTION")
            .map(|v| v != "false" && v != "0")
            .unwrap_or(true);

        let pem = match std::fs::read(&path) {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("APNs klíč nejde přečíst: {e}");
                return None;
            }
        };
        let key = match EncodingKey::from_ec_pem(&pem) {
            Ok(k) => k,
            Err(e) => {
                tracing::warn!("APNs klíč (.p8) nejde načíst: {e}");
                return None;
            }
        };
        tracing::info!(production, "APNs nativní push aktivní");
        Some(Arc::new(ApnsSender {
            team_id,
            key_id,
            topic,
            host: if production { PROD_HOST } else { SANDBOX_HOST },
            key,
            cached: Mutex::new(None),
        }))
    }

    async fn auth_token(&self) -> Option<String> {
        let now = Utc::now().timestamp();
        let mut cached = self.cached.lock().await;
        if let Some((jwt, issued)) = cached.as_ref() {
            // APNs token platí max 1 h; refresh po 50 min (a min 20 s starý)
            if now - issued < 3000 {
                return Some(jwt.clone());
            }
        }
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let jwt = jsonwebtoken::encode(
            &header,
            &Claims {
                iss: &self.team_id,
                iat: now,
            },
            &self.key,
        )
        .map_err(|e| tracing::warn!("APNs JWT podpis selhal: {e}"))
        .ok()?;
        *cached = Some((jwt.clone(), now));
        Some(jwt)
    }

    /// Tichý budíček na APNs device token. Best-effort; loguje jen stav
    /// (nikdy token). `apns-push-type: background` + `content-available:1`
    /// = probuzení bez viditelné notifikace (tu si klient případně ukáže
    /// lokálně sám, bez obsahu).
    ///
    /// Priorita musí zůstat 5: u typu `background` APNs prioritu 10 odmítá
    /// jako chybu a iOS takové budíčky doručuje podle stavu baterie. Okamžité
    /// doručení umí jen viditelná notifikace (`alert` + `mutable-content`),
    /// kterou appka v Notification Service Extension nahradí — to je změna
    /// appky, ne jen relaye.
    pub async fn send_wake(&self, client: &reqwest::Client, device_token: &str) {
        let Some(jwt) = self.auth_token().await else {
            return;
        };
        let url = format!("{}/3/device/{}", self.host, device_token);
        let resp = client
            .post(&url)
            .header("authorization", format!("bearer {jwt}"))
            .header("apns-topic", &self.topic)
            .header("apns-push-type", "background")
            .header("apns-priority", "5")
            .header("apns-expiration", wake_expiration(Utc::now()).to_string())
            // Víc budíčků pro jedno zařízení APNs sloučí do jednoho.
            .header("apns-collapse-id", "wake")
            .body(r#"{"aps":{"content-available":1}}"#)
            .send()
            .await;
        // warn, ne debug — viz shodný komentář ve fcm.rs: na RUST_LOG=info
        // bylo selhání pushe neviditelné.
        match resp {
            Ok(r) if !r.status().is_success() => {
                tracing::warn!(status = %r.status(), "APNs budíček odmítnut");
            }
            // without_url: URL nese device token.
            Err(e) => tracing::warn!("APNs budíček selhal: {}", e.without_url()),
            _ => {}
        }
    }

    /// VoIP push (PushKit) pro příchozí hovor. iOS po něm MUSÍ hned ukázat
    /// hovor v CallKit — to zařídí appka. Topic je `<bundle>.voip`, priorita
    /// 10 (u typu voip povolená) a krátká expirace: zvonit po minutě nemá
    /// smysl.
    pub async fn send_voip_call(&self, client: &reqwest::Client, voip_token: &str) {
        let Some(jwt) = self.auth_token().await else {
            return;
        };
        let url = format!("{}/3/device/{}", self.host, voip_token);
        let expiration = Utc::now().timestamp() + CALL_RING_SECONDS;
        let resp = client
            .post(&url)
            .header("authorization", format!("bearer {jwt}"))
            .header("apns-topic", format!("{}.voip", self.topic))
            .header("apns-push-type", "voip")
            .header("apns-priority", "10")
            .header("apns-expiration", expiration.to_string())
            .body(r#"{"aps":{},"k":"call"}"#)
            .send()
            .await;
        match resp {
            Ok(r) if !r.status().is_success() => {
                tracing::warn!(status = %r.status(), "APNs VoIP push odmítnut");
            }
            Err(e) => tracing::warn!("APNs VoIP push selhal: {}", e.without_url()),
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budicek_drzi_apns_stejne_dlouho_jako_fronta() {
        let ted = DateTime::parse_from_rfc3339("2026-09-29T18:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let limit = wake_expiration(ted) - ted.timestamp();
        assert_eq!(limit, crate::state::QUEUE_TTL_DAYS * 86_400);
        assert!(limit <= 30 * 86_400, "APNs nedrží notifikace déle než 30 dní");
    }
    

    /// APNs mluví jen HTTP/2. Bez featury `http2` v reqwestu relay spojení
    /// vůbec nenaváže a iPhone žádný budíček nedostane. Bez platného JWT
    /// vrátí Apple 403 (nebo 400) — to stačí: spojení i protokol sedí.
    #[tokio::test]
    #[ignore = "vyžaduje síť (api.push.apple.com)"]
    async fn apns_spojeni_jde_pres_http2() {
        let client = crate::push::build_client();
        let res = client
            .post(format!("{PROD_HOST}/3/device/00"))
            .header("apns-topic", "cz.sepot.sepot")
            .body("{}")
            .send()
            .await
            .expect("spojení s APNs");
        assert_eq!(res.version(), reqwest::Version::HTTP_2);
        assert!(
            matches!(res.status().as_u16(), 400 | 403),
            "čekána odpověď APNs bez platného tokenu, přišlo {}",
            res.status()
        );
    }
}
