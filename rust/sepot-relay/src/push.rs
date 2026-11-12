//! Push budíčky. TVRDÉ PRAVIDLO: přes push se posílá
//! VŽDY jen „ťuk" `{"v":1,"k":…}` — nikdy ciphertext, nikdy odesílatel.
//! Klient se po probuzení sám připojí na WS a vyzvedne frontu sealed-sender
//! kanálem. Endpoint se nikde neloguje.
//!
//! Pole `k` říká jen druh budíčku ([`WakeKind`]): `msg` = čeká zpráva,
//! kterou člověk uvidí, `sync` = jen provozní obálka (doručenka, potvrzení
//! přečtení, reakce…). Zamčená appka nic nerozšifruje, takže bez téhle
//! nápovědy hlásila „nové zprávy“ i na cizí doručenku. Příchozí hovor
//! (`ContentHint::Call`) nese `"k":"call"`, aby telefon začal zvonit hned
//! (CallKit / celoobrazovkové zvonění). Kdo píše nebo volá, v budíčku dál
//! není.
//!
//! Podporované cesty:
//!  - UnifiedPush (3) / WebPush (4): HTTP POST na endpoint URL distributora.
//!  - FCM (1) / APNs (2): opt-in „fast mode" — vyžaduje externí credentials
//!    (Firebase/Apple). Implementováno v `fcm.rs` / `apns.rs`; zapojeno níže
//!    v `send_wake`. Bez nakonfigurovaných credentials se cesta tiše přeskočí
//!    a klient spadne zpět na výchozí UnifiedPush.
//!
//! SSRF: endpoint zadává klient, takže relay by jinak POSToval na libovolné
//! URL. `endpoint_allowed` proto vynucuje https (http jen pro .onion) a
//! odmítá adresy zapsané číslem; jména hlídá resolver klienta
//! ([`PublicOnlyResolver`]), který odmítne cíl s interní, loopback nebo
//! privátní adresou.

use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;

use reqwest::dns::{Addrs, Name, Resolve, Resolving};
use reqwest::Client;

/// Platform kódy (musí sedět s proto RegisterPush.Platform).
pub const PLATFORM_NONE: i16 = 0;
pub const PLATFORM_FCM: i16 = 1;
pub const PLATFORM_APNS: i16 = 2;
pub const PLATFORM_UNIFIEDPUSH: i16 = 3;
pub const PLATFORM_WEBPUSH: i16 = 4;
pub const PLATFORM_MAX: i16 = 4;

/// Druh budíčku — jediná informace, kterou push nese.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WakeKind {
    /// Čeká zpráva, kterou člověk uvidí → appka smí ukázat notifikaci.
    Message,
    /// Provozní obálka → appka se jen tiše připojí (nebo neudělá nic).
    Sync,
}

impl WakeKind {
    pub fn as_str(self) -> &'static str {
        match self {
            WakeKind::Message => "msg",
            WakeKind::Sync => "sync",
        }
    }

    /// Tělo budíčku pro UnifiedPush/WebPush. Šifrovat (RFC 8291) netřeba,
    /// nese jen druh.
    fn body(self) -> &'static str {
        match self {
            WakeKind::Message => "{\"v\":1,\"k\":\"msg\"}",
            WakeKind::Sync => "{\"v\":1,\"k\":\"sync\"}",
        }
    }
}

/// Token, který push služba natrvalo odmítla (appka odinstalovaná, token
/// vyměněný). Relay ho má zapomenout: jinak na něj posílá dál, dokud účet
/// nezmizí, a z opakovaných pokusů na mrtvé tokeny Apple i Google usuzují
/// na špatného odesílatele.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DeadToken {
    Push,
    Voip,
}

/// Push cíl zařízení včetně iOS VoIP tokenu (jen pro hovory).
pub struct PushTarget {
    pub platform: i16,
    pub token: Option<Vec<u8>>,
    pub voip_token: Option<Vec<u8>>,
}

/// Budíček pro příchozí hovor. iPhone s VoIP tokenem → VoIP push (jediná
/// cesta, jak iOS nechá zazvonit zabitou appku); Android FCM → budíček
/// `k=call` s krátkou platností; ostatní (UnifiedPush, starší iOS appka)
/// → běžný budíček, zazvoní až po vyzvednutí fronty.
pub async fn send_call_wake(
    client: &Client,
    target: &PushTarget,
    fcm: Option<&crate::fcm::FcmSender>,
    apns: Option<&crate::apns::ApnsSender>,
) -> Option<DeadToken> {
    if let (Some(sender), Some(Ok(voip))) = (
        apns,
        target.voip_token.as_deref().map(std::str::from_utf8),
    ) {
        return sender
            .send_voip_call(client, voip)
            .await
            .then_some(DeadToken::Voip);
    }
    let token = target.token.as_deref()?;
    if target.platform == PLATFORM_FCM {
        let (Some(sender), Ok(device_token)) = (fcm, std::str::from_utf8(token)) else {
            return None;
        };
        return sender
            .send_call_wake(client, device_token)
            .await
            .then_some(DeadToken::Push);
    }
    // Bez zvonění ať se o hovoru člověk dozví aspoň notifikací — zamčená
    // appka by tichý budíček zahodila.
    send_wake(client, target.platform, token, WakeKind::Message, fcm, apns).await
}

/// Budíček pro zprávu, kterou člověk uvidí (`ContentHint::Visible`).
/// iPhone dostane hned viditelnou notifikaci s obecným lokalizovaným textem
/// (tichý budíček iOS zdržuje podle baterie); obsah ani odesílatel v ní
/// nejsou. Ostatní platformy dostanou budíček druhu [`WakeKind::Message`].
pub async fn send_message_wake(
    client: &Client,
    platform: i16,
    token: &[u8],
    fcm: Option<&crate::fcm::FcmSender>,
    apns: Option<&crate::apns::ApnsSender>,
) -> Option<DeadToken> {
    if platform == PLATFORM_APNS {
        let (Some(sender), Ok(device_token)) = (apns, std::str::from_utf8(token)) else {
            return None;
        };
        return sender
            .send_message_alert(client, device_token)
            .await
            .then_some(DeadToken::Push);
    }
    send_wake(client, platform, token, WakeKind::Message, fcm, apns).await
}

/// Resolver HTTP klienta pro budíčky: jméno, které vede na vnitřní adresu,
/// nepřeloží vůbec.
///
/// Kontrola musí být přímo v resolveru spojení. Dřív se jméno přeložilo
/// zvlášť kvůli kontrole a adresy se připínaly do nového klienta, který se
/// stavěl pro každý budíček (načtení kořenových certifikátů, žádné sdílení
/// spojení). Jediný klient s hlídaným resolverem dá totéž bez té ceny a bez
/// okna mezi kontrolou a spojením (DNS rebinding).
struct PublicOnlyResolver;

/// Záměrně bez jména: endpoint je identifikátor uživatele a chyba se loguje.
const INTERNAL_TARGET: &str = "cíl vede na vnitřní adresu";
const NO_ADDRESS: &str = "cíl nemá žádnou adresu";

impl Resolve for PublicOnlyResolver {
    fn resolve(&self, name: Name) -> Resolving {
        Box::pin(async move {
            // Port doplní až spojení; resolver vrací jen adresy.
            let resolved: Vec<SocketAddr> =
                tokio::net::lookup_host((name.as_str(), 0)).await?.collect();
            if resolved.is_empty() {
                return Err(NO_ADDRESS.into());
            }
            // Stačí jedna vnitřní adresa a neplatí žádná: jinak by si
            // klient při výpadku té veřejné vybral vnitřní.
            if resolved.iter().any(|addr| is_internal_ip(&addr.ip())) {
                return Err(INTERNAL_TARGET.into());
            }
            Ok(Box::new(resolved.into_iter()) as Addrs)
        })
    }
}

/// HTTP klient pro budíčky: bez redirectů (anti-SSRF přes 3xx), krátký
/// timeout, generický UA, jména jen na veřejné adresy.
pub fn build_client() -> Client {
    Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(5))
        .connect_timeout(Duration::from_secs(3))
        .user_agent("sepot-relay")
        .dns_resolver(Arc::new(PublicOnlyResolver))
        .build()
        .expect("reqwest klient")
}

/// Pošle budíček. Best-effort: chyby se tiše polykají (offline zařízení,
/// vypnutý distributor…). Nic o endpointu se neloguje. Vrací token, který
/// push služba natrvalo odmítla.
pub async fn send_wake(
    client: &Client,
    platform: i16,
    token: &[u8],
    kind: WakeKind,
    fcm: Option<&crate::fcm::FcmSender>,
    apns: Option<&crate::apns::ApnsSender>,
) -> Option<DeadToken> {
    match platform {
        PLATFORM_UNIFIEDPUSH | PLATFORM_WEBPUSH => {
            let url = std::str::from_utf8(token).ok()?;
            if !endpoint_allowed(url) {
                tracing::debug!("push endpoint odmítnut (scheme/SSRF guard)");
                return None;
            }
            post_wake(client, url, kind).await;
            // Odmítnutí distributora token nemaže: UnifiedPush nemá
            // jednotný kód pro zaniklý endpoint a 404 vrací i server,
            // který má jen výpadek.
            None
        }
        PLATFORM_FCM => {
            // Opt-in fast mode — jen když je relay nakonfigurován
            // (SEPOT_FCM_CREDENTIALS); jinak tichý skip, default
            // (UnifiedPush) funguje vždy.
            let (Some(sender), Ok(device_token)) = (fcm, std::str::from_utf8(token)) else {
                tracing::debug!("FCM budíček přeskočen (bez credentials)");
                return None;
            };
            sender
                .send_wake(client, device_token, kind)
                .await
                .then_some(DeadToken::Push)
        }
        PLATFORM_APNS => {
            let (Some(sender), Ok(device_token)) = (apns, std::str::from_utf8(token)) else {
                tracing::debug!("APNs budíček přeskočen (bez credentials)");
                return None;
            };
            sender
                .send_wake(client, device_token)
                .await
                .then_some(DeadToken::Push)
        }
        _ => None,
    }
}

/// Samotný POST budíčku (bez guardu — ten řeší volající). Oddělené kvůli
/// testovatelnosti proti loopback mocku (guard by loopback jinak odmítl).
async fn post_wake(client: &Client, url: &str, kind: WakeKind) {
    let resp = client
        .post(url)
        .header("content-type", "application/json")
        .header("ttl", "2419200") // WebPush TTL (28 dní), ntfy ignoruje
        .body(kind.body())
        .send()
        .await;
    // Výsledek se dřív zahazoval (`let _ =`), takže nešlo poznat, jestli
    // budíčky vůbec odcházejí. Logujeme jen stavový kód — endpoint je
    // identifikátor uživatele a do logu nesmí.
    match resp {
        Ok(r) if !r.status().is_success() => {
            tracing::warn!(status = %r.status(), "UnifiedPush budíček odmítnut");
        }
        // without_url: chyba reqwest nese URL = endpoint = identifikátor
        // uživatele; do logu nesmí.
        Err(e) => tracing::warn!("UnifiedPush budíček selhal: {}", e.without_url()),
        _ => {}
    }
}

/// Povolit jen bezpečné cíle: https vždy, http jen pro .onion (samo
/// šifruje), adresa zapsaná číslem jen veřejná. Jména tu neprojdou
/// kontrolou adres — tu dělá resolver klienta až při spojení.
fn endpoint_allowed(url: &str) -> bool {
    let Ok(parsed) = reqwest::Url::parse(url) else {
        return false;
    };
    let Some(host) = parsed.host_str() else {
        return false;
    };
    // Parser URL srovná do běžného tvaru i zápisy jako `0x7f.1` nebo
    // `2130706433`; IPv6 vrací v hranatých závorkách.
    let literal = host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .parse::<IpAddr>();
    match (parsed.scheme(), literal) {
        ("https", Ok(ip)) => !is_internal_ip(&ip),
        ("https", Err(_)) => true,
        // .onion šifruje sám; relay stejně nemá tor egress, request tiše
        // selže — ale schéma povolíme, ať je to připravené.
        ("http", Err(_)) => host.ends_with(".onion"),
        _ => false,
    }
}

fn is_internal_v4(v4: &std::net::Ipv4Addr) -> bool {
    v4.is_loopback()
        || v4.is_private()
        || v4.is_link_local()
        || v4.is_unspecified()
        || v4.is_broadcast()
        || v4.is_documentation()
        || v4.is_multicast()
        // 100.64.0.0/10 CGNAT (Tailscale apod.)
        || (v4.octets()[0] == 100 && (v4.octets()[1] & 0xc0) == 0x40)
        // 0.0.0.0/8 „tahle síť“: Linux ji směruje na vlastní stroj
        || v4.octets()[0] == 0
        // 192.0.0.0/24 přidělení pro protokoly IETF
        || v4.octets()[..3] == [192, 0, 0]
        // 198.18.0.0/15 měření sítí, v praxi vnitřní testovací segmenty
        || (v4.octets()[0] == 198 && (v4.octets()[1] & 0xfe) == 18)
        // 240.0.0.0/4 rezervováno; některé sítě ho používají uvnitř
        || v4.octets()[0] >= 240
}

fn is_internal_ip(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => is_internal_v4(v4),
        IpAddr::V6(v6) => {
            let o = v6.octets();
            v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                || (o[..4] == [0x20, 0x01, 0x0d, 0xb8]) // 2001:db8::/32 dokumentace
                || (o[0] & 0xfe) == 0xfc // fc00::/7 ULA
                || (o[0] == 0xfe && (o[1] & 0xc0) == 0x80) // fe80::/10 link-local
                || (o[0] == 0xfe && (o[1] & 0xc0) == 0xc0) // fec0::/10 site-local
                || v6.to_ipv4_mapped().map(|v4| is_internal_v4(&v4)).unwrap_or(false)
                // 64:ff9b::/96 NAT64 a 2002::/16 6to4 nesou vnořenou IPv4
                || (o[..12] == [0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0]
                    && is_internal_v4(&std::net::Ipv4Addr::new(o[12], o[13], o[14], o[15])))
                || (o[0] == 0x20
                    && o[1] == 0x02
                    && is_internal_v4(&std::net::Ipv4Addr::new(o[2], o[3], o[4], o[5])))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[test]
    fn interni_adresy_se_odmitnou() {
        for ip in [
            "127.0.0.1",
            "10.0.0.5",
            "192.168.1.1",
            "172.16.0.5",
            "169.254.1.1",
            "0.0.0.0",
            "100.64.0.1", // Tailscale CGNAT
        ] {
            assert!(is_internal_ip(&ip.parse().unwrap()), "{ip} mělo být interní");
        }
    }

    #[test]
    fn verejne_adresy_projdou() {
        for ip in ["1.1.1.1", "8.8.8.8", "9.9.9.9", "2606:4700:4700::1111"] {
            assert!(!is_internal_ip(&ip.parse().unwrap()), "{ip} nemělo být interní");
        }
    }

    #[test]
    fn ipv4_mapped_v6_loopback_je_interni() {
        let mapped: IpAddr = "::ffff:127.0.0.1".parse().unwrap();
        assert!(is_internal_ip(&mapped));
    }

    #[test]
    fn nat64_a_6to4_s_vnorenou_privatni_v4_jsou_interni() {
        let nat64: IpAddr = "64:ff9b::10.0.0.1".parse().unwrap();
        assert!(is_internal_ip(&nat64));
        let sixtofour: IpAddr = "2002:c0a8:101::1".parse().unwrap(); // 192.168.1.1
        assert!(is_internal_ip(&sixtofour));
        let verejna_nat64: IpAddr = "64:ff9b::1.1.1.1".parse().unwrap();
        assert!(!is_internal_ip(&verejna_nat64));
    }

    #[test]
    fn rezervovane_rozsahy_jsou_interni() {
        for ip in [
            "0.1.2.3",
            "192.0.0.8",
            "198.18.0.1",
            "198.19.255.255",
            "224.0.0.1",
            "239.255.255.250",
            "240.0.0.1",
            "255.255.255.255",
            "ff02::1",
            "2001:db8::1",
        ] {
            assert!(is_internal_ip(&ip.parse().unwrap()), "{ip} mělo být interní");
        }
        for ip in ["198.17.255.255", "198.20.0.1", "192.0.1.1", "223.255.255.255"] {
            assert!(!is_internal_ip(&ip.parse().unwrap()), "{ip} nemělo být interní");
        }
    }

    #[test]
    fn schema_a_ssrf_guard() {
        // http (ne-onion) se odmítne
        assert!(!endpoint_allowed("http://ntfy.sh/abc"));
        assert!(endpoint_allowed("https://ntfy.sh/abc"));
        // adresa zapsaná číslem: loopback a interní se odmítne i přes https
        for refused in [
            "https://127.0.0.1/abc",
            "https://10.0.0.5:8000/x",
            "https://0x7f.1/x",
            "https://2130706433/x",
            "https://0.0.0.0/x",
            "https://[::1]/x",
            "https://[::ffff:10.0.0.1]/x",
            "http://1.1.1.1/x",
        ] {
            assert!(!endpoint_allowed(refused), "{refused}");
        }
        assert!(endpoint_allowed("https://1.1.1.1/x"));
        // http na .onion se pustí (schéma OK)
        assert!(endpoint_allowed(
            "http://cipjsctoeyf4fcrntvdvt22o2ansgr73qvthmewo246vuntd7cqmykyd.onion/x"
        ));
        // nesmysl se odmítne
        assert!(!endpoint_allowed("není url"));
        assert!(!endpoint_allowed("ftp://ntfy.sh/x"));
    }

    /// Jméno vedoucí na loopback resolver klienta nepřeloží; chyba nenese
    /// jméno (endpoint je identifikátor uživatele).
    #[tokio::test]
    async fn resolver_odmitne_jmeno_s_vnitrni_adresou() {
        let name: Name = "localhost".parse().expect("jméno");
        let error = PublicOnlyResolver
            .resolve(name)
            .await
            .err()
            .expect("localhost je vnitřní");
        assert_eq!(error.to_string(), INTERNAL_TARGET);
    }

    /// Klient pro budíčky se na jméno s vnitřní adresou vůbec nepřipojí.
    #[tokio::test]
    async fn klient_se_na_vnitrni_jmeno_nepripoji() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let client = build_client();
        let sent = client
            .post(format!("http://localhost:{port}/up"))
            .send()
            .await;
        assert!(sent.is_err(), "požadavek na vnitřní jméno prošel");
        let accepted =
            tokio::time::timeout(Duration::from_millis(200), listener.accept()).await;
        assert!(accepted.is_err(), "spojení na vnitřní adresu vzniklo");
    }

    #[test]
    fn telo_budicku_nese_jen_verzi_a_druh() {
        for kind in [WakeKind::Message, WakeKind::Sync] {
            let v: serde_json::Value = serde_json::from_str(kind.body()).unwrap();
            let obj = v.as_object().unwrap();
            assert_eq!(obj.len(), 2, "jen v a k");
            assert_eq!(obj["v"], 1);
            assert_eq!(obj["k"], kind.as_str());
        }
    }

    #[test]
    fn cgnat_hranice() {
        assert!(is_internal_v4(&Ipv4Addr::new(100, 64, 0, 1)));
        assert!(is_internal_v4(&Ipv4Addr::new(100, 127, 255, 255)));
        // 100.63 a 100.128 jsou mimo CGNAT blok → veřejné
        assert!(!is_internal_v4(&Ipv4Addr::new(100, 63, 0, 1)));
        assert!(!is_internal_v4(&Ipv4Addr::new(100, 128, 0, 1)));
    }

    /// post_wake musí poslat POST jen s verzí a druhem budíčku — žádný obsah.
    /// Mock server na loopbacku (guard se tu záměrně obchází — testuje jen
    /// tvar POSTu, guard má vlastní testy).
    #[tokio::test]
    async fn post_wake_posle_prazdny_tuk() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let server = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut buf = vec![0u8; 4096];
            let n = sock.read(&mut buf).await.unwrap();
            let req = String::from_utf8_lossy(&buf[..n]).to_string();
            sock.write_all(b"HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n")
                .await
                .unwrap();
            req
        });

        let client = build_client();
        post_wake(&client, &format!("http://{addr}/up?token=abc"), WakeKind::Sync).await;

        let req = server.await.unwrap();
        assert!(req.starts_with("POST /up?token=abc "), "čekal POST, dostal: {req}");
        assert!(
            req.ends_with("\r\n\r\n{\"v\":1,\"k\":\"sync\"}"),
            "tělo není holý ťuk: {req}"
        );
        // budíček nesmí nést nic dalšího
        assert!(!req.to_lowercase().contains("payload"));
    }
}
