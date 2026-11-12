//! Společné pomůcky DB testů: sdílená testovací DB s migracemi, vlastní
//! schémata pro testy, které sahají na celé tabulky, a testovací identita
//! se skutečnými klíči.

use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use axum::http::{HeaderMap, HeaderValue};
use base64::prelude::*;
use libsignal_protocol::KeyPair;
use rand::RngCore;
use sqlx::migrate::Migrator;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{PgConnection, PgPool};
use tokio::sync::{oneshot, OnceCell};

use crate::fingerprint::Fingerprint;
use crate::rest::{ApiError, PreKeyIn, RegisterIn};
use crate::outbox::OutboxReceiver;
use crate::state::{AppState, OnlineDevice};

/// Délka Kyber1024 veřejného klíče v serializaci libsignal.
const KYBER_PUBLIC_KEY_LEN: usize = 1569;
/// Verze migrace, kterou přinesla blokace identit.
const BLOCKING_MIGRATION: i64 = 5;

pub fn database_url() -> String {
    std::env::var("DATABASE_URL").unwrap_or_else(|_| crate::DEFAULT_DATABASE_URL.into())
}

pub fn rand_bytes(n: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; n];
    rand::rng().fill_bytes(&mut bytes);
    bytes
}

static SHARED_READY: OnceCell<()> = OnceCell::const_new();

/// Pool nad sdílenou testovací DB. Migrace a klíče CA jen jednou za proces:
/// souběžné testy by jinak závodily o první zápis do `relay_keys`.
pub async fn shared_pool(max_connections: u32) -> PgPool {
    let pool = PgPoolOptions::new()
        .max_connections(max_connections)
        .connect(&database_url())
        .await
        .expect("testovací DB");
    SHARED_READY
        .get_or_init(|| async {
            sqlx::migrate!("./migrations")
                .run(&pool)
                .await
                .expect("migrace");
            crate::certs::CertAuthority::init(&pool)
                .await
                .expect("klíče CA");
        })
        .await;
    pool
}

/// AppState nad sdílenou testovací DB.
pub async fn state() -> AppState {
    state_with_pool(shared_pool(4).await).await
}

pub async fn state_with_pool(pool: PgPool) -> AppState {
    let certs = crate::certs::CertAuthority::init(&pool)
        .await
        .expect("klíče CA");
    AppState::new(
        pool,
        certs,
        crate::attachments::Config::from_env(),
        Arc::new(crate::net::TrustedProxies::from_env()),
        crate::limits::Limits::from_env(),
    )
}

/// Právě ověřené spojení zařízení a konec jeho fronty, který by jinak
/// držel writer.
pub fn device(state: &AppState) -> (Arc<OnlineDevice>, OutboxReceiver) {
    let (outbox, queued) = crate::outbox::channel();
    (Arc::new(OnlineDevice::new(outbox, state.now_ms())), queued)
}

/// Vlastní schéma pro test, který čte nebo mění celé tabulky (údržba,
/// úklid, počty řádků) nebo samotné schéma. Ve sdíleném schématu by mu
/// souběžné testy měnily data pod rukama a on jim.
pub struct Isolated {
    pub pool: PgPool,
    schema: String,
}

impl Isolated {
    async fn empty() -> Self {
        let schema = format!("test_{}", hex::encode(rand_bytes(6)));
        let admin = PgPool::connect(&database_url())
            .await
            .expect("testovací DB");
        sqlx::query(&format!("CREATE SCHEMA {schema}"))
            .execute(&admin)
            .await
            .expect("schéma");
        admin.close().await;
        // Nekvalifikované tabulky včetně `_sqlx_migrations` pak žijí jen
        // v tomto schématu.
        let options = PgConnectOptions::from_str(&database_url())
            .expect("DATABASE_URL")
            .options([("search_path", schema.as_str())]);
        let pool = PgPoolOptions::new()
            .max_connections(4)
            .connect_with(options)
            .await
            .expect("testovací DB");
        Self { pool, schema }
    }

    /// Schéma se všemi migracemi.
    pub async fn new() -> Self {
        let isolated = Self::empty().await;
        sqlx::migrate!("./migrations")
            .run(&isolated.pool)
            .await
            .expect("migrace");
        isolated
    }

    /// Schéma, na kterém běžela jen starší verze relaye (migrace před
    /// blokací identit).
    pub async fn before_blocking() -> Self {
        let isolated = Self::empty().await;
        old_migrator()
            .await
            .run(&isolated.pool)
            .await
            .expect("migrace před 0005");
        isolated
    }

    pub async fn state(&self) -> AppState {
        state_with_pool(self.pool.clone()).await
    }

    /// Smaže schéma i s daty. Po panice testu zůstane v dočasné DB,
    /// kterou běh testů stejně zahodí.
    pub async fn remove(self) {
        self.pool.close().await;
        let admin = PgPool::connect(&database_url())
            .await
            .expect("testovací DB");
        sqlx::query(&format!("DROP SCHEMA {} CASCADE", self.schema))
            .execute(&admin)
            .await
            .expect("úklid schématu");
        admin.close().await;
    }
}

/// Migrátor starší verze relaye: dočasný adresář jen s migracemi před
/// blokací identit, tak jak je zná starý image.
pub async fn old_migrator() -> Migrator {
    let source = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/migrations"));
    let dir = std::env::temp_dir().join(format!("sepot-migrace-{}", hex::encode(rand_bytes(6))));
    std::fs::create_dir_all(&dir).expect("dočasný adresář");
    for entry in std::fs::read_dir(source).expect("adresář migrací") {
        let path = entry.expect("migrace").path();
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default();
        let version: i64 = name
            .split('_')
            .next()
            .and_then(|v| v.parse().ok())
            .unwrap_or(i64::MAX);
        if version < BLOCKING_MIGRATION {
            std::fs::copy(&path, dir.join(name)).expect("kopie migrace");
        }
    }
    let migrator = Migrator::new(dir.as_path()).await.expect("starý migrátor");
    std::fs::remove_dir_all(&dir).expect("úklid dočasného adresáře");
    migrator
}

/// Háčky v registraci pro testy souběhu; v produkčním buildu nejsou.
#[derive(Default)]
pub struct Hooks {
    /// Zpoždění mezi kontrolou blokace a zápisem identity: bez zámku
    /// otisku by se do něj vešla celá souběžná blokace.
    pub sleep_after_block_check: AtomicBool,
    pub before_takeover_lock: Gate,
    pub after_takeover_lock: Gate,
}

impl Hooks {
    pub async fn after_block_check(&self, conn: &mut PgConnection) -> sqlx::Result<()> {
        if self.sleep_after_block_check.load(Ordering::Relaxed) {
            sqlx::query("SELECT pg_sleep(0.05)").execute(conn).await?;
        }
        Ok(())
    }
}

type Armed = (oneshot::Sender<()>, oneshot::Receiver<()>);

/// Zarážka v kódu pod testem. Nastražená oznámí příchod a čeká, až ji test
/// pustí; nenastražená nic nedělá. Platí pro jeden průchod.
#[derive(Default)]
pub struct Gate(Mutex<Option<Armed>>);

impl Gate {
    /// Vrací (příchod, puštění).
    pub fn arm(&self) -> (oneshot::Receiver<()>, oneshot::Sender<()>) {
        let (arrived_tx, arrived_rx) = oneshot::channel();
        let (resume_tx, resume_rx) = oneshot::channel();
        *self.0.lock().expect("zarážka") = Some((arrived_tx, resume_rx));
        (arrived_rx, resume_tx)
    }

    pub async fn pass(&self) {
        let armed = self.0.lock().expect("zarážka").take();
        if let Some((arrived, resume)) = armed {
            // Test, který zarážku nastražil a pak zahodil, nečeká na nic.
            let _ = arrived.send(());
            let _ = resume.await;
        }
    }
}

/// Zachycený výstup tracingu: testy hlídají, co relay loguje a co ne.
#[derive(Clone, Default)]
pub struct LogCapture(Arc<Mutex<Vec<u8>>>);

impl LogCapture {
    /// Zachytává logy všech úrovní v tomto vlákně, dokud žije guard;
    /// `#[tokio::test]` pouští i spawnuté úlohy na témže vlákně.
    pub fn start(&self) -> tracing::subscriber::DefaultGuard {
        let subscriber = tracing_subscriber::fmt()
            .with_writer(self.clone())
            .with_max_level(tracing::Level::TRACE)
            .with_ansi(false)
            .finish();
        tracing::subscriber::set_default(subscriber)
    }

    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.0.lock().expect("log")).into_owned()
    }
}

impl std::io::Write for LogCapture {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().expect("log").extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for LogCapture {
    type Writer = Self;

    fn make_writer(&'a self) -> Self {
        self.clone()
    }
}

/// Identita se skutečným párem klíčů: podepisuje důkazy jako appka.
pub struct TestIdentity {
    pub keys: KeyPair,
    /// Serializovaný veřejný klíč (33 B, 0x05 na začátku).
    pub key: Vec<u8>,
    pub fingerprint: Fingerprint,
}

impl TestIdentity {
    pub fn new() -> Self {
        let keys = KeyPair::generate(&mut rand::rng());
        let key = keys.public_key.serialize().to_vec();
        let fingerprint = Fingerprint::of_identity_key(&key);
        Self {
            keys,
            key,
            fingerprint,
        }
    }

    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        self.keys
            .private_key
            .calculate_signature(message, &mut rand::rng())
            .expect("podpis")
            .to_vec()
    }

    /// Tělo POST /v1/register se zařízením 1 a třemi OTP klíči.
    pub fn register_body(&self, address: &[u8]) -> RegisterIn {
        let signed = KeyPair::generate(&mut rand::rng())
            .public_key
            .serialize()
            .to_vec();
        let kyber = rand_bytes(KYBER_PUBLIC_KEY_LEN);
        let prekey = |key_id: i32, public_key: &[u8], signature: Option<Vec<u8>>| PreKeyIn {
            key_id,
            public_key: BASE64_STANDARD.encode(public_key),
            signature: signature.map(|s| BASE64_STANDARD.encode(s)),
            is_last_resort: false,
        };
        RegisterIn {
            identity_key: BASE64_STANDARD.encode(&self.key),
            device_id: 1,
            registration_id: 1,
            delivery_address: BASE64_STANDARD.encode(address),
            signed_prekey: prekey(1, &signed, Some(self.sign(&signed))),
            kyber_prekey: PreKeyIn {
                is_last_resort: true,
                ..prekey(1, &kyber, Some(self.sign(&kyber)))
            },
            one_time_prekeys: (1..=3)
                .map(|key_id| {
                    let otp = KeyPair::generate(&mut rand::rng()).public_key.serialize();
                    prekey(key_id, &otp, None)
                })
                .collect(),
        }
    }

    /// Důkaz držení klíče pro POST /v1/register.
    pub fn proof_headers(&self) -> HeaderMap {
        self.proof(None)
    }

    /// Důkaz držení klíče, který kryje i tělo s daným otiskem.
    pub fn proof_headers_for_body(&self, body_sha256: &[u8; 32]) -> HeaderMap {
        self.proof(Some(body_sha256))
    }

    fn proof(&self, body_sha256: Option<&[u8; 32]>) -> HeaderMap {
        let ts = chrono::Utc::now().timestamp_millis();
        let (message, mut headers) = signed_message("POST /v1/register", ts, body_sha256);
        let value = format!("{ts}.{}", BASE64_STANDARD.encode(self.sign(message.as_bytes())));
        headers.insert(
            "x-sepot-identity-proof",
            HeaderValue::from_str(&value).expect("hlavička"),
        );
        headers
    }

    /// X-Sepot-Auth zařízení pro `method_path`.
    pub fn auth_headers(&self, device_uuid: &[u8], method_path: &str) -> HeaderMap {
        self.auth(device_uuid, method_path, None)
    }

    /// X-Sepot-Auth, který kryje i tělo s daným otiskem.
    pub fn auth_headers_for_body(
        &self,
        device_uuid: &[u8],
        method_path: &str,
        body_sha256: &[u8; 32],
    ) -> HeaderMap {
        self.auth(device_uuid, method_path, Some(body_sha256))
    }

    fn auth(
        &self,
        device_uuid: &[u8],
        method_path: &str,
        body_sha256: Option<&[u8; 32]>,
    ) -> HeaderMap {
        let ts = chrono::Utc::now().timestamp_millis();
        let (message, mut headers) = signed_message(method_path, ts, body_sha256);
        let value = format!(
            "{}.{ts}.{}",
            hex::encode(device_uuid),
            BASE64_STANDARD.encode(self.sign(message.as_bytes()))
        );
        headers.insert(
            "x-sepot-auth",
            HeaderValue::from_str(&value).expect("hlavička"),
        );
        headers
    }
}

/// Zpráva k podpisu, jak ji skládá klient, a hlavička s otiskem těla,
/// pokud ho podpis kryje.
fn signed_message(
    method_path: &str,
    ts: i64,
    body_sha256: Option<&[u8; 32]>,
) -> (String, HeaderMap) {
    let mut headers = HeaderMap::new();
    let message = match body_sha256 {
        Some(digest) => {
            let digest = hex::encode(digest);
            headers.insert(
                crate::rest::BODY_HASH_HEADER,
                HeaderValue::from_str(&digest).expect("hlavička"),
            );
            format!("{method_path}\n{ts}\n{digest}")
        }
        None => format!("{method_path}\n{ts}"),
    };
    (message, headers)
}

#[derive(Debug)]
pub struct Registered {
    pub account_id: Vec<u8>,
    pub device_uuid: Vec<u8>,
}

/// Registrace přes handler (bez HTTP vrstvy a limitů), jak ji pošle appka.
pub async fn register(
    state: &AppState,
    identity: &TestIdentity,
    address: &[u8],
) -> Result<Registered, ApiError> {
    let (_, axum::Json(out)) = crate::rest::register_device(
        state,
        &identity.proof_headers(),
        identity.key.clone(),
        identity.register_body(address),
        // Důkaz z `proof_headers` tělo nekryje, na otisku nezáleží.
        &[0; 32],
    )
    .await?;
    Ok(Registered {
        account_id: hex::decode(out.account_id).expect("hex"),
        device_uuid: hex::decode(out.device_uuid).expect("hex"),
    })
}

/// Obálka do fronty adresy, jak ji tam uloží relay.
pub async fn enqueue(pool: &PgPool, address: &[u8]) {
    sqlx::query(
        "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at)
         VALUES ($1, $2, $3, now() + interval '1 day')",
    )
    .bind(rand_bytes(16))
    .bind(address)
    .bind(rand_bytes(64))
    .execute(pool)
    .await
    .expect("obálka");
}

pub async fn count(pool: &PgPool, sql: &str, value: &[u8]) -> i64 {
    sqlx::query_scalar(sql)
        .bind(value)
        .fetch_one(pool)
        .await
        .expect("počet")
}

/// Úklid po testu ve sdílené DB: registrace, blokace, zajištění, vyřazené
/// adresy identity a fronta jejích adres.
pub async fn forget(pool: &PgPool, identity: &TestIdentity, addresses: &[&[u8]]) {
    let addresses: Vec<Vec<u8>> = addresses.iter().map(|address| address.to_vec()).collect();
    let hashes: Vec<[u8; 32]> = addresses
        .iter()
        .map(|address| crate::blocking::addr_hash(address))
        .collect();
    sqlx::query("DELETE FROM identities WHERE identity_key = $1")
        .bind(&identity.key)
        .execute(pool)
        .await
        .expect("úklid identity");
    sqlx::query("DELETE FROM message_queue WHERE dst_address = ANY($1)")
        .bind(&addresses)
        .execute(pool)
        .await
        .expect("úklid fronty");
    sqlx::query("DELETE FROM retired_addresses WHERE addr_hash = ANY($1)")
        .bind(&hashes)
        .execute(pool)
        .await
        .expect("úklid adres");
    for table in ["blocked_identities", "identity_holds"] {
        sqlx::query(&format!("DELETE FROM {table} WHERE fingerprint = $1"))
            .bind(identity.fingerprint.0)
            .execute(pool)
            .await
            .expect("úklid blokace a zajištění");
    }
}
