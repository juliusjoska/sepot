use std::sync::Arc;
use std::time::Instant;

use chrono::{DateTime, Duration, Utc};
use dashmap::DashMap;
use prost::Message;
use sepot_proto::v1;
use sepot_proto::MAX_ENVELOPE_PAYLOAD;
use sqlx::PgPool;
use tokio::sync::mpsc;

use crate::certs::CertAuthority;
use crate::net::TrustedProxies;

/// TTL offline fronty.
pub const QUEUE_TTL_DAYS: i64 = 30;

/// Největší zakódovaná obálka, kterou fronta přijme (CHECK v migraci 0001).
const MAX_STORED_ENVELOPE_BYTES: usize = 262_144;

/// Velikost dávky při vylévání fronty (SECURITY audit #3). Strop paměti =
/// FLUSH_BATCH × MAX_ENVELOPE_PAYLOAD (~16 MiB), ne celá fronta najednou.
const FLUSH_BATCH: i64 = 64;

/// Po kolika marných pokusech o doručení obálku zahodit.
///
/// Ztracený ACK je jednosměrka: klient obálku dešifruje (ratchet postoupí),
/// uloží a pošle ACK — když ten cestou zmizí (mrtvé spojení), relay obálku
/// drží dál, jenže druhý pokus o dešifrování už libsignal odmítne. Klient ji
/// tedy neACKuje a fronta se otravuje: tatáž obálka se posílá při každém
/// připojení až do TTL 30 dní a příjemce ji nikdy nedostane. Strop tomu dá
/// konec. Osm pokusů je velkoryse nad běžné „appka spadla před ACK".
const MAX_DELIVERY_ATTEMPTS: i16 = 8;

/// Jak dlouho po posledním rámci od klienta se spojení ještě považuje za
/// prokazatelně živé. Klient odpovídá na ping à 30 s (ws::PING_INTERVAL),
/// takže dva zmeškané cykly znamenají, že už nedýchá.
const FRESH_CONNECTION_MS: u64 = 70_000;

/// Běžný budíček na jeden cíl nejvýš jednou za tohle okno: třicet zpráv ve
/// skupině během výpadku sítě = jeden push, ne třicet (APNs i FCM nápor
/// tichých pushů škrtí, baterie taky).
const WAKE_MIN_INTERVAL: std::time::Duration = std::time::Duration::from_secs(5);
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

/// Okno kvóty odesílatele (`Limits::send_*_per_hour`).
const SEND_BUDGET_PERIOD: std::time::Duration = std::time::Duration::from_secs(3600);
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

/// Značky budíčků jednoho cíle (jen v paměti, nikam se neukládají).
#[derive(Default)]
pub struct WakeMarks {
    last_wake: Option<Instant>,
    call_wakes: std::collections::VecDeque<Instant>,
}

/// Připojené zařízení: kanál na jeho WS + kdy od něj naposled něco přišlo.
///
/// Samotný `tx` o životnosti spojení nic neříká — je to mpsc s bufferem, do
/// kterého zápis projde i u dávno mrtvého socketu. Právě proto se dřív vracelo
/// falešné DELIVERED_ONLINE a push budíček se vůbec nezkusil.
pub struct OnlineDevice {
    pub tx: mpsc::Sender<v1::ServerFrame>,
    /// ms od startu procesu; monotónní, aby s ním neházel NTP.
    last_frame_ms: std::sync::atomic::AtomicU64,
}

impl OnlineDevice {
    pub fn new(tx: mpsc::Sender<v1::ServerFrame>, now_ms: u64) -> Self {
        Self {
            tx,
            last_frame_ms: std::sync::atomic::AtomicU64::new(now_ms),
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
    /// téhož zařízení, které ještě nevypršelo.
    pub fn attach(&self, delivery_address: Vec<u8>, device: Arc<OnlineDevice>) {
        self.0.insert(delivery_address, device);
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

pub struct AppState {
    pub pool: PgPool,
    /// Kdy proces nastartoval — základ monotónních značek v [`OnlineDevice`].
    pub started: std::time::Instant,
    /// delivery_address → živé WS spojení zařízení.
    pub online: OnlineDevices,
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
    /// Kvóta příloh na účet: tempo za den a uloženo celkem (paměť).
    pub attachment_budget: crate::quota::Budgets,
    pub attachment_stored: crate::quota::StoredLedger,
    /// Volné místo na datovém filesystému (přílohy i DB).
    pub disk: Arc<crate::disk::DiskWatch>,
    /// delivery_address → značky budíčků (throttling pushů a hovorů).
    pub wake_marks: DashMap<Vec<u8>, WakeMarks>,
    /// delivery_address → (začátek okna, vydaných OTP) — drain ochrana.
    pub otp_issued: DashMap<Vec<u8>, (Instant, u32)>,
    /// Odkaz na zdroj a revize běžící binárky (AGPL §13, /v1/server-info).
    pub source_url: String,
    pub revision: String,
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
            limits,
            wake_marks: DashMap::new(),
            otp_issued: DashMap::new(),
            source_url: std::env::var("SEPOT_SOURCE_URL")
                .unwrap_or_else(|_| "https://github.com/juliusjoska/sepot".into()),
            revision: std::env::var("SEPOT_REVISION").unwrap_or_else(|_| "dev".into()),
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
                || !m.call_wakes.is_empty()
        });
        self.otp_issued
            .retain(|_, (start, _)| now.duration_since(*start) < OTP_ISSUE_WINDOW);
        self.send_budget.prune();
        self.attachment_budget.prune();
        self.attachment_stored.prune();
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

    /// Přijme obálku: validace → existence příjemce → kvóta odesílatele a
    /// místo na disku → perzistentní fronta (dedup) → pokud je příjemce
    /// online, doručí hned. At-least-once: záznam z fronty maže až ACK
    /// příjemce, ne odeslání. `sender_account` = ověřený účet spojení (jen
    /// klíč kvóty v paměti; do fronty se neukládá — sealed sender).
    pub async fn route_envelope(
        &self,
        env: v1::Envelope,
        sender_account: &[u8],
    ) -> Result<v1::receipt::Status, RouteError> {
        if env.dst_address.len() != 32
            || env.msg_uuid.len() != 16
            || env.payload.is_empty()
            || env.payload.len() > MAX_ENVELOPE_PAYLOAD
        {
            return Err(RouteError::Invalid);
        }

        if env.content_hint == v1::ContentHint::Ephemeral as i32 {
            return Ok(self.route_ephemeral(env).await);
        }

        let dst = env.dst_address.clone();
        // Online příjemce existuje; jinak jeden indexovaný dotaz (UNIQUE).
        if self.online.get(&dst).is_none() && !self.address_exists(&dst).await? {
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
        if !self
            .send_budget
            .try_take(sender_account, encoded.len() as u64)
        {
            return Err(RouteError::SenderQuota);
        }
        let expires = Utc::now() + Duration::days(QUEUE_TTL_DAYS);
        sqlx::query(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at)
             VALUES ($1, $2, $3, $4) ON CONFLICT (msg_uuid) DO NOTHING",
        )
        .bind(&env.msg_uuid)
        .bind(&dst)
        .bind(&encoded)
        .bind(expires)
        .execute(&self.pool)
        .await?;
        // FIFO strop na příjemce (audit #3). Nově vložená má nejmladší
        // enqueued_at → sama se nikdy nezahodí, padne jen starý přebytek.
        self.trim_queue(
            &dst,
            self.limits.queue_max_bytes_per_recipient,
            self.limits.queue_max_per_recipient,
        )
        .await
        .map_err(RouteError::Internal)?;

        let is_call = env.content_hint == v1::ContentHint::Call as i32;
        if let Some(dev) = self.online.get(&dst) {
            let deliver = v1::ServerFrame {
                frame: Some(v1::server_frame::Frame::Deliver(env)),
            };
            let fresh = dev.is_fresh(self.now_ms());
            // try_send, ne send().await: plný kanál znamená, že příjemce ze
            // socketu nečte. Čekat na něj by drželo odesílatelovo spojení
            // (a jeho paměť) rukojmím — nečtoucí příjemci by tak shodili
            // relay. Obálka je v DB, půjde budíček.
            let queued = dev.tx.try_send(deliver).is_ok();
            // ONLINE hlásíme jen u spojení, které prokazatelně dýchá. Do
            // zatuchlého se sice pošle taky (kdyby to byl jen tichý klient),
            // ale propadne se i na push — jinak by mrtvé spojení budíček
            // spolklo a příjemce se o zprávě nedozvěděl.
            if fresh && queued {
                return Ok(v1::receipt::Status::DeliveredOnline);
            }
        }
        // Offline, zatuchlé nebo plný kanál → zkusit push budíček.
        if is_call && self.allow_call_wake(&dst) {
            self.wake_call(&dst).await;
        } else if self.allow_wake(&dst) {
            self.wake(&dst).await;
        }
        Ok(v1::receipt::Status::StoredOffline)
    }

    async fn address_exists(&self, dst: &[u8]) -> Result<bool, sqlx::Error> {
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE delivery_address = $1)")
            .bind(dst)
            .fetch_one(&self.pool)
            .await
    }

    /// Jen živé doručení („píše…“): do fronty nic, push nic. Zatuchlé
    /// spojení se nepočítá — obálka by v mrtvém kanálu zmizela stejně
    /// a odesílatel se má dozvědět, že příjemce nikdo neposlouchá.
    async fn route_ephemeral(&self, env: v1::Envelope) -> v1::receipt::Status {
        let Some(dev) = self.online.get(&env.dst_address) else {
            return v1::receipt::Status::Dropped;
        };
        if !dev.is_fresh(self.now_ms()) {
            return v1::receipt::Status::Dropped;
        }
        let deliver = v1::ServerFrame {
            frame: Some(v1::server_frame::Frame::Deliver(env)),
        };
        if dev.tx.try_send(deliver).is_ok() {
            v1::receipt::Status::DeliveredOnline
        } else {
            v1::receipt::Status::Dropped
        }
    }

    /// FIFO strop fronty příjemce: nech nejnovější obálky do `cap_bytes`
    /// (běžný součet od nejnovější) a nejvýš `cap_count` kusů, starší
    /// přebytek zahoď. Strop počtu chrání před miliony drobných obálek, kde
    /// řádek v DB stojí víc než payload. Vrací počet zahozených. Oddělené
    /// kvůli přímému testu bez vkládání 50 MiB.
    async fn trim_queue(&self, dst: &[u8], cap_bytes: i64, cap_count: i64) -> anyhow::Result<u64> {
        let res = sqlx::query(
            "DELETE FROM message_queue
             WHERE dst_address = $1 AND msg_uuid IN (
                 SELECT msg_uuid FROM (
                     SELECT msg_uuid,
                            sum(octet_length(envelope)) OVER newest AS running,
                            row_number() OVER newest AS position
                     FROM message_queue WHERE dst_address = $1
                     WINDOW newest AS (ORDER BY enqueued_at DESC, msg_uuid DESC
                                       ROWS UNBOUNDED PRECEDING)
                 ) s WHERE running > $2 OR position > $3
             )",
        )
        .bind(dst)
        .bind(cap_bytes)
        .bind(cap_count)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected())
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
        tokio::spawn(async move {
            crate::push::send_wake(&client, platform, &token, fcm.as_deref(), apns.as_deref())
                .await;
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
        tokio::spawn(async move {
            crate::push::send_call_wake(&client, &target, fcm.as_deref(), apns.as_deref())
                .await;
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
        sqlx::query(
            "INSERT INTO push_tokens (device_uuid, platform, token, voip_token, updated_at)
             VALUES ($1, $2, $3, $4, now())
             ON CONFLICT (device_uuid)
             DO UPDATE SET platform = excluded.platform,
                           token = excluded.token,
                           voip_token = excluded.voip_token,
                           updated_at = now()",
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
    /// nemají (bearer capability) — dožijí TTL sweep.
    pub async fn delete_identity(&self, account_id: &[u8]) -> anyhow::Result<()> {
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            "DELETE FROM message_queue WHERE dst_address IN (
                 SELECT delivery_address FROM devices WHERE account_id = $1)",
        )
        .bind(account_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM identities WHERE account_id = $1")
            .bind(account_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    /// Po AUTH: vyleje nedoručenou frontu zařízení (DELIVER stream). Čte po
    /// dávkách keyset kurzorem přes (enqueued_at, msg_uuid) — paměť je
    /// omezená na FLUSH_BATCH obálek, ne celá fronta najednou (audit #3).
    /// Index idx_queue_dst(dst_address, enqueued_at) kurzor pokrývá.
    pub async fn flush_queue(
        &self,
        delivery_address: &[u8],
        tx: &mpsc::Sender<v1::ServerFrame>,
    ) -> anyhow::Result<usize> {
        // Obálky, které strop pokusů vyčerpaly, jsou neprůchodné (skoro vždy
        // ztracený ACK po úspěšném dešifrování) — zahodit dřív, než se znovu
        // pošlou. Maže se až tady, ne hned po inkrementu: poslední pokus
        // dostane šanci doběhnout do ACK.
        let dropped = sqlx::query(
            "DELETE FROM message_queue WHERE dst_address = $1 AND attempt_count >= $2",
        )
        .bind(delivery_address)
        .bind(MAX_DELIVERY_ATTEMPTS)
        .execute(&self.pool)
        .await?
        .rows_affected();
        if dropped > 0 {
            // Bez identifikátoru příjemce — jen že se fronta čistila.
            tracing::info!(dropped, "nedoručitelné obálky zahozeny (strop pokusů)");
        }

        let mut total = 0usize;
        // (enqueued_at, msg_uuid) poslední odeslané obálky = kurzor další dávky.
        let mut cursor: Option<(DateTime<Utc>, Vec<u8>)> = None;
        loop {
            let rows: Vec<(Vec<u8>, DateTime<Utc>, Vec<u8>)> = match &cursor {
                None => {
                    sqlx::query_as(
                        "SELECT envelope, enqueued_at, msg_uuid FROM message_queue
                         WHERE dst_address = $1 AND expires_at > now()
                           AND attempt_count < $2
                         ORDER BY enqueued_at, msg_uuid
                         LIMIT $3",
                    )
                    .bind(delivery_address)
                    .bind(MAX_DELIVERY_ATTEMPTS)
                    .bind(FLUSH_BATCH)
                    .fetch_all(&self.pool)
                    .await?
                }
                Some((ts, uuid)) => {
                    sqlx::query_as(
                        "SELECT envelope, enqueued_at, msg_uuid FROM message_queue
                         WHERE dst_address = $1 AND expires_at > now()
                           AND attempt_count < $2
                           AND (enqueued_at, msg_uuid) > ($3, $4)
                         ORDER BY enqueued_at, msg_uuid
                         LIMIT $5",
                    )
                    .bind(delivery_address)
                    .bind(MAX_DELIVERY_ATTEMPTS)
                    .bind(ts)
                    .bind(uuid)
                    .bind(FLUSH_BATCH)
                    .fetch_all(&self.pool)
                    .await?
                }
            };
            let batch_len = rows.len();
            if batch_len == 0 {
                break;
            }
            let last = rows
                .last()
                .map(|(_, ts, uuid)| (*ts, uuid.clone()))
                .expect("dávka není prázdná");
            let mut sent_uuids: Vec<Vec<u8>> = Vec::with_capacity(batch_len);
            for (encoded, _, uuid) in &rows {
                let env = v1::Envelope::decode(encoded.as_slice())?;
                let frame = v1::ServerFrame {
                    frame: Some(v1::server_frame::Frame::Deliver(env)),
                };
                if tx.send(frame).await.is_err() {
                    // Příjemce odpadl uprostřed dávky — započítat jen to, co
                    // reálně odešlo, ať pokus „zdarma" nekrátí strop.
                    self.bump_attempts(&sent_uuids).await;
                    return Ok(total);
                }
                sent_uuids.push(uuid.clone());
                total += 1;
            }
            self.bump_attempts(&sent_uuids).await;
            if (batch_len as i64) < FLUSH_BATCH {
                break; // poslední (neúplná) dávka
            }
            cursor = Some(last);
        }
        Ok(total)
    }

    /// Započítá pokus o doručení odeslaným obálkám. Selhání se jen zaloguje —
    /// obálky už jsou na drátě a shodit kvůli tomu flush by bylo horší než
    /// nepřesné počítadlo.
    async fn bump_attempts(&self, msg_uuids: &[Vec<u8>]) {
        if msg_uuids.is_empty() {
            return;
        }
        if let Err(e) = sqlx::query(
            "UPDATE message_queue SET attempt_count = attempt_count + 1
             WHERE msg_uuid = ANY($1)",
        )
        .bind(msg_uuids)
        .execute(&self.pool)
        .await
        {
            tracing::warn!("attempt_count se nepodařilo zvýšit: {e}");
        }
    }

    /// ACK příjemce → hard-delete z fronty (žádná retence po doručení).
    pub async fn ack(&self, delivery_address: &[u8], msg_uuid: &[u8]) -> anyhow::Result<()> {
        sqlx::query("DELETE FROM message_queue WHERE msg_uuid = $1 AND dst_address = $2")
            .bind(msg_uuid)
            .bind(delivery_address)
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}

#[cfg(test)]
mod online_tests {
    use super::*;

    fn spojeni() -> Arc<OnlineDevice> {
        let (tx, _rx) = mpsc::channel::<v1::ServerFrame>(1);
        Arc::new(OnlineDevice::new(tx, 0))
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

    async fn test_state() -> AppState {
        let url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://sepot:sepot_dev@127.0.0.1/sepot_relay".into());
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(2)
            .connect(&url)
            .await
            .expect("dev DB");
        let certs = crate::certs::CertAuthority::init(&pool).await.unwrap();
        let trusted = Arc::new(crate::net::TrustedProxies::from_env());
        AppState::new(
            pool,
            certs,
            crate::attachments::Config::from_env(),
            trusted,
            crate::limits::Limits::from_env(),
        )
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
        let status = state.route_envelope(env, SENDER).await.unwrap();
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
        let status = state.route_envelope(env, SENDER).await.unwrap();
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
        let status = state.route_envelope(env, SENDER).await.unwrap();
        assert_eq!(status, v1::receipt::Status::Dropped);

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

        let (tx, mut rx) = mpsc::channel::<v1::ServerFrame>(256);
        let count = state.flush_queue(&dst, &tx).await.unwrap();
        drop(tx);
        assert_eq!(count, n);

        let mut got = std::collections::HashSet::new();
        while let Some(frame) = rx.recv().await {
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

    /// Zapsat do mpsc bufferu jde i u dávno mrtvého spojení — DELIVERED_ONLINE
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
        let (tx, _rx) = mpsc::channel::<v1::ServerFrame>(64);
        let device = Arc::new(OnlineDevice::new(tx, 0));
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
            state.route_envelope(env, SENDER).await.unwrap(),
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
            state.route_envelope(env2, SENDER).await.unwrap(),
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

        let (tx_stare, _rx_stare) = mpsc::channel::<v1::ServerFrame>(64);
        let stare = Arc::new(OnlineDevice::new(tx_stare, state.now_ms()));
        state.online.attach(delivery_address.clone(), stare.clone());

        let (tx_nove, mut rx_nove) = mpsc::channel::<v1::ServerFrame>(64);
        let nove = Arc::new(OnlineDevice::new(tx_nove, state.now_ms()));
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
            state.route_envelope(env, SENDER).await.unwrap(),
            v1::receipt::Status::DeliveredOnline,
            "konec zombie spojení nesmí vyřadit nové spojení"
        );
        match rx_nove.try_recv().map(|f| f.frame) {
            Ok(Some(v1::server_frame::Frame::Deliver(env))) => assert_eq!(env.msg_uuid, msg_uuid),
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
            let (tx, rx) = mpsc::channel::<v1::ServerFrame>(16);
            assert_eq!(state.flush_queue(&dst, &tx).await.unwrap(), 1);
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
        // Rovnou na stropu = obálka, která se marně posílala MAX_DELIVERY_ATTEMPTS×.
        sqlx::query(
            "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at, attempt_count)
             VALUES ($1, $2, $3, now() + interval '30 days', $4)",
        )
        .bind(&msg_uuid)
        .bind(&dst)
        .bind(env.encode_to_vec())
        .bind(MAX_DELIVERY_ATTEMPTS)
        .execute(&state.pool)
        .await
        .unwrap();

        let (tx, rx) = mpsc::channel::<v1::ServerFrame>(16);
        assert_eq!(
            state.flush_queue(&dst, &tx).await.unwrap(),
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

    /// Audit #3: FIFO strop zahodí nejstarší přes limit, nejnovější nechá.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn trim_queue_fifo_zahodi_nejstarsi() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        // 5 obálek po 100 B, rostoucí enqueued_at. Strop 250 B → nejnovější
        // dvě (2×100 ≤ 250) zůstanou, tři nejstarší padnou.
        let mut uuids = Vec::new();
        for i in 0..5 {
            let msg_uuid = rand_bytes(16);
            uuids.push(msg_uuid.clone());
            sqlx::query(
                "INSERT INTO message_queue (msg_uuid, dst_address, envelope, enqueued_at, expires_at)
                 VALUES ($1, $2, $3, now() + (interval '1 second' * $4), now() + interval '30 days')",
            )
            .bind(&msg_uuid)
            .bind(&dst)
            .bind(vec![0u8; 100])
            .bind(i as i32)
            .execute(&state.pool)
            .await
            .unwrap();
        }

        let dropped = state.trim_queue(&dst, 250, 1000).await.unwrap();
        assert_eq!(dropped, 3);

        let remaining: Vec<Vec<u8>> = sqlx::query_scalar(
            "SELECT msg_uuid FROM message_queue WHERE dst_address = $1 ORDER BY enqueued_at",
        )
        .bind(&dst)
        .fetch_all(&state.pool)
        .await
        .unwrap();
        assert_eq!(remaining, vec![uuids[3].clone(), uuids[4].clone()]);

        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(&dst)
            .execute(&state.pool)
            .await
            .unwrap();
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
        let err = state.route_envelope(envelope(&dst, 64), SENDER).await.unwrap_err();
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
            state.route_envelope(envelope(&dst, 64), &sender).await.unwrap();
        }
        let err = state.route_envelope(envelope(&dst, 64), &sender).await.unwrap_err();
        assert!(matches!(err, RouteError::SenderQuota), "{err:?}");
        state
            .route_envelope(envelope(&dst, 64), &rand_bytes(16))
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
        let err = state.route_envelope(envelope(&dst, 64), SENDER).await.unwrap_err();
        assert!(matches!(err, RouteError::DiskFull), "{err:?}");
        assert_eq!(queued(&state, &dst).await, 0);
        cleanup(&state, &account_id, &dst).await;
    }

    /// Strop počtu obálek na příjemce drží nejnovější, i když bajty stačí.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn trim_queue_strop_poctu() {
        let state = test_state().await;
        let dst = rand_bytes(32);
        let mut uuids = Vec::new();
        for i in 0..5 {
            let msg_uuid = rand_bytes(16);
            uuids.push(msg_uuid.clone());
            sqlx::query(
                "INSERT INTO message_queue (msg_uuid, dst_address, envelope, enqueued_at, expires_at)
                 VALUES ($1, $2, $3, now() + (interval '1 second' * $4), now() + interval '30 days')",
            )
            .bind(&msg_uuid)
            .bind(&dst)
            .bind(vec![0u8; 10])
            .bind(i as i32)
            .execute(&state.pool)
            .await
            .unwrap();
        }
        assert_eq!(state.trim_queue(&dst, 1 << 30, 2).await.unwrap(), 3);
        let remaining: Vec<Vec<u8>> = sqlx::query_scalar(
            "SELECT msg_uuid FROM message_queue WHERE dst_address = $1 ORDER BY enqueued_at",
        )
        .bind(&dst)
        .fetch_all(&state.pool)
        .await
        .unwrap();
        assert_eq!(remaining, vec![uuids[3].clone(), uuids[4].clone()]);
        sqlx::query("DELETE FROM message_queue WHERE dst_address = $1")
            .bind(&dst)
            .execute(&state.pool)
            .await
            .unwrap();
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

    /// Obálka, která se zakódovaná nevejde do CHECK fronty, je 400 dřív, než
    /// ukrojí z kvóty odesílatele — ne 500 z databáze.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn obalka_nad_strop_fronty_je_neplatna() {
        let state = test_state().await;
        let (account_id, _device, dst) = seed_device(&state).await;
        let err = state
            .route_envelope(envelope(&dst, MAX_ENVELOPE_PAYLOAD), SENDER)
            .await
            .unwrap_err();
        assert!(matches!(err, RouteError::Invalid), "{err:?}");
        assert_eq!(queued(&state, &dst).await, 0);
        cleanup(&state, &account_id, &dst).await;
    }
}
