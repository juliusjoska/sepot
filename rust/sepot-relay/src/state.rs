use std::sync::Arc;

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

/// Strop celkové velikosti fronty na příjemce (SECURITY audit #3). Bez něj
/// autentizovaný útočník nasype neomezeně obálek (256 KiB × N) a při flushi
/// z toho vznikne OOM, na disku neomezený růst. Přetečení = FIFO zahození
/// nejstarších. 50 MiB ≈ 200 max obálek na příjemce.
const MAX_QUEUE_BYTES_PER_RECIPIENT: i64 = 50 * 1024 * 1024;

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
}

impl AppState {
    pub fn new(
        pool: PgPool,
        certs: CertAuthority,
        attachments: crate::attachments::Config,
        trusted_proxies: Arc<TrustedProxies>,
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
        }
    }

    /// Přijme obálku: validace → perzistentní fronta (dedup) → pokud je
    /// příjemce online, doručí hned. At-least-once: záznam z fronty maže
    /// až ACK příjemce, ne odeslání.
    pub async fn route_envelope(
        &self,
        env: v1::Envelope,
    ) -> anyhow::Result<v1::receipt::Status> {
        if env.dst_address.len() != 32
            || env.msg_uuid.len() != 16
            || env.payload.is_empty()
            || env.payload.len() > MAX_ENVELOPE_PAYLOAD
        {
            anyhow::bail!("neplatná obálka");
        }

        let dst = env.dst_address.clone();
        let encoded = env.encode_to_vec();
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
        self.trim_queue(&dst, MAX_QUEUE_BYTES_PER_RECIPIENT).await?;

        if let Some(dev) = self.online.get(&dst) {
            let deliver = v1::ServerFrame {
                frame: Some(v1::server_frame::Frame::Deliver(env)),
            };
            let fresh = dev.is_fresh(self.now_ms());
            let queued = dev.tx.send(deliver).await.is_ok();
            // ONLINE hlásíme jen u spojení, které prokazatelně dýchá. Do
            // zatuchlého se sice pošle taky (kdyby to byl jen tichý klient),
            // ale propadne se i na push — jinak by mrtvé spojení budíček
            // spolklo a příjemce se o zprávě nedozvěděl.
            if fresh && queued {
                return Ok(v1::receipt::Status::DeliveredOnline);
            }
        }
        // Offline, zatuchlé nebo selhalý kanál → zkusit push budíček.
        self.wake(&dst).await;
        Ok(v1::receipt::Status::StoredOffline)
    }

    /// FIFO strop fronty příjemce: nech nejnovější obálky do `cap_bytes`
    /// (běžný součet od nejnovější), starší přebytek zahoď. Vrací počet
    /// zahozených. Oddělené kvůli přímému testu bez vkládání 50 MiB.
    async fn trim_queue(&self, dst: &[u8], cap_bytes: i64) -> anyhow::Result<u64> {
        let res = sqlx::query(
            "DELETE FROM message_queue
             WHERE dst_address = $1 AND msg_uuid IN (
                 SELECT msg_uuid FROM (
                     SELECT msg_uuid,
                            sum(octet_length(envelope)) OVER (
                                ORDER BY enqueued_at DESC, msg_uuid DESC
                                ROWS UNBOUNDED PRECEDING) AS running
                     FROM message_queue WHERE dst_address = $1
                 ) s WHERE running > $2
             )",
        )
        .bind(dst)
        .bind(cap_bytes)
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
    ) -> anyhow::Result<()> {
        if platform == crate::push::PLATFORM_NONE || endpoint.is_none() {
            sqlx::query("DELETE FROM push_tokens WHERE device_uuid = $1")
                .bind(device_uuid)
                .execute(&self.pool)
                .await?;
            return Ok(());
        }
        sqlx::query(
            "INSERT INTO push_tokens (device_uuid, platform, token, updated_at)
             VALUES ($1, $2, $3, now())
             ON CONFLICT (device_uuid)
             DO UPDATE SET platform = excluded.platform,
                           token = excluded.token,
                           updated_at = now()",
        )
        .bind(device_uuid)
        .bind(platform)
        .bind(endpoint)
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
        AppState::new(pool, certs, crate::attachments::Config::from_env(), trusted)
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
            .register_push(&device_uuid, crate::push::PLATFORM_UNIFIEDPUSH, Some(&ep1))
            .await
            .unwrap();
        assert_eq!(
            state.push_target(&delivery_address).await,
            Some((crate::push::PLATFORM_UNIFIEDPUSH, ep1))
        );

        // upsert na WebPush (jiná platforma i token)
        let ep2 = b"https://push.example/w".to_vec();
        state
            .register_push(&device_uuid, crate::push::PLATFORM_WEBPUSH, Some(&ep2))
            .await
            .unwrap();
        assert_eq!(
            state.push_target(&delivery_address).await,
            Some((crate::push::PLATFORM_WEBPUSH, ep2))
        );

        // NONE → smaže (anonymní režim)
        state
            .register_push(&device_uuid, crate::push::PLATFORM_NONE, None)
            .await
            .unwrap();
        assert!(state.push_target(&delivery_address).await.is_none());

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
            )
            .await
            .unwrap();

        let env = v1::Envelope {
            dst_address: delivery_address.clone(),
            msg_uuid: rand_bytes(16),
            content_hint: 0,
            payload: vec![0xAB; 64],
        };
        let status = state.route_envelope(env).await.unwrap();
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
    async fn delete_identity_smaze_ucet_frontu_i_push() {
        let state = test_state().await;
        let (account_id, device_uuid, delivery_address) = seed_device(&state).await;

        // účet má push token i nedoručenou zprávu ve frontě
        state
            .register_push(
                &device_uuid,
                crate::push::PLATFORM_UNIFIEDPUSH,
                Some(b"https://localhost/up"),
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
            state.route_envelope(env).await.unwrap(),
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
            state.route_envelope(env2).await.unwrap(),
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
            state.route_envelope(env).await.unwrap(),
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

        let dropped = state.trim_queue(&dst, 250).await.unwrap();
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
}
