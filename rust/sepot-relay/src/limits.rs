//! Limity relaye — všechny nastavitelné přes env.
//!
//! Proč env a ne konstanty: limit, který se pod skutečnou zátěží ukáže
//! špatně (sdílené CGNAT adresy, Tor, nápor po zveřejnění), se musí dát
//! změnit úpravou `.env` a restartem (sekundy), ne novým buildem.
//!
//! Výchozí hodnoty drží chování dřívějších verzí se třemi vědomými
//! výjimkami popsanými u polí: registrace per IP je výrazně volnější (mobilní
//! CGNAT dá za jednu IPv4 stovky lidí) a DB místo toho chrání globální strop;
//! Tor klienti mají vlastní, větší buckety (všichni přicházejí z jedné
//! adresy); a nové kvóty (odesílatel, přílohy na účet, místo na disku) dřív
//! neexistovaly.
//!
//! Rate limity jsou token buckety: `*_BURST` tokenů naráz, jeden token zpět
//! každých `*_PERIOD_MS` ms. Kvóty bajtů/kusů: 0 = bez omezení.

use std::net::{IpAddr, SocketAddr};
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{ConnectInfo, Request, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use governor::clock::{Clock, DefaultClock};
use governor::{DefaultDirectRateLimiter, DefaultKeyedRateLimiter, Quota};

use crate::net::TrustedProxies;

const MIB: u64 = 1024 * 1024;

fn env_parse<T: std::str::FromStr>(name: &str, default: T) -> T {
    match std::env::var(name) {
        Ok(raw) => match raw.trim().parse() {
            Ok(v) => v,
            Err(_) => {
                tracing::warn!(name, "neplatná hodnota, platí výchozí");
                default
            }
        },
        Err(_) => default,
    }
}

/// Token bucket: `burst` požadavků naráz, pak jeden za `period`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rate {
    pub burst: u32,
    pub period: Duration,
}

impl Rate {
    pub const fn new(burst: u32, period_ms: u64) -> Self {
        Self {
            burst,
            period: Duration::from_millis(period_ms),
        }
    }

    /// `{prefix}_BURST` a `{prefix}_PERIOD_MS`, každá s vlastní výchozí hodnotou.
    fn from_env(prefix: &str, default: Rate) -> Self {
        let burst = env_parse(&format!("{prefix}_BURST"), default.burst).max(1);
        let period_ms = env_parse(
            &format!("{prefix}_PERIOD_MS"),
            default.period.as_millis() as u64,
        )
        .max(1);
        Self::new(burst, period_ms)
    }

    fn quota(&self) -> Quota {
        Quota::with_period(self.period)
            .expect("period > 0")
            .allow_burst(NonZeroU32::new(self.burst).expect("burst > 0"))
    }
}

/// Oddělené buckety: clearnet klienti (podle IP klienta) a všichni Tor
/// klienti dohromady (sdílí adresu kontejneru Toru).
#[derive(Clone, Copy, Debug)]
pub struct RatePair {
    pub clearnet: Rate,
    pub tor: Rate,
}

#[derive(Clone, Debug)]
pub struct Limits {
    /// Spojení relaye do Postgresu (`SEPOT_DB_POOL`, výchozí 8).
    pub db_pool: u32,

    /// `SEPOT_RL_REGISTER_*` na IP: 50 naráz, pak 1 za 10 s (360/h).
    /// Dřív 10 + 1/5 min: za CGNAT mobilního operátora čekal jedenáctý
    /// člověk na účet minuty.
    pub register: RatePair,
    /// `SEPOT_RL_REGISTER_POW_*` na IP pro registrace s platným proof-of-work
    /// (pow.rs): 200 naráz, pak 1 za 2 s (1 800/h). Výpočet zdražuje každou
    /// registraci, takže velký CGNAT může dostat víc bez rizika levné záplavy
    /// z jedné adresy. Globální strop platí společně s registracemi bez PoW.
    pub register_pow: RatePair,
    /// `SEPOT_RL_POW_CHALLENGE_*`: vydávání výzev (jen HMAC, nic do DB).
    pub pow_challenge: RatePair,
    /// `SEPOT_RL_REGISTER_GLOBAL_*`: všechny registrace dohromady, 600 naráz,
    /// pak 40/s. Chrání DB (změřeno 117–147 registrací/s na 2 jádrech), když
    /// registruje mnoho adres naráz; BURST 0 = vypnuto.
    pub register_global: Option<Rate>,
    /// `SEPOT_REGISTRATION_PAUSED=1`: nové registrace dostanou 503 + Retry-After
    /// (nouzový vypínač při záplavě registrací); existující zařízení jedou dál.
    pub registration_paused: bool,
    /// `SEPOT_RL_GENERAL_*`: server-info, bundly klíčů, certifikát, smazání.
    pub general: RatePair,
    /// `SEPOT_RL_ATTACHMENTS_*`: upload i stažení příloh.
    pub attachments: RatePair,
    /// `SEPOT_RL_WS_*`: otevírání WS spojení (každý AUTH = dotaz do DB).
    pub ws_upgrade: RatePair,

    /// `SEPOT_MAX_CONNS_PER_IP` (výchozí 32) a `SEPOT_TOR_MAX_CONNS`
    /// (výchozí 5000, všichni Tor klienti dohromady).
    pub max_conns_per_ip: u32,
    pub max_conns_tor: u32,
    /// `SEPOT_WS_FRAMES_PER_10S`: drahé rámce na spojení (výchozí 200).
    pub ws_frames_per_window: u32,

    /// `SEPOT_OTP_ISSUE_PER_HOUR`: vydaných one-time prekeys na adresu za hodinu.
    pub otp_issue_per_hour: u32,
    /// `SEPOT_MAX_STORED_OTP`: zásoba one-time prekeys na zařízení.
    pub max_stored_otp: i64,
    /// `SEPOT_CALL_WAKES_PER_10MIN` a `SEPOT_CALL_WAKE_MIN_INTERVAL_S`.
    pub call_wakes_per_window: usize,
    pub call_wake_min_interval: Duration,

    /// `SEPOT_QUEUE_MAX_BYTES_PER_RECIPIENT` (50 MiB) a
    /// `SEPOT_QUEUE_MAX_PER_RECIPIENT` (10 000 obálek): přebytek padá od nejstarších.
    pub queue_max_bytes_per_recipient: i64,
    pub queue_max_per_recipient: i64,
    /// `SEPOT_SEND_MAX_PER_HOUR` / `SEPOT_SEND_MAX_BYTES_PER_HOUR` na odesílající
    /// účet (ukládané obálky; „píše…“ se nepočítá).
    pub send_per_hour: u64,
    pub send_bytes_per_hour: u64,

    /// `SEPOT_ATT_ACCOUNT_BYTES_PER_DAY` (100 MiB) a
    /// `SEPOT_ATT_ACCOUNT_STORED_BYTES` (250 MiB živých v rámci TTL).
    pub att_account_bytes_per_day: u64,
    pub att_account_stored_bytes: u64,

    /// `SEPOT_DISK_MIN_FREE_PCT_ATTACHMENTS` (15) a `SEPOT_DISK_MIN_FREE_PCT_QUEUE`
    /// (8): pod tímto podílem volného místa na datovém filesystému relay
    /// odmítá nové přílohy, resp. nové offline obálky (507) — Postgres si tak
    /// nechá místo na WAL a na všechno, co už přijal.
    pub disk_min_free_pct_attachments: f64,
    pub disk_min_free_pct_queue: f64,
}

impl Limits {
    pub fn from_env() -> Self {
        let pair = |prefix: &str, clearnet: Rate, tor: Rate| RatePair {
            clearnet: Rate::from_env(prefix, clearnet),
            tor: Rate::from_env(&format!("{prefix}_TOR"), tor),
        };
        let global = Rate::from_env("SEPOT_RL_REGISTER_GLOBAL", Rate::new(600, 25));
        let global_off = env_parse("SEPOT_RL_REGISTER_GLOBAL_BURST", 600u32) == 0;
        Self {
            db_pool: env_parse("SEPOT_DB_POOL", 8u32).max(1),
            register: pair(
                "SEPOT_RL_REGISTER",
                Rate::new(50, 10_000),
                Rate::new(100, 3_000),
            ),
            register_pow: pair(
                "SEPOT_RL_REGISTER_POW",
                Rate::new(200, 2_000),
                Rate::new(300, 1_000),
            ),
            pow_challenge: pair(
                "SEPOT_RL_POW_CHALLENGE",
                Rate::new(120, 100),
                Rate::new(600, 20),
            ),
            register_global: (!global_off).then_some(global),
            registration_paused: matches!(
                std::env::var("SEPOT_REGISTRATION_PAUSED").as_deref(),
                Ok("1") | Ok("true")
            ),
            general: pair("SEPOT_RL_GENERAL", Rate::new(60, 500), Rate::new(600, 20)),
            attachments: pair(
                "SEPOT_RL_ATTACHMENTS",
                Rate::new(30, 1_000),
                Rate::new(300, 100),
            ),
            ws_upgrade: pair("SEPOT_RL_WS", Rate::new(120, 100), Rate::new(600, 20)),
            max_conns_per_ip: env_parse("SEPOT_MAX_CONNS_PER_IP", 32u32),
            max_conns_tor: env_parse("SEPOT_TOR_MAX_CONNS", 5000u32),
            ws_frames_per_window: env_parse("SEPOT_WS_FRAMES_PER_10S", 200u32),
            otp_issue_per_hour: env_parse("SEPOT_OTP_ISSUE_PER_HOUR", 30u32),
            max_stored_otp: env_parse("SEPOT_MAX_STORED_OTP", 100i64),
            call_wakes_per_window: env_parse("SEPOT_CALL_WAKES_PER_10MIN", 6usize),
            call_wake_min_interval: Duration::from_secs(env_parse(
                "SEPOT_CALL_WAKE_MIN_INTERVAL_S",
                10u64,
            )),
            queue_max_bytes_per_recipient: env_parse(
                "SEPOT_QUEUE_MAX_BYTES_PER_RECIPIENT",
                (50 * MIB) as i64,
            ),
            queue_max_per_recipient: env_parse("SEPOT_QUEUE_MAX_PER_RECIPIENT", 10_000i64),
            send_per_hour: env_parse("SEPOT_SEND_MAX_PER_HOUR", 5_000u64),
            send_bytes_per_hour: env_parse("SEPOT_SEND_MAX_BYTES_PER_HOUR", 32 * MIB),
            att_account_bytes_per_day: env_parse("SEPOT_ATT_ACCOUNT_BYTES_PER_DAY", 100 * MIB),
            att_account_stored_bytes: env_parse("SEPOT_ATT_ACCOUNT_STORED_BYTES", 250 * MIB),
            disk_min_free_pct_attachments: env_parse("SEPOT_DISK_MIN_FREE_PCT_ATTACHMENTS", 15.0),
            disk_min_free_pct_queue: env_parse("SEPOT_DISK_MIN_FREE_PCT_QUEUE", 8.0),
        }
    }
}

/// Rate limiter skupiny rout, jen v paměti. Nic se nezapisuje ani neloguje
/// (adresy klientů jsou osobní údaj).
pub struct RateLimit {
    clearnet: DefaultKeyedRateLimiter<IpAddr>,
    tor: DefaultDirectRateLimiter,
    global: Option<Arc<DefaultDirectRateLimiter>>,
    trusted: Arc<TrustedProxies>,
}

/// Registrace bez a s proof-of-work: vlastní buckety per IP, společný
/// globální strop (chrání DB bez ohledu na to, kdo PoW přinesl).
pub struct RegisterLimits {
    pub base: Arc<RateLimit>,
    pub pow: Arc<RateLimit>,
}

impl RegisterLimits {
    pub fn new(limits: &Limits, trusted: Arc<TrustedProxies>) -> Arc<Self> {
        let base = RateLimit::new(limits.register, limits.register_global, trusted);
        let pow = base.sibling(limits.register_pow);
        Arc::new(Self { base, pow })
    }
}

impl RateLimit {
    pub fn new(rates: RatePair, global: Option<Rate>, trusted: Arc<TrustedProxies>) -> Arc<Self> {
        let global = global.map(|g| Arc::new(DefaultDirectRateLimiter::direct(g.quota())));
        Self::build(rates, global, trusted)
    }

    /// Limiter s vlastními buckety per IP a stejným globálním stropem.
    pub fn sibling(&self, rates: RatePair) -> Arc<Self> {
        Self::build(rates, self.global.clone(), self.trusted.clone())
    }

    fn build(
        rates: RatePair,
        global: Option<Arc<DefaultDirectRateLimiter>>,
        trusted: Arc<TrustedProxies>,
    ) -> Arc<Self> {
        let limiter = Arc::new(Self {
            clearnet: DefaultKeyedRateLimiter::keyed(rates.clearnet.quota()),
            tor: DefaultDirectRateLimiter::direct(rates.tor.quota()),
            global,
            trusted,
        });
        // Zapomenout nečinné buckety, ať mapa neroste s každou kdy viděnou IP.
        let weak = Arc::downgrade(&limiter);
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(60));
            loop {
                tick.tick().await;
                let Some(limiter) = weak.upgrade() else { break };
                limiter.clearnet.retain_recent();
            }
        });
        limiter
    }

    /// `Ok` = povoleno, `Err(wait)` = odmítnuto, zkusit znovu za `wait`.
    pub fn check(&self, peer: IpAddr, headers: &axum::http::HeaderMap) -> Result<(), Duration> {
        let now = DefaultClock::default().now();
        let own = if self.trusted.is_tor(peer) {
            self.tor.check()
        } else {
            self.clearnet
                .check_key(&self.trusted.client_ip(peer, headers))
        };
        own.map_err(|not_until| not_until.wait_time_from(now))?;
        if let Some(global) = &self.global {
            global.check().map_err(|not_until| not_until.wait_time_from(now))?;
        }
        Ok(())
    }
}

/// axum middleware: 429 s Retry-After, když je bucket prázdný.
pub async fn enforce(
    State(limit): State<Arc<RateLimit>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    request: Request,
    next: Next,
) -> Response {
    match limit.check(peer.ip(), request.headers()) {
        Ok(()) => next.run(request).await,
        Err(wait) => too_many(wait),
    }
}

pub fn too_many(wait: Duration) -> Response {
    let secs = wait.as_secs() + u64::from(wait.subsec_nanos() > 0);
    let mut response = (StatusCode::TOO_MANY_REQUESTS, "příliš mnoho požadavků").into_response();
    if let Ok(value) = HeaderValue::from_str(&secs.max(1).to_string()) {
        response.headers_mut().insert(header::RETRY_AFTER, value);
    }
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderMap;

    fn trusted(proxies: &str, tor: &str) -> Arc<TrustedProxies> {
        Arc::new(TrustedProxies::parse(proxies, tor))
    }

    fn xff(ip: &str) -> HeaderMap {
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", ip.parse().unwrap());
        h
    }

    #[tokio::test]
    async fn clearnet_bucket_je_na_ip_klienta() {
        let rates = RatePair {
            clearnet: Rate::new(2, 3_600_000),
            tor: Rate::new(100, 1),
        };
        let rl = RateLimit::new(rates, None, trusted("10.0.0.1", ""));
        let proxy: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(rl.check(proxy, &xff("198.51.100.1")).is_ok());
        assert!(rl.check(proxy, &xff("198.51.100.1")).is_ok());
        let wait = rl.check(proxy, &xff("198.51.100.1")).unwrap_err();
        assert!(wait > Duration::from_secs(3000), "Retry-After odpovídá periodě");
        assert!(rl.check(proxy, &xff("198.51.100.2")).is_ok(), "jiný klient limit nesdílí");
    }

    #[tokio::test]
    async fn tor_ma_vlastni_bucket_a_nepodvrhne_ip() {
        let rates = RatePair {
            clearnet: Rate::new(1, 3_600_000),
            tor: Rate::new(3, 3_600_000),
        };
        let rl = RateLimit::new(rates, None, trusted("10.0.0.1", "172.20.1.0/24"));
        let tor_peer: IpAddr = "172.20.1.3".parse().unwrap();
        for i in 0..3 {
            // podvržená XFF z Toru nesmí založit nové buckety
            assert!(rl.check(tor_peer, &xff(&format!("203.0.113.{i}"))).is_ok());
        }
        assert!(rl.check(tor_peer, &xff("203.0.113.99")).is_err());
        // vyčerpaný Tor bucket clearnet klienta neomezí
        let proxy: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(rl.check(proxy, &xff("198.51.100.1")).is_ok());
    }

    #[tokio::test]
    async fn globalni_strop_plati_pres_klienty() {
        let rates = RatePair {
            clearnet: Rate::new(100, 1),
            tor: Rate::new(100, 1),
        };
        let rl = RateLimit::new(rates, Some(Rate::new(2, 3_600_000)), trusted("10.0.0.1", ""));
        let proxy: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(rl.check(proxy, &xff("198.51.100.1")).is_ok());
        assert!(rl.check(proxy, &xff("198.51.100.2")).is_ok());
        assert!(rl.check(proxy, &xff("198.51.100.3")).is_err());
    }

    #[tokio::test]
    async fn sourozenec_sdili_globalni_strop_ne_ip_bucket() {
        let base_rates = RatePair {
            clearnet: Rate::new(1, 3_600_000),
            tor: Rate::new(1, 3_600_000),
        };
        let pow_rates = RatePair {
            clearnet: Rate::new(5, 3_600_000),
            tor: Rate::new(5, 3_600_000),
        };
        let base = RateLimit::new(base_rates, Some(Rate::new(3, 3_600_000)), trusted("10.0.0.1", ""));
        let pow = base.sibling(pow_rates);
        let proxy: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(base.check(proxy, &xff("198.51.100.1")).is_ok());
        assert!(base.check(proxy, &xff("198.51.100.1")).is_err(), "IP bucket bez PoW vyčerpán");
        assert!(pow.check(proxy, &xff("198.51.100.1")).is_ok(), "s PoW vlastní bucket");
        assert!(pow.check(proxy, &xff("198.51.100.1")).is_ok());
        assert!(pow.check(proxy, &xff("198.51.100.1")).is_err(), "globální strop 3 společný");
    }

    #[test]
    fn rate_z_env_padne_na_vychozi_po_polich() {
        std::env::set_var("SEPOT_TEST_RL_BURST", "7");
        std::env::set_var("SEPOT_TEST_RL_PERIOD_MS", "nonsense");
        let rate = Rate::from_env("SEPOT_TEST_RL", Rate::new(1, 250));
        assert_eq!(rate, Rate::new(7, 250));
    }
}
