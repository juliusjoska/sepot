//! Otisk identity: BLAKE2b-256 serializovaného veřejného identity klíče.
//!
//! Totéž číslo ukazuje aplikace (52 znaků Crockford base32, zkratka `SEP-`
//! a 10 znaků) a nese ho hlášení zneužití. Relay podle něj eviduje blokace
//! a zajištění, takže provozovatel, uživatel i hlášení mluví o stejném
//! identifikátoru.

use base64::alphabet;
use base64::engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig};
use base64::Engine;
use blake2::digest::consts::U32;
use blake2::{Blake2b, Digest};

/// Crockford base32: bez I, L, O a U, aby se otisk dal přečíst nahlas.
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
/// 256 bitů po pěti: 51 celých znaků a jeden se 4 nulovými bity výplně.
const ENCODED_LEN: usize = 52;
/// Zkratka v aplikaci: `SEP-` a prvních 10 znaků otisku (50 bitů).
const SHORT_PREFIX: &str = "SEP-";
const SHORT_LEN: usize = 10;
/// Sdílený odkaz aplikace (`PublicIdentity.toShareString`).
const LINK_PREFIX: &str = "sepot://add/";
/// Serializovaný veřejný klíč Curve25519 v libsignal: typový bajt a 32 B.
const IDENTITY_KEY_LEN: usize = 33;
const DJB_KEY_TYPE: u8 = 0x05;

/// Base64 bez nároku na výplň: odkaz i klíč lidé kopírují různě oříznuté.
const LENIENT: GeneralPurposeConfig =
    GeneralPurposeConfig::new().with_decode_padding_mode(DecodePaddingMode::Indifferent);
const URL_SAFE_LENIENT: GeneralPurpose = GeneralPurpose::new(&alphabet::URL_SAFE, LENIENT);
const STANDARD_LENIENT: GeneralPurpose = GeneralPurpose::new(&alphabet::STANDARD, LENIENT);

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Fingerprint(pub [u8; 32]);

/// Debug bez hodnoty: otisk je identifikátor a do logů nepatří.
impl std::fmt::Debug for Fingerprint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Fingerprint(…)")
    }
}

impl Fingerprint {
    pub fn of_identity_key(identity_key: &[u8]) -> Self {
        Self(Blake2b::<U32>::digest(identity_key).into())
    }

    pub fn to_crockford(self) -> String {
        let mut out = String::with_capacity(ENCODED_LEN);
        let mut acc: u32 = 0;
        let mut bits = 0;
        for &byte in &self.0 {
            acc = (acc << 8) | u32::from(byte);
            bits += 8;
            while bits >= 5 {
                bits -= 5;
                out.push(char::from(ALPHABET[((acc >> bits) & 0x1f) as usize]));
            }
            acc &= (1 << bits) - 1;
        }
        if bits > 0 {
            out.push(char::from(ALPHABET[((acc << (5 - bits)) & 0x1f) as usize]));
        }
        out
    }

    pub fn short(&self) -> String {
        format!("{SHORT_PREFIX}{}", &self.to_crockford()[..SHORT_LEN])
    }

    /// Klíč `pg_advisory_xact_lock`: prvních 8 B otisku. Kolize dvou otisků
    /// jen serializuje dvě nesouvisející transakce.
    pub fn lock_key(&self) -> i64 {
        let mut head = [0u8; 8];
        head.copy_from_slice(&self.0[..8]);
        i64::from_be_bytes(head)
    }

    /// Plný otisk, jak ho opíše člověk: velikost písmen, mezery a pomlčky
    /// nevadí, `O` se čte jako 0, `I` a `L` jako 1. Musí sedět všech 52
    /// znaků i nulová výplň, jinak by dva různé zápisy dávaly jeden otisk.
    pub fn parse_full(text: &str) -> Option<Self> {
        let mut out = [0u8; 32];
        let mut acc: u32 = 0;
        let mut bits = 0;
        let mut written = 0;
        let mut count = 0;
        for c in text.chars().filter(|c| !c.is_whitespace() && *c != '-') {
            count += 1;
            if count > ENCODED_LEN {
                return None;
            }
            acc = (acc << 5) | crockford_value(c)?;
            bits += 5;
            if bits >= 8 {
                bits -= 8;
                out[written] = (acc >> bits) as u8;
                written += 1;
                acc &= (1 << bits) - 1;
            }
        }
        (count == ENCODED_LEN && acc == 0).then_some(Self(out))
    }
}

fn crockford_value(c: char) -> Option<u32> {
    let c = match c.to_ascii_uppercase() {
        'O' => '0',
        'I' | 'L' => '1',
        other => other,
    };
    ALPHABET
        .iter()
        .position(|&a| char::from(a) == c)
        .map(|i| i as u32)
}

/// Co provozovatel poslal na stdin podpříkazu.
#[derive(PartialEq, Eq)]
pub enum AdminInput {
    Full(Fingerprint),
    /// Zkratka `SEP-…` jen pro hledání: má 50 bitů, kolizní klíč k cizí
    /// zkratce jde předpočítat, a blokovat podle ní se proto nesmí.
    Short(String),
}

/// Debug bez hodnoty jako u `Fingerprint`: zkratka je identifikátor.
impl std::fmt::Debug for AdminInput {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Full(fingerprint) => f.debug_tuple("Full").field(fingerprint).finish(),
            Self::Short(_) => f.write_str("Short(…)"),
        }
    }
}

/// Přijme plný otisk, text se sdíleným odkazem `sepot://add/…`, samotný
/// identity klíč v base64 nebo zkratku `SEP-…`.
pub fn parse_admin_input(text: &str) -> Option<AdminInput> {
    let text = text.trim();
    // Lidé vkládají celou pozvánku i s průvodním textem, ne jen odkaz;
    // znaky payloadu jako regulární výraz v aplikaci.
    if let Some(start) = text.find(LINK_PREFIX) {
        let payload: String = text[start + LINK_PREFIX.len()..]
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '='))
            .collect();
        return identity_key_from_link(&payload)
            .map(|key| AdminInput::Full(Fingerprint::of_identity_key(&key)));
    }
    if let Some(short) = parse_short(text) {
        return Some(AdminInput::Short(short));
    }
    if let Some(fingerprint) = Fingerprint::parse_full(text) {
        return Some(AdminInput::Full(fingerprint));
    }
    identity_key_from_base64(text).map(|key| AdminInput::Full(Fingerprint::of_identity_key(&key)))
}

fn parse_short(text: &str) -> Option<String> {
    let head = text.get(..SHORT_PREFIX.len())?;
    if !head.eq_ignore_ascii_case(SHORT_PREFIX) {
        return None;
    }
    let mut short = String::from(SHORT_PREFIX);
    for c in text[SHORT_PREFIX.len()..]
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
    {
        short.push(char::from(ALPHABET[crockford_value(c)? as usize]));
    }
    (short.len() == SHORT_PREFIX.len() + SHORT_LEN).then_some(short)
}

/// Payload odkazu: base64url JSON s polem `ik` (identity klíč v base64).
fn identity_key_from_link(payload: &str) -> Option<Vec<u8>> {
    let json = URL_SAFE_LENIENT.decode(payload).ok()?;
    let value: serde_json::Value = serde_json::from_slice(&json).ok()?;
    identity_key_from_base64(value.get("ik")?.as_str()?)
}

fn identity_key_from_base64(text: &str) -> Option<Vec<u8>> {
    let key = STANDARD_LENIENT.decode(text.trim()).ok()?;
    (key.len() == IDENTITY_KEY_LEN && key[0] == DJB_KEY_TYPE).then_some(key)
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::prelude::*;

    const KAT: &str = "2TFMWYYW4MRZH3BR8QCWQZVVM20EPFEP40N91S6J9HXW1GGHATRG";

    /// Testovací vektor aplikace: typový bajt 0x05 a bajty 0x00..=0x1f.
    fn kat_key() -> Vec<u8> {
        let mut key = vec![DJB_KEY_TYPE];
        key.extend(0u8..32);
        key
    }

    #[test]
    fn otisk_kat_shodny_s_appkou() {
        let fingerprint = Fingerprint::of_identity_key(&kat_key());
        assert_eq!(fingerprint.to_crockford(), KAT);
        assert_eq!(Fingerprint::parse_full(KAT), Some(fingerprint));
    }

    #[test]
    fn otisk_zkratka_sep() {
        assert_eq!(
            Fingerprint::of_identity_key(&kat_key()).short(),
            "SEP-2TFMWYYW4M"
        );
    }

    #[test]
    fn otisk_lock_key_kat() {
        assert_eq!(
            Fingerprint::of_identity_key(&kat_key()).lock_key(),
            1_630_107_884_012_777_976
        );
    }

    #[test]
    fn otisk_parse_shovivavy() {
        let expected = Fingerprint::parse_full(KAT);
        assert!(expected.is_some());
        let grouped: Vec<String> = KAT
            .as_bytes()
            .chunks(4)
            .map(|c| String::from_utf8_lossy(c).into_owned())
            .collect();
        for variant in [
            KAT.to_lowercase(),
            grouped.join(" "),
            grouped.join("-"),
            format!("  {}\n", grouped.join(" - ")),
            KAT.replace('0', "O").replace('1', "I"),
            KAT.replace('0', "o").replace('1', "l"),
        ] {
            assert_eq!(Fingerprint::parse_full(&variant), expected, "{variant}");
        }
    }

    #[test]
    fn otisk_parse_odmitne_neplatne() {
        let nonzero_padding = format!("{}H", &KAT[..ENCODED_LEN - 1]);
        let with_u = format!("U{}", &KAT[1..]);
        for bad in [
            &KAT[..ENCODED_LEN - 1],
            &format!("{KAT}0"),
            &with_u,
            &nonzero_padding,
            "",
            "   ",
        ] {
            assert_eq!(Fingerprint::parse_full(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn vstup_z_odkazu_a_klice() {
        let key = kat_key();
        let expected = Some(AdminInput::Full(Fingerprint::of_identity_key(&key)));

        // Pozvánka jako z aplikace: base64url JSON s výplní a průvodní text.
        let json = serde_json::json!({
            "v": 2,
            "n": "Jana",
            "ik": BASE64_STANDARD.encode(&key),
            "ts": "2026-11-05T10:00:00.000",
            "aid": "00112233445566778899aabbccddeeff",
        });
        let payload = BASE64_URL_SAFE.encode(json.to_string());
        let invitation = format!("Ahoj, přidej si mě v Šepotu: sepot://add/{payload} Díky!");
        assert_eq!(parse_admin_input(&invitation), expected);
        let unpadded = format!("sepot://add/{}", payload.trim_end_matches('='));
        assert_eq!(parse_admin_input(&unpadded), expected);

        assert_eq!(parse_admin_input(&BASE64_STANDARD.encode(&key)), expected);
        assert_eq!(parse_admin_input(KAT), expected);
        assert_eq!(
            parse_admin_input(" sep-2tfmwyyw4m\n"),
            Some(AdminInput::Short("SEP-2TFMWYYW4M".into()))
        );

        let mut without_type = key.clone();
        without_type[0] = 0x06;
        let link_without_ik = format!(
            "sepot://add/{}",
            BASE64_URL_SAFE.encode(serde_json::json!({ "v": 2, "n": "Jana" }).to_string())
        );
        for bad in [
            BASE64_STANDARD.encode(&key[1..]),
            BASE64_STANDARD.encode(&without_type),
            link_without_ik,
            "SEP-2TFMWYYW4".into(),
            "nesmysl".into(),
        ] {
            assert_eq!(parse_admin_input(&bad), None, "{bad}");
        }
    }
}
