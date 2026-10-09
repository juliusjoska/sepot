//! Dočasné údaje k TURN serveru pro hovory (REST schéma coturnu,
//! `use-auth-secret`). Relay i coturn sdílí tajemství; coturn údaje ověří
//! sám, bez dotazu na relay, a po expiraci je odmítne.
//!
//! Údaje dostane jen přihlášené zařízení přes WS — TURN tak neslouží jako
//! otevřené přeposílání provozu pro kohokoli z internetu.

use base64::Engine;
use hmac::{Hmac, Mac};
use rand::Rng;
use sepot_proto::v1;
use sha1::Sha1;

/// Platnost údajů. Pokrývá i dlouhý hovor — coturn kontroluje expiraci jen
/// při alokaci a jejím obnovení, ne u běžícího hovoru. Dvanáct hodin stačí
/// (dřív 24 h: zbytečně dlouhé okno pro údaje, které přežijí i smazání účtu).
pub const TTL_SECONDS: u32 = 12 * 3600;

pub struct TurnConfig {
    secret: Vec<u8>,
    urls: Vec<String>,
}

impl TurnConfig {
    /// Tajemství z `SEPOT_TURN_SECRET_FILE` (soubor mimo compose, stejně
    /// jako FCM a APNs klíče) nebo `SEPOT_TURN_SECRET`, adresy z `SEPOT_TURN_URLS`
    /// (čárkou oddělené turn:/turns:). Bez nich = hovory jen napřímo / přes
    /// STUN, relay údaje nevydává.
    pub fn from_env() -> Option<Self> {
        let secret = match std::env::var("SEPOT_TURN_SECRET_FILE") {
            Ok(path) if !path.is_empty() => std::fs::read_to_string(&path)
                .map_err(|e| tracing::warn!("TURN tajemství nejde přečíst: {e}"))
                .ok()?
                .trim()
                .to_string(),
            _ => std::env::var("SEPOT_TURN_SECRET").ok()?,
        };
        let urls: Vec<String> = std::env::var("SEPOT_TURN_URLS")
            .ok()?
            .split(',')
            .map(str::trim)
            .filter(|u| u.starts_with("turn:") || u.starts_with("turns:"))
            .map(String::from)
            .collect();
        if secret.len() < 32 || urls.is_empty() {
            tracing::warn!("TURN nenakonfigurován správně (secret < 32 znaků nebo bez URL)");
            return None;
        }
        tracing::info!(urls = urls.len(), "TURN údaje pro hovory aktivní");
        Some(Self::new(secret.into_bytes(), urls))
    }

    pub fn new(secret: Vec<u8>, urls: Vec<String>) -> Self {
        Self { secret, urls }
    }

    /// Údaje platné `TTL_SECONDS` od `now_unix`. Náhodná část jména, ne id
    /// zařízení — coturn si jména loguje a nemá z nich poznat, kdo volá.
    pub fn credentials(&self, now_unix: i64) -> v1::TurnCredentials {
        let expires = now_unix + i64::from(TTL_SECONDS);
        let nonce: u64 = rand::rng().random();
        let username = format!("{expires}:{nonce:016x}");
        v1::TurnCredentials {
            urls: self.urls.clone(),
            credential: sign(&self.secret, &username),
            username,
            ttl_seconds: TTL_SECONDS,
        }
    }
}

/// base64(HMAC-SHA1(secret, username)) — přesně to, co počítá coturn.
fn sign(secret: &[u8], username: &str) -> String {
    let mut mac =
        Hmac::<Sha1>::new_from_slice(secret).expect("HMAC bere klíč libovolné délky");
    mac.update(username.as_bytes());
    base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn podpis_odpovida_referencni_hodnote() {
        // Referenční hodnota: printf '%s' '1700000000:abc' |
        //   openssl dgst -sha1 -hmac 'tajne' -binary | base64
        assert_eq!(sign(b"tajne", "1700000000:abc"), "2PhtGxNe/gV7QGWYKw750CWo8fw=");
    }

    #[test]
    fn udaje_nesou_expiraci_a_sedi_k_podpisu() {
        let cfg = TurnConfig::new(b"x".repeat(32), vec!["turn:t.example:3478".into()]);
        let c = cfg.credentials(1_000);
        let (exp, _) = c.username.split_once(':').unwrap();
        assert_eq!(exp.parse::<i64>().unwrap(), 1_000 + i64::from(TTL_SECONDS));
        assert_eq!(c.credential, sign(&b"x".repeat(32), &c.username));
        assert_eq!(c.urls, vec!["turn:t.example:3478".to_string()]);
    }

    #[test]
    fn jmena_se_neopakuji() {
        let cfg = TurnConfig::new(b"x".repeat(32), vec!["turn:t:3478".into()]);
        assert_ne!(cfg.credentials(1).username, cfg.credentials(1).username);
    }
}
