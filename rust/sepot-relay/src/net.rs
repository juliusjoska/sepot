//! Určení klientské IP za reverse proxy — anti-abuse klíč.
//!
//! BEZPEČNOST (SECURITY audit #1): forwarded hlavičky (X-Forwarded-For,
//! X-Real-Ip) smí nastavit kdokoli. Relay je dosažitelný dvěma cestami:
//! clearnet přes traefik (síť `pangolin`), kde traefik klientské X-hlavičky
//! přepisuje a jsou tedy důvěryhodné; a Tor onion přes tor kontejner (síť
//! `tornet`) PŘÍMO na :8470, mimo traefik — tor forwarduje HTTP beze změny,
//! takže hlavičky si nastaví sám klient.
//!
//! Kdybychom hlavičkám věřili vždy, onion klient by si zvolil libovolnou IP
//! a obešel VŠECHNY rate-limity i WS conn-cap (registrace, fetch_bundle,
//! upload, počet spojení). Proto: hlavičku uznej JEN když peer (skutečná
//! TCP adresa spojení) padne do explicitně nakonfigurované sady trusted
//! proxy. Onion peer (tor kontejner) tam není → použije se jeho IP a všichni
//! onion klienti sdílí jeden bucket (přesně jak počítal původní komentář).

use std::net::IpAddr;

use axum::http::HeaderMap;
use ipnet::IpNet;

/// Sada sítí, jejichž forwarded hlavičkám se věří (traefik/pangolin).
/// Konfiguruje se přes `SEPOT_TRUSTED_PROXIES` (čárkou oddělené IP nebo CIDR).
pub struct TrustedProxies {
    nets: Vec<IpNet>,
    /// Adresy, ze kterých přichází Tor (kontejner `tor` v síti tornet,
    /// `SEPOT_TOR_PEERS`). Takový peer nikdy není trusted proxy a dostává
    /// vlastní, společné limity — všichni onion klienti mají jeho IP.
    tor: Vec<IpNet>,
}

fn parse_nets(raw: &str) -> Vec<IpNet> {
    raw.split(',')
        .filter_map(|s| {
            let s = s.trim();
            if s.is_empty() {
                return None;
            }
            // "10.0.0.0/24" i holé "10.0.0.5" (bereme jako /32, resp. /128)
            s.parse::<IpNet>()
                .ok()
                .or_else(|| s.parse::<IpAddr>().ok().map(IpNet::from))
        })
        .collect()
}

impl TrustedProxies {
    /// Načte z env `SEPOT_TRUSTED_PROXIES`. Prázdné/nenastavené = nevěří se
    /// nikomu (vždy peer IP) — fail-safe: chybějící konfigurace nesmí otevřít
    /// spoofing, maximálně sloučí clearnet klienty do jednoho bucketu.
    pub fn from_env() -> Self {
        let proxies = Self::parse(
            &std::env::var("SEPOT_TRUSTED_PROXIES").unwrap_or_default(),
            &std::env::var("SEPOT_TOR_PEERS").unwrap_or_default(),
        );
        if proxies.nets.is_empty() {
            tracing::warn!(
                "SEPOT_TRUSTED_PROXIES prázdné — forwarded hlavičky se ignorují, \
                 anti-abuse klíč = peer IP. Za reverse proxy nastav CIDR proxy sítě."
            );
        }
        proxies
    }

    /// Prázdné/nenastavené proxy = nevěří se nikomu (vždy peer IP) — fail-safe:
    /// chybějící konfigurace nesmí otevřít spoofing, maximálně sloučí clearnet
    /// klienty do jednoho bucketu. Tor má přednost: síť, která je zároveň
    /// v obou sadách, se jako proxy nebere (onion klient by si jinak IP
    /// nastavil hlavičkou).
    pub fn parse(proxies: &str, tor: &str) -> Self {
        Self {
            nets: parse_nets(proxies),
            tor: parse_nets(tor),
        }
    }

    pub fn is_tor(&self, peer: IpAddr) -> bool {
        self.tor.iter().any(|n| n.contains(&peer))
    }

    fn trusts(&self, peer: IpAddr) -> bool {
        !self.is_tor(peer) && self.nets.iter().any(|n| n.contains(&peer))
    }

    /// Klientská IP pro anti-abuse. Forwarded hlavičku uznej jen od trusted
    /// proxy; jinak (onion, dev, přímé spojení) peer IP. Pořadí X-Forwarded-For
    /// → X-Real-Ip drží konzistenci s governor extraktorem. Bere se PRVNÍ
    /// (nejlevější) záznam XFF = původní klient — platí jen díky tomu, že
    /// traefik pro netrusted klienty příchozí XFF přepisuje (nedopisuje).
    pub fn client_ip(&self, peer: IpAddr, headers: &HeaderMap) -> IpAddr {
        if !self.trusts(peer) {
            return peer;
        }
        let from_header = |name: &str| {
            headers
                .get(name)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.split(',').next())
                .and_then(|v| v.trim().parse::<IpAddr>().ok())
        };
        from_header("x-forwarded-for")
            .or_else(|| from_header("x-real-ip"))
            .unwrap_or(peer)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::header::{HeaderName, HeaderValue};
    use axum::http::HeaderMap;

    fn proxies(cfg: &[&str]) -> TrustedProxies {
        TrustedProxies::parse(&cfg.join(","), "")
    }

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn headers(pairs: &[(&str, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.insert(
                HeaderName::from_bytes(k.as_bytes()).unwrap(),
                HeaderValue::from_str(v).unwrap(),
            );
        }
        h
    }

    /// JÁDRO auditu #1: onion peer (mimo trusted sadu) si NESMÍ nastavit IP
    /// hlavičkou — anti-abuse klíč = peer IP tor kontejneru, ne spoof.
    #[test]
    fn onion_peer_nesmi_spoofnout_ip() {
        let tp = proxies(&["10.20.0.0/16"]); // jen pangolin síť
        let onion_peer = ip("172.30.0.5"); // tor kontejner na jiné síti
        let spoof = headers(&[("x-real-ip", "1.2.3.4"), ("x-forwarded-for", "5.6.7.8")]);
        assert_eq!(tp.client_ip(onion_peer, &spoof), onion_peer);
    }

    /// Trusted proxy (traefik) → forwarded hlavička se uzná, klíč = klient.
    #[test]
    fn trusted_proxy_uzna_forwarded() {
        let tp = proxies(&["10.20.0.0/16"]);
        let traefik = ip("10.20.0.3");
        let h = headers(&[("x-forwarded-for", "203.0.113.9")]);
        assert_eq!(tp.client_ip(traefik, &h), ip("203.0.113.9"));
    }

    /// XFF má přednost před X-Real-Ip (konzistence s governor extraktorem);
    /// z řetězce se bere nejlevější (původní klient).
    #[test]
    fn xff_prednost_a_nejlevejsi() {
        let tp = proxies(&["10.20.0.3"]); // holá IP = /32
        let traefik = ip("10.20.0.3");
        let h = headers(&[
            ("x-forwarded-for", "203.0.113.9, 10.20.0.3"),
            ("x-real-ip", "198.51.100.1"),
        ]);
        assert_eq!(tp.client_ip(traefik, &h), ip("203.0.113.9"));
    }

    /// Trusted proxy bez hlaviček → fallback na peer.
    #[test]
    fn trusted_bez_hlavicek_fallback_peer() {
        let tp = proxies(&["10.20.0.0/16"]);
        let traefik = ip("10.20.0.3");
        assert_eq!(tp.client_ip(traefik, &HeaderMap::new()), traefik);
    }

    /// Prázdná konfigurace (fail-safe) → vždy peer, hlavičky se ignorují.
    #[test]
    fn prazdna_konfigurace_vzdy_peer() {
        let tp = proxies(&[]);
        let peer = ip("10.20.0.3");
        let spoof = headers(&[("x-forwarded-for", "1.2.3.4")]);
        assert_eq!(tp.client_ip(peer, &spoof), peer);
    }

    /// IPv6 trusted CIDR taky funguje.
    #[test]
    fn ipv6_trusted_cidr() {
        let tp = proxies(&["fd00::/8"]);
        let peer = ip("fd00::1234");
        let h = headers(&[("x-forwarded-for", "2001:db8::1")]);
        assert_eq!(tp.client_ip(peer, &h), ip("2001:db8::1"));
    }

    /// Síť Toru v sadě proxy omylem: onion peer si IP hlavičkou nastavit nesmí.
    #[test]
    fn tor_peer_neni_proxy_ani_pri_prekryvu() {
        let tp = TrustedProxies::parse("172.20.0.0/16", "172.20.1.0/24");
        let tor = ip("172.20.1.3");
        assert!(tp.is_tor(tor));
        assert_eq!(tp.client_ip(tor, &headers(&[("x-forwarded-for", "1.2.3.4")])), tor);
    }
}
