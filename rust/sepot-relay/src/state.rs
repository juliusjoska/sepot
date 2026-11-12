use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

use chrono::{DateTime, Duration, Utc};
use dashmap::DashMap;
use prost::Message;
use sepot_proto::v1;
use sepot_proto::MAX_ENVELOPE_PAYLOAD;
use sqlx::PgPool;
use tokio::sync::{oneshot, Notify};

use crate::blocking::{self, Registration, Retire};
use crate::certs::CertAuthority;
use crate::fingerprint::Fingerprint;
use crate::gauge::{QueueTotal, QueueUsage, RecipientCaps, RecipientGauges};
use crate::net::TrustedProxies;
use crate::outbox::{Outbox, OUTBOX_MAX_BYTES};

/// TTL offline fronty.
pub const QUEUE_TTL_DAYS: i64 = 30;

/// Největší zakódovaná obálka, kterou fronta přijme (CHECK v migraci 0001).
const MAX_STORED_ENVELOPE_BYTES: usize = 262_144;

/// Dávka při vylévání fronty: nejvýš tolik obálek a nejvýš tolik bajtů
/// naráz v paměti. Samotný počet nestačil: 64 obálek po 256 KiB je 16 MiB
/// na každé spojení, které právě vylévá. První obálka dávky se bere vždy,
/// i kdyby byla větší než strop.
const FLUSH_BATCH: i64 = 64;
const FLUSH_BATCH_BYTES: i64 = OUTBOX_MAX_BYTES as i64;

/// Po kolika marných pokusech o doručení obálku zahodit.
///
/// Ztracený ACK je jednosměrka: klient obálku dešifruje (ratchet postoupí),
/// uloží a pošle ACK — když ten cestou zmizí (mrtvé spojení), relay obálku
/// drží dál, jenže druhý pokus o dešifrování už libsignal odmítne. Klient ji
/// tedy neACKuje a fronta se otravuje: tatáž obálka se posílá při každém
/// připojení až do TTL 30 dní a příjemce ji nikdy nedostane. Strop tomu dá
/// konec. Osm pokusů je velkoryse nad běžné „appka spadla před ACK".
const MAX_DELIVERY_ATTEMPTS: i16 = 8;

/// Strop pokusů smí obálku zahodit až po téhle době ve frontě. Pokus se
/// počítá za každé připojení. iPhone, který appku otevírá a uspává, jich
/// za den spálí desítky — a klient do 1.2.4 nechával bez ACK i obálky, které
/// předběhly stažení certifikátu nebo přišly těsně před zamčením. Zahazovaly
/// se tak i obálky, které by se dalším pokusem v pořádku doručily. Opravdu
/// neprůchodné obálky (ztracený ACK u klienta do 1.2.4) zmizí o pár dní
/// později; klient od 1.2.5 nedešifrovatelné obálky ACKuje sám.
const MIN_HOURS_BEFORE_DROP: i32 = 72;

/// Jak dlouho po posledním rámci od klienta se spojení ještě považuje za
/// prokazatelně živé. Klient odpovídá na ping à 30 s (ws::PING_INTERVAL),
/// takže dva zmeškané cykly znamenají, že už nedýchá.
const FRESH_CONNECTION_MS: u64 = 70_000;

/// Běžný budíček na jeden cíl nejvýš jednou za tohle okno: třicet zpráv ve
/// skupině během výpadku sítě = jeden push, ne třicet (APNs i FCM nápor
/// tichých pushů škrtí, baterie taky).
const WAKE_MIN_INTERVAL: std::time::Duration = std::time::Duration::from_secs(5);
/// Viditelná notifikace („Nová zpráva“) se zvukem na jeden cíl nejvýš
/// jednou za tohle okno. APNs je sloučí (collapse-id), ale každá by
/// zazvonila — výměna deseti zpráv za minutu nemá zvonit desetkrát.
/// V okně jde místo ní jen běžný tichý budíček.
const ALERT_MIN_INTERVAL: std::time::Duration = std::time::Duration::from_secs(10);
/// Okno pro `Limits::alerts_per_hour`. Samotný rozestup nestačí: druh
/// obálky volí odesílatel, takže kdo zná adresu, zvonil by cizímu telefonu
/// každých deset sekund celý den. Živý rozhovor s telefonem v kapse se do
/// hodinového stropu vejde; nad ním chodí dál tichý budíček a zprávy
/// čekají ve frontě.
///
/// Strop se počítá na dvojici odesílatel → cíl, ne na cíl: společný strop
/// by jeden odesílatel vyčerpal a umlčel tím notifikace všem ostatním.
const ALERT_WINDOW: std::time::Duration = std::time::Duration::from_secs(3600);
/// Kolik odesílatelů si značky jednoho cíle pamatují. Dalšímu v okně
/// notifikace se zvukem neodejde (tichý budíček ano): bez stropu by paměť
/// rostla s počtem účtů, ze kterých kdo na jeden cíl píše.
const ALERT_SENDERS_TRACKED: usize = 256;
/// Budíček hovoru (VoIP push / FCM k=call) zvoní na telefonu hned a bez
/// ověření — proto má vlastní, přísnější strop na cíl: nejvýš jeden za
/// `Limits::call_wake_min_interval` a `Limits::call_wakes_per_window` za
/// CALL_WAKE_WINDOW. Nad strop se obálka uloží a jde jen běžný budíček
/// (phantom hovory od kohokoli, kdo zná adresu).
const CALL_WAKE_WINDOW: std::time::Duration = std::time::Duration::from_secs(600);
/// Okno pro `Limits::otp_issue_per_hour`: noví kontakti jsou jednotky za den;
/// sto GET /v1/keys za dvacet sekund je vyčerpání zásoby cizím. Nad strop
/// jde bundle bez OTP.
const OTP_ISSUE_WINDOW: std::time::Duration = std::time::Duration::from_secs(3600);

/// Kolik zařízení z registru živých spojení ověří kontrola jedním dotazem.
const LIVE_CHECK_BATCH: usize = 10_000;

/// Okno kvóty odesílatele (`Limits::send_*_per_hour`, `ephemeral_per_hour`).
const SEND_BUDGET_PERIOD: std::time::Duration = std::time::Duration::from_secs(3600);
/// Jak často se bajty celé fronty přeměří v DB (jeden průchod tabulkou;
/// mezi měřeními relay počítá vlastní vložení a potvrzení).
pub const QUEUE_TOTAL_MEASURE_EVERY: std::time::Duration = std::time::Duration::from_secs(300);
/// Okno kvóty příloh na účet (`Limits::att_account_bytes_per_day`).
const ATTACHMENT_BUDGET_PERIOD: std::time::Duration = std::time::Duration::from_secs(86_400);

/// Proč relay obálku nepřijal. Klient dostane Error rámec s kódem, spojení
/// zůstává otevřené.
#[derive(Debug)]
pub enum RouteError {
    /// 400: formát (délky, prázdný payload, nad strop velikosti).
    Invalid,
    /// 404: adresa nepatří žádnému zařízení. Ukládat by ji nikdo nevyzvedl
    /// — a fronta na náhodné adresy byla nejlevnější cesta, jak zaplnit disk.
    /// Nic nového to neprozradí: GET /v1/keys vrací na neznámou adresu 404 taky.
    UnknownRecipient,
    /// 429: odesílající účet vyčerpal hodinovou kvótu.
    SenderQuota,
    /// Fronta příjemce je plná (odesílatel dostane doručenku DROPPED,
    /// ws.rs). Nová obálka se odmítne a čekající zůstanou; mazat nejstarší by dalo každému, kdo zná adresu, způsob,
    /// jak příjemci potichu smazat nedoručené zprávy.
    RecipientFull,
    /// 507: na disku zbývá méně než `Limits::disk_min_free_pct_queue`.
    DiskFull,
    Internal(anyhow::Error),
}

impl RouteError {
    pub fn code_and_message(&self) -> (u32, &'static str) {
        match self {
            Self::Invalid => (400, "obálka odmítnuta"),
            Self::UnknownRecipient => (404, "příjemce neexistuje"),
            Self::SenderQuota => (429, "příliš mnoho zpráv, zkus to později"),
            Self::RecipientFull => (507, "příjemce má plnou frontu zpráv, zkus to později"),
            Self::DiskFull => (507, "relay je dočasně plný, zkus to později"),
            Self::Internal(_) => (500, "interní chyba"),
        }
    }
}

impl From<sqlx::Error> for RouteError {
    fn from(e: sqlx::Error) -> Self {
        Self::Internal(e.into())
    }
}

/// Kdo obálku posílá: ověřené spojení odesílatele. Slouží jen kvótám
/// v paměti; do fronty se z toho nic neukládá (sealed sender).
#[derive(Clone, Copy)]
pub struct Sender<'a> {
    pub account: &'a [u8],
    /// Vlastní doručovací adresa odesílatele.
    pub address: &'a [u8],
    pub registered_at: DateTime<Utc>,
}

/// Značky budíčků jednoho cíle (jen v paměti, nikam se neukládají).
#[derive(Default)]
pub struct WakeMarks {
    last_wake: Option<Instant>,
    last_alert: Option<Instant>,
    /// Viditelné notifikace v ALERT_WINDOW podle odesílatele. Klíč je
    /// značka účtu ([`AppState::sender_tag`]), ne jeho id: kdo komu píše,
    /// relay jinde nedrží a nemá to jít vyčíst ani odsud.
    alerts: std::collections::HashMap<u64, std::collections::VecDeque<Instant>>,
    call_wakes: std::collections::VecDeque<Instant>,
}

impl WakeMarks {
    /// Smí teď odejít viditelná notifikace od `sender`? Na cíl nejvýš jedna
    /// za ALERT_MIN_INTERVAL, od jednoho odesílatele nejvýš `per_hour` za
    /// ALERT_WINDOW (0 = bez hodinového stropu). Povolená se počítá i jako
    /// běžný budíček.
    fn allow_alert(&mut self, now: Instant, sender: u64, per_hour: usize) -> bool {
        if self
            .last_alert
            .is_some_and(|last| now.duration_since(last) < ALERT_MIN_INTERVAL)
        {
            return false;
        }
        if per_hour > 0 {
            self.expire_alerts(now);
            if !self.alerts.contains_key(&sender) && self.alerts.len() >= ALERT_SENDERS_TRACKED {
                return false;
            }
            let sent = self.alerts.entry(sender).or_default();
            if sent.len() >= per_hour {
                return false;
            }
            sent.push_back(now);
        }
        self.last_alert = Some(now);
        self.last_wake = Some(now);
        true
    }

    fn expire_alerts(&mut self, now: Instant) {
        self.alerts.retain(|_, sent| {
            sent.retain(|at| now.duration_since(*at) < ALERT_WINDOW);
            !sent.is_empty()
        });
    }

    /// Příjemce se přihlásil: appku otevřel a zmeškané zprávy vidí, další
    /// má zase slyšet od kohokoli.
    fn reset_alerts(&mut self) {
        self.alerts.clear();
    }
}

/// Připojené zařízení: fronta na jeho WS + kdy od něj naposled něco přišlo.
///
/// Samotná fronta o životnosti spojení nic neříká — zápis do ní projde
/// i u dávno mrtvého socketu. Právě proto se dřív vracelo falešné
/// DELIVERED_ONLINE a push budíček se vůbec nezkusil.
pub struct OnlineDevice {
    pub outbox: Outbox,
    /// ms od startu procesu; monotónní, aby s ním neházel NTP.
    last_frame_ms: std::sync::atomic::AtomicU64,
    /// Doručování převzalo novější spojení téhož zařízení.
    retired: AtomicBool,
    retired_notify: Notify,
    /// Obálky, které se do fronty spojení nevešly (viz [`Backlog`]).
    backlog: std::sync::Mutex<Backlog>,
    backlog_notify: Notify,
}

/// Pozice ve frontě adresy: (enqueued_at, msg_uuid) obálky, za kterou se
/// čte dál. Prázdné msg_uuid řadí před každé skutečné, tedy „od prvního
/// zařazeného v ten okamžik“.
pub type QueueCursor = (DateTime<Utc>, Vec<u8>);

/// Obálky pro připojené zařízení, které šly jen do DB, protože fronta
/// spojení byla plná. Bez téhle značky by na ně nikdo nesáhl do dalšího
/// připojení: klient je připojený, takže budíček nic nespustí, a frontu
/// v DB vylévá relay jen po AUTH.
#[derive(Default)]
struct Backlog {
    /// Za kterou pozicí fronty je potřeba dolít.
    missed_after: Option<QueueCursor>,
    /// Dolévání právě běží. Nové obálky jdou do té doby jen do DB, ať je
    /// dolévání pošle v pořadí a žádná nepřijde dvakrát.
    refilling: bool,
}

impl OnlineDevice {
    pub fn new(outbox: Outbox, now_ms: u64) -> Self {
        Self {
            outbox,
            last_frame_ms: std::sync::atomic::AtomicU64::new(now_ms),
            retired: AtomicBool::new(false),
            retired_notify: Notify::new(),
            backlog: std::sync::Mutex::default(),
            backlog_notify: Notify::new(),
        }
    }

    fn backlog(&self) -> std::sync::MutexGuard<'_, Backlog> {
        self.backlog
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// Má nová obálka přeskočit frontu spojení a počkat v DB na dolití?
    fn defers_delivery(&self) -> bool {
        let backlog = self.backlog();
        backlog.refilling || backlog.missed_after.is_some()
    }

    /// Obálka zařazená v `enqueued_at` se do fronty spojení nedostala.
    fn note_missed(&self, enqueued_at: DateTime<Utc>) {
        let missed = (enqueued_at, Vec::new());
        let mut backlog = self.backlog();
        backlog.missed_after = Some(match backlog.missed_after.take() {
            Some(earlier) => earlier.min(missed),
            None => missed,
        });
        drop(backlog);
        self.backlog_notify.notify_one();
    }

    /// Vylévání došlo po `sent_up_to` včetně: co bylo zmeškané před tím,
    /// spojení už dostalo. Dolévat zbývá jen to, co přibylo potom.
    fn note_flushed(&self, sent_up_to: &QueueCursor) {
        let mut backlog = self.backlog();
        if backlog
            .missed_after
            .as_ref()
            .is_some_and(|missed| missed < sent_up_to)
        {
            backlog.missed_after = Some(sent_up_to.clone());
        }
    }

    /// Doběhne, jakmile je co dolévat a žádné dolévání neběží; vrací
    /// pozici, za kterou dolévat. Volající pak pustí
    /// [`AppState::refill_queue`].
    pub async fn refill_due(&self) -> QueueCursor {
        loop {
            {
                let mut backlog = self.backlog();
                if !backlog.refilling {
                    if let Some(after) = backlog.missed_after.take() {
                        backlog.refilling = true;
                        return after;
                    }
                }
            }
            self.backlog_notify.notified().await;
        }
    }

    /// Dolévání skončilo (i neúspěchem). Co se mezitím nevešlo, ohlásí
    /// další [`Self::refill_due`].
    fn refill_done(&self) {
        let mut backlog = self.backlog();
        backlog.refilling = false;
        let again = backlog.missed_after.is_some();
        drop(backlog);
        if again {
            self.backlog_notify.notify_one();
        }
    }

    fn retire(&self) {
        self.retired.store(true, Ordering::Release);
        self.retired_notify.notify_waiters();
    }

    /// Doběhne, jakmile doručování převezme novější spojení.
    async fn retired(&self) {
        let notified = self.retired_notify.notified();
        tokio::pin!(notified);
        // Zapsat se k odběru dřív, než se přečte příznak: jinak by
        // `retire` mezi čtením a čekáním proklouzlo bez probuzení.
        notified.as_mut().enable();
        if !self.retired.load(Ordering::Acquire) {
            notified.await;
        }
    }

    /// Přišel rámec od klienta (Pong/ACK/Envelope) — spojení dýchá.
    pub fn touch(&self, now_ms: u64) {
        self.last_frame_ms
            .store(now_ms, std::sync::atomic::Ordering::Relaxed);
    }

    fn is_fresh(&self, now_ms: u64) -> bool {
        let last = self.last_frame_ms.load(std::sync::atomic::Ordering::Relaxed);
        now_ms.saturating_sub(last) <= FRESH_CONNECTION_MS
    }
}

/// Cíl živého doručování: delivery_address → spojení, na kterém zařízení
/// právě poslouchá.
///
/// Jedno zařízení může mít chvíli víc spojení naráz: po změně sítě (Wi-Fi ↔
/// mobilní data) se appka připojí znovu hned, kdežto staré spojení relay
/// pozná jako mrtvé až po `ws::IDLE_TIMEOUT`. Doručuje se vždy na naposledy
/// ověřené spojení a staré spojení smí při svém konci odebrat jen samo sebe.
#[derive(Default)]
pub struct OnlineDevices(DashMap<Vec<u8>, Arc<OnlineDevice>>);

impl OnlineDevices {
    pub fn get(&self, delivery_address: &[u8]) -> Option<Arc<OnlineDevice>> {
        self.0.get(delivery_address).map(|d| d.clone())
    }

    /// Nově ověřené spojení přebírá doručování — i od staršího spojení
    /// téhož zařízení, které ještě nevypršelo. Starší se o tom dozví
    /// a přestane vylévat frontu: dvě vylévání téže adresy by jen držela
    /// paměť a posílala každou obálku dvakrát.
    pub fn attach(&self, delivery_address: Vec<u8>, device: Arc<OnlineDevice>) {
        if let Some(previous) = self.0.insert(delivery_address, device) {
            previous.retire();
        }
    }

    /// Konec spojení: odebere záznam, jen pokud pořád patří tomuto spojení.
    /// Mazat podle samotné adresy nejde — zombie spojení, které dožije až
    /// po reconnectu, by tím vyřadilo nové živé spojení a relay by pak každou
    /// zprávu jen uložil do fronty a čekal na budíček, přestože je zařízení
    /// připojené. Vrací, zda se záznam odebral.
    pub fn detach(&self, delivery_address: &[u8], device: &Arc<OnlineDevice>) -> bool {
        self.0
            .remove_if(delivery_address, |_, current| Arc::ptr_eq(current, device))
            .is_some()
    }
}

/// Ověřené WS spojení v registru: čí je a kudy mu poslat kód odpojení.
struct AuthedConn {
    device_uuid: Vec<u8>,
    fingerprint: [u8; 32],
    kick: oneshot::Sender<u32>,
}

/// Registr všech ověřených WS spojení, i těch, která online mapa už nevidí
/// (starší spojení téhož zařízení po reconnectu přepíše `attach`). Přes něj
/// jde kontrola proti DB i okamžité odpojení po smazání účtu nebo převzetí.
#[derive(Default)]
pub struct AuthedConns {
    next_id: AtomicU64,
    conns: Arc<DashMap<u64, AuthedConn>>,
}

/// Záznam v registru žije, dokud žije spojení: guard ho smaže v `Drop`,
/// i když handler spadne.
pub struct AuthedConnGuard {
    id: u64,
    conns: Arc<DashMap<u64, AuthedConn>>,
}

impl Drop for AuthedConnGuard {
    fn drop(&mut self) {
        self.conns.remove(&self.id);
    }
}

impl AuthedConns {
    /// Zapíše ověřené spojení. Přijímač dostane kód (403/410), až relay
    /// rozhodne spojení odpojit.
    pub fn add(
        &self,
        device_uuid: Vec<u8>,
        fingerprint: [u8; 32],
    ) -> (AuthedConnGuard, oneshot::Receiver<u32>) {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (kick, kicked) = oneshot::channel();
        self.conns.insert(
            id,
            AuthedConn {
                device_uuid,
                fingerprint,
                kick,
            },
        );
        let guard = AuthedConnGuard {
            id,
            conns: self.conns.clone(),
        };
        (guard, kicked)
    }

    /// Zařízení s živým spojením a jejich otisky, každé zařízení jednou.
    pub fn snapshot(&self) -> Vec<(Vec<u8>, [u8; 32])> {
        let mut seen = HashSet::new();
        self.conns
            .iter()
            .filter(|conn| seen.insert(conn.device_uuid.clone()))
            .map(|conn| (conn.device_uuid.clone(), conn.fingerprint))
            .collect()
    }

    pub fn live_devices(&self) -> Vec<Vec<u8>> {
        self.snapshot()
            .into_iter()
            .map(|(device, _)| device)
            .collect()
    }

    /// Odpojí všechna spojení daných zařízení kódem `code`. Vrací počet
    /// odpojených spojení.
    pub fn kick_devices(&self, device_uuids: &[Vec<u8>], code: u32) -> usize {
        if device_uuids.is_empty() {
            return 0;
        }
        let wanted: HashSet<&[u8]> = device_uuids.iter().map(Vec::as_slice).collect();
        // Nejdřív id, pak odebrat: mazat z DashMap během iterace by zamklo
        // vlastní shard.
        let ids: Vec<u64> = self
            .conns
            .iter()
            .filter(|conn| wanted.contains(conn.device_uuid.as_slice()))
            .map(|conn| *conn.key())
            .collect();
        let mut kicked = 0;
        for id in ids {
            if let Some((_, conn)) = self.conns.remove(&id) {
                // Přijímač zaniká jen s koncem spojení; pak už není koho
                // odpojit a neúspěšné odeslání nic neznamená.
                let _ = conn.kick.send(code);
                kicked += 1;
            }
        }
        kicked
    }
}

pub struct AppState {
    pub pool: PgPool,
    /// Kdy proces nastartoval — základ monotónních značek v [`OnlineDevice`].
    pub started: std::time::Instant,
    /// delivery_address → živé WS spojení zařízení.
    pub online: OnlineDevices,
    /// delivery_address → zámek vylévání fronty (nejvýš jedno naráz).
    flush_locks: DashMap<Vec<u8>, Arc<tokio::sync::Mutex<()>>>,
    /// Registr ověřených WS spojení: kontrola proti DB a odpojení.
    pub conns: AuthedConns,
    /// klientská IP → počet souběžných WS spojení (anti-flood cap).
    /// Jen v paměti, nikam se neloguje ani neukládá.
    pub ws_conns: DashMap<std::net::IpAddr, u32>,
    pub certs: CertAuthority,
    /// Trusted proxy sada pro určení klientské IP (WS conn-cap). Sdílená
    /// s governor limity — komu se věří forwarded hlavička.
    pub trusted_proxies: Arc<TrustedProxies>,
    /// HTTP klient na push budíčky (bez redirectů, krátký timeout).
    pub http: reqwest::Client,
    /// Úložiště šifrovaných příloh (adresář + strop velikosti).
    pub attachments: crate::attachments::Config,
    /// FCM fast mode (None = nenakonfigurováno, budíčky jen UnifiedPush).
    pub fcm: Option<std::sync::Arc<crate::fcm::FcmSender>>,
    /// APNs nativní iOS push (None = nenakonfigurováno).
    pub apns: Option<std::sync::Arc<crate::apns::ApnsSender>>,
    /// TURN pro hovory (None = relay údaje nevydává).
    pub turn: Option<crate::turn::TurnConfig>,
    /// Všechny limity relaye (env, viz limits.rs).
    pub limits: crate::limits::Limits,
    /// Kvóta ukládaných obálek na odesílající účet (paměť).
    pub send_budget: crate::quota::Budgets,
    /// Kvóty „píše…“: na odesílající účet a na cílovou adresu (paměť).
    pub ephemeral_budget: crate::quota::Budgets,
    pub ephemeral_target_budget: crate::quota::Budgets,
    /// Obsazenost offline fronty: na příjemce a celkem (paměť, gauge.rs).
    pub queue_gauges: RecipientGauges,
    pub queue_total: QueueTotal,
    /// Kvóta příloh na účet: tempo za den a uloženo celkem (paměť).
    pub attachment_budget: crate::quota::Budgets,
    pub attachment_stored: crate::quota::StoredLedger,
    /// Volné místo na datovém filesystému (přílohy i DB).
    pub disk: Arc<crate::disk::DiskWatch>,
    /// delivery_address → značky budíčků (throttling pushů a hovorů).
    pub wake_marks: DashMap<Vec<u8>, WakeMarks>,
    /// Klíč značek odesílatelů ve `wake_marks`, náhodný pro každý start.
    sender_tags: std::hash::RandomState,
    /// delivery_address → (začátek okna, vydaných OTP) — drain ochrana.
    pub otp_issued: DashMap<Vec<u8>, (Instant, u32)>,
    /// Proof-of-work registrace: klíč výzev, spotřebované výzvy, zátěž (paměť).
    pub pow: crate::pow::RegisterPow,
    /// Strop všech registrací dohromady; bere se až po ověření důkazů.
    pub register_global: crate::limits::GlobalLimit,
    /// Poslední výsledek sondy DB pro `/v1/ready`.
    pub ready_probe: crate::rest::ReadyProbe,
    /// Kdy naposledy proběhlo dorovnání blokací (úplné a jakékoli).
    block_reconcile: std::sync::Mutex<ReconcileMarks>,
    /// Odkaz na zdroj a revize běžící binárky (AGPL §13, /v1/server-info).
    pub source_url: String,
    pub revision: String,
    #[cfg(test)]
    pub test_hooks: crate::testkit::Hooks,
}

/// Jak často projde dorovnání blokací celou tabulku identit. Mezi tím
/// stačí registrace od minulého běhu: nová registrace zablokované identity
/// je jediné, co může přibýt. Úplný průchod zůstává pojistkou pro případy,
/// které přírůstek nevidí (blokace zapsaná mimo běžnou cestu).
const RECONCILE_FULL_EVERY: std::time::Duration = std::time::Duration::from_secs(24 * 3600);
/// Přesah přírůstkového okna: `registered_at` je čas začátku transakce,
/// commit přijde později, a hodiny DB a relaye se můžou lišit.
const RECONCILE_OVERLAP_MINUTES: i64 = 10;

#[derive(Default)]
struct ReconcileMarks {
    last_full: Option<Instant>,
    last_run: Option<DateTime<Utc>>,
}

impl ReconcileMarks {
    /// Od kdy stačí registrace projít; `None` = je čas na úplný průchod
    /// (první běh po startu a pak jednou za `RECONCILE_FULL_EVERY`).
    fn incremental_since(&self, now: Instant) -> Option<DateTime<Utc>> {
        let full_due = self
            .last_full
            .is_none_or(|at| now.duration_since(at) >= RECONCILE_FULL_EVERY);
        if full_due {
            return None;
        }
        self.last_run
            .map(|at| at - Duration::minutes(RECONCILE_OVERLAP_MINUTES))
    }

    fn done(&mut self, now: Instant, started: DateTime<Utc>, full: bool) {
        self.last_run = Some(started);
        if full {
            self.last_full = Some(now);
        }
    }
}

/// Zapomene token, který push služba natrvalo odmítla. Jen když ho zařízení
/// pořád má: appka mezitím mohla zaregistrovat nový a ten se smazat nesmí.
/// Řádek bez obou tokenů nikoho nevzbudí, proto zmizí celý.
async fn forget_dead_token(
    pool: &PgPool,
    dst_address: &[u8],
    dead: crate::push::DeadToken,
    token: &[u8],
) {
    let clear = match dead {
        crate::push::DeadToken::Push => {
            "UPDATE push_tokens p SET token = NULL FROM devices d
             WHERE d.device_uuid = p.device_uuid AND d.delivery_address = $1 AND p.token = $2"
        }
        crate::push::DeadToken::Voip => {
            "UPDATE push_tokens p SET voip_token = NULL FROM devices d
             WHERE d.device_uuid = p.device_uuid AND d.delivery_address = $1
               AND p.voip_token = $2"
        }
    };
    let forgotten = async {
        let cleared = sqlx::query(clear)
            .bind(dst_address)
            .bind(token)
            .execute(pool)
            .await?
            .rows_affected();
        sqlx::query(
            "DELETE FROM push_tokens p USING devices d
             WHERE d.device_uuid = p.device_uuid AND d.delivery_address = $1
               AND p.token IS NULL AND p.voip_token IS NULL",
        )
        .bind(dst_address)
        .execute(pool)
        .await?;
        Ok::<u64, sqlx::Error>(cleared)
    };
    match forgotten.await {
        Ok(0) => {}
        // Bez adresy i tokenu: obojí je identifikátor uživatele.
        Ok(_) => tracing::info!(kind = ?dead, "mrtvý push token zapomenut"),
        Err(e) => tracing::warn!("mrtvý push token se nepodařilo smazat: {e}"),
    }
}

impl AppState {
    pub fn new(
        pool: PgPool,
        certs: CertAuthority,
        attachments: crate::attachments::Config,
        trusted_proxies: Arc<TrustedProxies>,
        limits: crate::limits::Limits,
    ) -> Self {
        Self {
            pool,
            started: std::time::Instant::now(),
            online: OnlineDevices::default(),
            flush_locks: DashMap::new(),
            conns: AuthedConns::default(),
            ws_conns: DashMap::new(),
            certs,
            trusted_proxies,
            http: crate::push::build_client(),
            attachments,
            fcm: crate::fcm::FcmSender::from_env(),
            apns: crate::apns::ApnsSender::from_env(),
            turn: crate::turn::TurnConfig::from_env(),
            send_budget: crate::quota::Budgets::new(
                limits.send_per_hour,
                limits.send_bytes_per_hour,
                SEND_BUDGET_PERIOD,
            ),
            ephemeral_budget: crate::quota::Budgets::new(
                limits.ephemeral_per_hour,
                0,
                SEND_BUDGET_PERIOD,
            ),
            ephemeral_target_budget: crate::quota::Budgets::new(
                limits.ephemeral_target_burst,
                0,
                limits.ephemeral_target_period,
            ),
            queue_gauges: RecipientGauges::default(),
            queue_total: QueueTotal::default(),
            attachment_budget: crate::quota::Budgets::new(
                0,
                limits.att_account_bytes_per_day,
                ATTACHMENT_BUDGET_PERIOD,
            ),
            attachment_stored: crate::quota::StoredLedger::new(
                limits.att_account_stored_bytes,
                crate::attachments::ATTACHMENT_TTL_DAYS,
            ),
            disk: Arc::new(crate::disk::DiskWatch::unknown()),
            register_global: crate::limits::GlobalLimit::new(limits.register_global),
            ready_probe: crate::rest::ReadyProbe::default(),
            block_reconcile: std::sync::Mutex::default(),
            limits,
            wake_marks: DashMap::new(),
            sender_tags: std::hash::RandomState::new(),
            otp_issued: DashMap::new(),
            pow: crate::pow::RegisterPow::new(crate::pow::Config::from_env()),
            source_url: std::env::var("SEPOT_SOURCE_URL")
                .unwrap_or_else(|_| "https://github.com/juliusjoska/sepot".into()),
            revision: std::env::var("SEPOT_REVISION").unwrap_or_else(|_| "dev".into()),
            #[cfg(test)]
            test_hooks: crate::testkit::Hooks::default(),
        }
    }

    /// Kontrola živých spojení proti DB (main.rs, á 30 s). Odpojí s 403
    /// každé spojení zablokované identity (blokaci zapsal provozovatel
    /// jiným procesem), i když její registrace ještě existuje: vzniká jen
    /// obejitím blokace a dorovnání ji smaže až v hodinové údržbě. Zařízení,
    /// které jinak zmizelo (úklid, smazání účtu), odpojí s 410. Při chybě DB
    /// nikoho neodpojí: výpadek databáze nesmí shodit všechna spojení.
    pub async fn check_live_connections(&self) -> sqlx::Result<()> {
        let live = self.conns.snapshot();
        if live.is_empty() {
            return Ok(());
        }
        let mut gone = Vec::new();
        let mut blocked = HashSet::new();
        for chunk in live.chunks(LIVE_CHECK_BATCH) {
            let devices: Vec<&[u8]> = chunk.iter().map(|(device, _)| device.as_slice()).collect();
            let present: Vec<Vec<u8>> =
                sqlx::query_scalar("SELECT device_uuid FROM devices WHERE device_uuid = ANY($1)")
                    .bind(&devices)
                    .fetch_all(&self.pool)
                    .await?;
            let present: HashSet<Vec<u8>> = present.into_iter().collect();
            gone.extend(chunk.iter().filter(|(device, _)| !present.contains(device)));
            let fingerprints: Vec<[u8; 32]> =
                chunk.iter().map(|(_, fingerprint)| *fingerprint).collect();
            blocked.extend(blocking::blocked_among(&self.pool, &fingerprints).await?);
        }
        let devices = |conns: Vec<&(Vec<u8>, [u8; 32])>| -> Vec<Vec<u8>> {
            conns
                .into_iter()
                .map(|(device, _)| device.clone())
                .collect()
        };
        let blocked_devices: Vec<_> = live
            .iter()
            .filter(|(_, fingerprint)| blocked.contains(fingerprint))
            .collect();
        let gone_devices: Vec<_> = gone
            .into_iter()
            .filter(|(_, fingerprint)| !blocked.contains(fingerprint))
            .collect();
        let kicked_403 = self.conns.kick_devices(&devices(blocked_devices), 403);
        let kicked_410 = self.conns.kick_devices(&devices(gone_devices), 410);
        if kicked_403 + kicked_410 > 0 {
            tracing::info!(
                odpojeno_403 = kicked_403,
                odpojeno_410 = kicked_410,
                "kontrola spojení"
            );
        }
        Ok(())
    }

    /// Údržba blokací (main.rs, á hodinu): konce blokací a zajištění,
    /// dorovnání registrací zablokovaných identit. Dorovnání běží, i když
    /// konce selhaly.
    pub async fn maintain_blocks(&self) {
        match blocking::expire(&self.pool).await {
            Ok(expired) if !expired.is_empty() => tracing::info!(
                blokace_vyprsely = expired.blocks,
                zajisteni_smazana = expired.holds,
                adresy_uvolnene = expired.addresses_released,
                adresy_smazane = expired.addresses_freed,
                "údržba blokací"
            ),
            Ok(_) => {}
            Err(e) => tracing::warn!("údržba blokací: {e}"),
        }
        let started = Utc::now();
        let since = self
            .block_reconcile
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .incremental_since(Instant::now());
        match blocking::reconcile(&self.pool, since).await {
            Ok(reconciled) => {
                self.block_reconcile
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .done(Instant::now(), started, since.is_none());
                if reconciled.identities == 0 {
                    return;
                }
                // Registrace zablokované identity vzniká jen obejitím
                // blokace; počet je signál pro provozovatele.
                tracing::warn!(
                    dorovnano = reconciled.identities,
                    "zablokovaná identita byla registrovaná"
                );
                self.conns.kick_devices(&reconciled.device_uuids, 403);
            }
            Err(e) => tracing::warn!("dorovnání blokací: {e}"),
        }
    }

    /// Úklid neaktivních registrací (main.rs, á hodinu), jen se
    /// `SEPOT_INACTIVE_CLEANUP=1`.
    pub async fn clean_inactive(&self) {
        if !self.limits.inactive_cleanup {
            return;
        }
        match crate::cleanup::run(&self.pool, &self.conns).await {
            Ok(sweep) if sweep.registrations > 0 => {
                tracing::info!(uklid = sweep.registrations, "neaktivní registrace smazány")
            }
            Ok(_) => {}
            Err(e) => tracing::warn!("úklid neaktivních registrací: {e}"),
        }
    }

    /// Úklid značek starších než největší okno — volá periodická úloha.
    pub fn prune_marks(&self) {
        let now = Instant::now();
        self.wake_marks.retain(|_, m| {
            m.call_wakes
                .retain(|t| now.duration_since(*t) < CALL_WAKE_WINDOW);
            m.last_wake
                .map(|t| now.duration_since(t) < CALL_WAKE_WINDOW)
                .unwrap_or(false)
                || m.last_alert
                    .map(|t| now.duration_since(t) < ALERT_MIN_INTERVAL)
                    .unwrap_or(false)
                || {
                    m.expire_alerts(now);
                    !m.alerts.is_empty()
                }
                || !m.call_wakes.is_empty()
        });
        self.otp_issued
            .retain(|_, (start, _)| now.duration_since(*start) < OTP_ISSUE_WINDOW);
        // Zámek, který nikdo nedrží ani na něj nečeká, má jediný odkaz.
        self.flush_locks
            .retain(|_, lock| Arc::strong_count(lock) > 1);
        self.send_budget.prune();
        self.ephemeral_budget.prune();
        self.ephemeral_target_budget.prune();
        self.queue_gauges.prune();
        self.attachment_budget.prune();
        self.attachment_stored.prune();
        self.pow
            .prune(chrono::Utc::now().timestamp().max(0) as u64);
    }

    /// Smí se vydat další OTP pro tuhle adresu? Počítá v hodinovém okně.
    pub fn allow_otp_issue(&self, dst_address: &[u8]) -> bool {
        let now = Instant::now();
        let mut entry = self
            .otp_issued
            .entry(dst_address.to_vec())
            .or_insert((now, 0));
        if now.duration_since(entry.0) >= OTP_ISSUE_WINDOW {
            *entry = (now, 0);
        }
        if entry.1 >= self.limits.otp_issue_per_hour {
            return false;
        }
        entry.1 += 1;
        true
    }

    /// Běžný budíček smí odejít nejvýš jednou za WAKE_MIN_INTERVAL na cíl.
    fn allow_wake(&self, dst_address: &[u8]) -> bool {
        let now = Instant::now();
        let mut marks = self.wake_marks.entry(dst_address.to_vec()).or_default();
        if marks
            .last_wake
            .map(|t| now.duration_since(t) < WAKE_MIN_INTERVAL)
            .unwrap_or(false)
        {
            return false;
        }
        marks.last_wake = Some(now);
        true
    }

    /// Viditelná notifikace na cíl: rozestup a hodinový strop viz
    /// [`WakeMarks::allow_alert`].
    fn allow_alert(&self, dst_address: &[u8], sender_account: &[u8]) -> bool {
        let sender = self.sender_tag(sender_account);
        self.wake_marks
            .entry(dst_address.to_vec())
            .or_default()
            .allow_alert(Instant::now(), sender, self.limits.alerts_per_hour)
    }

    /// Značka odesílajícího účtu pro značky budíčků: hash s klíčem, který
    /// žije jen v paměti tohoto procesu.
    fn sender_tag(&self, sender_account: &[u8]) -> u64 {
        use std::hash::BuildHasher;
        self.sender_tags.hash_one(sender_account)
    }

    /// Po úspěšném AUTH zařízení (ws.rs): vynuluje počítadla viditelných
    /// notifikací na jeho adresu.
    pub fn reset_alerts(&self, delivery_address: &[u8]) {
        if let Some(mut marks) = self.wake_marks.get_mut(delivery_address) {
            marks.reset_alerts();
        }
    }

    /// Budíček hovoru: vlastní strop na cíl (viz CALL_WAKE_*). Vrací false,
    /// když je cíl v okně už vyčerpaný — pak jde nanejvýš běžný budíček.
    fn allow_call_wake(&self, dst_address: &[u8]) -> bool {
        let now = Instant::now();
        let mut marks = self.wake_marks.entry(dst_address.to_vec()).or_default();
        marks
            .call_wakes
            .retain(|t| now.duration_since(*t) < CALL_WAKE_WINDOW);
        if let Some(last) = marks.call_wakes.back() {
            if now.duration_since(*last) < self.limits.call_wake_min_interval {
                return false;
            }
        }
        if marks.call_wakes.len() >= self.limits.call_wakes_per_window {
            return false;
        }
        marks.call_wakes.push_back(now);
        marks.last_wake = Some(now);
        true
    }

    /// Kolik one-time prekeys zařízení ještě má.
    pub async fn one_time_prekey_count(&self, device_uuid: &[u8]) -> anyhow::Result<i64> {
        let (n,): (i64,) =
            sqlx::query_as("SELECT count(*) FROM one_time_prekeys WHERE device_uuid = $1")
                .bind(device_uuid)
                .fetch_one(&self.pool)
                .await?;
        Ok(n)
    }

    /// Přijme obálku: validace → existence příjemce → místo na disku a ve
    /// frontě příjemce → kvóta odesílatele → perzistentní fronta (dedup) →
    /// pokud je příjemce online, doručí hned. At-least-once: záznam z fronty
    /// maže až ACK příjemce, ne odeslání.
    pub async fn route_envelope(
        &self,
        env: v1::Envelope,
        sender: Sender<'_>,
    ) -> Result<v1::receipt::Status, RouteError> {
        if env.dst_address.len() != 32
            || env.msg_uuid.len() != 16
            || env.payload.is_empty()
            || env.payload.len() > MAX_ENVELOPE_PAYLOAD
        {
            return Err(RouteError::Invalid);
        }

        if env.content_hint == v1::ContentHint::Ephemeral as i32 {
            return self.route_ephemeral(env, sender);
        }

        let dst = env.dst_address.clone();
        // Vždy proti DB (jeden indexovaný dotaz, UNIQUE), i když je adresa
        // v `online`: spojení smazaného nebo zablokovaného zařízení tam
        // zůstává, dokud ho relay neodpojí, a do té doby by dál plnilo frontu.
        if !self.address_exists(&dst).await? {
            return Err(RouteError::UnknownRecipient);
        }
        if self.disk.below(self.limits.disk_min_free_pct_queue) {
            return Err(RouteError::DiskFull);
        }
        let encoded = env.encode_to_vec();
        // Strop zakódované obálky = CHECK message_queue.envelope v 0001; payload
        // těsně pod MAX_ENVELOPE_PAYLOAD ho s hlavičkou protobufu přesáhne a DB
        // by zápis odmítla až po odečtení kvóty (dřív jako 400 přes chybu DB).
        if encoded.len() > MAX_STORED_ENVELOPE_BYTES {
            return Err(RouteError::Invalid);
        }
        let stored_bytes = encoded.len() as i64;
        // Před kvótou odesílatele: obálka, kterou relay nepřijme, z ní
        // nemá ukrojit.
        let usage = self.recipient_usage(&dst).await?;
        if !self.recipient_caps().admits(usage, stored_bytes) {
            // Opakovaná obálka, kterou fronta už má, není nová: klient ji
            // posílá znovu, protože mu nedošla doručenka, a má ji dostat.
            if self.is_queued(&dst, &env.msg_uuid).await? {
                return Ok(v1::receipt::Status::StoredOffline);
            }
            return Err(RouteError::RecipientFull);
        }
        if !self
            .send_budget
            .try_take(sender.account, self.send_cost(&sender, &dst, encoded.len() as u64))
        {
            return Err(RouteError::SenderQuota);
        }
        let expires = Utc::now() + Duration::days(QUEUE_TTL_DAYS);
        let enqueued_at: Option<DateTime<Utc>> = sqlx::query_scalar(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at)
             VALUES ($1, $2, $3, $4) ON CONFLICT (msg_uuid) DO NOTHING
             RETURNING enqueued_at",
        )
        .bind(&env.msg_uuid)
        .bind(&dst)
        .bind(&encoded)
        .bind(expires)
        .fetch_optional(&self.pool)
        .await?;
        // Opakovaná obálka (dedup) frontu nezvětšila.
        if enqueued_at.is_some() {
            self.queue_gauges.added(&dst, stored_bytes);
            self.queue_total.added(stored_bytes);
        }

        let is_call = env.content_hint == v1::ContentHint::Call as i32;
        let is_visible = env.content_hint == v1::ContentHint::Visible as i32;
        if let Some(dev) = self.online.get(&dst) {
            let deliver = v1::ServerFrame {
                frame: Some(v1::server_frame::Frame::Deliver(env)),
            };
            let fresh = dev.is_fresh(self.now_ms());
            // try_send, ne send().await: plná fronta znamená, že příjemce ze
            // socketu nečte. Čekat na něj by drželo odesílatelovo spojení
            // (a jeho paměť) rukojmím — nečtoucí příjemci by tak shodili
            // relay. Obálka je v DB, půjde budíček, a spojení si ji dolije,
            // až bude mít místo. Dokud dolévá, jdou další obálky jen do DB.
            let queued = !dev.defers_delivery() && dev.outbox.try_send(&deliver);
            if !queued {
                // Opakovaná obálka čas zařazení nevrací; tu už ohlásil
                // první pokus, nebo ji klient dostal.
                if let Some(enqueued_at) = enqueued_at {
                    dev.note_missed(enqueued_at);
                }
            }
            // ONLINE hlásíme jen u spojení, které prokazatelně dýchá. Do
            // zatuchlého se sice pošle taky (kdyby to byl jen tichý klient),
            // ale propadne se i na push — jinak by mrtvé spojení budíček
            // spolklo a příjemce se o zprávě nedozvěděl.
            if fresh && queued {
                return Ok(v1::receipt::Status::DeliveredOnline);
            }
        }
        // Offline, zatuchlé nebo plná fronta spojení → zkusit push budíček.
        // Nad hodinový strop viditelných notifikací jde jen tichý.
        if is_call && self.allow_call_wake(&dst) {
            self.wake_call(&dst).await;
        } else if is_visible && self.allow_alert(&dst, sender.account) {
            self.wake_message(&dst).await;
        } else if self.allow_wake(&dst) {
            self.wake(&dst).await;
        }
        Ok(v1::receipt::Status::StoredOffline)
    }

    async fn is_queued(&self, dst: &[u8], msg_uuid: &[u8]) -> sqlx::Result<bool> {
        sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM message_queue WHERE msg_uuid = $1 AND dst_address = $2)",
        )
        .bind(msg_uuid)
        .bind(dst)
        .fetch_one(&self.pool)
        .await
    }

    async fn address_exists(&self, dst: &[u8]) -> Result<bool, sqlx::Error> {
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE delivery_address = $1)")
            .bind(dst)
            .fetch_one(&self.pool)
            .await
    }

    /// Je účet ještě čerstvý (`Limits::fresh_account_age`)?
    pub fn is_fresh_account(&self, registered_at: DateTime<Utc>) -> bool {
        let age = Utc::now().signed_duration_since(registered_at);
        // Registrace „v budoucnosti“ (posun hodin DB a relaye) je čerstvá.
        age.to_std()
            .map_or(true, |age| age < self.limits.fresh_account_age)
    }

    /// Kolik bajtů ukrojit z hodinové kvóty odesílatele za obálku pro
    /// `dst`: čerstvý účet a obálka na vlastní adresu mají nižší kvótu,
    /// platí ta přísnější.
    fn send_cost(&self, sender: &Sender<'_>, dst: &[u8], bytes: u64) -> u64 {
        let full = self.limits.send_bytes_per_hour;
        let mut cost = bytes;
        if self.is_fresh_account(sender.registered_at) {
            cost = crate::quota::scaled_cost(bytes, full, self.limits.send_fresh_bytes_per_hour);
        }
        if dst == sender.address {
            cost = cost.max(crate::quota::scaled_cost(
                bytes,
                full,
                self.limits.send_self_bytes_per_hour,
            ));
        }
        cost
    }

    /// Strop fronty jednoho příjemce při současném zaplnění celé fronty.
    fn recipient_caps(&self) -> RecipientCaps {
        RecipientCaps {
            count: self.limits.queue_max_per_recipient,
            bytes: self.limits.queue_max_bytes_per_recipient,
        }
        .under_pressure(self.queue_total.get(), self.limits.queue_max_bytes_total)
    }

    /// Obsazenost fronty příjemce: z paměti, nebo po vypršení změřená v DB.
    /// Měřit při každé obálce by u plné fronty znamenalo projít tisíce
    /// řádků na každý pokus o vložení.
    async fn recipient_usage(&self, dst: &[u8]) -> sqlx::Result<QueueUsage> {
        if let Some(usage) = self.queue_gauges.get(dst) {
            return Ok(usage);
        }
        let (count, bytes): (i64, i64) = sqlx::query_as(
            "SELECT count(*), coalesce(sum(octet_length(envelope)), 0)::bigint
             FROM message_queue WHERE dst_address = $1",
        )
        .bind(dst)
        .fetch_one(&self.pool)
        .await?;
        let usage = QueueUsage { count, bytes };
        self.queue_gauges.set(dst, usage);
        Ok(usage)
    }

    /// Přeměří bajty celé fronty (main.rs, á QUEUE_TOTAL_MEASURE_EVERY).
    /// Délku obálky čte Postgres z hlavičky hodnoty, velké obálky nenačítá.
    pub async fn measure_queue_total(&self) -> sqlx::Result<()> {
        let bytes: i64 = sqlx::query_scalar(
            "SELECT coalesce(sum(octet_length(envelope)), 0)::bigint FROM message_queue",
        )
        .fetch_one(&self.pool)
        .await?;
        self.queue_total.set(bytes);
        Ok(())
    }

    /// Jen živé doručení („píše…“): do fronty nic, push nic. Zatuchlé
    /// spojení se nepočítá — obálka by v mrtvém kanálu zmizela stejně.
    ///
    /// Odpověď je vždy stejná (QUEUED = přijato, bez záruky), ať je příjemce
    /// online, offline, neexistuje, nebo došla kvóta. Dřív relay vracel
    /// DELIVERED_ONLINE / DROPPED podle stavu cizí adresy: kdo adresu znal,
    /// sledoval tím zdarma a beze stopy, kdy je její majitel připojený.
    /// Starší appky berou cokoli jiného než DROPPED jako doručeno a jen
    /// nezpomalí další „píše…“ offline příjemci; ta relay tiše zahodí.
    fn route_ephemeral(
        &self,
        env: v1::Envelope,
        sender: Sender<'_>,
    ) -> Result<v1::receipt::Status, RouteError> {
        // Jediná odmítnutá věc závisí jen na obálce samotné: velké rámce
        // by „píše…“ měnilo v záplavu mimo kvótu ukládaných zpráv.
        if env.payload.len() > self.limits.ephemeral_max_bytes {
            return Err(RouteError::Invalid);
        }
        let dst = env.dst_address.clone();
        let within_quota = self.ephemeral_budget.try_take(sender.account, 0)
            && self.ephemeral_target_budget.try_take(&dst, 0);
        if within_quota {
            if let Some(dev) = self.online.get(&dst) {
                if dev.is_fresh(self.now_ms()) {
                    let deliver = v1::ServerFrame {
                        frame: Some(v1::server_frame::Frame::Deliver(env)),
                    };
                    // Plná fronta spojení = zahodit, odesílateli se to neříká.
                    dev.outbox.try_send(&deliver);
                }
            }
        }
        Ok(v1::receipt::Status::Queued)
    }

    /// Monotónní značka pro [`OnlineDevice`] — ms od startu procesu.
    pub fn now_ms(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }

    /// Budíček pro offline příjemce: dohledá jeho push token a pošle prázdný
    /// „ťuk". Best-effort, na pozadí — neblokuje receipt odesílateli.
    /// Endpoint se NELOGUJE.
    async fn wake(&self, dst_address: &[u8]) {
        let Some((platform, token)) = self.push_target(dst_address).await else {
            return; // bez tokenu / anonymní režim → žádný push
        };
        let client = self.http.clone();
        let fcm = self.fcm.clone();
        let apns = self.apns.clone();
        let (pool, dst_address) = (self.pool.clone(), dst_address.to_vec());
        tokio::spawn(async move {
            let dead = crate::push::send_wake(
                &client,
                platform,
                &token,
                crate::push::WakeKind::Sync,
                fcm.as_deref(),
                apns.as_deref(),
            )
            .await;
            if let Some(dead) = dead {
                forget_dead_token(&pool, &dst_address, dead, &token).await;
            }
        });
    }

    /// Budíček pro novou zprávu, kterou člověk uvidí: iPhone dostane hned
    /// viditelnou notifikaci s obecným textem, ostatní běžný budíček.
    async fn wake_message(&self, dst_address: &[u8]) {
        let Some((platform, token)) = self.push_target(dst_address).await else {
            return;
        };
        let client = self.http.clone();
        let fcm = self.fcm.clone();
        let apns = self.apns.clone();
        let (pool, dst_address) = (self.pool.clone(), dst_address.to_vec());
        tokio::spawn(async move {
            let dead = crate::push::send_message_wake(
                &client,
                platform,
                &token,
                fcm.as_deref(),
                apns.as_deref(),
            )
            .await;
            if let Some(dead) = dead {
                forget_dead_token(&pool, &dst_address, dead, &token).await;
            }
        });
    }

    /// Budíček pro příchozí hovor: iPhone s VoIP tokenem dostane VoIP push
    /// (CallKit zazvoní i u zabité appky), ostatní běžný budíček — FCM
    /// s krátkou platností, ať po hodině nezvoní hovor, který dávno skončil.
    async fn wake_call(&self, dst_address: &[u8]) {
        let Some(target) = self.push_target_full(dst_address).await else {
            return;
        };
        let client = self.http.clone();
        let fcm = self.fcm.clone();
        let apns = self.apns.clone();
        let (pool, dst_address) = (self.pool.clone(), dst_address.to_vec());
        tokio::spawn(async move {
            let dead =
                crate::push::send_call_wake(&client, &target, fcm.as_deref(), apns.as_deref())
                    .await;
            let token = match dead {
                Some(crate::push::DeadToken::Push) => target.token,
                Some(crate::push::DeadToken::Voip) => target.voip_token,
                None => None,
            };
            if let (Some(dead), Some(token)) = (dead, token) {
                forget_dead_token(&pool, &dst_address, dead, &token).await;
            }
        });
    }

    /// Push cíl včetně VoIP tokenu (hovory).
    pub(crate) async fn push_target_full(
        &self,
        dst_address: &[u8],
    ) -> Option<crate::push::PushTarget> {
        let row: Option<(i16, Option<Vec<u8>>, Option<Vec<u8>>)> = sqlx::query_as(
            "SELECT p.platform, p.token, p.voip_token FROM push_tokens p
             JOIN devices d USING (device_uuid)
             WHERE d.delivery_address = $1",
        )
        .bind(dst_address)
        .fetch_optional(&self.pool)
        .await
        .ok()
        .flatten();
        let (platform, token, voip_token) = row?;
        if token.is_none() && voip_token.is_none() {
            return None;
        }
        Some(crate::push::PushTarget {
            platform,
            token,
            voip_token,
        })
    }

    /// Dohledá push cíl (platform, token) pro delivery_address příjemce.
    /// `pub(crate)` kvůli integračnímu testu correctness JOINu.
    pub(crate) async fn push_target(&self, dst_address: &[u8]) -> Option<(i16, Vec<u8>)> {
        let row: Option<(i16, Option<Vec<u8>>)> = sqlx::query_as(
            "SELECT p.platform, p.token FROM push_tokens p
             JOIN devices d USING (device_uuid)
             WHERE d.delivery_address = $1",
        )
        .bind(dst_address)
        .fetch_optional(&self.pool)
        .await
        .ok()
        .flatten();
        match row {
            Some((platform, Some(token))) => Some((platform, token)),
            _ => None,
        }
    }

    /// Registrace/aktualizace push endpointu zařízení. platform=NONE token
    /// smaže (anonymní režim). Volá se z autentizovaného WS.
    pub async fn register_push(
        &self,
        device_uuid: &[u8],
        platform: i16,
        endpoint: Option<&[u8]>,
        voip_token: Option<&[u8]>,
    ) -> anyhow::Result<()> {
        // APNs s jediným VoIP tokenem (appka hovory zvoní přes PushKit, běžný
        // APNs token ještě nemá) se ukládá taky — dřív by ji tahle větev
        // smazala a hovor by offline iPhone nikdy nevzbudil.
        let voip_only = platform == crate::push::PLATFORM_APNS && voip_token.is_some();
        if platform == crate::push::PLATFORM_NONE || (endpoint.is_none() && !voip_only) {
            sqlx::query("DELETE FROM push_tokens WHERE device_uuid = $1")
                .bind(device_uuid)
                .execute(&self.pool)
                .await?;
            return Ok(());
        }
        // updated_at po hodinách jako devices.last_seen_at: přesný čas by
        // prozradil okamžik připojení, který relay jinde zaokrouhluje.
        sqlx::query(
            "INSERT INTO push_tokens (device_uuid, platform, token, voip_token, updated_at)
             VALUES ($1, $2, $3, $4, date_trunc('hour', now()))
             ON CONFLICT (device_uuid)
             DO UPDATE SET platform = excluded.platform,
                           token = excluded.token,
                           voip_token = excluded.voip_token,
                           updated_at = date_trunc('hour', now())",
        )
        .bind(device_uuid)
        .bind(platform)
        .bind(endpoint)
        .bind(voip_token)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Deregistrace účtu (GDPR čl. 17). Kaskáda v DB odnese devices →
    /// prekeys + push_tokens; fronta zpráv je vázaná na delivery_address
    /// bez FK, maže se explicitně v téže transakci. Přílohy vazbu na účet
    /// nemají (bearer capability) — dožijí TTL sweep. Adresy se vyřadí na
    /// rok se značkou vlastníka: obsadit je smí jen tatáž identita.
    ///
    /// Pod zámkem otisku, aby se smazání nepotkalo s blokací téže identity.
    /// Vrací device_uuid smazaných zařízení; jejich spojení odpojí volající
    /// až po commitu.
    pub async fn delete_identity(&self, account_id: &[u8]) -> anyhow::Result<Vec<Vec<u8>>> {
        let mut tx = self.pool.begin().await?;
        let identity_key: Option<Vec<u8>> =
            sqlx::query_scalar("SELECT identity_key FROM identities WHERE account_id = $1")
                .bind(account_id)
                .fetch_optional(&mut *tx)
                .await?;
        let Some(identity_key) = identity_key else {
            return Ok(Vec::new());
        };
        let fingerprint = Fingerprint::of_identity_key(&identity_key);
        blocking::lock(&mut tx, &fingerprint).await?;
        let registration = Registration {
            account_id: account_id.to_vec(),
            identity_key,
        };
        let removed =
            blocking::delete_registration(&mut tx, &registration, &fingerprint, Retire::Standard)
                .await?;
        tx.commit().await?;
        Ok(removed.device_uuids)
    }

    /// Po AUTH: vyleje nedoručenou frontu zařízení (DELIVER stream). Čte po
    /// dávkách keyset kurzorem přes (enqueued_at, msg_uuid) — paměť je
    /// omezená na jednu dávku (FLUSH_BATCH, FLUSH_BATCH_BYTES), ne celá
    /// fronta najednou. Index idx_queue_dst(dst_address, enqueued_at) kurzor
    /// pokrývá.
    ///
    /// Jednu adresu vylévá nejvýš jedno spojení naráz a jen to, které právě
    /// doručuje: desítky spojení téhož zařízení, která nečtou, by jinak
    /// držely každé svou dávku. Na místo ve frontě spojení čeká, proto běh
    /// hlídá volající (odpojení, ticho klienta, konec writeru).
    pub async fn flush_queue(
        &self,
        delivery_address: &[u8],
        device: &OnlineDevice,
    ) -> anyhow::Result<usize> {
        self.flush_queue_from(delivery_address, device, None).await
    }

    /// Dolije připojenému zařízení obálky za pozicí `after`, které se do
    /// fronty jeho spojení nevešly ([`OnlineDevice::refill_due`]). Starší
    /// nechává být: ty spojení dostalo a čeká se na jejich ACK.
    pub async fn refill_queue(
        &self,
        delivery_address: &[u8],
        device: &OnlineDevice,
        after: QueueCursor,
    ) -> anyhow::Result<usize> {
        let refilled = self
            .flush_queue_from(delivery_address, device, Some(after))
            .await;
        device.refill_done();
        refilled
    }

    async fn flush_queue_from(
        &self,
        delivery_address: &[u8],
        device: &OnlineDevice,
        after: Option<QueueCursor>,
    ) -> anyhow::Result<usize> {
        let lock = self
            .flush_locks
            .entry(delivery_address.to_vec())
            .or_default()
            .clone();
        let _flushing = lock.lock().await;
        if device.retired.load(Ordering::Acquire) {
            return Ok(0);
        }

        // Obálky, které strop pokusů vyčerpaly, jsou neprůchodné (skoro vždy
        // ztracený ACK po úspěšném dešifrování) — zahodit dřív, než se znovu
        // pošlou. Maže se až tady, ne hned po inkrementu: poslední pokus
        // dostane šanci doběhnout do ACK.
        let dropped = sqlx::query(
            "DELETE FROM message_queue WHERE dst_address = $1 AND attempt_count >= $2
               AND enqueued_at < now() - make_interval(hours => $3)",
        )
        .bind(delivery_address)
        .bind(MAX_DELIVERY_ATTEMPTS)
        .bind(MIN_HOURS_BEFORE_DROP)
        .execute(&self.pool)
        .await?
        .rows_affected();
        if dropped > 0 {
            // Bez identifikátoru příjemce — jen že se fronta čistila.
            tracing::info!(dropped, "nedoručitelné obálky zahozeny (strop pokusů)");
            self.queue_gauges.forget(delivery_address);
        }

        let mut total = 0usize;
        // (enqueued_at, msg_uuid) poslední odeslané obálky = kurzor další dávky.
        let mut cursor: Option<QueueCursor> = after;
        loop {
            let rows = self.flush_batch(delivery_address, cursor.as_ref()).await?;
            let Some(last) = rows.last().map(|(_, ts, uuid)| (*ts, uuid.clone())) else {
                break;
            };
            let mut sent_uuids: Vec<Vec<u8>> = Vec::with_capacity(rows.len());
            for (encoded, _, uuid) in rows {
                let env = v1::Envelope::decode(encoded.as_slice())?;
                drop(encoded);
                let frame = v1::ServerFrame {
                    frame: Some(v1::server_frame::Frame::Deliver(env)),
                };
                let sent = tokio::select! {
                    biased;
                    () = device.retired() => false,
                    sent = device.outbox.send(&frame) => sent.is_ok(),
                };
                if !sent {
                    // Příjemce odpadl (nebo doručování převzalo novější
                    // spojení) uprostřed dávky — započítat jen to, co reálně
                    // odešlo, ať pokus „zdarma" nekrátí strop.
                    self.bump_attempts(&sent_uuids).await;
                    return Ok(total);
                }
                sent_uuids.push(uuid);
                total += 1;
            }
            self.bump_attempts(&sent_uuids).await;
            device.note_flushed(&last);
            cursor = Some(last);
        }
        Ok(total)
    }

    /// Další dávka fronty za kurzorem: nejvýš FLUSH_BATCH obálek, z nich jen
    /// začátek, který se vejde do FLUSH_BATCH_BYTES. Délku umí Postgres
    /// z hlavičky hodnoty, velké obálky mimo dávku tedy vůbec nenačte.
    async fn flush_batch(
        &self,
        delivery_address: &[u8],
        cursor: Option<&(DateTime<Utc>, Vec<u8>)>,
    ) -> sqlx::Result<Vec<(Vec<u8>, DateTime<Utc>, Vec<u8>)>> {
        // Podmínka kurzoru jen když kurzor je: jako `$4 IS NULL OR …` by
        // z ní plánovač neudělal mez indexu a každá dávka by četla frontu
        // od začátku.
        let after_cursor = match cursor {
            Some(_) => "AND (enqueued_at, msg_uuid) > ($4, $5)",
            None => "",
        };
        let sql = format!(
            "SELECT envelope, enqueued_at, msg_uuid FROM (
                 SELECT envelope, enqueued_at, msg_uuid,
                        sum(octet_length(envelope)) OVER oldest AS running,
                        row_number() OVER oldest AS position
                 FROM (
                     SELECT envelope, enqueued_at, msg_uuid FROM message_queue
                     WHERE dst_address = $1 AND expires_at > now() {after_cursor}
                     ORDER BY enqueued_at, msg_uuid
                     LIMIT $2
                 ) batch
                 WINDOW oldest AS (ORDER BY enqueued_at, msg_uuid)
             ) sized
             WHERE running <= $3 OR position = 1
             ORDER BY enqueued_at, msg_uuid"
        );
        let query = sqlx::query_as(&sql)
            .bind(delivery_address)
            .bind(FLUSH_BATCH)
            .bind(FLUSH_BATCH_BYTES);
        match cursor {
            Some((ts, uuid)) => query.bind(ts).bind(uuid).fetch_all(&self.pool).await,
            None => query.fetch_all(&self.pool).await,
        }
    }

    /// Započítá pokus o doručení odeslaným obálkám. Selhání se jen zaloguje —
    /// obálky už jsou na drátě a shodit kvůli tomu flush by bylo horší než
    /// nepřesné počítadlo.
    async fn bump_attempts(&self, msg_uuids: &[Vec<u8>]) {
        if msg_uuids.is_empty() {
            return;
        }
        // Strop typu sloupce: obálka se teď doručuje 72 h bez ohledu na
        // počet pokusů a přetečení SMALLINT by shodilo UPDATE celé dávky.
        if let Err(e) = sqlx::query(
            "UPDATE message_queue SET attempt_count = LEAST(attempt_count + 1, $2)
             WHERE msg_uuid = ANY($1)",
        )
        .bind(msg_uuids)
        .bind(i16::MAX)
        .execute(&self.pool)
        .await
        {
            tracing::warn!("attempt_count se nepodařilo zvýšit: {e}");
        }
    }

    /// ACK příjemce → hard-delete z fronty (žádná retence po doručení).
    pub async fn ack(&self, delivery_address: &[u8], msg_uuid: &[u8]) -> anyhow::Result<()> {
        let freed: Option<i32> = sqlx::query_scalar(
            "DELETE FROM message_queue WHERE msg_uuid = $1 AND dst_address = $2
             RETURNING octet_length(envelope)",
        )
        .bind(msg_uuid)
        .bind(delivery_address)
        .fetch_optional(&self.pool)
        .await?;
        if let Some(freed) = freed {
            self.queue_gauges.removed(delivery_address, i64::from(freed));
            self.queue_total.removed(i64::from(freed));
        }
        Ok(())
    }
}

#[cfg(test)]
mod online_tests {
    use super::*;

    /// První běh po startu a pak jednou denně projde všechno, mezi tím jen
    /// registrace od minulého běhu (s přesahem).
    #[test]
    fn dorovnani_blokaci_je_uplne_jen_obcas() {
        let mut marks = ReconcileMarks::default();
        let start = Instant::now();
        let ran_at = Utc::now();
        assert_eq!(marks.incremental_since(start), None, "po startu úplný průchod");

        marks.done(start, ran_at, true);
        let hour = std::time::Duration::from_secs(3600);
        assert_eq!(
            marks.incremental_since(start + hour),
            Some(ran_at - Duration::minutes(RECONCILE_OVERLAP_MINUTES))
        );
        let later = ran_at + Duration::hours(1);
        marks.done(start + hour, later, false);
        assert_eq!(
            marks.incremental_since(start + 2 * hour),
            Some(later - Duration::minutes(RECONCILE_OVERLAP_MINUTES)),
            "okno navazuje na poslední běh"
        );
        assert_eq!(
            marks.incremental_since(start + RECONCILE_FULL_EVERY),
            None,
            "přírůstkový běh úplný průchod neodkládá"
        );
    }

    fn spojeni() -> Arc<OnlineDevice> {
        let (outbox, _rx) = crate::outbox::channel();
        Arc::new(OnlineDevice::new(outbox, 0))
    }

    #[test]
    fn novejsi_spojeni_prebira_dorucovani() {
        let online = OnlineDevices::default();
        let adresa = vec![7u8; 32];
        let (stare, nove) = (spojeni(), spojeni());

        online.attach(adresa.clone(), stare.clone());
        online.attach(adresa.clone(), nove.clone());

        let cil = online.get(&adresa).expect("adresa je online");
        assert!(Arc::ptr_eq(&cil, &nove));
    }

    #[test]
    fn konec_stareho_spojeni_neodebere_nove() {
        let online = OnlineDevices::default();
        let adresa = vec![7u8; 32];
        let (stare, nove) = (spojeni(), spojeni());
        online.attach(adresa.clone(), stare.clone());
        online.attach(adresa.clone(), nove.clone());

        assert!(!online.detach(&adresa, &stare), "cizí záznam se nesmí odebrat");
        let cil = online.get(&adresa).expect("nové spojení zůstává online");
        assert!(Arc::ptr_eq(&cil, &nove));

        assert!(online.detach(&adresa, &nove));
        assert!(online.get(&adresa).is_none());
    }

    #[test]
    fn registr_kick_zasahne_vsechna_spojeni_zarizeni() {
        let conns = AuthedConns::default();
        let (zarizeni, cizi) = (vec![1u8; 16], vec![2u8; 16]);
        let (_g1, mut prvni) = conns.add(zarizeni.clone(), [1u8; 32]);
        let (_g2, mut druhe) = conns.add(zarizeni.clone(), [1u8; 32]);
        let (_g3, mut cizi_spojeni) = conns.add(cizi.clone(), [2u8; 32]);

        let mut snimek = conns.live_devices();
        snimek.sort();
        assert_eq!(snimek, vec![zarizeni.clone(), cizi], "snímek bez duplicit");

        assert_eq!(conns.kick_devices(std::slice::from_ref(&zarizeni), 403), 2);
        assert_eq!(prvni.try_recv(), Ok(403));
        assert_eq!(druhe.try_recv(), Ok(403));
        assert!(
            cizi_spojeni.try_recv().is_err(),
            "cizí spojení nic nedostane"
        );
        assert_eq!(
            conns.kick_devices(&[zarizeni], 410),
            0,
            "odpojené už v registru nejsou"
        );
    }

    /// Druh obálky volí odesílatel: bez hodinového stropu by cizí telefon
    /// zvonil každých deset sekund, jak dlouho by si kdo přál.
    #[test]
    fn viditelne_notifikace_maji_hodinovy_strop() {
        const PER_HOUR: usize = 3;
        const SENDER: u64 = 1;
        let step = ALERT_MIN_INTERVAL + std::time::Duration::from_secs(1);
        let mut marks = WakeMarks::default();
        let start = Instant::now();
        for i in 0..PER_HOUR as u32 {
            assert!(marks.allow_alert(start + step * i, SENDER, PER_HOUR), "{i}");
        }
        let over = start + step * PER_HOUR as u32;
        assert!(!marks.allow_alert(over, SENDER, PER_HOUR), "nad hodinový strop");
        assert!(
            marks.allow_alert(over, SENDER, 0),
            "0 = bez hodinového stropu, platí jen rozestup"
        );
        let next_hour = start + ALERT_WINDOW + step;
        assert!(marks.allow_alert(next_hour, SENDER, PER_HOUR), "okno se posunulo");
    }

    /// Kdo vyčerpal svůj strop, neumlčí notifikace od ostatních, a po
    /// přihlášení příjemce slyší zase všechny.
    #[test]
    fn strop_notifikaci_je_na_odesilatele_a_prihlaseni_ho_nuluje() {
        const PER_HOUR: usize = 2;
        const NOISY: u64 = 1;
        const FRIEND: u64 = 2;
        let step = ALERT_MIN_INTERVAL + std::time::Duration::from_secs(1);
        let mut marks = WakeMarks::default();
        let start = Instant::now();
        assert!(marks.allow_alert(start, NOISY, PER_HOUR));
        assert!(marks.allow_alert(start + step, NOISY, PER_HOUR));
        assert!(!marks.allow_alert(start + step * 2, NOISY, PER_HOUR), "vyčerpáno");
        assert!(
            marks.allow_alert(start + step * 2, FRIEND, PER_HOUR),
            "jiný odesílatel má vlastní strop"
        );

        marks.reset_alerts();
        assert!(
            marks.allow_alert(start + step * 3, NOISY, PER_HOUR),
            "po přihlášení příjemce se počítá znovu"
        );
    }

    /// Značky jednoho cíle nerostou s počtem odesílajících účtů a po okně
    /// zmizí.
    #[test]
    fn znacky_notifikaci_maji_strop_odesilatelu() {
        const PER_HOUR: usize = 60;
        let step = ALERT_MIN_INTERVAL + std::time::Duration::from_secs(1);
        let mut marks = WakeMarks::default();
        let start = Instant::now();
        for sender in 0..ALERT_SENDERS_TRACKED as u64 {
            assert!(marks.allow_alert(start, sender, PER_HOUR), "{sender}");
            // Rozestup tu test nezajímá, jen počet zapamatovaných odesílatelů.
            marks.last_alert = None;
        }
        assert!(
            !marks.allow_alert(start, u64::MAX, PER_HOUR),
            "další odesílatel se už nezapamatuje"
        );
        assert_eq!(marks.alerts.len(), ALERT_SENDERS_TRACKED);

        marks.expire_alerts(start + ALERT_WINDOW + step);
        assert!(marks.alerts.is_empty(), "po okně značky zmizí");
    }

    #[test]
    fn viditelna_notifikace_drzi_rozestup() {
        let mut marks = WakeMarks::default();
        let start = Instant::now();
        assert!(marks.allow_alert(start, 1, 60), "první zpráva zazvoní");
        assert!(!marks.allow_alert(start, 2, 60), "druhá v okně už ne");
        assert_eq!(
            marks.last_wake,
            Some(start),
            "notifikace se počítá i jako budíček"
        );
    }

    #[test]
    fn registr_guard_uklidi_pri_dropu() {
        let conns = AuthedConns::default();
        let zarizeni = vec![3u8; 16];
        let (guard, _rx) = conns.add(zarizeni.clone(), [3u8; 32]);
        assert_eq!(conns.snapshot().len(), 1);
        drop(guard);
        assert!(conns.snapshot().is_empty(), "drop guardu záznam odebere");

        // Kick záznam odebere dřív než guard; pozdější drop nesmí spadnout.
        let (guard, mut rx) = conns.add(zarizeni.clone(), [3u8; 32]);
        assert_eq!(conns.kick_devices(&[zarizeni], 410), 1);
        assert_eq!(rx.try_recv(), Ok(410));
        drop(guard);
        assert!(conns.snapshot().is_empty());
    }
}

#[cfg(test)]
mod db_tests {
    //! Integrace push registrace nad reálným Postgresem. #[ignore] — spouštět
    //! s běžící dev DB: `cargo test -p sepot-relay -- --ignored`. Používá
    //! náhodná ID a po sobě uklízí (žádná pollution existujících dat).
    use super::*;
    use rand::RngCore;

    /// Účet odesílatele v testech — kvóta je jen v paměti, DB ho nezná.
    const SENDER: &[u8] = b"test-odesilatel";

    /// Odesílatel s plnými kvótami: dávno registrovaný, píše cizím adresám.
    fn established(account: &[u8]) -> Sender<'_> {
        Sender {
            account,
            address: &[],
            registered_at: DateTime::UNIX_EPOCH,
        }
    }

    /// Testovací DB s aktuálním schématem (migrace spouští testkit).
    async fn test_state() -> AppState {
        crate::testkit::state().await
    }

    fn rand_bytes(n: usize) -> Vec<u8> {
        let mut v = vec![0u8; n];
        rand::rng().fill_bytes(&mut v);
        v
    }

    /// Naseje identitu+zařízení. Vrací (account_id, device_uuid, delivery_address).
    async fn seed_device(state: &AppState) -> (Vec<u8>, Vec<u8>, Vec<u8>) {
        let account_id = rand_bytes(16);
        let identity_key = rand_bytes(33); // CHECK octet_length = 33
        let device_uuid = rand_bytes(16);
        let delivery_address = rand_bytes(32);
        sqlx::query("INSERT INTO identities (account_id, identity_key) VALUES ($1, $2)")
            .bind(&account_id)
            .bind(&identity_key)
            .execute(&state.pool)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO devices
             (device_uuid, account_id, device_id, registration_id, delivery_address)
             VALUES ($1, $2, 1, 1, $3)",
        )
        .bind(&device_uuid)
        .bind(&account_id)
        .bind(&delivery_address)
        .execute(&state.pool)
        .await
        .unwrap();
        (account_id, device_uuid, delivery_address)
    }

    async fn cleanup(state: &AppState, account_id: &[u8], delivery_address: &[u8]) {
        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(delivery_address)
            .execute(&state.pool)
            .await
            .unwrap();
        // CASCADE smaže devices i push_tokens
        sqlx::query("DELETE FROM identities WHERE account_id = $1")
            .bind(account_id)
            .execute(&state.pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn register_push_upsert_a_lookup() {
        let state = test_state().await;
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;

        // bez registrace → žádný cíl
        assert!(state.push_target(&delivery_address).await.is_none());

        // UnifiedPush endpoint
        let ep1 = b"https://ntfy.sh/UPabc".to_vec();
        state
            .register_push(&device_uuid, crate::push::PLATFORM_UNIFIEDPUSH, Some(&ep1), None)
            .await
            .unwrap();
        assert_eq!(
            state.push_target(&delivery_address).await,
            Some((crate::push::PLATFORM_UNIFIEDPUSH, ep1))
        );

        // upsert na WebPush (jiná platforma i token)
        let ep2 = b"https://push.example/w".to_vec();
        state
            .register_push(&device_uuid, crate::push::PLATFORM_WEBPUSH, Some(&ep2), None)
            .await
            .unwrap();
        assert_eq!(
            state.push_target(&delivery_address).await,
            Some((crate::push::PLATFORM_WEBPUSH, ep2))
        );

        // NONE → smaže (anonymní režim)
        state
            .register_push(&device_uuid, crate::push::PLATFORM_NONE, None, None)
            .await
            .unwrap();
        assert!(state.push_target(&delivery_address).await.is_none());

        cleanup(&state, &account_id, &delivery_address).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn voip_token_se_ulozi_a_hovor_jde_do_fronty() {
        let state = test_state().await;
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;

        state
            .register_push(
                &device_uuid,
                crate::push::PLATFORM_APNS,
                Some(b"apns-token"),
                Some(b"voip-token"),
            )
            .await
            .unwrap();
        let target = state.push_target_full(&delivery_address).await.unwrap();
        assert_eq!(target.platform, crate::push::PLATFORM_APNS);
        assert_eq!(target.token.as_deref(), Some(&b"apns-token"[..]));
        assert_eq!(target.voip_token.as_deref(), Some(&b"voip-token"[..]));
        // Běžné zprávy dál budí běžný token, ne VoIP.
        assert_eq!(
            state.push_target(&delivery_address).await,
            Some((crate::push::PLATFORM_APNS, b"apns-token".to_vec()))
        );

        // Nabídka hovoru offline příjemci: uloží se jako běžná obálka
        // (vyzvedne si ji po probuzení), jen budíček je jiný.
        let env = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: rand_bytes(16),
            content_hint: v1::ContentHint::Call as i32,
            payload: vec![0xCD; 64],
        };
        let status = state.route_envelope(env, established(SENDER)).await.unwrap();
        assert_eq!(status, v1::receipt::Status::StoredOffline);
        let queued: i64 =
            sqlx::query_scalar("SELECT count(*) FROM message_queue WHERE dst_address = $1")
                .bind(&delivery_address)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(queued, 1);

        // Nová registrace bez VoIP tokenu ho smaže (appka PushKit vypnula).
        state
            .register_push(&device_uuid, crate::push::PLATFORM_APNS, Some(b"apns-token"), None)
            .await
            .unwrap();
        assert!(state
            .push_target_full(&delivery_address)
            .await
            .unwrap()
            .voip_token
            .is_none());

        cleanup(&state, &account_id, &delivery_address).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn route_envelope_offline_ulozi_a_spusti_wake() {
        let state = test_state().await;
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;
        // Endpoint schválně na loopback → guard ho odmítne, žádný externí POST
        // (test zůstává hermetický). Ověřujeme, že offline cesta projde a
        // route_envelope se na budíčku nezhroutí.
        state
            .register_push(
                &device_uuid,
                crate::push::PLATFORM_UNIFIEDPUSH,
                Some(b"https://localhost/up"),
                None,
            )
            .await
            .unwrap();

        let env = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: rand_bytes(16),
            content_hint: 0,
            payload: vec![0xAB; 64],
        };
        let status = state.route_envelope(env, established(SENDER)).await.unwrap();
        assert_eq!(status, v1::receipt::Status::StoredOffline);

        // obálka je ve frontě (příjemce byl offline)
        let queued: i64 =
            sqlx::query_scalar("SELECT count(*) FROM message_queue WHERE dst_address = $1")
                .bind(&delivery_address)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(queued, 1);

        cleanup(&state, &account_id, &delivery_address).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn ephemeral_offline_se_zahodi_bez_fronty() {
        let state = test_state().await;
        let (account_id, _device_uuid, delivery_address) = seed_device(&state).await;

        let env = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: rand_bytes(16),
            content_hint: v1::ContentHint::Ephemeral as i32,
            payload: vec![0xAB; 64],
        };
        let status = state.route_envelope(env, established(SENDER)).await.unwrap();
        assert_eq!(status, v1::receipt::Status::Queued);

        // „píše…“ pro offline příjemce nesmí skončit ve frontě
        let queued: i64 =
            sqlx::query_scalar("SELECT count(*) FROM message_queue WHERE dst_address = $1")
                .bind(&delivery_address)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(queued, 0);

        cleanup(&state, &account_id, &delivery_address).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn delete_identity_smaze_ucet_frontu_i_push() {
        let state = test_state().await;
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;

        // účet má push token i nedoručenou zprávu ve frontě
        state
            .register_push(
                &device_uuid,
                crate::push::PLATFORM_UNIFIEDPUSH,
                Some(b"https://localhost/up"),
                None,
            )
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at)
             VALUES ($1, $2, $3, now() + interval '30 days')",
        )
        .bind(rand_bytes(16))
        .bind(&delivery_address)
        .bind(vec![0xCDu8; 64])
        .execute(&state.pool)
        .await
        .unwrap();

        state.delete_identity(&account_id).await.unwrap();

        let identities: i64 =
            sqlx::query_scalar("SELECT count(*) FROM identities WHERE account_id = $1")
                .bind(&account_id)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        let devices: i64 =
            sqlx::query_scalar("SELECT count(*) FROM devices WHERE account_id = $1")
                .bind(&account_id)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        let queued: i64 =
            sqlx::query_scalar("SELECT count(*) FROM message_queue WHERE dst_address = $1")
                .bind(&delivery_address)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        let tokens: i64 =
            sqlx::query_scalar("SELECT count(*) FROM push_tokens WHERE device_uuid = $1")
                .bind(&device_uuid)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!((identities, devices, queued, tokens), (0, 0, 0, 0));

        // idempotence: druhé smazání neexistujícího účtu nesmí spadnout
        state.delete_identity(&account_id).await.unwrap();
    }

    /// Audit #3: flush přes hranici dávky (150 > FLUSH_BATCH) nesmí keyset
    /// kurzorem žádnou obálku ztratit ani zdvojit.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_davkuje_pres_hranici_bez_ztraty() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let n = 150usize;
        let mut expected = std::collections::HashSet::new();
        for i in 0..n {
            let msg_uuid = rand_bytes(16);
            expected.insert(msg_uuid.clone());
            let env = v1::Envelope {
                dst_address: dst.clone(),
                msg_uuid: msg_uuid.clone(),
                content_hint: 0,
                payload: vec![0x11; 32],
            };
            sqlx::query(
                "INSERT INTO message_queue (msg_uuid, dst_address, envelope, enqueued_at, expires_at)
                 VALUES ($1, $2, $3, now() + (interval '1 millisecond' * $4), now() + interval '30 days')",
            )
            .bind(&msg_uuid)
            .bind(&dst)
            .bind(env.encode_to_vec())
            .bind(i as i32)
            .execute(&state.pool)
            .await
            .unwrap();
        }

        let (device, mut rx) = crate::testkit::device(&state);
        let count = state.flush_queue(&dst, &device).await.unwrap();
        drop(device);
        assert_eq!(count, n);

        let mut got = std::collections::HashSet::new();
        while let Some(frame) = rx.frame().await {
            if let Some(v1::server_frame::Frame::Deliver(env)) = frame.frame {
                assert!(got.insert(env.msg_uuid), "obálka doručena dvakrát");
            }
        }
        assert_eq!(got, expected, "sada doručených ≠ sada zařazených");

        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(&dst)
            .execute(&state.pool)
            .await
            .unwrap();
    }

    /// Naplní frontu adresy velkými obálkami v daném pořadí.
    async fn enqueue_big(state: &AppState, dst: &[u8], count: usize) {
        /// Čtyři takové se do dávky i do fronty spojení vejdou, pátá ne.
        const BIG_PAYLOAD_BYTES: usize = 250 * 1024;
        for i in 0..count {
            let env = v1::Envelope {
                dst_address: dst.to_vec(),
                msg_uuid: rand_bytes(16),
                content_hint: 0,
                payload: vec![0x77; BIG_PAYLOAD_BYTES],
            };
            sqlx::query(
                "INSERT INTO message_queue (msg_uuid, dst_address, envelope, enqueued_at, expires_at)
                 VALUES ($1, $2, $3, now() + (interval '1 millisecond' * $4), now() + interval '30 days')",
            )
            .bind(&env.msg_uuid)
            .bind(dst)
            .bind(env.encode_to_vec())
            .bind(i as i32)
            .execute(&state.pool)
            .await
            .unwrap();
        }
    }

    async fn clear_queue(state: &AppState, dst: &[u8]) {
        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(dst)
            .execute(&state.pool)
            .await
            .unwrap();
    }

    /// Dávka vylévání má strop i v bajtech (dřív 64 obálek × 256 KiB =
    /// 16 MiB v paměti na spojení) a přes hranice dávek se nic neztratí.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_davka_ma_strop_bajtu() {
        const QUEUED: usize = 9;
        let state = test_state().await;
        let dst = rand_bytes(32);
        enqueue_big(&state, &dst, QUEUED).await;

        let batch = state.flush_batch(&dst, None).await.unwrap();
        let bytes: usize = batch.iter().map(|(envelope, _, _)| envelope.len()).sum();
        assert!(bytes <= FLUSH_BATCH_BYTES as usize, "dávka má {bytes} B");
        assert!(!batch.is_empty() && batch.len() < QUEUED, "{}", batch.len());

        let (device, mut rx) = crate::testkit::device(&state);
        let reader = tokio::spawn(async move {
            let mut delivered = std::collections::HashSet::new();
            while let Some(frame) = rx.frame().await {
                if let Some(v1::server_frame::Frame::Deliver(env)) = frame.frame {
                    delivered.insert(env.msg_uuid);
                }
            }
            delivered.len()
        });
        assert_eq!(state.flush_queue(&dst, &device).await.unwrap(), QUEUED);
        drop(device);
        assert_eq!(reader.await.unwrap(), QUEUED, "každá obálka právě jednou");
        clear_queue(&state, &dst).await;
    }

    /// Jednu adresu vylévá jen spojení, které právě doručuje. Starší
    /// spojení, které nečte, po reconnectu přestane a zámek adresy pustí —
    /// jinak by každé nečtoucí spojení téhož zařízení drželo svou dávku.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_prevezme_novejsi_spojeni() {
        /// Víc, než pojme fronta jednoho spojení.
        const QUEUED: usize = 12;
        const STEP: std::time::Duration = std::time::Duration::from_millis(200);
        let state = Arc::new(test_state().await);
        let dst = rand_bytes(32);
        enqueue_big(&state, &dst, QUEUED).await;

        let (old, _old_never_reads) = crate::testkit::device(&state);
        state.online.attach(dst.clone(), old.clone());
        let old_flush = tokio::spawn({
            let (state, dst) = (state.clone(), dst.clone());
            async move { state.flush_queue(&dst, &old).await.unwrap() }
        });
        tokio::time::sleep(STEP).await;
        assert!(!old_flush.is_finished(), "starší spojení stojí o plnou frontu");

        let (new, mut new_rx) = crate::testkit::device(&state);
        state.online.attach(dst.clone(), new.clone());
        // Hned, ne až po lhůtě zápisu staršího spojení: to stojí na plné
        // frontě a čekání na místo se převzetím přeruší.
        let sent_to_old = tokio::time::timeout(STEP, old_flush)
            .await
            .expect("starší spojení má vylévání pustit hned")
            .unwrap();
        assert!(sent_to_old < QUEUED, "{sent_to_old}");

        let reader = tokio::spawn(async move {
            let mut delivered = 0;
            while new_rx.frame().await.is_some() {
                delivered += 1;
            }
            delivered
        });
        assert_eq!(state.flush_queue(&dst, &new).await.unwrap(), QUEUED);
        state.online.detach(&dst, &new);
        drop(new);
        assert_eq!(reader.await.unwrap(), QUEUED);
        clear_queue(&state, &dst).await;
    }

    /// Zapsat do fronty spojení jde i u dávno mrtvého spojení — DELIVERED_ONLINE
    /// se proto smí hlásit jen u zařízení, od kterého nedávno něco přišlo.
    /// Zatuchlé musí spadnout na offline větev, jinak spolkne push budíček.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn route_envelope_zatuchle_spojeni_neni_online() {
        let mut state = test_state().await;
        // Posunout start procesu do minulosti, ať jde značka „naposled se
        // ozval na začátku" vyjádřit bez čekání reálných 70 s.
        state.started = std::time::Instant::now()
            - std::time::Duration::from_millis(FRESH_CONNECTION_MS + 10_000);
        let (_account_id, _device_uuid, delivery_address) = seed_device(&state).await;

        // Kanál nikdo nečte, ale buffer zápis spolkne — přesně situace
        // mrtvého klienta, kterou dřív relay hlásil jako doručeno.
        let (outbox, _rx) = crate::outbox::channel();
        let device = Arc::new(OnlineDevice::new(outbox, 0));
        state
            .online
            .attach(delivery_address.clone(), device.clone());

        let env = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: rand_bytes(16),
            content_hint: 0,
            payload: vec![0xCD; 64],
        };
        assert_eq!(
            state.route_envelope(env, established(SENDER)).await.unwrap(),
            v1::receipt::Status::StoredOffline,
            "zatuchlé spojení se nesmí hlásit jako doručené online"
        );

        // A naopak: čerstvě označené zařízení online být má.
        device.touch(state.now_ms());
        let env2 = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: rand_bytes(16),
            content_hint: 0,
            payload: vec![0xCE; 64],
        };
        assert_eq!(
            state.route_envelope(env2, established(SENDER)).await.unwrap(),
            v1::receipt::Status::DeliveredOnline,
            "živé spojení má být online"
        );

        state.online.detach(&delivery_address, &device);
        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(&delivery_address)
            .execute(&state.pool)
            .await
            .unwrap();
    }

    /// Reconnect po změně sítě: staré spojení dožije až po novém a jeho
    /// konec nesmí vyřadit nové spojení z živého doručování.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn route_envelope_po_konci_zombie_spojeni_dorucuje_na_nove() {
        let state = test_state().await;
        let (account_id, _device_uuid, delivery_address) = seed_device(&state).await;

        let (stare, _rx_stare) = crate::testkit::device(&state);
        state.online.attach(delivery_address.clone(), stare.clone());

        let (nove, mut rx_nove) = crate::testkit::device(&state);
        state.online.attach(delivery_address.clone(), nove.clone());

        // Handler starého spojení končí (idle timeout) až po reconnectu.
        assert!(!state.online.detach(&delivery_address, &stare));

        let msg_uuid = rand_bytes(16);
        let env = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: msg_uuid.clone(),
            content_hint: 0,
            payload: vec![0xEF; 64],
        };
        assert_eq!(
            state.route_envelope(env, established(SENDER)).await.unwrap(),
            v1::receipt::Status::DeliveredOnline,
            "konec zombie spojení nesmí vyřadit nové spojení"
        );
        match rx_nove.try_frame().map(|f| f.frame) {
            Some(Some(v1::server_frame::Frame::Deliver(env))) => assert_eq!(env.msg_uuid, msg_uuid),
            jinak => panic!("nové spojení nedostalo DELIVER: {jinak:?}"),
        }

        assert!(state.online.detach(&delivery_address, &nove));
        cleanup(&state, &account_id, &delivery_address).await;
    }

    /// Flush počítá pokusy — bez toho by strop nikdy nezabral.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_pocita_pokusy() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let msg_uuid = rand_bytes(16);
        let env = v1::Envelope {
            dst_address: dst.clone(),
            msg_uuid: msg_uuid.clone(),
            content_hint: 0,
            payload: vec![0x22; 32],
        };
        sqlx::query(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at)
             VALUES ($1, $2, $3, now() + interval '30 days')",
        )
        .bind(&msg_uuid)
        .bind(&dst)
        .bind(env.encode_to_vec())
        .execute(&state.pool)
        .await
        .unwrap();

        // Dva flushe bez ACK = dva započtené pokusy.
        for _ in 0..2 {
            let (device, rx) = crate::testkit::device(&state);
            assert_eq!(state.flush_queue(&dst, &device).await.unwrap(), 1);
            drop(rx);
        }

        let attempts: (i16,) =
            sqlx::query_as("SELECT attempt_count FROM message_queue WHERE msg_uuid = $1")
                .bind(&msg_uuid)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(attempts.0, 2, "každý flush musí započítat pokus");

        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(&dst)
            .execute(&state.pool)
            .await
            .unwrap();
    }

    /// Obálka, kterou příjemce nikdy neACKne (ztracený ACK → ratchet už
    /// postoupil), musí po stropu zmizet, ne otravovat frontu 30 dní.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_zahodi_nepruchodnou_obalku() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let msg_uuid = rand_bytes(16);
        let env = v1::Envelope {
            dst_address: dst.clone(),
            msg_uuid: msg_uuid.clone(),
            content_hint: 0,
            payload: vec![0x33; 32],
        };
        // Rovnou na stropu a dost stará = obálka, která se marně posílala
        // MAX_DELIVERY_ATTEMPTS× déle než MIN_HOURS_BEFORE_DROP.
        sqlx::query(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at,
                                        attempt_count, enqueued_at)
             VALUES ($1, $2, $3, now() + interval '30 days', $4, now() - interval '4 days')",
        )
        .bind(&msg_uuid)
        .bind(&dst)
        .bind(env.encode_to_vec())
        .bind(MAX_DELIVERY_ATTEMPTS)
        .execute(&state.pool)
        .await
        .unwrap();

        let (device, rx) = crate::testkit::device(&state);
        assert_eq!(
            state.flush_queue(&dst, &device).await.unwrap(),
            0,
            "vyčerpaná obálka se nesmí znovu poslat"
        );
        drop(rx);

        let zbylo: (i64,) =
            sqlx::query_as("SELECT count(*) FROM message_queue WHERE dst_address = $1")
                .bind(&dst)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(zbylo.0, 0, "vyčerpaná obálka měla být zahozena");
    }

    /// Mladá obálka na stropu pokusů se dál doručuje: pokusy pálí každé
    /// připojení (iPhone otevírá a uspává appku), ne skutečná nedoručitelnost.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_mlada_obalka_na_stropu_se_doruci() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let msg_uuid = rand_bytes(16);
        let env = v1::Envelope {
            dst_address: dst.clone(),
            msg_uuid: msg_uuid.clone(),
            content_hint: 0,
            payload: vec![0x44; 32],
        };
        sqlx::query(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at, attempt_count)
             VALUES ($1, $2, $3, now() + interval '30 days', $4)",
        )
        .bind(&msg_uuid)
        .bind(&dst)
        .bind(env.encode_to_vec())
        .bind(MAX_DELIVERY_ATTEMPTS + 5)
        .execute(&state.pool)
        .await
        .unwrap();

        let (device, mut rx) = crate::testkit::device(&state);
        assert_eq!(state.flush_queue(&dst, &device).await.unwrap(), 1);
        assert!(rx.try_frame().is_some(), "obálka odešla příjemci");

        state.ack(&dst, &msg_uuid).await.unwrap();
        let zbylo: (i64,) =
            sqlx::query_as("SELECT count(*) FROM message_queue WHERE dst_address = $1")
                .bind(&dst)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(zbylo.0, 0, "ACK ji smazal");
    }

    /// Počítadlo pokusů nepřeteče: obálka na stropu typu sloupce nesmí
    /// shodit započítání pokusu ostatním obálkám v dávce.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn flush_queue_pocitadlo_pokusu_nepretece() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let mut uuids = Vec::new();
        for (i, attempts) in [i16::MAX, 3].into_iter().enumerate() {
            let msg_uuid = rand_bytes(16);
            let env = v1::Envelope {
                dst_address: dst.clone(),
                msg_uuid: msg_uuid.clone(),
                content_hint: 0,
                payload: vec![0x55; 32],
            };
            sqlx::query(
                "INSERT INTO message_queue
                   (msg_uuid, dst_address, envelope, enqueued_at, expires_at, attempt_count)
                 VALUES ($1, $2, $3, now() + (interval '1 second' * $4),
                         now() + interval '30 days', $5)",
            )
            .bind(&msg_uuid)
            .bind(&dst)
            .bind(env.encode_to_vec())
            .bind(i as i32)
            .bind(attempts)
            .execute(&state.pool)
            .await
            .unwrap();
            uuids.push(msg_uuid);
        }

        let (device, _rx) = crate::testkit::device(&state);
        assert_eq!(state.flush_queue(&dst, &device).await.unwrap(), 2);

        let mut pokusy = Vec::new();
        for uuid in &uuids {
            let (n,): (i16,) =
                sqlx::query_as("SELECT attempt_count FROM message_queue WHERE msg_uuid = $1")
                    .bind(uuid)
                    .fetch_one(&state.pool)
                    .await
                    .unwrap();
            pokusy.push(n);
        }
        assert_eq!(pokusy, vec![i16::MAX, 4]);
    }

    fn envelope(dst: &[u8], payload_len: usize) -> v1::Envelope {
        v1::Envelope {
            dst_address: dst.to_vec(),
            msg_uuid: rand_bytes(16),
            content_hint: 0,
            payload: vec![0x5Au8; payload_len],
        }
    }

    async fn queued(state: &AppState, dst: &[u8]) -> i64 {
        sqlx::query_scalar("SELECT count(*) FROM message_queue WHERE dst_address = $1")
            .bind(dst)
            .fetch_one(&state.pool)
            .await
            .unwrap()
    }

    /// Obálka na adresu bez zařízení se neuloží (dřív 30 dní ve frontě =
    /// nejlevnější cesta, jak zaplnit disk relaye).
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn obalka_na_neexistujici_adresu_se_neulozi() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let err = state.route_envelope(envelope(&dst, 64), established(SENDER)).await.unwrap_err();
        assert!(matches!(err, RouteError::UnknownRecipient), "{err:?}");
        assert_eq!(err.code_and_message().0, 404);
        assert_eq!(queued(&state, &dst).await, 0);
    }

    /// Kvóta odesílatele: nad hodinový strop 429, jiný účet jede dál.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn kvota_odesilatele_odmitne_nad_strop() {
        let mut state = test_state().await;
        state.send_budget = crate::quota::Budgets::new(3, 0, SEND_BUDGET_PERIOD);
        let (account_id, _device, dst) = seed_device(&state).await;
        let sender = rand_bytes(16);
        for _ in 0..3 {
            state
                .route_envelope(envelope(&dst, 64), established(&sender))
                .await
                .unwrap();
        }
        let err = state
            .route_envelope(envelope(&dst, 64), established(&sender))
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::SenderQuota), "{err:?}");
        state
            .route_envelope(envelope(&dst, 64), established(&rand_bytes(16)))
            .await
            .expect("jiný odesílatel má vlastní kvótu");
        assert_eq!(queued(&state, &dst).await, 4);
        cleanup(&state, &account_id, &dst).await;
    }

    /// Málo místa na disku: offline fronta stojí (507), nic se nezapíše.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plny_disk_zastavi_frontu() {
        let state = test_state().await;
        let (account_id, _device, dst) = seed_device(&state).await;
        state.disk.set_free_pct(state.limits.disk_min_free_pct_queue - 1.0);
        let err = state.route_envelope(envelope(&dst, 64), established(SENDER)).await.unwrap_err();
        assert!(matches!(err, RouteError::DiskFull), "{err:?}");
        assert_eq!(queued(&state, &dst).await, 0);
        cleanup(&state, &account_id, &dst).await;
    }

    /// Plná fronta příjemce novou obálku odmítne a čekající nechá. Dřív
    /// strop mazal nejstarší: kdo znal adresu, tím příjemci smazal zprávy.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plna_fronta_odmitne_novou_a_stare_necha() {
        const CAP: i64 = 3;
        let mut state = test_state().await;
        state.limits.queue_max_per_recipient = CAP;
        let (account_id, _device, dst) = seed_device(&state).await;
        let mut waiting = Vec::new();
        let mut first = None;
        for _ in 0..CAP {
            let env = envelope(&dst, 64);
            waiting.push(env.msg_uuid.clone());
            first.get_or_insert_with(|| env.clone());
            state.route_envelope(env, established(SENDER)).await.unwrap();
        }
        let err = state
            .route_envelope(envelope(&dst, 64), established(SENDER))
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::RecipientFull), "{err:?}");

        // Obálku, kterou fronta už má, klient opakuje kvůli ztracené
        // doručence: ta odmítnutí dostat nesmí.
        let repeated = state
            .route_envelope(first.expect("první obálka"), established(SENDER))
            .await
            .expect("opakovaná obálka není nová");
        assert_eq!(repeated, v1::receipt::Status::StoredOffline);

        let mut kept: Vec<Vec<u8>> =
            sqlx::query_scalar("SELECT msg_uuid FROM message_queue WHERE dst_address = $1")
                .bind(&dst)
                .fetch_all(&state.pool)
                .await
                .unwrap();
        kept.sort();
        waiting.sort();
        assert_eq!(kept, waiting, "čekající obálky zůstaly všechny");

        // Příjemce si jednu vyzvedne: místo je hned zpět, bez čekání na
        // další měření fronty.
        state.ack(&dst, &waiting[0]).await.unwrap();
        state
            .route_envelope(envelope(&dst, 64), established(SENDER))
            .await
            .expect("po potvrzení je ve frontě místo");
        cleanup(&state, &account_id, &dst).await;
    }

    /// Strop bajtů na příjemce: obálka, která by ho přesáhla, neprojde,
    /// menší ano.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plna_fronta_strop_bajtu() {
        let mut state = test_state().await;
        state.limits.queue_max_bytes_per_recipient = 1000;
        let (account_id, _device, dst) = seed_device(&state).await;
        state
            .route_envelope(envelope(&dst, 600), established(SENDER))
            .await
            .unwrap();
        let err = state
            .route_envelope(envelope(&dst, 600), established(SENDER))
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::RecipientFull), "{err:?}");
        state
            .route_envelope(envelope(&dst, 100), established(SENDER))
            .await
            .expect("menší obálka se vejde");
        assert_eq!(queued(&state, &dst).await, 2);
        cleanup(&state, &account_id, &dst).await;
    }

    /// Odmítnutá obálka neukrojí z kvóty odesílatele.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plna_fronta_nestoji_kvotu_odesilatele() {
        let mut state = test_state().await;
        state.limits.queue_max_per_recipient = 1;
        state.send_budget = crate::quota::Budgets::new(2, 0, SEND_BUDGET_PERIOD);
        let (full_account, _device, full) = seed_device(&state).await;
        let (free_account, _device, free) = seed_device(&state).await;
        let sender = rand_bytes(16);
        state
            .route_envelope(envelope(&full, 64), established(&sender))
            .await
            .unwrap();
        for _ in 0..5 {
            let err = state
                .route_envelope(envelope(&full, 64), established(&sender))
                .await
                .unwrap_err();
            assert!(matches!(err, RouteError::RecipientFull), "{err:?}");
        }
        state
            .route_envelope(envelope(&free, 64), established(&sender))
            .await
            .expect("druhá obálka z kvóty dvou");
        cleanup(&state, &full_account, &full).await;
        cleanup(&state, &free_account, &free).await;
    }

    /// Globální strop fronty je měkký: nad ním dostane každý příjemce jen
    /// zaručený příděl. Kdo si frontu vybírá, tomu relay doručuje dál; plná
    /// fronta útočníkových adres další obálky nepřijme.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn nad_globalnim_stropem_zbyva_zaruceny_pridel() {
        /// Větší než polovina zaručeného přídělu: druhá se už nevejde.
        const LARGE: usize = 200 * 1024;
        let mut state = test_state().await;
        state.limits.queue_max_bytes_total = 1 << 20;
        let (hoarder_account, _device, hoarder) = seed_device(&state).await;
        let (reader_account, _device, reader) = seed_device(&state).await;
        state.queue_total.set(state.limits.queue_max_bytes_total);

        for _ in 0..2 {
            state
                .route_envelope(envelope(&hoarder, LARGE), established(SENDER))
                .await
                .expect("zaručený příděl");
        }
        let err = state
            .route_envelope(envelope(&hoarder, LARGE), established(SENDER))
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::RecipientFull), "{err:?}");
        state
            .route_envelope(envelope(&reader, LARGE), established(SENDER))
            .await
            .expect("příjemce s prázdnou frontou dostává dál");

        // Pod polovinou stropu platí zase plný strop příjemce.
        state.queue_total.set(0);
        state
            .route_envelope(envelope(&hoarder, LARGE), established(SENDER))
            .await
            .expect("bez tlaku plný strop");
        cleanup(&state, &hoarder_account, &hoarder).await;
        cleanup(&state, &reader_account, &reader).await;
    }

    /// Měření celé fronty vidí vložené obálky; mezi měřeními je relay
    /// dopočítává sám.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn celkova_fronta_se_meri_a_dopocitava() {
        let isolated = crate::testkit::Isolated::new().await;
        let state = isolated.state().await;
        let (_account, _device, dst) = seed_device(&state).await;
        state.measure_queue_total().await.unwrap();
        assert_eq!(state.queue_total.get(), 0);

        let env = envelope(&dst, 1000);
        let (msg_uuid, stored) = (env.msg_uuid.clone(), env.encoded_len() as i64);
        state.route_envelope(env, established(SENDER)).await.unwrap();
        assert_eq!(state.queue_total.get(), stored, "vložení se dopočítá");
        state.queue_total.set(0);
        state.measure_queue_total().await.unwrap();
        assert_eq!(state.queue_total.get(), stored, "měření ho potvrdí");

        state.ack(&dst, &msg_uuid).await.unwrap();
        assert_eq!(state.queue_total.get(), 0, "potvrzení se odečte");
        isolated.remove().await;
    }

    /// Čerstvý účet a obálky na vlastní adresu mají nižší hodinovou kvótu
    /// bajtů; zavedený účet píšící jinam ji má plnou.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn cerstvy_ucet_a_vlastni_adresa_maji_nizsi_kvotu() {
        const PAYLOAD: usize = 1000;
        let mut state = test_state().await;
        // Plná kvóta na pět obálek, čerstvý účet na dvě, vlastní adresa
        // na jednu (obálka má s hlavičkou něco přes PAYLOAD bajtů).
        state.limits.send_bytes_per_hour = 6000;
        state.limits.send_fresh_bytes_per_hour = 2400;
        state.limits.send_self_bytes_per_hour = 1200;
        state.send_budget = crate::quota::Budgets::new(0, 6000, SEND_BUDGET_PERIOD);
        let (account_id, _device, dst) = seed_device(&state).await;
        let (own_account, _device, own) = seed_device(&state).await;

        async fn accepted(state: &AppState, sender: Sender<'_>, to: &[u8]) -> usize {
            let mut count = 0;
            while state
                .route_envelope(envelope(to, PAYLOAD), sender)
                .await
                .is_ok()
            {
                count += 1;
            }
            count
        }
        let (old, fresh, own_sender) = (rand_bytes(16), rand_bytes(16), rand_bytes(16));
        assert_eq!(accepted(&state, established(&old), &dst).await, 5);
        let just_registered = Sender {
            account: &fresh,
            address: &[],
            registered_at: Utc::now(),
        };
        assert_eq!(accepted(&state, just_registered, &dst).await, 2);
        let to_self = Sender {
            account: &own_sender,
            address: &own,
            registered_at: DateTime::UNIX_EPOCH,
        };
        assert_eq!(accepted(&state, to_self, &own).await, 1);

        cleanup(&state, &account_id, &dst).await;
        cleanup(&state, &own_account, &own).await;
    }

    /// „Píše…“ odpovídá vždy stejně: online, offline i neexistující adresa
    /// vypadají pro odesílatele stejně, takže z odpovědi nepozná, kdy je
    /// cizí zařízení připojené. Živému spojení se přitom doručí.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn ephemeral_odpovida_stejne_at_je_prijemce_kdekoli() {
        let state = test_state().await;
        let (online_account, _device, online) = seed_device(&state).await;
        let (offline_account, _device, offline) = seed_device(&state).await;
        let (device, mut rx) = crate::testkit::device(&state);
        state.online.attach(online.clone(), device.clone());

        let typing = |dst: &[u8]| v1::Envelope {
            content_hint: v1::ContentHint::Ephemeral as i32,
            ..envelope(dst, 64)
        };
        for dst in [&online, &offline, &rand_bytes(32)] {
            let status = state
                .route_envelope(typing(dst), established(SENDER))
                .await
                .unwrap();
            assert_eq!(status, v1::receipt::Status::Queued);
        }
        assert!(rx.try_frame().is_some(), "online příjemce „píše…“ dostal");
        assert!(rx.try_frame().is_none(), "a jen to jedno");

        state.online.detach(&online, &device);
        cleanup(&state, &online_account, &online).await;
        cleanup(&state, &offline_account, &offline).await;
    }

    /// „Píše…“ má vlastní kvótu na odesílatele, strop na cíl i strop
    /// velikosti. Nad kvótu se zahazuje tiše — odpověď se nemění.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn ephemeral_ma_kvotu_strop_na_cil_a_velikost() {
        const SENDER_QUOTA: u64 = 3;
        const TARGET_QUOTA: u64 = 2;
        let mut state = test_state().await;
        state.ephemeral_budget = crate::quota::Budgets::new(SENDER_QUOTA, 0, SEND_BUDGET_PERIOD);
        state.ephemeral_target_budget =
            crate::quota::Budgets::new(TARGET_QUOTA, 0, SEND_BUDGET_PERIOD);
        let (account_id, _device, dst) = seed_device(&state).await;
        let (other_account, _device, other) = seed_device(&state).await;
        let (device, mut rx) = crate::testkit::device(&state);
        let (other_device, mut other_rx) = crate::testkit::device(&state);
        state.online.attach(dst.clone(), device.clone());
        state.online.attach(other.clone(), other_device.clone());
        let typing = |dst: &[u8], payload_len: usize| v1::Envelope {
            content_hint: v1::ContentHint::Ephemeral as i32,
            ..envelope(dst, payload_len)
        };
        let delivered = |rx: &mut crate::outbox::OutboxReceiver| {
            std::iter::from_fn(|| rx.try_frame()).count()
        };

        let too_big = typing(&dst, state.limits.ephemeral_max_bytes + 1);
        let err = state
            .route_envelope(too_big, established(SENDER))
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::Invalid), "{err:?}");

        // Strop na cíl: dva odesílatelé, na adresu dojdou jen TARGET_QUOTA.
        let (first, second) = (rand_bytes(16), rand_bytes(16));
        for sender in [&first, &second, &first] {
            let status = state
                .route_envelope(typing(&dst, 64), established(sender))
                .await
                .unwrap();
            assert_eq!(status, v1::receipt::Status::Queued);
        }
        assert_eq!(delivered(&mut rx), TARGET_QUOTA as usize);

        // Kvóta odesílatele: `first` už poslal dvě, zbývá mu jedna.
        for _ in 0..3 {
            let status = state
                .route_envelope(typing(&other, 64), established(&first))
                .await
                .unwrap();
            assert_eq!(status, v1::receipt::Status::Queued);
        }
        assert_eq!(delivered(&mut other_rx), 1);
        assert_eq!(queued(&state, &dst).await, 0, "„píše…“ se neukládá");

        state.online.detach(&dst, &device);
        state.online.detach(&other, &other_device);
        cleanup(&state, &account_id, &dst).await;
        cleanup(&state, &other_account, &other).await;
    }

    /// iPhone s jediným VoIP tokenem (běžný APNs token ještě nemá) musí jít
    /// vzbudit hovorem — registrace se nesmí zahodit.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn apns_jen_s_voip_tokenem_se_ulozi() {
        let state = test_state().await;
        let (account_id, device_uuid, dst) = seed_device(&state).await;
        state
            .register_push(&device_uuid, crate::push::PLATFORM_APNS, None, Some(b"voip"))
            .await
            .unwrap();
        let target = state.push_target_full(&dst).await.expect("VoIP cíl");
        assert_eq!(target.voip_token.as_deref(), Some(&b"voip"[..]));
        assert!(target.token.is_none());
        assert!(state.push_target(&dst).await.is_none(), "běžný budíček nemá kam");
        cleanup(&state, &account_id, &dst).await;
    }

    /// Token, který push služba natrvalo odmítla, zmizí; token, který si
    /// zařízení mezitím vyměnilo, a druhý token téhož zařízení zůstanou.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn mrtvy_push_token_se_zapomene() {
        use crate::push::{DeadToken, PLATFORM_APNS};
        let state = test_state().await;
        let (account_id, device_uuid, dst) = seed_device(&state).await;
        state
            .register_push(&device_uuid, PLATFORM_APNS, Some(b"novy"), Some(b"voip"))
            .await
            .unwrap();

        forget_dead_token(&state.pool, &dst, DeadToken::Push, b"stary").await;
        assert_eq!(
            state.push_target(&dst).await,
            Some((PLATFORM_APNS, b"novy".to_vec())),
            "odmítnutí starého tokenu nesmí smazat nově registrovaný"
        );

        forget_dead_token(&state.pool, &dst, DeadToken::Push, b"novy").await;
        assert!(state.push_target(&dst).await.is_none());
        let target = state.push_target_full(&dst).await.expect("VoIP token zůstal");
        assert_eq!(target.voip_token.as_deref(), Some(&b"voip"[..]));

        forget_dead_token(&state.pool, &dst, DeadToken::Voip, b"voip").await;
        let rows: i64 =
            sqlx::query_scalar("SELECT count(*) FROM push_tokens WHERE device_uuid = $1")
                .bind(&device_uuid)
                .fetch_one(&state.pool)
                .await
                .unwrap();
        assert_eq!(rows, 0, "řádek bez tokenů nemá zůstat");
        cleanup(&state, &account_id, &dst).await;
    }

    /// Obálka, která se zakódovaná nevejde do CHECK fronty, je 400 dřív, než
    /// ukrojí z kvóty odesílatele — ne 500 z databáze.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn obalka_nad_strop_fronty_je_neplatna() {
        let state = test_state().await;
        let (account_id, _device, dst) = seed_device(&state).await;
        let err = state
            .route_envelope(envelope(&dst, MAX_ENVELOPE_PAYLOAD), established(SENDER))
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::Invalid), "{err:?}");
        assert_eq!(queued(&state, &dst).await, 0);
        cleanup(&state, &account_id, &dst).await;
    }

    /// Blokaci i smazání zapsal jiný proces: kontrola pozná, kdo dostane
    /// 403 a kdo 410, a živé zařízení nechá.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn kontrola_spojeni_odpoji_403_a_410() {
        let state = test_state().await;
        let blocked: [u8; 32] = rand_bytes(32).try_into().unwrap();
        sqlx::query(
            "INSERT INTO blocked_identities (fingerprint, expires_on) VALUES ($1, current_date + 30)",
        )
        .bind(blocked)
        .execute(&state.pool)
        .await
        .unwrap();
        let (_g1, mut blocked_conn) = state.conns.add(rand_bytes(16), blocked);
        let (_g2, mut gone_conn) = state
            .conns
            .add(rand_bytes(16), rand_bytes(32).try_into().unwrap());
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;
        let (_g3, mut live_conn) = state
            .conns
            .add(device_uuid, rand_bytes(32).try_into().unwrap());

        state.check_live_connections().await.expect("kontrola");
        assert_eq!(blocked_conn.try_recv(), Ok(403));
        assert_eq!(gone_conn.try_recv(), Ok(410));
        assert!(live_conn.try_recv().is_err(), "živé zařízení zůstává");
        assert_eq!(state.conns.snapshot().len(), 1);

        sqlx::query("DELETE FROM blocked_identities WHERE fingerprint = $1")
            .bind(blocked)
            .execute(&state.pool)
            .await
            .unwrap();
        cleanup(&state, &account_id, &delivery_address).await;
    }

    /// Registrace zablokované identity (vzniklá obejitím blokace) v DB je,
    /// přesto ji kontrola odpojí s 403: dorovnání by ji smazalo až v hodinové
    /// údržbě.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn kontrola_spojeni_odpoji_zablokovanou_registraci() {
        let state = test_state().await;
        let fingerprint: [u8; 32] = rand_bytes(32).try_into().unwrap();
        sqlx::query(
            "INSERT INTO blocked_identities (fingerprint, expires_on) VALUES ($1, current_date + 30)",
        )
        .bind(fingerprint)
        .execute(&state.pool)
        .await
        .unwrap();
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;
        let (_guard, mut kick) = state.conns.add(device_uuid, fingerprint);

        state.check_live_connections().await.expect("kontrola");
        assert_eq!(kick.try_recv(), Ok(403));
        assert!(state.conns.snapshot().is_empty());

        sqlx::query("DELETE FROM blocked_identities WHERE fingerprint = $1")
            .bind(fingerprint)
            .execute(&state.pool)
            .await
            .unwrap();
        cleanup(&state, &account_id, &delivery_address).await;
    }

    /// Výpadek DB nesmí odpojit všechna spojení: zařízení, které v DB není,
    /// by jinak dostalo 410.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn kontrola_spojeni_pri_chybe_db_nikoho_neodpoji() {
        let state = test_state().await;
        let (_guard, mut kick) = state.conns.add(rand_bytes(16), [9u8; 32]);
        state.pool.close().await;

        assert!(state.check_live_connections().await.is_err());
        assert!(kick.try_recv().is_err(), "žádný kick");
        assert_eq!(
            state.conns.snapshot().len(),
            1,
            "spojení zůstává v registru"
        );
    }
}
