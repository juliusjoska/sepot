//! Dočasné údaje k TURN serveru pro hovory (REST schéma coturnu,
//! `use-auth-secret`). Relay i coturn sdílí tajemství; coturn údaje ověří
//! sám, bez dotazu na relay, a po expiraci je odmítne.
//!
//! Údaje dostane jen přihlášené zařízení přes WS — TURN tak neslouží jako
//! otevřené přeposílání provozu pro kohokoli z internetu.

use base64::Engine;
use hmac::{Hmac, Mac};
use sepot_proto::v1;
use sha1::Sha1;
use sha2::Sha256;

/// Nejdelší platnost údajů. Pokrývá i dlouhý hovor — coturn kontroluje
/// expiraci jen při alokaci a jejím obnovení, ne u běžícího hovoru. Dvanáct
/// hodin stačí (dřív 24 h: zbytečně dlouhé okno pro údaje, které přežijí
/// i smazání účtu).
pub const TTL_SECONDS: u32 = 12 * 3600;
/// Účet má v jednom okně jedno jméno. Okno je polovina platnosti a údaje
/// platí do konce okna následujícího, takže vydané údaje mají vždy aspoň
/// půl platnosti před sebou a nikdy víc než celou.
const WINDOW_SECONDS: i64 = (TTL_SECONDS / 2) as i64;
/// Kolik oken od začátku toho současného údaje platí.
const WINDOWS_VALID: i64 = 2;
/// Odděluje odvození jména od podpisu, který stejným tajemstvím počítá coturn.
const USERNAME_CONTEXT: &[u8] = b"sepot-turn-username-v1";
/// Délka značky účtu ve jménu; 8 B stačí, aby se dva účty v okně nepotkaly.
const USERNAME_TAG_BYTES: usize = 8;

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

    /// Údaje účtu pro okno, do kterého padá `now_unix`.
    ///
    /// Jméno je v okně pro účet pořád stejné. Dřív neslo náhodnou část a
    /// stačilo se připojit znovu, aby relay vydal další: kvóta coturnu je na
    /// jméno, takže jeden účet si nasbíral libovolně mnoho jmen a s nimi
    /// libovolně mnoho přenosové kapacity. Teď má účet jedno jméno a kvóta
    /// coturnu (`user-quota`) platí na účet.
    ///
    /// Jméno není id účtu ani zařízení, ale HMAC z něj — coturn si jména
    /// loguje a nemá z nich poznat, kdo volá, ani spojit hovory téhož účtu
    /// napříč okny.
    pub fn credentials(&self, account_id: &[u8], now_unix: i64) -> v1::TurnCredentials {
        let window = now_unix.div_euclid(WINDOW_SECONDS);
        let expires = (window + WINDOWS_VALID) * WINDOW_SECONDS;
        let username = format!("{expires}:{}", self.account_tag(account_id, window));
        v1::TurnCredentials {
            urls: self.urls.clone(),
            credential: sign(&self.secret, &username),
            username,
            ttl_seconds: u32::try_from(expires - now_unix).unwrap_or(TTL_SECONDS),
        }
    }

    fn account_tag(&self, account_id: &[u8], window: i64) -> String {
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.secret)
            .expect("HMAC bere klíč libovolné délky");
        mac.update(USERNAME_CONTEXT);
        mac.update(&window.to_be_bytes());
        mac.update(account_id);
        hex::encode(&mac.finalize().into_bytes()[..USERNAME_TAG_BYTES])
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

    const NOW: i64 = 1_700_000_000;

    fn config() -> TurnConfig {
        TurnConfig::new(b"x".repeat(32), vec!["turn:t.example:3478".into()])
    }

    #[test]
    fn udaje_nesou_expiraci_a_sedi_k_podpisu() {
        let c = config().credentials(b"ucet", NOW);
        let (exp, _) = c.username.split_once(':').unwrap();
        let expires = exp.parse::<i64>().unwrap();
        assert_eq!(expires - NOW, i64::from(c.ttl_seconds));
        assert_eq!(c.credential, sign(&b"x".repeat(32), &c.username));
        assert_eq!(c.urls, vec!["turn:t.example:3478".to_string()]);
    }

    /// Opakovaná žádost ani nové spojení nevyrobí další jméno.
    #[test]
    fn ucet_ma_v_okne_jedine_jmeno() {
        let cfg = config();
        let window_start = NOW.div_euclid(WINDOW_SECONDS) * WINDOW_SECONDS;
        let first = cfg.credentials(b"ucet", window_start);
        let last = cfg.credentials(b"ucet", window_start + WINDOW_SECONDS - 1);
        assert_eq!(first.username, last.username);
        assert_eq!(first.credential, last.credential);
        assert_ne!(
            first.username,
            cfg.credentials(b"jiny", window_start).username,
            "jiný účet"
        );
        assert_ne!(
            first.username,
            cfg.credentials(b"ucet", window_start + WINDOW_SECONDS).username,
            "další okno"
        );
    }

    #[test]
    fn platnost_je_pul_az_cela() {
        let cfg = config();
        let window_start = NOW.div_euclid(WINDOW_SECONDS) * WINDOW_SECONDS;
        assert_eq!(cfg.credentials(b"ucet", window_start).ttl_seconds, TTL_SECONDS);
        assert_eq!(
            cfg.credentials(b"ucet", window_start + WINDOW_SECONDS - 1).ttl_seconds,
            TTL_SECONDS / 2 + 1
        );
    }

    /// Jméno nesmí prozradit účet ani jít spojit mezi okny bez tajemství.
    #[test]
    fn jmeno_neobsahuje_id_uctu() {
        let account = [0xABu8; 16];
        let c = config().credentials(&account, NOW);
        assert!(!c.username.contains(&hex::encode(account)));
        let other_secret = TurnConfig::new(b"y".repeat(32), vec!["turn:t:3478".into()]);
        assert_ne!(c.username, other_secret.credentials(&account, NOW).username);
    }
}
