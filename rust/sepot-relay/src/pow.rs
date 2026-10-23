//! Proof-of-work při registraci (`GET /v1/register/challenge`).
//!
//! Proč: registrace je jediný anonymní zápis do DB. Limit per IP nejde
//! utáhnout (za CGNAT mobilního operátora sdílí jednu IPv4 stovky lidí)
//! a proti záplavě z mnoha adres stojí jen globální strop, který zablokuje
//! i skutečné lidi. PoW zdraží každou registraci výpočtem na straně klienta;
//! kdo ho přinese, dostane volnější limit per IP.
//!
//! Úloha (hashcash): `SHA-256("sepot-register-pow-v1" ‖ výzva ‖ identity_key
//! ‖ counter_be64)` má aspoň `bits` úvodních nulových bitů. Ověření = jedna
//! HMAC a jedna SHA-256 — levné i pod náporem, proto ne Argon2 (paměťově
//! náročné ověření by relay pod záplavou sám přetížilo).
//!
//! Výzva je bezstavová: verze, obtížnost, expirace a náhodná nonce podepsané
//! HMAC klíčem, který vzniká náhodně při startu procesu. Nic se neukládá do DB
//! ani do `.env`; restart relaye zneplatní rozdané výzvy (klient si vyžádá
//! novou) a tím i znovupoužití řešení přes restart. Jednorázovost v rámci
//! běhu hlídá paměťová sada spotřebovaných nonce, mazaná po expiraci.
//!
//! Stejné testovací vektory má klient (app/lib/core/network/register_pow.dart).

use std::sync::Mutex;
use std::time::{Duration, Instant};

use axum::http::HeaderMap;
use base64::prelude::*;
use dashmap::DashMap;
use hmac::{Hmac, Mac};
use rand::RngCore;
use sha2::{Digest, Sha256};

const DOMAIN: &[u8] = b"sepot-register-pow-v1";
const VERSION: u8 = 1;
const NONCE_LEN: usize = 16;
const TAG_LEN: usize = 16;
/// verze(1) ‖ bits(1) ‖ expirace unix s (8, BE) ‖ nonce(16) ‖ HMAC(16)
pub const TOKEN_LEN: usize = 2 + 8 + NONCE_LEN + TAG_LEN;
const SIGNED_LEN: usize = TOKEN_LEN - TAG_LEN;
/// Strop obtížnosti: 2^32 pokusů je na telefonu přes hodinu — víc nemá smysl
/// nastavovat ani adaptivně.
const MAX_BITS: u8 = 32;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Relay výzvy nevydává (`/v1/register/challenge` = 404), registruje jako dřív.
    Off,
    /// Výzvy vydává, registrace bez PoW projde s běžným limitem per IP,
    /// s platným PoW s volnějším. Výchozí — appky v obchodech PoW neumí.
    Optional,
    /// Registrace bez platného PoW = 428. Nouzová páka; staré appky se
    /// nezaregistrují.
    Required,
}

impl Mode {
    pub fn as_str(self) -> &'static str {
        match self {
            Mode::Off => "off",
            Mode::Optional => "optional",
            Mode::Required => "required",
        }
    }

    fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "off" | "0" => Some(Mode::Off),
            "optional" => Some(Mode::Optional),
            "required" | "1" => Some(Mode::Required),
            _ => None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Config {
    /// `SEPOT_REGISTER_POW` (off | optional | required), výchozí optional.
    pub mode: Mode,
    /// `SEPOT_REGISTER_POW_BITS`: základní obtížnost (výchozí 18 ≈ 0,3 s na
    /// x86 jádře, ~1 s na středním Androidu — měření v README relaye).
    pub bits: u8,
    /// `SEPOT_REGISTER_POW_MAX_BITS`: strop adaptivní obtížnosti (výchozí 22).
    pub max_bits: u8,
    /// `SEPOT_REGISTER_POW_ADAPT_PER_MIN`: od kolika registrací za minutu
    /// (všech, s PoW i bez) přidávat obtížnost — +1 bit za každé zdvojnásobení
    /// nad prahem. 0 = obtížnost pevná (výchozí 600 = 10/s, ~10× nad odhadem
    /// běžné špičky; při útoku se zdraží registrace jen těm, kdo PoW posílají,
    /// ostatní drží limity per IP a globální strop).
    pub adapt_per_min: u32,
    /// `SEPOT_REGISTER_POW_TTL_S`: platnost výzvy (výchozí 120 s; pomalý telefon
    /// při 20 bitech potřebuje v 99 % případů pod 60 s).
    pub ttl: Duration,
}

impl Config {
    pub fn from_env() -> Self {
        let mode = match std::env::var("SEPOT_REGISTER_POW") {
            Ok(raw) => Mode::parse(&raw).unwrap_or_else(|| {
                tracing::warn!("SEPOT_REGISTER_POW neplatná hodnota, platí optional");
                Mode::Optional
            }),
            Err(_) => Mode::Optional,
        };
        let bits = env_u64("SEPOT_REGISTER_POW_BITS", 18).clamp(1, MAX_BITS as u64) as u8;
        let max_bits =
            env_u64("SEPOT_REGISTER_POW_MAX_BITS", 22).clamp(bits as u64, MAX_BITS as u64) as u8;
        Self {
            mode,
            bits,
            max_bits,
            adapt_per_min: env_u64("SEPOT_REGISTER_POW_ADAPT_PER_MIN", 600) as u32,
            ttl: Duration::from_secs(env_u64("SEPOT_REGISTER_POW_TTL_S", 120).clamp(10, 3600)),
        }
    }
}

fn env_u64(name: &str, default: u64) -> u64 {
    match std::env::var(name) {
        Ok(raw) => raw.trim().parse().unwrap_or_else(|_| {
            tracing::warn!(name, "neplatná hodnota, platí výchozí");
            default
        }),
        Err(_) => default,
    }
}

/// Výsledek kontroly hlavičky `X-Sepot-Pow`.
#[derive(Debug, PartialEq, Eq)]
pub enum Verdict {
    Valid,
    Missing,
    Invalid(&'static str),
}

/// Výzva pro klienta (`GET /v1/register/challenge`).
pub struct Challenge {
    pub token: [u8; TOKEN_LEN],
    pub bits: u8,
    pub expires_at: u64,
}

pub struct RegisterPow {
    pub cfg: Config,
    key: [u8; 32],
    /// nonce → expirace (unix s). Jen spotřebované výzvy; velikost drží
    /// globální strop registrací × TTL.
    used: DashMap<[u8; NONCE_LEN], u64>,
    /// (začátek aktuální minuty, registrace v ní, registrace v minulé minutě)
    load: Mutex<(Instant, u32, u32)>,
}

impl RegisterPow {
    pub fn new(cfg: Config) -> Self {
        let mut key = [0u8; 32];
        rand::rng().fill_bytes(&mut key);
        Self {
            cfg,
            key,
            used: DashMap::new(),
            load: Mutex::new((Instant::now(), 0, 0)),
        }
    }

    pub fn mode(&self) -> Mode {
        self.cfg.mode
    }

    fn mac(&self, signed: &[u8]) -> Hmac<Sha256> {
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.key).expect("HMAC bere libovolný klíč");
        mac.update(signed);
        mac
    }

    pub fn issue(&self, now_unix: u64) -> Challenge {
        let bits = self.current_bits();
        let expires_at = now_unix + self.cfg.ttl.as_secs();
        let mut token = [0u8; TOKEN_LEN];
        token[0] = VERSION;
        token[1] = bits;
        token[2..10].copy_from_slice(&expires_at.to_be_bytes());
        rand::rng().fill_bytes(&mut token[10..10 + NONCE_LEN]);
        let tag = self.mac(&token[..SIGNED_LEN]).finalize().into_bytes();
        token[SIGNED_LEN..].copy_from_slice(&tag[..TAG_LEN]);
        Challenge {
            token,
            bits,
            expires_at,
        }
    }

    /// Ověří `X-Sepot-Pow: <výzva base64url>.<counter>` vůči identity klíči
    /// registrace. Platné řešení se tím spotřebuje (druhé použití = Invalid).
    pub fn verify(&self, headers: &HeaderMap, identity_key: &[u8], now_unix: u64) -> Verdict {
        let Some(raw) = headers.get("x-sepot-pow").and_then(|v| v.to_str().ok()) else {
            return Verdict::Missing;
        };
        let Some((token_b64, counter_str)) = raw.trim().split_once('.') else {
            return Verdict::Invalid("formát");
        };
        let Ok(token) = BASE64_URL_SAFE_NO_PAD.decode(token_b64) else {
            return Verdict::Invalid("formát");
        };
        let Ok(counter) = counter_str.parse::<u64>() else {
            return Verdict::Invalid("formát");
        };
        if token.len() != TOKEN_LEN || token[0] != VERSION {
            return Verdict::Invalid("formát");
        }
        if self
            .mac(&token[..SIGNED_LEN])
            .verify_truncated_left(&token[SIGNED_LEN..])
            .is_err()
        {
            return Verdict::Invalid("podpis");
        }
        let expires_at = u64::from_be_bytes(token[2..10].try_into().expect("8 B"));
        if now_unix > expires_at {
            return Verdict::Invalid("prošlá");
        }
        if leading_zero_bits(&digest(&token, identity_key, counter)) < token[1] as u32 {
            return Verdict::Invalid("řešení");
        }
        let nonce: [u8; NONCE_LEN] = token[10..10 + NONCE_LEN].try_into().expect("16 B");
        // entry = atomické vložení: dva souběžné požadavky se stejným řešením
        // neprojdou oba.
        match self.used.entry(nonce) {
            dashmap::Entry::Occupied(_) => Verdict::Invalid("použitá"),
            dashmap::Entry::Vacant(slot) => {
                slot.insert(expires_at);
                Verdict::Valid
            }
        }
    }

    /// Započítá registraci do zátěže pro adaptivní obtížnost.
    pub fn note_registration(&self) {
        let mut load = self.load.lock().expect("zámek zátěže");
        roll_window(&mut load, Instant::now());
        load.1 = load.1.saturating_add(1);
    }

    /// Obtížnost pro novou výzvu: základ + 1 bit za každé zdvojnásobení
    /// zátěže nad prahem (větší z aktuální a minulé minuty, ať obtížnost
    /// nespadne hned na začátku nové minuty).
    pub fn current_bits(&self) -> u8 {
        if self.cfg.adapt_per_min == 0 {
            return self.cfg.bits;
        }
        let per_min = {
            let mut load = self.load.lock().expect("zámek zátěže");
            roll_window(&mut load, Instant::now());
            load.1.max(load.2)
        };
        self.cfg
            .bits
            .saturating_add(extra_bits(per_min, self.cfg.adapt_per_min))
            .min(self.cfg.max_bits)
    }

    /// Zapomene spotřebované výzvy po expiraci (periodická úloha).
    pub fn prune(&self, now_unix: u64) {
        self.used.retain(|_, expires_at| *expires_at >= now_unix);
    }
}

fn roll_window(load: &mut (Instant, u32, u32), now: Instant) {
    const MINUTE: Duration = Duration::from_secs(60);
    let elapsed = now.duration_since(load.0);
    if elapsed >= MINUTE {
        // Víc než dvě minuty bez registrace = minulá minuta byla prázdná.
        load.2 = if elapsed >= 2 * MINUTE { 0 } else { load.1 };
        load.1 = 0;
        load.0 = now;
    }
}

fn extra_bits(per_min: u32, threshold: u32) -> u8 {
    if per_min < threshold {
        return 0;
    }
    // per_min ≥ práh → +1, ≥ 2× práh → +2, ≥ 4× → +3 …
    let ratio = per_min / threshold;
    (32 - ratio.leading_zeros()) as u8
}

pub fn digest(token: &[u8], identity_key: &[u8], counter: u64) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(DOMAIN);
    h.update(token);
    h.update(identity_key);
    h.update(counter.to_be_bytes());
    h.finalize().into()
}

pub fn leading_zero_bits(digest: &[u8; 32]) -> u32 {
    let mut bits = 0;
    for byte in digest {
        if *byte == 0 {
            bits += 8;
        } else {
            return bits + byte.leading_zeros();
        }
    }
    bits
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    fn cfg(mode: Mode, bits: u8) -> Config {
        Config {
            mode,
            bits,
            max_bits: 22,
            adapt_per_min: 0,
            ttl: Duration::from_secs(120),
        }
    }

    fn solve(token: &[u8], identity_key: &[u8], bits: u8) -> u64 {
        (0u64..)
            .find(|c| leading_zero_bits(&digest(token, identity_key, *c)) >= bits as u32)
            .unwrap()
    }

    fn header(token: &[u8], counter: u64) -> HeaderMap {
        let mut h = HeaderMap::new();
        let value = format!("{}.{counter}", BASE64_URL_SAFE_NO_PAD.encode(token));
        h.insert("x-sepot-pow", HeaderValue::from_str(&value).unwrap());
        h
    }

    const NOW: u64 = 1_800_000_000;
    const IK: [u8; 33] = [5u8; 33];

    #[test]
    fn platne_reseni_projde_jednou() {
        let pow = RegisterPow::new(cfg(Mode::Optional, 8));
        let ch = pow.issue(NOW);
        assert_eq!(ch.expires_at, NOW + 120);
        let counter = solve(&ch.token, &IK, ch.bits);
        assert_eq!(
            pow.verify(&header(&ch.token, counter), &IK, NOW),
            Verdict::Valid
        );
        assert_eq!(
            pow.verify(&header(&ch.token, counter), &IK, NOW),
            Verdict::Invalid("použitá")
        );
    }

    #[test]
    fn chybejici_a_poskozena_hlavicka() {
        let pow = RegisterPow::new(cfg(Mode::Optional, 8));
        assert_eq!(pow.verify(&HeaderMap::new(), &IK, NOW), Verdict::Missing);
        let mut h = HeaderMap::new();
        h.insert("x-sepot-pow", HeaderValue::from_static("bez-tecky"));
        assert_eq!(pow.verify(&h, &IK, NOW), Verdict::Invalid("formát"));
        h.insert("x-sepot-pow", HeaderValue::from_static("AAAA.12"));
        assert_eq!(pow.verify(&h, &IK, NOW), Verdict::Invalid("formát"));
    }

    #[test]
    fn spatne_reseni_a_jiny_identity_klic() {
        let pow = RegisterPow::new(cfg(Mode::Optional, 12));
        let ch = pow.issue(NOW);
        let counter = solve(&ch.token, &IK, ch.bits);
        let bad = (0u64..)
            .find(|c| leading_zero_bits(&digest(&ch.token, &IK, *c)) < 12)
            .unwrap();
        assert_eq!(
            pow.verify(&header(&ch.token, bad), &IK, NOW),
            Verdict::Invalid("řešení")
        );
        // řešení je vázané na identitu — pro jiný účet neplatí (bez spotřeby)
        let other = [6u8; 33];
        if leading_zero_bits(&digest(&ch.token, &other, counter)) < 12 {
            assert_eq!(
                pow.verify(&header(&ch.token, counter), &other, NOW),
                Verdict::Invalid("řešení")
            );
        }
        assert_eq!(
            pow.verify(&header(&ch.token, counter), &IK, NOW),
            Verdict::Valid
        );
    }

    #[test]
    fn prosla_vyzva() {
        let pow = RegisterPow::new(cfg(Mode::Optional, 8));
        let ch = pow.issue(NOW);
        let counter = solve(&ch.token, &IK, ch.bits);
        assert_eq!(
            pow.verify(&header(&ch.token, counter), &IK, NOW + 121),
            Verdict::Invalid("prošlá")
        );
    }

    #[test]
    fn podvrzena_obtiznost_nebo_cizi_klic() {
        let pow = RegisterPow::new(cfg(Mode::Optional, 16));
        let mut ch = pow.issue(NOW);
        // klient si sníží obtížnost v tokenu → HMAC nesedí
        ch.token[1] = 1;
        assert_eq!(
            pow.verify(&header(&ch.token, 0), &IK, NOW),
            Verdict::Invalid("podpis")
        );
        // výzva jiného procesu relaye (jiný klíč, např. před restartem)
        let jiny = RegisterPow::new(cfg(Mode::Optional, 8));
        let ch = jiny.issue(NOW);
        let counter = solve(&ch.token, &IK, ch.bits);
        assert_eq!(
            pow.verify(&header(&ch.token, counter), &IK, NOW),
            Verdict::Invalid("podpis")
        );
    }

    #[test]
    fn prune_maze_jen_prosle() {
        let pow = RegisterPow::new(cfg(Mode::Optional, 4));
        let ch = pow.issue(NOW);
        let counter = solve(&ch.token, &IK, ch.bits);
        assert_eq!(
            pow.verify(&header(&ch.token, counter), &IK, NOW),
            Verdict::Valid
        );
        pow.prune(NOW);
        assert_eq!(pow.used.len(), 1);
        pow.prune(NOW + 121);
        assert_eq!(pow.used.len(), 0);
    }

    #[test]
    fn adaptivni_obtiznost() {
        assert_eq!(extra_bits(0, 600), 0);
        assert_eq!(extra_bits(599, 600), 0);
        assert_eq!(extra_bits(600, 600), 1);
        assert_eq!(extra_bits(1200, 600), 2);
        assert_eq!(extra_bits(2399, 600), 2);
        assert_eq!(extra_bits(2400, 600), 3);
        let pow = RegisterPow::new(Config {
            adapt_per_min: 2,
            ..cfg(Mode::Optional, 18)
        });
        assert_eq!(pow.current_bits(), 18);
        for _ in 0..4 {
            pow.note_registration();
        }
        assert_eq!(pow.current_bits(), 20);
        for _ in 0..1000 {
            pow.note_registration();
        }
        assert_eq!(pow.current_bits(), 22, "strop max_bits");
    }

    #[test]
    fn rezim_z_env_hodnoty() {
        assert_eq!(Mode::parse("OFF"), Some(Mode::Off));
        assert_eq!(Mode::parse(" optional "), Some(Mode::Optional));
        assert_eq!(Mode::parse("required"), Some(Mode::Required));
        assert_eq!(Mode::parse("ano"), None);
    }

    /// Sdílené vektory s klientem (app/test/network/register_pow_test.dart):
    /// pevný token (42 B = 0..41), identity klíč 33 × 0x05.
    #[test]
    fn vektory_kompatibilni_s_klientem() {
        let token: Vec<u8> = (0u8..42).collect();
        assert_eq!(
            hex::encode(digest(&token, &IK, 0)),
            "ab9d9008c6ad674271da019b142f25cba7045107da67ad0938fd90a3d096d90a"
        );
        assert_eq!(
            hex::encode(digest(&token, &IK, 0x0123_4567_89ab_cdef)),
            "3fc46d7b70b5c23fef86d979503e03a723929f31e52d2c49e84349e07cfe7d46"
        );
        assert_eq!(solve(&token, &IK, 16), 145_733);
    }
}
