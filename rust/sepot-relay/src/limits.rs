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
//! Čerstvý účet (`fresh_account_age`) má kvóty nižší: založit účet nic
//! nestojí, takže plné kvóty hned po registraci by každý limit „na účet“
//! násobily počtem účtů, které si útočník právě vyrobil. Kdo počká, limity
//! obejde — čekání ale útok zdražuje a dává čas si ho všimnout.
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
const SECONDS_PER_HOUR: u64 = 3600;

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
    /// registruje mnoho adres naráz; BURST 0 = vypnuto. Počítají se jen
    /// registrace s platnými podpisy a důkazem držení klíče ([`GlobalLimit`]).
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
    /// `SEPOT_QUEUE_MAX_PER_RECIPIENT` (10 000 obálek): do plné fronty relay
    /// další obálku nepřijme (507). Starší se nemažou — kdo zná adresu, by
    /// jinak příjemci přeplněním fronty potichu smazal čekající zprávy.
    pub queue_max_bytes_per_recipient: i64,
    pub queue_max_per_recipient: i64,
    /// `SEPOT_QUEUE_MAX_BYTES_TOTAL` (2 GiB): strop obálek ve frontě všech
    /// příjemců dohromady. Od poloviny se krátí příděl jednoho příjemce, nad
    /// stropem zbývá každému jen malý zaručený příděl (gauge.rs).
    pub queue_max_bytes_total: i64,
    /// `SEPOT_SEND_MAX_PER_HOUR` / `SEPOT_SEND_MAX_BYTES_PER_HOUR` na odesílající
    /// účet (ukládané obálky; „píše…“ má vlastní kvótu).
    pub send_per_hour: u64,
    pub send_bytes_per_hour: u64,
    /// `SEPOT_FRESH_ACCOUNT_HOURS` (72): po tuhle dobu od registrace je účet
    /// čerstvý a platí pro něj nižší kvóty; 0 = bez rozlišení.
    pub fresh_account_age: Duration,
    /// `SEPOT_SEND_FRESH_BYTES_PER_HOUR` (16 MiB): bajty ukládaných obálek za
    /// hodinu od čerstvého účtu. Na psaní to stačí s velkou rezervou (obálka
    /// s textem má kolem 1 KiB). Míru udávají fotky do skupiny: obálka
    /// s fotkou nese náhled (desítky KiB) a jde každému členovi zvlášť, a
    /// čerstvý je i dlouholetý uživatel po obnově na novém telefonu.
    pub send_fresh_bytes_per_hour: u64,
    /// `SEPOT_SEND_SELF_BYTES_PER_HOUR` (2 MiB): obálky na vlastní adresu.
    /// Běžná appka si sama sobě neposílá; fronta, kterou si odesílatel sám
    /// nevybírá, je nejlevnější způsob, jak relayi plnit disk.
    pub send_self_bytes_per_hour: u64,

    /// `SEPOT_EPHEMERAL_MAX_BYTES` (4 KiB): strop payloadu obálky „píše…“.
    /// Zapečetěné „píše…“ má stovky bajtů, s úvodním PQXDH materiálem
    /// (Kyber ciphertext 1 568 B) kolem 2,5 KiB.
    pub ephemeral_max_bytes: usize,
    /// `SEPOT_EPHEMERAL_PER_HOUR` (3 000) na odesílající účet. Appka posílá
    /// nejvýš jedno „píše…“ za 4 s na konverzaci, ve skupině až 19 obálek.
    pub ephemeral_per_hour: u64,
    /// `SEPOT_EPHEMERAL_TARGET_BURST` (30) a `SEPOT_EPHEMERAL_TARGET_PERIOD_S`
    /// (30): kolik „píše…“ smí dojít na jednu adresu naráz a za jak dlouho
    /// se příděl doplní.
    pub ephemeral_target_burst: u64,
    pub ephemeral_target_period: Duration,

    /// `SEPOT_ALERTS_PER_HOUR` (60): viditelných notifikací se zvukem od
    /// jednoho odesílatele na jeden cíl za hodinu; nad strop jde jen tichý
    /// budíček. Přihlášení příjemce počítadla nuluje. 0 = bez stropu.
    pub alerts_per_hour: usize,

    /// `SEPOT_ATT_ACCOUNT_BYTES_PER_DAY` (100 MiB) a
    /// `SEPOT_ATT_ACCOUNT_STORED_BYTES` (250 MiB živých v rámci TTL).
    pub att_account_bytes_per_day: u64,
    pub att_account_stored_bytes: u64,
    /// `SEPOT_ATT_FRESH_BYTES_PER_DAY` (30 MiB): kolik příloh smí čerstvý
    /// účet nahrát za den a zároveň kolik jich smí mít uloženo. Uložené
    /// přílohy se z účtu odepíšou až po vypršení (30 dní), takže za celou
    /// dobu, co je účet čerstvý, nahraje dohromady nejvýš tolik — není to
    /// 30 MiB každý den. Nový uživatel pošle fotky i jedno video v plné
    /// velikosti hned po registraci; plnit úložiště čerstvě vyrobenými účty
    /// ale chce násobně víc účtů než dřív.
    pub att_fresh_bytes_per_day: u64,
    /// `SEPOT_ATT_EVICT_MIN_AGE_HOURS` (48): když je úložiště příloh plné,
    /// nová příloha vytlačí nejstarší bloby starší než tohle; 0 = nevytlačovat
    /// (plné úložiště pak odmítá až do vypršení TTL). Dřív stačilo úložiště
    /// jednou zaplnit a 30 dní nikdo nic neposlal; teď musí útočník
    /// zaplňovat pořád dokola. Cena: pod tlakem přijde o přílohu příjemce,
    /// který si ji do té doby nestáhl.
    pub att_evict_min_age_hours: i32,

    /// `SEPOT_DISK_MIN_FREE_PCT_ATTACHMENTS` (15) a `SEPOT_DISK_MIN_FREE_PCT_QUEUE`
    /// (8): pod tímto podílem volného místa na datovém filesystému relay
    /// odmítá nové přílohy, resp. nové offline obálky (507) — Postgres si tak
    /// nechá místo na WAL a na všechno, co už přijal.
    pub disk_min_free_pct_attachments: f64,
    pub disk_min_free_pct_queue: f64,

    /// `SEPOT_INACTIVE_CLEANUP=1`: hodinová údržba maže registrace bez
    /// připojení `cleanup::INACTIVE_REGISTRATION_DAYS` dní. Výchozí vypnuto:
    /// zapnout ho smí až podmínky služby, které úklid uvádějí, a appka,
    /// která po úklidu nabídne obnovu registrace.
    pub inactive_cleanup: bool,
}

/// Neplatná hodnota vypínače úklidu.
#[derive(Debug, PartialEq, Eq)]
pub struct InvalidSwitch;

/// `SEPOT_INACTIVE_CLEANUP`: přesně "1" zapne, chybějící nebo "0" vypne.
/// Cokoli jiného ("true", "180") je chyba a úklid zůstane vypnutý: maže
/// registrace, takže překlep ho nesmí zapnout.
pub fn parse_inactive_cleanup(raw: Option<&str>) -> Result<bool, InvalidSwitch> {
    match raw {
        None | Some("0") => Ok(false),
        Some("1") => Ok(true),
        Some(_) => Err(InvalidSwitch),
    }
}

/// Vypínač úklidu z prostředí; podpříkazy ho čtou stejně jako server.
pub fn inactive_cleanup_from_env() -> Result<bool, InvalidSwitch> {
    parse_inactive_cleanup(std::env::var("SEPOT_INACTIVE_CLEANUP").ok().as_deref())
}

fn inactive_cleanup_or_off(setting: Result<bool, InvalidSwitch>) -> bool {
    setting.unwrap_or_else(|InvalidSwitch| {
        tracing::error!("SEPOT_INACTIVE_CLEANUP: neplatná hodnota, úklid vypnut");
        false
    })
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
            queue_max_bytes_total: env_parse("SEPOT_QUEUE_MAX_BYTES_TOTAL", (2048 * MIB) as i64),
            send_per_hour: env_parse("SEPOT_SEND_MAX_PER_HOUR", 5_000u64),
            send_bytes_per_hour: env_parse("SEPOT_SEND_MAX_BYTES_PER_HOUR", 32 * MIB),
            fresh_account_age: Duration::from_secs(
                env_parse("SEPOT_FRESH_ACCOUNT_HOURS", 72u64) * SECONDS_PER_HOUR,
            ),
            send_fresh_bytes_per_hour: env_parse("SEPOT_SEND_FRESH_BYTES_PER_HOUR", 16 * MIB),
            send_self_bytes_per_hour: env_parse("SEPOT_SEND_SELF_BYTES_PER_HOUR", 2 * MIB),
            ephemeral_max_bytes: env_parse("SEPOT_EPHEMERAL_MAX_BYTES", 4096usize),
            ephemeral_per_hour: env_parse("SEPOT_EPHEMERAL_PER_HOUR", 3_000u64),
            ephemeral_target_burst: env_parse("SEPOT_EPHEMERAL_TARGET_BURST", 30u64),
            ephemeral_target_period: Duration::from_secs(
                env_parse("SEPOT_EPHEMERAL_TARGET_PERIOD_S", 30u64).max(1),
            ),
            alerts_per_hour: env_parse("SEPOT_ALERTS_PER_HOUR", 60usize),
            att_account_bytes_per_day: env_parse("SEPOT_ATT_ACCOUNT_BYTES_PER_DAY", 100 * MIB),
            att_account_stored_bytes: env_parse("SEPOT_ATT_ACCOUNT_STORED_BYTES", 250 * MIB),
            att_fresh_bytes_per_day: env_parse("SEPOT_ATT_FRESH_BYTES_PER_DAY", 30 * MIB),
            att_evict_min_age_hours: env_parse("SEPOT_ATT_EVICT_MIN_AGE_HOURS", 48i32).max(0),
            disk_min_free_pct_attachments: env_parse("SEPOT_DISK_MIN_FREE_PCT_ATTACHMENTS", 15.0),
            disk_min_free_pct_queue: env_parse("SEPOT_DISK_MIN_FREE_PCT_QUEUE", 8.0),
            inactive_cleanup: inactive_cleanup_or_off(inactive_cleanup_from_env()),
        }
    }
}

/// Rate limiter skupiny rout, jen v paměti. Nic se nezapisuje ani neloguje
/// (adresy klientů jsou osobní údaj).
pub struct RateLimit {
    clearnet: DefaultKeyedRateLimiter<IpAddr>,
    tor: DefaultDirectRateLimiter,
    trusted: Arc<TrustedProxies>,
}

/// Registrace bez a s proof-of-work: vlastní buckety per IP. Globální
/// strop je zvlášť ([`GlobalLimit`]) a platí pro obě cesty.
pub struct RegisterLimits {
    pub base: Arc<RateLimit>,
    pub pow: Arc<RateLimit>,
}

impl RegisterLimits {
    pub fn new(limits: &Limits, trusted: Arc<TrustedProxies>) -> Arc<Self> {
        let base = RateLimit::new(limits.register, trusted.clone());
        let pow = RateLimit::new(limits.register_pow, trusted);
        Arc::new(Self { base, pow })
    }
}

/// Strop přes všechny klienty dohromady (registrace: chrání DB).
///
/// Bere se až po ověření podpisů a důkazu držení klíče. Dřív ubíral každý
/// požadavek, který prošel limitem na adresu, i s nesmyslným tělem: kdo měl
/// dost adres, vybral strop požadavky, které se do DB nikdy nedostaly, a
/// skutečné registrace dostávaly 429.
pub struct GlobalLimit(Option<DefaultDirectRateLimiter>);

impl GlobalLimit {
    pub fn new(rate: Option<Rate>) -> Self {
        Self(rate.map(|rate| DefaultDirectRateLimiter::direct(rate.quota())))
    }

    /// `Ok` = povoleno, `Err(wait)` = odmítnuto, zkusit znovu za `wait`.
    pub fn check(&self) -> Result<(), Duration> {
        let Some(limiter) = &self.0 else {
            return Ok(());
        };
        limiter
            .check()
            .map_err(|not_until| not_until.wait_time_from(DefaultClock::default().now()))
    }
}

impl RateLimit {
    pub fn new(rates: RatePair, trusted: Arc<TrustedProxies>) -> Arc<Self> {
        let limiter = Arc::new(Self {
            clearnet: DefaultKeyedRateLimiter::keyed(rates.clearnet.quota()),
            tor: DefaultDirectRateLimiter::direct(rates.tor.quota()),
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
                .check_key(&self.trusted.client_key(peer, headers))
        };
        own.map_err(|not_until| not_until.wait_time_from(now))
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

pub const TEXT_TOO_MANY: &str = "příliš mnoho požadavků";

/// Hodnota Retry-After: celé sekundy nahoru, nejméně jedna.
pub fn retry_after(wait: Duration) -> HeaderValue {
    let secs = wait.as_secs() + u64::from(wait.subsec_nanos() > 0);
    HeaderValue::from(secs.max(1))
}

pub fn too_many(wait: Duration) -> Response {
    let mut response = (StatusCode::TOO_MANY_REQUESTS, TEXT_TOO_MANY).into_response();
    response
        .headers_mut()
        .insert(header::RETRY_AFTER, retry_after(wait));
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
        let rl = RateLimit::new(rates, trusted("10.0.0.1", ""));
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
        let rl = RateLimit::new(rates, trusted("10.0.0.1", "172.20.1.0/24"));
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

    #[test]
    fn globalni_strop_plati_pres_klienty() {
        let global = GlobalLimit::new(Some(Rate::new(2, 3_600_000)));
        assert!(global.check().is_ok());
        assert!(global.check().is_ok());
        let wait = global.check().expect_err("strop vyčerpán");
        assert!(wait > Duration::from_secs(3000), "Retry-After odpovídá periodě");
        let off = GlobalLimit::new(None);
        for _ in 0..1000 {
            assert!(off.check().is_ok());
        }
    }

    #[tokio::test]
    async fn registrace_s_pow_ma_vlastni_ip_bucket() {
        let mut limits = Limits::from_env();
        limits.register = RatePair {
            clearnet: Rate::new(1, 3_600_000),
            tor: Rate::new(1, 3_600_000),
        };
        limits.register_pow = RatePair {
            clearnet: Rate::new(2, 3_600_000),
            tor: Rate::new(2, 3_600_000),
        };
        let register = RegisterLimits::new(&limits, trusted("10.0.0.1", ""));
        let proxy: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(register.base.check(proxy, &xff("198.51.100.1")).is_ok());
        assert!(
            register.base.check(proxy, &xff("198.51.100.1")).is_err(),
            "IP bucket bez PoW vyčerpán"
        );
        assert!(register.pow.check(proxy, &xff("198.51.100.1")).is_ok(), "s PoW vlastní bucket");
        assert!(register.pow.check(proxy, &xff("198.51.100.1")).is_ok());
        assert!(register.pow.check(proxy, &xff("198.51.100.1")).is_err());
    }

    /// Adresy z jedné IPv6 sítě /64 sdílí bucket: jinak má jeden zákazník
    /// pro každý požadavek čerstvý.
    #[tokio::test]
    async fn ipv6_bucket_je_na_sit() {
        let rates = RatePair {
            clearnet: Rate::new(2, 3_600_000),
            tor: Rate::new(2, 3_600_000),
        };
        let rl = RateLimit::new(rates, trusted("10.0.0.1", ""));
        let proxy: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(rl.check(proxy, &xff("2001:db8:1:2::1")).is_ok());
        assert!(rl.check(proxy, &xff("2001:db8:1:2:ffff::2")).is_ok());
        assert!(
            rl.check(proxy, &xff("2001:db8:1:2:1234:5678:9abc:def0")).is_err(),
            "třetí adresa téže /64"
        );
        assert!(rl.check(proxy, &xff("2001:db8:1:3::1")).is_ok(), "jiná /64");
    }

    #[test]
    fn limity_vypinac_uklidu() {
        assert_eq!(parse_inactive_cleanup(None), Ok(false));
        assert_eq!(parse_inactive_cleanup(Some("0")), Ok(false));
        assert_eq!(parse_inactive_cleanup(Some("1")), Ok(true));
        for typo in ["true", "180", " 1", ""] {
            assert_eq!(
                parse_inactive_cleanup(Some(typo)),
                Err(InvalidSwitch),
                "{typo:?}"
            );
            assert!(!inactive_cleanup_or_off(parse_inactive_cleanup(Some(typo))));
        }
        assert!(inactive_cleanup_or_off(Ok(true)));
    }

    /// Neplatná hodnota vypínače: úklid vypnutý a chyba v logu, ať si
    /// provozovatel překlepu všimne.
    #[test]
    fn limity_vypinac_uklidu_neplatna_hodnota_zaloguje_chybu() {
        let log = crate::testkit::LogCapture::default();
        let guard = log.start();
        let setting = parse_inactive_cleanup(Some("true"));
        assert!(!inactive_cleanup_or_off(setting));
        drop(guard);
        let text = log.text();
        assert!(text.contains("ERROR"), "{text}");
        assert!(text.contains("SEPOT_INACTIVE_CLEANUP"), "{text}");
    }

    #[test]
    fn rate_z_env_padne_na_vychozi_po_polich() {
        std::env::set_var("SEPOT_TEST_RL_BURST", "7");
        std::env::set_var("SEPOT_TEST_RL_PERIOD_MS", "nonsense");
        let rate = Rate::from_env("SEPOT_TEST_RL", Rate::new(1, 250));
        assert_eq!(rate, Rate::new(7, 250));
    }
}
