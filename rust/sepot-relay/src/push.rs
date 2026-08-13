//! Push budíčky. TVRDÉ PRAVIDLO: přes push se posílá
//! VŽDY jen prázdný „ťuk" `{"v":1}` — nikdy ciphertext, nikdy odesílatel.
//! Klient se po probuzení sám připojí na WS a vyzvedne frontu sealed-sender
//! kanálem. Endpoint se nikde neloguje.
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
//! odmítá cíle, které resolvují na interní/loopback/privátní adresy.

use std::net::IpAddr;
use std::time::Duration;

use reqwest::Client;

/// Platform kódy (musí sedět s proto RegisterPush.Platform).
pub const PLATFORM_NONE: i16 = 0;
pub const PLATFORM_FCM: i16 = 1;
pub const PLATFORM_APNS: i16 = 2;
pub const PLATFORM_UNIFIEDPUSH: i16 = 3;
pub const PLATFORM_WEBPUSH: i16 = 4;
pub const PLATFORM_MAX: i16 = 4;

/// Konstantní budíček — žádná informace. Šifrovat (RFC 8291) netřeba,
/// není co chránit.
const WAKE_BODY: &str = "{\"v\":1}";

/// HTTP klient pro budíčky: bez redirectů (anti-SSRF přes 3xx), krátký
/// timeout, generický UA.
pub fn build_client() -> Client {
    Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(5))
        .connect_timeout(Duration::from_secs(3))
        .user_agent("sepot-relay")
        .build()
        .expect("reqwest klient")
}

/// Pošle budíček. Best-effort: chyby se tiše polykají (offline zařízení,
/// vypnutý distributor…). Nic o endpointu se neloguje.
pub async fn send_wake(
    client: &Client,
    platform: i16,
    token: &[u8],
    fcm: Option<&crate::fcm::FcmSender>,
    apns: Option<&crate::apns::ApnsSender>,
) {
    match platform {
        PLATFORM_UNIFIEDPUSH | PLATFORM_WEBPUSH => {
            let Ok(url) = std::str::from_utf8(token) else { return };
            if !endpoint_allowed(url).await {
                tracing::debug!("push endpoint odmítnut (scheme/SSRF guard)");
                return;
            }
            post_wake(client, url).await;
        }
        PLATFORM_FCM => {
            // Opt-in fast mode — jen když je relay nakonfigurován
            // (SEPOT_FCM_CREDENTIALS); jinak tichý skip, default
            // (UnifiedPush) funguje vždy.
            let (Some(sender), Ok(device_token)) = (fcm, std::str::from_utf8(token)) else {
                tracing::debug!("FCM budíček přeskočen (bez credentials)");
                return;
            };
            sender.send_wake(client, device_token).await;
        }
        PLATFORM_APNS => {
            let (Some(sender), Ok(device_token)) = (apns, std::str::from_utf8(token)) else {
                tracing::debug!("APNs budíček přeskočen (bez credentials)");
                return;
            };
            sender.send_wake(client, device_token).await;
        }
        _ => {}
    }
}

/// Samotný POST budíčku (bez guardu — ten řeší volající). Oddělené kvůli
/// testovatelnosti proti loopback mocku (guard by loopback jinak odmítl).
async fn post_wake(client: &Client, url: &str) {
    let resp = client
        .post(url)
        .header("content-type", "application/json")
        .header("ttl", "2419200") // WebPush TTL (28 dní), ntfy ignoruje
        .body(WAKE_BODY)
        .send()
        .await;
    // Výsledek se dřív zahazoval (`let _ =`), takže nešlo poznat, jestli
    // budíčky vůbec odcházejí. Logujeme jen stavový kód — endpoint je
    // identifikátor uživatele a do logu nesmí.
    match resp {
        Ok(r) if !r.status().is_success() => {
            tracing::warn!(status = %r.status(), "UnifiedPush budíček odmítnut");
        }
        Err(e) => tracing::warn!("UnifiedPush budíček selhal: {e}"),
        _ => {}
    }
}

/// Povolit jen bezpečné cíle. https vždy; http jen pro .onion (samo šifruje).
/// Odmítnout hostitele resolvující na interní adresy (blind-SSRF ochrana).
///
/// ZNÁMÁ LIMITACE (DNS rebinding / TOCTOU): guard resolvuje host přes
/// `lookup_host` zde, ale samotný POST v `post_wake` resolvuje znovu. Mezi
/// kontrolou a requestem může útočníkem řízené DNS vrátit napřed veřejnou a
/// pak interní adresu, čímž guard obejde. Plný fix = resolvovat jednou a
/// připojit se přímo na ověřenou IP (reqwest `resolve()` / vlastní connector),
/// což je mimo rozsah tohoto vydání. Dopad je zúžen tím, že tělo je konstantní
/// `{"v":1}`, redirecty jsou vypnuté a odpověď se nikam nevrací (blind).
async fn endpoint_allowed(url: &str) -> bool {
    let Ok(parsed) = reqwest::Url::parse(url) else {
        return false;
    };
    let Some(host) = parsed.host_str() else {
        return false;
    };
    let is_onion = host.ends_with(".onion");

    match parsed.scheme() {
        "https" => {}
        // .onion šifruje sám; relay stejně nemá tor egress, request tiše
        // selže — ale schéma povolíme, ať je to připravené.
        "http" if is_onion => return true,
        _ => return false,
    }
    // .onion přes https (neobvyklé) — neresolvuje se přes DNS, pustit.
    if is_onion {
        return true;
    }

    // Vlastnit host+port, ať `parsed` nepřežívá await na lookup_host.
    let host = host.to_string();
    let port = parsed.port_or_known_default().unwrap_or(443);
    drop(parsed);

    let resolved = tokio::net::lookup_host((host.as_str(), port)).await;
    let Ok(addrs) = resolved else {
        return false; // host nejde resolvovat → nepouštět
    };
    let mut saw_any = false;
    for a in addrs {
        saw_any = true;
        if is_internal_ip(&a.ip()) {
            return false; // aspoň jedna interní adresa → celé odmítnout
        }
    }
    saw_any
}

fn is_internal_v4(v4: &std::net::Ipv4Addr) -> bool {
    v4.is_loopback()
        || v4.is_private()
        || v4.is_link_local()
        || v4.is_unspecified()
        || v4.is_broadcast()
        || v4.is_documentation()
        // 100.64.0.0/10 CGNAT (Tailscale apod.)
        || (v4.octets()[0] == 100 && (v4.octets()[1] & 0xc0) == 0x40)
}

fn is_internal_ip(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => is_internal_v4(v4),
        IpAddr::V6(v6) => {
            let o = v6.octets();
            v6.is_loopback()
                || v6.is_unspecified()
                || (o[0] & 0xfe) == 0xfc // fc00::/7 ULA
                || (o[0] == 0xfe && (o[1] & 0xc0) == 0x80) // fe80::/10 link-local
                || v6.to_ipv4_mapped().map(|v4| is_internal_v4(&v4)).unwrap_or(false)
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

    #[tokio::test]
    async fn schema_a_ssrf_guard() {
        // http (ne-onion) se odmítne
        assert!(!endpoint_allowed("http://ntfy.sh/abc").await);
        // loopback se odmítne i přes https
        assert!(!endpoint_allowed("https://127.0.0.1/abc").await);
        assert!(!endpoint_allowed("https://localhost/abc").await);
        // interní IP se odmítne
        assert!(!endpoint_allowed("https://10.0.0.5:8000/x").await);
        // http na .onion se pustí (schéma OK)
        assert!(endpoint_allowed("http://cipjsctoeyf4fcrntvdvt22o2ansgr73qvthmewo246vuntd7cqmykyd.onion/x").await);
        // nesmysl se odmítne
        assert!(!endpoint_allowed("není url").await);
        assert!(!endpoint_allowed("ftp://ntfy.sh/x").await);
    }

    #[test]
    fn cgnat_hranice() {
        assert!(is_internal_v4(&Ipv4Addr::new(100, 64, 0, 1)));
        assert!(is_internal_v4(&Ipv4Addr::new(100, 127, 255, 255)));
        // 100.63 a 100.128 jsou mimo CGNAT blok → veřejné
        assert!(!is_internal_v4(&Ipv4Addr::new(100, 63, 0, 1)));
        assert!(!is_internal_v4(&Ipv4Addr::new(100, 128, 0, 1)));
    }

    /// post_wake musí poslat POST s tělem přesně `{"v":1}` — žádný obsah.
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
        post_wake(&client, &format!("http://{addr}/up?token=abc")).await;

        let req = server.await.unwrap();
        assert!(req.starts_with("POST /up?token=abc "), "čekal POST, dostal: {req}");
        assert!(req.contains("{\"v\":1}"), "tělo není prázdný ťuk: {req}");
        // budíček nesmí nést nic dalšího
        assert!(!req.to_lowercase().contains("payload"));
    }
}
