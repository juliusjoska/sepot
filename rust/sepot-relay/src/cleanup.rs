//! Úklid neaktivních registrací.
//!
//! Neaktivní je identita registrovaná déle než `INACTIVE_REGISTRATION_DAYS`,
//! jejíž žádné zařízení se za tu dobu nepřipojilo a žádné nemá živé
//! spojení. Maže se vždy celá registrace (identita, zařízení, předklíče,
//! push tokeny, nedoručená fronta), nikdy jen část zařízení; adresy se
//! vyřadí na rok se značkou vlastníka, takže vracející se uživatel si je
//! vezme zpět. Běží v hodinové údržbě jen se `SEPOT_INACTIVE_CLEANUP=1`.

use sqlx::PgPool;

use crate::blocking::{self, Registration, Removed, Retire};
use crate::fingerprint::Fingerprint;
use crate::state::AuthedConns;

/// Lhůta neaktivity. Konstanta, ne env: uvádějí ji podmínky služby a relay
/// ji zveřejňuje v `/v1/server-info`; překlep v konfiguraci nesmí text
/// a chování rozejít. Leží daleko za TTL fronty i za platností certifikátu
/// odesílatele, takže úklid nemaže nic, co by se ještě dalo doručit.
pub const INACTIVE_REGISTRATION_DAYS: i32 = 180;
/// Registrací v jedné transakci. Každá drží do commitu zámek otisku;
/// sdílená tabulka zámků Postgresu má výchozí místo pro 64 ×
/// max_connections, větší dávka by ji mohla vyčerpat.
const CLEANUP_BATCH: i64 = 500;
/// Dávek za jeden běh údržby: nejvýš 10 000 registrací za hodinu, první
/// zapnutí tak DB nezahltí.
const CLEANUP_MAX_BATCHES: i64 = 20;

/// $1 = lhůta ve dnech, $2 = device_uuid živých spojení, $3 = strop.
/// `last_seen_at` NULL = zařízení se nikdy nepřipojilo, rozhoduje vznik.
const CANDIDATES: &str = "SELECT i.account_id, i.identity_key FROM identities i
  WHERE i.registered_at < now() - make_interval(days => $1)
    AND NOT EXISTS (SELECT 1 FROM devices d
                     WHERE d.account_id = i.account_id
                       AND (coalesce(d.last_seen_at, d.created_at) >= now() - make_interval(days => $1)
                            OR d.device_uuid = ANY($2)))
  ORDER BY i.registered_at
  LIMIT $3";

/// Co úklid smazal, nebo by smazal.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Sweep {
    pub registrations: u64,
    pub devices: u64,
    pub push_tokens: u64,
    pub envelopes: u64,
}

impl Sweep {
    fn add(&mut self, removed: &Removed) {
        self.registrations += 1;
        self.devices += removed.device_uuids.len() as u64;
        self.push_tokens += removed.push_tokens;
        self.envelopes += removed.envelopes;
    }

    fn merge(&mut self, other: Sweep) {
        self.registrations += other.registrations;
        self.devices += other.devices;
        self.push_tokens += other.push_tokens;
        self.envelopes += other.envelopes;
    }
}

/// Jeden běh úklidu v hodinové údržbě.
pub async fn run(pool: &PgPool, conns: &AuthedConns) -> sqlx::Result<Sweep> {
    let mut total = Sweep::default();
    for _ in 0..CLEANUP_MAX_BATCHES {
        // Registr před každou dávkou: kdo se mezitím připojil, je chráněný.
        let live = conns.live_devices();
        let batch = run_batch(pool, &live, CLEANUP_BATCH).await?;
        total.merge(batch);
        if (batch.registrations as i64) < CLEANUP_BATCH {
            break;
        }
    }
    Ok(total)
}

/// Jedna dávka = jedna transakce. `SKIP LOCKED`: identitu, kterou právě
/// přebírá nové zařízení (`SELECT … FOR UPDATE` v registraci), úklid
/// přeskočí. Kandidáta, jehož otisk právě drží registrace, blokace,
/// smazání účtu nebo dorovnání, úklid přeskočí také: čekat na zámek
/// otisku se zamčenými řádky identit by vedlo k deadlocku a blokace by
/// mezitím přišla o registraci, kterou už našla. Přeskočené vezme další
/// běh.
async fn run_batch(pool: &PgPool, live: &[Vec<u8>], limit: i64) -> sqlx::Result<Sweep> {
    let mut tx = pool.begin().await?;
    let candidates: Vec<(Vec<u8>, Vec<u8>)> =
        sqlx::query_as(&format!("{CANDIDATES} FOR UPDATE OF i SKIP LOCKED"))
            .bind(INACTIVE_REGISTRATION_DAYS)
            .bind(live)
            .bind(limit)
            .fetch_all(&mut *tx)
            .await?;
    let mut sweep = Sweep::default();
    for (account_id, identity_key) in candidates {
        let fingerprint = Fingerprint::of_identity_key(&identity_key);
        if !blocking::try_lock(&mut tx, &fingerprint).await? {
            continue;
        }
        let registration = Registration {
            account_id,
            identity_key,
        };
        let removed =
            blocking::delete_registration(&mut tx, &registration, &fingerprint, Retire::Standard)
                .await?;
        sweep.add(&removed);
    }
    tx.commit().await?;
    Ok(sweep)
}

/// `uklid --nanecisto`: tentýž výběr bez zámků, sečtený jako skutečný běh
/// (včetně stropu dávek).
pub async fn dry_run(pool: &PgPool, live: &[Vec<u8>]) -> sqlx::Result<Sweep> {
    let (registrations, devices, push_tokens, envelopes): (i64, i64, i64, i64) =
        sqlx::query_as(&format!(
            "WITH c AS ({CANDIDATES}),
                  d AS (SELECT dv.device_uuid, dv.delivery_address
                          FROM devices dv JOIN c ON c.account_id = dv.account_id)
             SELECT (SELECT count(*) FROM c),
                    (SELECT count(*) FROM d),
                    (SELECT count(*) FROM push_tokens p JOIN d ON d.device_uuid = p.device_uuid),
                    (SELECT count(*) FROM message_queue q
                      WHERE q.dst_address IN (SELECT delivery_address FROM d))"
        ))
        .bind(INACTIVE_REGISTRATION_DAYS)
        .bind(live)
        .bind(CLEANUP_BATCH * CLEANUP_MAX_BATCHES)
        .fetch_one(pool)
        .await?;
    let count = |n: i64| u64::try_from(n).unwrap_or_default();
    Ok(Sweep {
        registrations: count(registrations),
        devices: count(devices),
        push_tokens: count(push_tokens),
        envelopes: count(envelopes),
    })
}

#[cfg(test)]
mod db_tests {
    //! Úklid nad reálným Postgresem, každý test ve vlastním schématu: úklid
    //! prochází celou tabulku identit.
    use std::sync::Arc;

    use super::*;
    use crate::testkit::{self, rand_bytes, Isolated, TestIdentity};

    /// Stáří neaktivní registrace a zařízení ve dnech.
    const OLD: i32 = INACTIVE_REGISTRATION_DAYS + 20;
    const RECENT: i32 = 1;

    struct Seeded {
        account_id: Vec<u8>,
        fingerprint: Fingerprint,
        device_uuids: Vec<Vec<u8>>,
        addresses: Vec<Vec<u8>>,
    }

    /// Registrace vložená SQL se zadaným stářím. Zařízení:
    /// (poslední připojení před dny, None = nikdy; vznik před dny).
    async fn seed(
        pool: &PgPool,
        registered_days_ago: i32,
        devices: &[(Option<i32>, i32)],
    ) -> Seeded {
        let account_id = rand_bytes(16);
        let mut identity_key = vec![0x05];
        identity_key.extend(rand_bytes(32));
        sqlx::query(
            "INSERT INTO identities (account_id, identity_key, registered_at)
             VALUES ($1, $2, now() - make_interval(days => $3))",
        )
        .bind(&account_id)
        .bind(&identity_key)
        .bind(registered_days_ago)
        .execute(pool)
        .await
        .unwrap();
        let mut seeded = Seeded {
            account_id: account_id.clone(),
            fingerprint: Fingerprint::of_identity_key(&identity_key),
            device_uuids: Vec::new(),
            addresses: Vec::new(),
        };
        for (device_id, (last_seen_days_ago, created_days_ago)) in (1..).zip(devices) {
            let (device_uuid, address) = (rand_bytes(16), rand_bytes(32));
            sqlx::query(
                "INSERT INTO devices (device_uuid, account_id, device_id, registration_id,
                                      delivery_address, last_seen_at, created_at)
                 VALUES ($1, $2, $3, 1, $4, now() - make_interval(days => $5),
                         now() - make_interval(days => $6))",
            )
            .bind(&device_uuid)
            .bind(&account_id)
            .bind(device_id)
            .bind(&address)
            .bind(*last_seen_days_ago)
            .bind(*created_days_ago)
            .execute(pool)
            .await
            .unwrap();
            seeded.device_uuids.push(device_uuid);
            seeded.addresses.push(address);
        }
        seeded
    }

    /// `count` neaktivních registrací s jedním zařízením najednou.
    async fn seed_many(pool: &PgPool, count: i32) {
        let salt = hex::encode(rand_bytes(8));
        sqlx::query(
            "INSERT INTO identities (account_id, identity_key, registered_at)
             SELECT decode(md5('a' || $1 || g), 'hex'),
                    '\\x05'::bytea || decode(md5('k' || $1 || g) || md5('l' || $1 || g), 'hex'),
                    now() - make_interval(days => $3)
               FROM generate_series(1, $2) AS g",
        )
        .bind(&salt)
        .bind(count)
        .bind(OLD)
        .execute(pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO devices (device_uuid, account_id, device_id, registration_id,
                                  delivery_address, last_seen_at, created_at)
             SELECT decode(md5('d' || $1 || g), 'hex'), decode(md5('a' || $1 || g), 'hex'), 1, 1,
                    decode(md5('e' || $1 || g) || md5('f' || $1 || g), 'hex'),
                    now() - make_interval(days => $3), now() - make_interval(days => $3)
               FROM generate_series(1, $2) AS g",
        )
        .bind(&salt)
        .bind(count)
        .bind(OLD)
        .execute(pool)
        .await
        .unwrap();
    }

    async fn push_token(pool: &PgPool, device_uuid: &[u8]) {
        sqlx::query(
            "INSERT INTO push_tokens (device_uuid, platform, token) VALUES ($1, 1, 'token')",
        )
        .bind(device_uuid)
        .execute(pool)
        .await
        .unwrap();
    }

    async fn registered(pool: &PgPool, account_id: &[u8]) -> bool {
        testkit::count(
            pool,
            "SELECT count(*) FROM identities WHERE account_id = $1",
            account_id,
        )
        .await
            == 1
    }

    async fn queued(pool: &PgPool, address: &[u8]) -> i64 {
        testkit::count(
            pool,
            "SELECT count(*) FROM message_queue WHERE dst_address = $1",
            address,
        )
        .await
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_maze_jen_cele_neaktivni_registrace() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;

        let inactive = seed(pool, OLD, &[(Some(OLD - 10), OLD), (None, OLD)]).await;
        let recent_device = seed(pool, OLD, &[(Some(OLD - 10), OLD), (Some(RECENT), OLD)]).await;
        let recent_registration = seed(pool, RECENT, &[(None, RECENT)]).await;
        let recent_never_connected = seed(pool, OLD, &[(None, RECENT)]).await;
        push_token(pool, &inactive.device_uuids[0]).await;
        for address in &inactive.addresses {
            testkit::enqueue(pool, address).await;
        }
        testkit::enqueue(pool, &recent_device.addresses[0]).await;
        crate::blocking::hold(pool, &inactive.fingerprint, 30, false)
            .await
            .unwrap()
            .expect("zajištění");

        // Víc kandidátů než jedna dávka: dávka jich vezme nejvýš CLEANUP_BATCH.
        let extra = 20;
        seed_many(pool, CLEANUP_BATCH as i32 + extra).await;
        let first = run_batch(pool, &[], CLEANUP_BATCH).await.expect("dávka");
        assert_eq!(first.registrations, CLEANUP_BATCH as u64);
        let rest = run(pool, &state.conns).await.expect("úklid");
        assert_eq!(
            first.registrations + rest.registrations,
            CLEANUP_BATCH as u64 + extra as u64 + 1
        );

        assert!(!registered(pool, &inactive.account_id).await);
        for kept in [
            &recent_device,
            &recent_registration,
            &recent_never_connected,
        ] {
            assert!(
                registered(pool, &kept.account_id).await,
                "mladší registrace zůstává"
            );
        }
        for address in &inactive.addresses {
            assert_eq!(queued(pool, address).await, 0, "fronta smazané registrace");
            let (year, tag): (bool, [u8; 32]) = sqlx::query_as(
                "SELECT expires_on = current_date + $2, owner_tag
                   FROM retired_addresses WHERE addr_hash = $1",
            )
            .bind(blocking::addr_hash(address))
            .bind(blocking::RETIRED_ADDRESS_DAYS)
            .fetch_one(pool)
            .await
            .expect("vyřazená adresa");
            assert!(year);
            assert_eq!(
                tag,
                blocking::owner_tag(&blocking::addr_hash(address), &inactive.fingerprint)
            );
        }
        assert_eq!(
            queued(pool, &recent_device.addresses[0]).await,
            1,
            "cizí fronta zůstává"
        );
        let holds = testkit::count(
            pool,
            "SELECT count(*) FROM identity_holds WHERE fingerprint = $1",
            &inactive.fingerprint.0,
        )
        .await;
        assert_eq!(holds, 1, "zajištěný snímek úklid přežije");
        isolated.remove().await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_setri_ziva_spojeni() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;
        let seeded = seed(pool, OLD, &[(Some(OLD - 10), OLD)]).await;

        let (guard, _kicked) = state
            .conns
            .add(seeded.device_uuids[0].clone(), seeded.fingerprint.0);
        assert_eq!(
            dry_run(pool, &state.conns.live_devices())
                .await
                .unwrap()
                .registrations,
            0
        );
        assert_eq!(run(pool, &state.conns).await.unwrap().registrations, 0);
        assert!(
            registered(pool, &seeded.account_id).await,
            "živé spojení chrání"
        );

        drop(guard);
        assert_eq!(run(pool, &state.conns).await.unwrap().registrations, 1);
        assert!(!registered(pool, &seeded.account_id).await);
        isolated.remove().await;
    }

    /// Převzetí s pravým důkazem, pak registrace zestárne jako po půl roce.
    async fn aged_registration(
        pool: &PgPool,
        state: &crate::state::AppState,
    ) -> (Arc<TestIdentity>, Vec<u8>) {
        let identity = Arc::new(TestIdentity::new());
        let registered = testkit::register(state, &identity, &rand_bytes(32))
            .await
            .expect("registrace");
        sqlx::query(
            "UPDATE identities SET registered_at = now() - make_interval(days => $2)
              WHERE account_id = $1",
        )
        .bind(&registered.account_id)
        .bind(OLD)
        .execute(pool)
        .await
        .unwrap();
        sqlx::query(
            "UPDATE devices SET last_seen_at = now() - make_interval(days => $2),
                                created_at = now() - make_interval(days => $2)
              WHERE account_id = $1",
        )
        .bind(&registered.account_id)
        .bind(OLD)
        .execute(pool)
        .await
        .unwrap();
        (identity, registered.account_id)
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_a_prevzeti_v_soubehu() {
        let isolated = Isolated::new().await;
        let state = Arc::new(isolated.state().await);
        let pool = &isolated.pool;
        let takeover = |identity: Arc<TestIdentity>| {
            let state = state.clone();
            tokio::spawn(async move { testkit::register(&state, &identity, &rand_bytes(32)).await })
        };

        // Převzetí drží zámek řádku identity: úklid ji přeskočí.
        let (identity, account_id) = aged_registration(pool, &state).await;
        let (arrived, resume) = state.test_hooks.after_takeover_lock.arm();
        let task = takeover(identity);
        arrived.await.expect("převzetí drží zámek");
        assert_eq!(run(pool, &state.conns).await.unwrap().registrations, 0);
        resume.send(()).expect("převzetí čeká");
        let taken = task.await.unwrap().expect("převzetí projde");
        assert_eq!(taken.account_id, account_id);

        // Převzetí ještě nezamklo řádek, drží ale zámek otisku: úklid
        // identitu přeskočí a převzetí projde.
        let (identity, account_id) = aged_registration(pool, &state).await;
        let (arrived, resume) = state.test_hooks.before_takeover_lock.arm();
        let task = takeover(identity);
        arrived.await.expect("převzetí před zámkem");
        assert_eq!(run(pool, &state.conns).await.unwrap().registrations, 0);
        assert!(registered(pool, &account_id).await);
        resume.send(()).expect("převzetí čeká");
        let taken = task.await.unwrap().expect("převzetí projde");
        assert_eq!(taken.account_id, account_id);
        isolated.remove().await;
    }

    /// Blokace (jiný proces) drží zámek otisku a registraci teprve smaže:
    /// úklid ji nesmí smazat pod ní, blokace by jinak nezapsala zařízení
    /// (410 místo 403) a zajištění by skončilo chybou.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_preskoci_identitu_pod_zamkem_otisku() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;
        let seeded = seed(pool, OLD, &[(Some(OLD - 10), OLD)]).await;

        let mut blocking_tx = pool.begin().await.unwrap();
        crate::blocking::lock(&mut blocking_tx, &seeded.fingerprint)
            .await
            .unwrap();
        assert_eq!(run(pool, &state.conns).await.unwrap().registrations, 0);
        assert!(registered(pool, &seeded.account_id).await);
        blocking_tx.rollback().await.unwrap();

        assert_eq!(run(pool, &state.conns).await.unwrap().registrations, 1);
        assert!(!registered(pool, &seeded.account_id).await);
        isolated.remove().await;
    }

    /// Úklid zamkne řádky identit a pak maže zařízení; smazání účtu
    /// a blokace téže identity běží souběžně. Všechny cesty musí zamykat
    /// ve stejném pořadí (identita, zařízení), jinak deadlock.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_smazani_uctu_a_blokace_se_nezaseknou() {
        /// Dost času, aby souběžná strana došla ke svému zámku.
        const LET_OTHER_LOCK: std::time::Duration = std::time::Duration::from_millis(400);
        let isolated = Isolated::new().await;
        let state = Arc::new(isolated.state().await);
        let pool = &isolated.pool;

        for blocks in [false, true] {
            let (identity, account_id) = aged_registration(pool, &state).await;
            // Úklid: řádek identity zamčený jako v `run_batch`.
            let mut cleanup_tx = pool.begin().await.unwrap();
            let locked: Option<Vec<u8>> = sqlx::query_scalar(
                "SELECT account_id FROM identities WHERE account_id = $1
                 FOR UPDATE SKIP LOCKED",
            )
            .bind(&account_id)
            .fetch_optional(&mut *cleanup_tx)
            .await
            .unwrap();
            assert!(locked.is_some());

            let other = {
                let (state, identity, account_id) =
                    (state.clone(), identity.clone(), account_id.clone());
                tokio::spawn(async move {
                    if blocks {
                        crate::blocking::block(
                            &state.pool,
                            &identity.fingerprint,
                            crate::blocking::BlockOptions::default(),
                        )
                        .await
                        .map(|_| ())
                        .map_err(|e| format!("{e:?}"))
                    } else {
                        state
                            .delete_identity(&account_id)
                            .await
                            .map(|_| ())
                            .map_err(|e| format!("{e:#}"))
                    }
                })
            };
            tokio::time::sleep(LET_OTHER_LOCK).await;

            let registration = Registration {
                account_id: account_id.clone(),
                identity_key: identity.key.clone(),
            };
            let cleanup = blocking::delete_registration(
                &mut cleanup_tx,
                &registration,
                &identity.fingerprint,
                Retire::Standard,
            )
            .await;
            let cleanup = match cleanup {
                Ok(_) => cleanup_tx.commit().await.map_err(|e| e.to_string()),
                Err(e) => Err(e.to_string()),
            };
            let other = other.await.unwrap();
            assert!(cleanup.is_ok(), "blokace {blocks}: úklid {cleanup:?}");
            assert!(other.is_ok(), "blokace {blocks}: druhá strana {other:?}");
            assert!(!registered(pool, &account_id).await);
        }
        isolated.remove().await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_vypnuty_nic_nemaze() {
        let isolated = Isolated::new().await;
        let mut state = isolated.state().await;
        let pool = &isolated.pool;
        let seeded = seed(pool, OLD, &[(Some(OLD - 10), OLD)]).await;

        state.limits.inactive_cleanup = false;
        state.clean_inactive().await;
        assert!(
            registered(pool, &seeded.account_id).await,
            "vypnutý úklid nemaže"
        );

        state.limits.inactive_cleanup = true;
        state.clean_inactive().await;
        assert!(!registered(pool, &seeded.account_id).await);
        isolated.remove().await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uklid_nanecisto_pocita_shodne() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;
        let first = seed(pool, OLD, &[(Some(OLD - 10), OLD), (None, OLD)]).await;
        let second = seed(pool, OLD, &[(Some(OLD - 5), OLD)]).await;
        let recent = seed(pool, OLD, &[(Some(RECENT), OLD)]).await;
        push_token(pool, &first.device_uuids[0]).await;
        push_token(pool, &second.device_uuids[0]).await;
        push_token(pool, &recent.device_uuids[0]).await;
        for address in [
            &first.addresses[0],
            &first.addresses[1],
            &first.addresses[1],
            &second.addresses[0],
        ] {
            testkit::enqueue(pool, address).await;
        }
        testkit::enqueue(pool, &recent.addresses[0]).await;

        let preview = dry_run(pool, &[]).await.expect("nanečisto");
        let swept = run(pool, &state.conns).await.expect("úklid");
        assert_eq!(preview, swept);
        assert_eq!(
            swept,
            Sweep {
                registrations: 2,
                devices: 3,
                push_tokens: 2,
                envelopes: 4,
            }
        );
        isolated.remove().await;
    }
}
