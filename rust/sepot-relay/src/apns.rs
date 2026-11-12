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

/// Obecná notifikace o nové zprávě. Klíč `PUSH_NEW_MESSAGE` je v
/// `Localizable.strings` appky; bez něj by iPhone ukázal holý klíč.
const MESSAGE_ALERT_BODY: &str = r#"{"aps":{"alert":{"loc-key":"PUSH_NEW_MESSAGE"},"sound":"default","mutable-content":1},"k":"msg"}"#;

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

/// Meze délky device tokenu v hex znacích. Dnes má 64 znaků, Apple ale
/// délku nezaručuje a radí ji nepředpokládat; horní mez nechává rezervu.
const DEVICE_TOKEN_MIN_HEX: usize = 64;
const DEVICE_TOKEN_MAX_HEX: usize = 200;

/// Token jde do cesty URL (`/3/device/<token>`), a posílá ho klient. Bez
/// kontroly by `../` nebo `?` v tokenu poslalo požadavek s přihlášením
/// relaye na jinou cestu APNs.
pub fn valid_device_token(token: &str) -> bool {
    (DEVICE_TOKEN_MIN_HEX..=DEVICE_TOKEN_MAX_HEX).contains(&token.len())
        && token.len() % 2 == 0
        && token.bytes().all(|b| b.is_ascii_hexdigit())
}

/// Odmítl APNs token natrvalo? 410 = appka odinstalovaná nebo token
/// vyměněný; 400 `BadDeviceToken` = token nepatří tomuhle prostředí APNs.
/// Jiná odmítnutí (přetížení, prošlé přihlášení relaye, špatný topic)
/// o tokenu nic neříkají.
fn is_dead_token(status: u16, body: &str) -> bool {
    const GONE: u16 = 410;
    const BAD_REQUEST: u16 = 400;
    match status {
        GONE => true,
        BAD_REQUEST => serde_json::from_str::<serde_json::Value>(body)
            .is_ok_and(|reply| reply["reason"] == "BadDeviceToken"),
        _ => false,
    }
}

/// Texty do logu pro jeden druh pushe.
struct LogLabels {
    rejected: &'static str,
    failed: &'static str,
}

const WAKE_LABELS: LogLabels = LogLabels {
    rejected: "APNs budíček odmítnut",
    failed: "APNs budíček selhal",
};
const ALERT_LABELS: LogLabels = LogLabels {
    rejected: "APNs notifikace odmítnuta",
    failed: "APNs notifikace selhala",
};
const VOIP_LABELS: LogLabels = LogLabels {
    rejected: "APNs VoIP push odmítnut",
    failed: "APNs VoIP push selhal",
};

/// Vyhodnotí odpověď APNs; `true` = token je natrvalo mrtvý. Loguje jen
/// stav, nikdy token.
async fn token_is_dead(resp: reqwest::Result<reqwest::Response>, labels: &LogLabels) -> bool {
    match resp {
        Ok(r) if r.status().is_success() => false,
        Ok(r) => {
            let status = r.status();
            let dead = is_dead_token(status.as_u16(), &r.text().await.unwrap_or_default());
            // warn, ne debug — viz shodný komentář ve fcm.rs: na RUST_LOG=info
            // bylo selhání pushe neviditelné.
            tracing::warn!(status = %status, dead_token = dead, "{}", labels.rejected);
            dead
        }
        // without_url: URL nese device token.
        Err(e) => {
            tracing::warn!("{}: {}", labels.failed, e.without_url());
            false
        }
    }
}

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
    ///
    /// Vrací `true`, když APNs token natrvalo odmítl (stejně i ostatní
    /// odesílací funkce).
    pub async fn send_wake(&self, client: &reqwest::Client, device_token: &str) -> bool {
        if !valid_device_token(device_token) {
            return false;
        }
        let Some(jwt) = self.auth_token().await else {
            return false;
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
        token_is_dead(resp, &WAKE_LABELS).await
    }

    /// Viditelná notifikace o nové zprávě. Text si iPhone vezme z vlastní
    /// lokalizace appky (`loc-key`), takže relay jazyk uživatele nezná.
    /// `mutable-content` nechává prostor rozšíření appky (NSE), které text
    /// nahradí dešifrovaným odesílatelem a obsahem. Víc notifikací APNs
    /// sloučí do jedné (collapse-id), `k` appce řekne, že jde o tenhle druh.
    pub async fn send_message_alert(&self, client: &reqwest::Client, device_token: &str) -> bool {
        if !valid_device_token(device_token) {
            return false;
        }
        let Some(jwt) = self.auth_token().await else {
            return false;
        };
        let url = format!("{}/3/device/{}", self.host, device_token);
        let resp = client
            .post(&url)
            .header("authorization", format!("bearer {jwt}"))
            .header("apns-topic", &self.topic)
            .header("apns-push-type", "alert")
            .header("apns-priority", "10")
            .header("apns-expiration", wake_expiration(Utc::now()).to_string())
            .header("apns-collapse-id", "msg")
            .body(MESSAGE_ALERT_BODY)
            .send()
            .await;
        token_is_dead(resp, &ALERT_LABELS).await
    }

    /// VoIP push (PushKit) pro příchozí hovor. iOS po něm MUSÍ hned ukázat
    /// hovor v CallKit — to zařídí appka. Topic je `<bundle>.voip`, priorita
    /// 10 (u typu voip povolená) a krátká expirace: zvonit po minutě nemá
    /// smysl.
    pub async fn send_voip_call(&self, client: &reqwest::Client, voip_token: &str) -> bool {
        if !valid_device_token(voip_token) {
            return false;
        }
        let Some(jwt) = self.auth_token().await else {
            return false;
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
        token_is_dead(resp, &VOIP_LABELS).await
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
    #[test]
    fn notifikace_o_zprave_nenese_obsah_ani_odesilatele() {
        let v: serde_json::Value = serde_json::from_str(MESSAGE_ALERT_BODY).unwrap();
        let aps = &v["aps"];
        assert_eq!(aps["alert"]["loc-key"], "PUSH_NEW_MESSAGE");
        assert_eq!(aps["mutable-content"], 1);
        assert_eq!(v.as_object().unwrap().len(), 2, "jen aps a k");
        assert_eq!(aps["alert"].as_object().unwrap().len(), 1, "jen loc-key");
    }

    /// Token jde do cesty URL: projít smí jen hex.
    #[test]
    fn device_token_musi_byt_hex() {
        let token = "a1".repeat(32);
        assert!(valid_device_token(&token));
        assert!(valid_device_token(&token.to_uppercase()));
        assert!(valid_device_token(&"0f".repeat(50)), "delší token Apple nevylučuje");
        for bad in [
            String::new(),
            "a1".repeat(31),
            format!("{}a", "a1".repeat(32)),
            "a1".repeat(101),
            format!("{}/../x", "a1".repeat(32)),
            format!("../../{}", "a1".repeat(29)),
            format!("{}?x=1", "a1".repeat(30)),
            format!("{}%2f", "a1".repeat(30)),
            "zz".repeat(32),
        ] {
            assert!(!valid_device_token(&bad), "{bad}");
        }
    }

    #[test]
    fn mrtvy_token_pozna_jen_z_jasne_odpovedi() {
        assert!(is_dead_token(410, r#"{"reason":"Unregistered","timestamp":1}"#));
        assert!(is_dead_token(410, ""));
        assert!(is_dead_token(400, r#"{"reason":"BadDeviceToken"}"#));
        for (status, body) in [
            (400, r#"{"reason":"BadTopic"}"#),
            (400, r#"{"reason":"DeviceTokenNotForTopic"}"#),
            (400, "není JSON"),
            (403, r#"{"reason":"ExpiredProviderToken"}"#),
            (429, r#"{"reason":"TooManyRequests"}"#),
            (503, r#"{"reason":"ServiceUnavailable"}"#),
        ] {
            assert!(!is_dead_token(status, body), "{status} {body}");
        }
    }

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
