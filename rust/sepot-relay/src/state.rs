use chrono::{Duration, Utc};
use dashmap::DashMap;
use prost::Message;
use sepot_proto::v1;
use sepot_proto::MAX_ENVELOPE_PAYLOAD;
use sqlx::PgPool;
use tokio::sync::mpsc;

use crate::certs::CertAuthority;

/// TTL offline fronty.
pub const QUEUE_TTL_DAYS: i64 = 30;

pub struct AppState {
    pub pool: PgPool,
    /// delivery_address → kanál na živé WS spojení zařízení.
    pub online: DashMap<Vec<u8>, mpsc::Sender<v1::ServerFrame>>,
    /// klientská IP → počet souběžných WS spojení (anti-flood cap).
    /// Jen v paměti, nikam se neloguje ani neukládá.
    pub ws_conns: DashMap<std::net::IpAddr, u32>,
    pub certs: CertAuthority,
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
    pub fn new(pool: PgPool, certs: CertAuthority, attachments: crate::attachments::Config) -> Self {
        Self {
            pool,
            online: DashMap::new(),
            ws_conns: DashMap::new(),
            certs,
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

        if let Some(tx) = self.online.get(&dst) {
            let deliver = v1::ServerFrame {
                frame: Some(v1::server_frame::Frame::Deliver(env)),
            };
            if tx.send(deliver).await.is_ok() {
                return Ok(v1::receipt::Status::DeliveredOnline);
            }
        }
        // Offline (nebo online kanál selhal) → zkusit push budíček.
        self.wake(&dst).await;
        Ok(v1::receipt::Status::StoredOffline)
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

    /// Po AUTH: vyleje nedoručenou frontu zařízení (DELIVER stream).
    pub async fn flush_queue(
        &self,
        delivery_address: &[u8],
        tx: &mpsc::Sender<v1::ServerFrame>,
    ) -> anyhow::Result<usize> {
        let rows: Vec<(Vec<u8>,)> = sqlx::query_as(
            "SELECT envelope FROM message_queue
             WHERE dst_address = $1 AND expires_at > now()
             ORDER BY enqueued_at",
        )
        .bind(delivery_address)
        .fetch_all(&self.pool)
        .await?;

        let count = rows.len();
        for (encoded,) in rows {
            let env = v1::Envelope::decode(encoded.as_slice())?;
            let frame = v1::ServerFrame {
                frame: Some(v1::server_frame::Frame::Deliver(env)),
            };
            if tx.send(frame).await.is_err() {
                break;
            }
        }
        Ok(count)
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
        AppState::new(pool, certs, crate::attachments::Config::from_env())
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
}
