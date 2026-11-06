//! Blokace identit, zajištění údajů a vyřazené doručovací adresy.
//!
//! Jedna logika pro server (registrace, převzetí, smazání účtu, údržba)
//! i pro podpříkazy provozovatele (admin.rs). Změny jedné identity běží
//! pod zámkem jejího otisku (`pg_advisory_xact_lock`) jako prvním příkazem
//! transakce: v READ COMMITTED pak každý další příkaz vidí commit souběžné
//! transakce, která zámek držela předtím. Blokace i registrace téhož otisku
//! se tak nikdy nepotkají napůl.

use std::collections::HashSet;

use chrono::NaiveDate;
use futures_util::TryStreamExt;
use sha2::{Digest, Sha256};
use sqlx::{PgConnection, PgExecutor, PgPool};

use crate::fingerprint::Fingerprint;

/// Výchozí délka blokace. Dva roky stačí, aby nahlášená identita nemohla
/// hned zpátky; delší držení je nové rozhodnutí.
pub const BLOCK_DEFAULT_DAYS: i32 = 730;
/// `zablokovat --do` smí být nejvýš dnes + tolik dní.
pub const BLOCK_MAX_DAYS: i32 = 730;
/// Strop jednoho zajištění: uchování údajů na pokyn orgánu podle § 7b
/// odst. 4 trestního řádu trvá nejvýš 90 dní.
pub const HOLD_MAX_DAYS: i32 = 90;
/// Jak dlouho smí adresu zrušené registrace znovu zaregistrovat jen tatáž
/// identita. Kontakty mezitím dostanou novou adresu z profilu, nebo psaní
/// vzdají.
pub const RETIRED_ADDRESS_DAYS: i32 = 365;

pub const TEXT_BLOCKED: &str = "identita je na tomto serveru zablokovaná";
pub const TEXT_DEVICE_GONE: &str = "zařízení není registrované";

/// Doménové oddělení hashů: hash adresy se nesmí dát zaměnit s ničím jiným.
const ADDRESS_DOMAIN: &[u8] = b"sepot-adresa-v1";
const OWNER_DOMAIN: &[u8] = b"sepot-vlastnik-v1";

/// Jednosměrný hash doručovací adresy pro `retired_addresses`: relay pozná
/// vyřazenou adresu, ale z tabulky ji nevyčte.
pub fn addr_hash(address: &[u8]) -> [u8; 32] {
    Sha256::new()
        .chain_update(ADDRESS_DOMAIN)
        .chain_update([0u8])
        .chain_update(address)
        .finalize()
        .into()
}

/// Značka vlastníka vyřazené adresy. Bez otisku z ní nejde zjistit, komu
/// adresa patřila; s otiskem ji relay ověří, když se identita vrátí.
pub fn owner_tag(addr_hash: &[u8], fingerprint: &Fingerprint) -> [u8; 32] {
    Sha256::new()
        .chain_update(OWNER_DOMAIN)
        .chain_update([0u8])
        .chain_update(addr_hash)
        .chain_update(fingerprint.0)
        .finalize()
        .into()
}

fn days_after(day: NaiveDate, days: i32) -> NaiveDate {
    day + chrono::Duration::days(i64::from(days))
}

/// Dnešek podle DB: všechny lhůty (`current_date`) počítá Postgres, Rust
/// s nimi musí počítat ve stejném kalendáři.
async fn today(conn: &mut PgConnection) -> sqlx::Result<NaiveDate> {
    sqlx::query_scalar("SELECT current_date")
        .fetch_one(conn)
        .await
}

pub async fn lock(conn: &mut PgConnection, fingerprint: &Fingerprint) -> sqlx::Result<()> {
    sqlx::query("SELECT pg_advisory_xact_lock($1)")
        .bind(fingerprint.lock_key())
        .execute(conn)
        .await?;
    Ok(())
}

/// Zámek otisku bez čekání; false = drží ho jiná transakce.
pub async fn try_lock(conn: &mut PgConnection, fingerprint: &Fingerprint) -> sqlx::Result<bool> {
    sqlx::query_scalar("SELECT pg_try_advisory_xact_lock($1)")
        .bind(fingerprint.lock_key())
        .fetch_one(conn)
        .await
}

/// Blokace platí včetně dne `expires_on`; prošlou, ještě neuklizenou
/// blokaci už nic nevynucuje.
pub async fn is_blocked<'e, E: PgExecutor<'e>>(
    exec: E,
    fingerprint: &Fingerprint,
) -> sqlx::Result<bool> {
    sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM blocked_identities
                         WHERE fingerprint = $1 AND expires_on >= current_date)",
    )
    .bind(fingerprint.0)
    .fetch_one(exec)
    .await
}

/// Smazala zařízení blokace? Rozlišuje 403 od 410 u zařízení, které v DB
/// už není; `device_uuid` zná jen zařízení samo, takže to nikomu jinému
/// nic neprozradí.
pub async fn blocked_device<'e, E: PgExecutor<'e>>(
    exec: E,
    device_uuid: &[u8],
) -> sqlx::Result<bool> {
    sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM blocked_identities
                         WHERE $1 = ANY(device_uuids) AND expires_on >= current_date)",
    )
    .bind(device_uuid)
    .fetch_one(exec)
    .await
}

/// Které z otisků jsou zablokované.
pub async fn blocked_among<'e, E: PgExecutor<'e>>(
    exec: E,
    fingerprints: &[[u8; 32]],
) -> sqlx::Result<HashSet<[u8; 32]>> {
    if fingerprints.is_empty() {
        return Ok(HashSet::new());
    }
    let blocked: Vec<[u8; 32]> = sqlx::query_scalar(
        "SELECT fingerprint FROM blocked_identities
          WHERE fingerprint = ANY($1) AND expires_on >= current_date",
    )
    .bind(fingerprints)
    .fetch_all(exec)
    .await?;
    Ok(blocked.into_iter().collect())
}

pub struct Registration {
    pub account_id: Vec<u8>,
    pub identity_key: Vec<u8>,
}

pub async fn find_registration(
    conn: &mut PgConnection,
    fingerprint: &Fingerprint,
) -> sqlx::Result<Option<Registration>> {
    let wanted = HashSet::from([*fingerprint]);
    Ok(find_registrations(conn, &wanted)
        .await?
        .pop()
        .map(|(_, registration)| registration))
}

/// Registrace identit s danými otisky. Postgres BLAKE2b neumí, otisk se
/// počítá v Rustu při jednom průchodu tabulkou identit; průchod skončí,
/// jakmile jsou nalezeny všechny.
pub async fn find_registrations(
    conn: &mut PgConnection,
    wanted: &HashSet<Fingerprint>,
) -> sqlx::Result<Vec<(Fingerprint, Registration)>> {
    let mut found = Vec::new();
    if wanted.is_empty() {
        return Ok(found);
    }
    let mut rows =
        sqlx::query_as::<_, (Vec<u8>, Vec<u8>)>("SELECT account_id, identity_key FROM identities")
            .fetch(&mut *conn);
    while let Some((account_id, identity_key)) = rows.try_next().await? {
        let fingerprint = Fingerprint::of_identity_key(&identity_key);
        if wanted.contains(&fingerprint) {
            found.push((
                fingerprint,
                Registration {
                    account_id,
                    identity_key,
                },
            ));
            if found.len() == wanted.len() {
                break;
            }
        }
    }
    Ok(found)
}

/// Co se stane s adresami smazaných zařízení.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Retire {
    /// Smazání účtu, převzetí, úklid: adresa je rok vyhrazená téže identitě.
    Standard,
    /// Blokace: adresu drží blokace (`expires_on` NULL) až do jejího konce.
    HeldByBlock,
}

#[derive(Default)]
pub struct Removed {
    pub device_uuids: Vec<Vec<u8>>,
    /// Adresy smazaných zařízení, i ta, kterou si převzetí ponechalo.
    pub addresses: Vec<Vec<u8>>,
    /// Hashe adres, které upsert do `retired_addresses` skutečně zapsal.
    /// Adresu se značkou jiné identity nezapíše a tady není: tu drží
    /// její vlastník, ne tato identita.
    pub retired: Vec<[u8; 32]>,
    pub envelopes: u64,
    pub push_tokens: u64,
}

/// Debug jen s počty: UUID zařízení a adresy jsou identifikátory.
impl std::fmt::Debug for Removed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Removed")
            .field("device_uuids", &self.device_uuids.len())
            .field("addresses", &self.addresses.len())
            .field("retired", &self.retired.len())
            .field("envelopes", &self.envelopes)
            .field("push_tokens", &self.push_tokens)
            .finish()
    }
}

const RETIRE_STANDARD: &str = "INSERT INTO retired_addresses (addr_hash, owner_tag, expires_on)
     SELECT h, t, current_date + $3 FROM unnest($1::bytea[], $2::bytea[]) AS u(h, t)
     ON CONFLICT (addr_hash) DO NOTHING
     RETURNING addr_hash";

/// Cizí značku blokace nepřebírá: takovou adresu nedrží tato identita.
const RETIRE_HELD_BY_BLOCK: &str =
    "INSERT INTO retired_addresses (addr_hash, owner_tag, expires_on)
     SELECT h, t, NULL FROM unnest($1::bytea[], $2::bytea[]) AS u(h, t)
     ON CONFLICT (addr_hash) DO UPDATE SET expires_on = NULL
      WHERE retired_addresses.owner_tag = excluded.owner_tag
     RETURNING addr_hash";

/// Smaže všechna zařízení účtu (kaskáda odnese předklíče a push tokeny)
/// a jejich nedoručenou frontu. Nové zařízení po převzetí staré relace
/// nemá, frontu by nerozšifrovalo. Adresy kromě `keep_address` vyřadí.
pub async fn delete_devices(
    conn: &mut PgConnection,
    account_id: &[u8],
    fingerprint: &Fingerprint,
    retire: Retire,
    keep_address: Option<&[u8]>,
) -> sqlx::Result<Removed> {
    let devices: Vec<(Vec<u8>, Vec<u8>)> = sqlx::query_as(
        "SELECT device_uuid, delivery_address FROM devices WHERE account_id = $1 FOR UPDATE",
    )
    .bind(account_id)
    .fetch_all(&mut *conn)
    .await?;
    if devices.is_empty() {
        return Ok(Removed::default());
    }
    let (device_uuids, addresses): (Vec<Vec<u8>>, Vec<Vec<u8>>) = devices.into_iter().unzip();

    let envelopes = sqlx::query("DELETE FROM message_queue WHERE dst_address = ANY($1)")
        .bind(&addresses)
        .execute(&mut *conn)
        .await?
        .rows_affected();
    let push_tokens: i64 =
        sqlx::query_scalar("SELECT count(*) FROM push_tokens WHERE device_uuid = ANY($1)")
            .bind(&device_uuids)
            .fetch_one(&mut *conn)
            .await?;
    sqlx::query("DELETE FROM devices WHERE account_id = $1")
        .bind(account_id)
        .execute(&mut *conn)
        .await?;

    let hashes: Vec<[u8; 32]> = addresses
        .iter()
        .filter(|address| Some(address.as_slice()) != keep_address)
        .map(|address| addr_hash(address))
        .collect();
    let mut retired = Vec::new();
    if !hashes.is_empty() {
        let tags: Vec<[u8; 32]> = hashes
            .iter()
            .map(|hash| owner_tag(hash, fingerprint))
            .collect();
        retired = match retire {
            Retire::Standard => {
                sqlx::query_scalar(RETIRE_STANDARD)
                    .bind(&hashes)
                    .bind(&tags)
                    .bind(RETIRED_ADDRESS_DAYS)
                    .fetch_all(&mut *conn)
                    .await?
            }
            Retire::HeldByBlock => {
                sqlx::query_scalar(RETIRE_HELD_BY_BLOCK)
                    .bind(&hashes)
                    .bind(&tags)
                    .fetch_all(&mut *conn)
                    .await?
            }
        };
    }

    Ok(Removed {
        device_uuids,
        addresses,
        retired,
        envelopes,
        push_tokens: u64::try_from(push_tokens).unwrap_or_default(),
    })
}

/// Smaže registraci celou. Zamyká v pořadí identita, pak zařízení, jako
/// převzetí a dorovnání: opačné pořadí by se s nimi i s úklidem zaseklo
/// (deadlock).
pub async fn delete_registration(
    conn: &mut PgConnection,
    registration: &Registration,
    fingerprint: &Fingerprint,
    retire: Retire,
) -> sqlx::Result<Removed> {
    sqlx::query("SELECT 1 FROM identities WHERE account_id = $1 FOR UPDATE")
        .bind(&registration.account_id)
        .execute(&mut *conn)
        .await?;
    let removed = delete_devices(conn, &registration.account_id, fingerprint, retire, None).await?;
    sqlx::query("DELETE FROM identities WHERE account_id = $1")
        .bind(&registration.account_id)
        .execute(&mut *conn)
        .await?;
    Ok(removed)
}

#[derive(Debug)]
pub enum AddressError {
    /// Adresu má živé zařízení, nebo je vyřazená a patřila jiné identitě.
    Taken,
    Db(sqlx::Error),
}

impl From<sqlx::Error> for AddressError {
    fn from(e: sqlx::Error) -> Self {
        Self::Db(e)
    }
}

/// Smí identita s otiskem `fingerprint` použít doručovací adresu?
/// `freed_now` = adresy, které tatáž identita uvolnila v téže transakci
/// (převzetí stejnou adresou).
pub async fn check_address(
    conn: &mut PgConnection,
    address: &[u8],
    fingerprint: &Fingerprint,
    freed_now: &[Vec<u8>],
) -> Result<(), AddressError> {
    if freed_now.iter().any(|freed| freed == address) {
        return Ok(());
    }
    let live: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM devices WHERE delivery_address = $1)")
            .bind(address)
            .fetch_one(&mut *conn)
            .await?;
    if live {
        return Err(AddressError::Taken);
    }
    let hash = addr_hash(address);
    let retired: Option<([u8; 32], bool)> = sqlx::query_as(
        "SELECT owner_tag, coalesce(expires_on < current_date, false)
           FROM retired_addresses WHERE addr_hash = $1 FOR UPDATE",
    )
    .bind(hash)
    .fetch_optional(&mut *conn)
    .await?;
    match retired {
        None => Ok(()),
        // Vlastník se vrací, nebo výluka už skončila: adresa je zase živá
        // a řádek pryč, ať ho hodinová údržba později neuvolní cizímu.
        Some((tag, expired)) if expired || tag == owner_tag(&hash, fingerprint) => {
            sqlx::query("DELETE FROM retired_addresses WHERE addr_hash = $1")
                .bind(hash)
                .execute(&mut *conn)
                .await?;
            Ok(())
        }
        Some(_) => Err(AddressError::Taken),
    }
}

#[derive(Debug)]
pub struct RegistrationInfo {
    pub registered_on: NaiveDate,
    pub devices: i64,
    /// Den posledního připojení; `last_seen_at` se ukládá po hodinách.
    pub last_seen_on: Option<NaiveDate>,
}

pub async fn registration_info(
    conn: &mut PgConnection,
    account_id: &[u8],
) -> sqlx::Result<Option<RegistrationInfo>> {
    let row: Option<(NaiveDate, i64, Option<NaiveDate>)> = sqlx::query_as(
        "SELECT i.registered_at::date, count(d.device_uuid), max(d.last_seen_at)::date
           FROM identities i LEFT JOIN devices d ON d.account_id = i.account_id
          WHERE i.account_id = $1
          GROUP BY i.account_id",
    )
    .bind(account_id)
    .fetch_optional(conn)
    .await?;
    Ok(
        row.map(|(registered_on, devices, last_seen_on)| RegistrationInfo {
            registered_on,
            devices,
            last_seen_on,
        }),
    )
}

/// Snímek registrace (verze 1) pro zajištění a `vydat`: identita, zařízení,
/// push tokeny; bez předklíčů a bez fronty. `bytea` v hex, protože
/// `encode(…, 'base64')` v Postgresu láme řádky.
const SNAPSHOT_SQL: &str = r#"
SELECT jsonb_build_object(
           'v', 1,
           'account_id', encode(i.account_id, 'hex'),
           'identity_key', encode(i.identity_key, 'hex'),
           'registered_at', to_char(i.registered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
           'devices', coalesce(jsonb_agg(jsonb_build_object(
               'device_uuid', encode(d.device_uuid, 'hex'),
               'device_id', d.device_id,
               'registration_id', d.registration_id,
               'delivery_address', encode(d.delivery_address, 'hex'),
               'created_at', to_char(d.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'last_seen_at', to_char(d.last_seen_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'push_platform', p.platform,
               'push_token', encode(p.token, 'hex'),
               'voip_token', encode(p.voip_token, 'hex')
           ) ORDER BY d.device_id) FILTER (WHERE d.device_uuid IS NOT NULL), '[]'::jsonb)
       )::text
  FROM identities i
  LEFT JOIN devices d ON d.account_id = i.account_id
  LEFT JOIN push_tokens p ON p.device_uuid = d.device_uuid
 WHERE i.account_id = $1
 GROUP BY i.account_id
"#;

async fn snapshot(conn: &mut PgConnection, account_id: &[u8]) -> sqlx::Result<Option<String>> {
    sqlx::query_scalar(SNAPSHOT_SQL)
        .bind(account_id)
        .fetch_optional(conn)
        .await
}

/// Stav zajištění po běhu.
#[derive(Clone, Copy, Debug)]
pub struct HoldState {
    pub outcome: Outcome,
    /// Den, ze kterého je kopie registrace.
    pub held_on: NaiveDate,
    pub hold_until: NaiveDate,
}

/// Platné zajištění; prošlé, hodinovou údržbou ještě nesmazané už nic
/// nedrží.
async fn current_hold(
    conn: &mut PgConnection,
    fingerprint: &Fingerprint,
) -> sqlx::Result<Option<NaiveDate>> {
    sqlx::query_scalar(
        "SELECT hold_until FROM identity_holds WHERE fingerprint = $1 AND hold_until >= current_date",
    )
    .bind(fingerprint.0)
    .fetch_optional(conn)
    .await
}

/// Uloží snímek registrace, nebo jen posune konec existujícího zajištění:
/// kopie z prvního dne zůstává.
async fn store_hold(
    conn: &mut PgConnection,
    fingerprint: &Fingerprint,
    account_id: &[u8],
    today: NaiveDate,
    until: NaiveDate,
) -> sqlx::Result<HoldState> {
    // Nové zajištění nesmí převzít kopii prošlého.
    sqlx::query("DELETE FROM identity_holds WHERE fingerprint = $1 AND hold_until < current_date")
        .bind(fingerprint.0)
        .execute(&mut *conn)
        .await?;
    let previous = current_hold(conn, fingerprint).await?;
    // Registraci volající našel pod zámkem otisku v téže transakci.
    let snapshot = snapshot(conn, account_id)
        .await?
        .ok_or(sqlx::Error::RowNotFound)?;
    let (held_on, hold_until): (NaiveDate, NaiveDate) = sqlx::query_as(
        "INSERT INTO identity_holds (fingerprint, hold_until, snapshot)
         VALUES ($1, $2, $3::jsonb)
         ON CONFLICT (fingerprint) DO UPDATE
            SET hold_until = greatest(identity_holds.hold_until, excluded.hold_until)
         RETURNING held_on, hold_until",
    )
    .bind(fingerprint.0)
    .bind(until)
    .bind(snapshot)
    .fetch_one(conn)
    .await?;
    Ok(HoldState {
        outcome: outcome(previous, hold_until, today),
        held_on,
        hold_until,
    })
}

#[derive(Clone, Copy, Debug, Default)]
pub struct BlockOptions {
    /// Poslední den blokace; None = dnes + `BLOCK_DEFAULT_DAYS`.
    pub until: Option<NaiveDate>,
    /// Před smazáním zajistit kopii registrace (`identity_holds`).
    pub hold: bool,
    /// Nanečisto: všechno proběhne a transakce se vrátí, počty tak sedí
    /// přesně s tím, co by udělal skutečný běh.
    pub dry_run: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    /// Blokace ani zajištění dosud nebyly (nebo už skončily).
    New,
    /// Konec existující blokace nebo zajištění se posunul.
    Extended,
    /// Existující záznam končí později, nic se nezkracuje.
    Unchanged,
}

fn outcome(previous: Option<NaiveDate>, now: NaiveDate, today: NaiveDate) -> Outcome {
    match previous {
        Some(previous) if previous >= today && now > previous => Outcome::Extended,
        Some(previous) if previous >= today => Outcome::Unchanged,
        _ => Outcome::New,
    }
}

#[derive(Debug)]
pub struct BlockReport {
    pub registration: Option<RegistrationInfo>,
    pub outcome: Outcome,
    /// Konec blokace po běhu (u `Unchanged` ten dosavadní).
    pub blocked_until: NaiveDate,
    /// Zajištění, když se zajišťovalo (jen s nalezenou registrací).
    pub hold: Option<HoldState>,
    /// Konec dřívějšího zajištění, když se zajistit chtělo, registrace ale
    /// už není: kopie zůstává a jde prodloužit příkazem `zajistit`.
    pub earlier_hold_until: Option<NaiveDate>,
    pub removed: Removed,
    /// Dříve vyřazené adresy téže identity, které teď drží blokace.
    pub older_addresses: usize,
}

#[derive(Debug)]
pub enum BlockError {
    UntilOutOfRange { min: NaiveDate, max: NaiveDate },
    Db(sqlx::Error),
}

impl From<sqlx::Error> for BlockError {
    fn from(e: sqlx::Error) -> Self {
        Self::Db(e)
    }
}

const UPSERT_BLOCK: &str =
    "INSERT INTO blocked_identities (fingerprint, expires_on, device_uuids, address_hashes)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (fingerprint) DO UPDATE SET
        blocked_on = CASE WHEN blocked_identities.expires_on < current_date
                          THEN current_date ELSE blocked_identities.blocked_on END,
        expires_on = greatest(blocked_identities.expires_on, excluded.expires_on),
        device_uuids = ARRAY(SELECT DISTINCT unnest(blocked_identities.device_uuids
                                                    || excluded.device_uuids)),
        address_hashes = ARRAY(SELECT DISTINCT unnest(blocked_identities.address_hashes
                                                      || excluded.address_hashes))
     RETURNING expires_on";

/// `zablokovat`: zajistí (volitelně), smaže registraci, podrží její adresy
/// a zapíše blokaci. Funguje i pro identitu, která registrovaná není:
/// blokace pak zabrání nové registraci.
pub async fn block(
    pool: &PgPool,
    fingerprint: &Fingerprint,
    options: BlockOptions,
) -> Result<BlockReport, BlockError> {
    let mut tx = pool.begin().await?;
    lock(&mut tx, fingerprint).await?;
    let today = today(&mut tx).await?;
    let max = days_after(today, BLOCK_MAX_DAYS);
    let until = match options.until {
        None => days_after(today, BLOCK_DEFAULT_DAYS),
        Some(day) if day > today && day <= max => day,
        Some(_) => {
            return Err(BlockError::UntilOutOfRange {
                min: days_after(today, 1),
                max,
            })
        }
    };

    let mut info = None;
    let mut hold = None;
    let mut earlier_hold_until = None;
    let mut removed = Removed::default();
    if let Some(registration) = find_registration(&mut tx, fingerprint).await? {
        info = registration_info(&mut tx, &registration.account_id).await?;
        if options.hold {
            let until = days_after(today, HOLD_MAX_DAYS);
            hold = Some(
                store_hold(&mut tx, fingerprint, &registration.account_id, today, until).await?,
            );
        }
        removed =
            delete_registration(&mut tx, &registration, fingerprint, Retire::HeldByBlock).await?;
    } else if options.hold {
        earlier_hold_until = current_hold(&mut tx, fingerprint).await?;
    }
    let older = hold_older_addresses(&mut tx, fingerprint).await?;

    let previous: Option<NaiveDate> =
        sqlx::query_scalar("SELECT expires_on FROM blocked_identities WHERE fingerprint = $1")
            .bind(fingerprint.0)
            .fetch_optional(&mut *tx)
            .await?;
    let mut address_hashes = removed.retired.clone();
    address_hashes.extend_from_slice(&older);
    let blocked_until: NaiveDate = sqlx::query_scalar(UPSERT_BLOCK)
        .bind(fingerprint.0)
        .bind(until)
        .bind(&removed.device_uuids)
        .bind(&address_hashes)
        .fetch_one(&mut *tx)
        .await?;

    if options.dry_run {
        tx.rollback().await?;
    } else {
        tx.commit().await?;
    }
    Ok(BlockReport {
        registration: info,
        outcome: outcome(previous, blocked_until, today),
        blocked_until,
        hold,
        earlier_hold_until,
        removed,
        older_addresses: older.len(),
    })
}

/// Dříve vyřazené adresy téže identity (smazání účtu, převzetí) přejdou
/// pod blokaci. Značka vlastníka je jednosměrná, proto průchod v Rustu.
async fn hold_older_addresses(
    conn: &mut PgConnection,
    fingerprint: &Fingerprint,
) -> sqlx::Result<Vec<[u8; 32]>> {
    let mut mine = Vec::new();
    {
        let mut rows = sqlx::query_as::<_, ([u8; 32], [u8; 32])>(
            "SELECT addr_hash, owner_tag FROM retired_addresses WHERE expires_on IS NOT NULL",
        )
        .fetch(&mut *conn);
        while let Some((hash, tag)) = rows.try_next().await? {
            if tag == owner_tag(&hash, fingerprint) {
                mine.push(hash);
            }
        }
    }
    if !mine.is_empty() {
        sqlx::query("UPDATE retired_addresses SET expires_on = NULL WHERE addr_hash = ANY($1)")
            .bind(&mine)
            .execute(&mut *conn)
            .await?;
    }
    Ok(mine)
}

/// Konec blokace: adresy, které držela, jsou ještě rok vyhrazené téže
/// identitě. Jen řádky s její značkou: adresu se značkou jiné identity
/// drží její vlastní blokace nebo lhůta a ta tu nekončí.
async fn release_held_addresses(
    conn: &mut PgConnection,
    fingerprint: &Fingerprint,
    address_hashes: &[[u8; 32]],
) -> sqlx::Result<u64> {
    let tags: Vec<[u8; 32]> = address_hashes
        .iter()
        .map(|hash| owner_tag(hash, fingerprint))
        .collect();
    Ok(sqlx::query(
        "UPDATE retired_addresses r SET expires_on = current_date + $3
           FROM unnest($1::bytea[], $2::bytea[]) AS u(h, t)
          WHERE r.addr_hash = u.h AND r.owner_tag = u.t AND r.expires_on IS NULL",
    )
    .bind(address_hashes)
    .bind(&tags)
    .bind(RETIRED_ADDRESS_DAYS)
    .execute(conn)
    .await?
    .rows_affected())
}

#[derive(Debug)]
pub struct UnblockReport {
    pub blocked_on: NaiveDate,
    pub expires_on: NaiveDate,
    /// Adresy, které blokace držela; teď jsou rok vyhrazené téže identitě.
    pub addresses: u64,
    pub addresses_until: NaiveDate,
    /// Zajištění zůstává: může na něm viset příkaz orgánu.
    pub hold_until: Option<NaiveDate>,
}

/// `odblokovat`. None = blokace neexistuje.
pub async fn unblock(
    pool: &PgPool,
    fingerprint: &Fingerprint,
    dry_run: bool,
) -> sqlx::Result<Option<UnblockReport>> {
    let mut tx = pool.begin().await?;
    lock(&mut tx, fingerprint).await?;
    let today = today(&mut tx).await?;
    let row: Option<(NaiveDate, NaiveDate, Vec<[u8; 32]>)> = sqlx::query_as(
        "DELETE FROM blocked_identities WHERE fingerprint = $1
         RETURNING blocked_on, expires_on, address_hashes",
    )
    .bind(fingerprint.0)
    .fetch_optional(&mut *tx)
    .await?;
    let Some((blocked_on, expires_on, address_hashes)) = row else {
        return Ok(None);
    };
    let addresses = release_held_addresses(&mut tx, fingerprint, &address_hashes).await?;
    let hold_until = current_hold(&mut tx, fingerprint).await?;
    if dry_run {
        tx.rollback().await?;
    } else {
        tx.commit().await?;
    }
    Ok(Some(UnblockReport {
        blocked_on,
        expires_on,
        addresses,
        addresses_until: days_after(today, RETIRED_ADDRESS_DAYS),
        hold_until,
    }))
}

#[derive(Debug)]
pub struct HoldReport {
    pub registration: Option<RegistrationInfo>,
    pub hold: HoldState,
}

/// `zajistit`: jen snímek, bez blokace a bez mazání. Opakování posune
/// konec, kopie z prvního dne zůstává. None = není registrace ani
/// zajištění, není co zajistit.
pub async fn hold(
    pool: &PgPool,
    fingerprint: &Fingerprint,
    days: i32,
    dry_run: bool,
) -> sqlx::Result<Option<HoldReport>> {
    let mut tx = pool.begin().await?;
    lock(&mut tx, fingerprint).await?;
    let today = today(&mut tx).await?;
    let until = days_after(today, days);
    let registration = find_registration(&mut tx, fingerprint).await?;
    let previous = current_hold(&mut tx, fingerprint).await?;

    let report = match (&registration, previous) {
        (None, None) => return Ok(None),
        (Some(registration), _) => HoldReport {
            registration: registration_info(&mut tx, &registration.account_id).await?,
            hold: store_hold(&mut tx, fingerprint, &registration.account_id, today, until).await?,
        },
        // Registrace mezitím zmizela, kopie z dřívějška se jen prodlouží.
        (None, Some(_)) => {
            let (held_on, hold_until): (NaiveDate, NaiveDate) = sqlx::query_as(
                "UPDATE identity_holds SET hold_until = greatest(hold_until, $2)
                  WHERE fingerprint = $1 RETURNING held_on, hold_until",
            )
            .bind(fingerprint.0)
            .bind(until)
            .fetch_one(&mut *tx)
            .await?;
            HoldReport {
                registration: None,
                hold: HoldState {
                    outcome: outcome(previous, hold_until, today),
                    held_on,
                    hold_until,
                },
            }
        }
    };
    if dry_run {
        tx.rollback().await?;
    } else {
        tx.commit().await?;
    }
    Ok(Some(report))
}

/// `uvolnit`: konec zajištění před lhůtou. Vrací (den zajištění, konec),
/// None = zajištění neexistuje.
pub async fn release(
    pool: &PgPool,
    fingerprint: &Fingerprint,
    dry_run: bool,
) -> sqlx::Result<Option<(NaiveDate, NaiveDate)>> {
    let mut tx = pool.begin().await?;
    lock(&mut tx, fingerprint).await?;
    let released = sqlx::query_as(
        "DELETE FROM identity_holds WHERE fingerprint = $1 RETURNING held_on, hold_until",
    )
    .bind(fingerprint.0)
    .fetch_optional(&mut *tx)
    .await?;
    if dry_run {
        tx.rollback().await?;
    } else {
        tx.commit().await?;
    }
    Ok(released)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExportSource {
    Hold,
    Live,
}

impl ExportSource {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Hold => "zajisteni",
            Self::Live => "zive",
        }
    }
}

/// `vydat`: snímek ze zajištění, jinak z živých tabulek. Vrací JSON
/// (verze 1) jako text; None = identita není zajištěná ani registrovaná.
pub async fn export(
    pool: &PgPool,
    fingerprint: &Fingerprint,
) -> sqlx::Result<Option<(ExportSource, String)>> {
    let mut conn = pool.acquire().await?;
    let held: Option<String> = sqlx::query_scalar(
        "SELECT snapshot::text FROM identity_holds
          WHERE fingerprint = $1 AND hold_until >= current_date",
    )
    .bind(fingerprint.0)
    .fetch_optional(&mut *conn)
    .await?;
    if let Some(snapshot) = held {
        return Ok(Some((ExportSource::Hold, snapshot)));
    }
    let Some(registration) = find_registration(&mut conn, fingerprint).await? else {
        return Ok(None);
    };
    Ok(snapshot(&mut conn, &registration.account_id)
        .await?
        .map(|snapshot| (ExportSource::Live, snapshot)))
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Expired {
    pub blocks: u64,
    pub holds: u64,
    /// Adresy po skončené blokaci: ještě rok vyhrazené téže identitě.
    pub addresses_released: u64,
    /// Prošlé vyřazené adresy: od teď volné pro kohokoli.
    pub addresses_freed: u64,
}

impl Expired {
    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

/// Hodinová údržba: prošlá zajištění, blokace a vyřazené adresy. Každá
/// prošlá blokace pod vlastním zámkem: `zablokovat` ji mohl mezitím
/// prodloužit.
pub async fn expire(pool: &PgPool) -> sqlx::Result<Expired> {
    let mut expired = Expired {
        holds: sqlx::query("DELETE FROM identity_holds WHERE hold_until < current_date")
            .execute(pool)
            .await?
            .rows_affected(),
        ..Expired::default()
    };
    let blocks: Vec<[u8; 32]> = sqlx::query_scalar(
        "SELECT fingerprint FROM blocked_identities WHERE expires_on < current_date",
    )
    .fetch_all(pool)
    .await?;
    for fingerprint in blocks.into_iter().map(Fingerprint) {
        let mut tx = pool.begin().await?;
        lock(&mut tx, &fingerprint).await?;
        let address_hashes: Option<Vec<[u8; 32]>> = sqlx::query_scalar(
            "DELETE FROM blocked_identities WHERE fingerprint = $1 AND expires_on < current_date
             RETURNING address_hashes",
        )
        .bind(fingerprint.0)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(address_hashes) = address_hashes {
            expired.blocks += 1;
            expired.addresses_released +=
                release_held_addresses(&mut tx, &fingerprint, &address_hashes).await?;
        }
        tx.commit().await?;
    }
    expired.addresses_freed =
        sqlx::query("DELETE FROM retired_addresses WHERE expires_on < current_date")
            .execute(pool)
            .await?
            .rows_affected();
    Ok(expired)
}

#[derive(Default)]
pub struct Reconciled {
    pub identities: u64,
    /// Zařízení smazaných registrací: relay jejich spojení odpojí s 403.
    pub device_uuids: Vec<Vec<u8>>,
}

/// Debug jen s počty: UUID zařízení jsou identifikátory a do logů ani do
/// panic výpisu nepatří.
impl std::fmt::Debug for Reconciled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Reconciled")
            .field("identities", &self.identities)
            .field("device_uuids", &self.device_uuids.len())
            .finish()
    }
}

/// Hodinové dorovnání: registrace zablokované identity nemá existovat.
/// Vznikne jen obejitím, typicky během návratu na starší verzi serveru,
/// která blokace nevynucuje. Každý výskyt je pro provozovatele signál.
pub async fn reconcile(pool: &PgPool) -> sqlx::Result<Reconciled> {
    let mut reconciled = Reconciled::default();
    let blocked: Vec<[u8; 32]> = sqlx::query_scalar(
        "SELECT fingerprint FROM blocked_identities WHERE expires_on >= current_date",
    )
    .fetch_all(pool)
    .await?;
    // Prázdný seznam (běžný stav) = žádný průchod tabulkou identit.
    if blocked.is_empty() {
        return Ok(reconciled);
    }
    let wanted: HashSet<Fingerprint> = blocked.into_iter().map(Fingerprint).collect();
    let found = {
        let mut conn = pool.acquire().await?;
        find_registrations(&mut conn, &wanted).await?
    };
    for (fingerprint, registration) in found {
        let mut tx = pool.begin().await?;
        lock(&mut tx, &fingerprint).await?;
        // Znovu pod zámkem: blokace mohla skončit a registrace zmizet.
        if !is_blocked(&mut *tx, &fingerprint).await? {
            continue;
        }
        let account_id: Option<Vec<u8>> = sqlx::query_scalar(
            "SELECT account_id FROM identities WHERE identity_key = $1 FOR UPDATE",
        )
        .bind(&registration.identity_key)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(account_id) = account_id else {
            continue;
        };
        let registration = Registration {
            account_id,
            identity_key: registration.identity_key,
        };
        let removed =
            delete_registration(&mut tx, &registration, &fingerprint, Retire::HeldByBlock).await?;
        sqlx::query(
            "UPDATE blocked_identities
                SET device_uuids = ARRAY(SELECT DISTINCT unnest(device_uuids || $2::bytea[])),
                    address_hashes = ARRAY(SELECT DISTINCT unnest(address_hashes || $3::bytea[]))
              WHERE fingerprint = $1",
        )
        .bind(fingerprint.0)
        .bind(&removed.device_uuids)
        .bind(&removed.retired)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        reconciled.identities += 1;
        reconciled.device_uuids.extend(removed.device_uuids);
    }
    Ok(reconciled)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adresa_hash_a_znacka_kat() {
        let zero = [0u8; 32];
        let hash = addr_hash(&zero);
        assert_eq!(hex::encode(&hash[..8]), "86740f877e50728a");
        assert_ne!(addr_hash(&[1u8; 32]), hash, "jiná adresa, jiný hash");

        let first = Fingerprint([1u8; 32]);
        let second = Fingerprint([2u8; 32]);
        assert_eq!(owner_tag(&hash, &first), owner_tag(&hash, &first));
        assert_ne!(owner_tag(&hash, &first), owner_tag(&hash, &second));

        // Jiná doména dá jiný hash: značka vlastníka nesmí jít zaměnit
        // s hashem adresy ani s holým SHA-256.
        let plain: [u8; 32] = Sha256::digest(zero).into();
        assert_ne!(plain, hash);
        let mut tag_input = hash.to_vec();
        tag_input.extend_from_slice(&first.0);
        assert_ne!(addr_hash(&tag_input), owner_tag(&hash, &first));
    }
}

#[cfg(test)]
mod db_tests {
    //! Blokace, zajištění a údržba nad reálným Postgresem (testkit).
    //! #[ignore] — spouštět s DB: `cargo test -p sepot-relay -- --ignored`.
    use axum::http::StatusCode;
    use sqlx::migrate::MigrateError;
    use sqlx::Connection;

    use super::*;
    use crate::testkit::{self, rand_bytes, Isolated, TestIdentity};

    async fn db_today(pool: &PgPool) -> NaiveDate {
        sqlx::query_scalar("SELECT current_date")
            .fetch_one(pool)
            .await
            .unwrap()
    }

    async fn count(pool: &PgPool, sql: &str, value: &[u8]) -> i64 {
        testkit::count(pool, sql, value).await
    }

    fn hold_options() -> BlockOptions {
        BlockOptions {
            hold: true,
            ..BlockOptions::default()
        }
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_smaze_registraci_frontu_a_push() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let (identity, other) = (TestIdentity::new(), TestIdentity::new());
        let (address, other_address) = (rand_bytes(32), rand_bytes(32));
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        state
            .register_push(
                &registered.device_uuid,
                crate::push::PLATFORM_FCM,
                Some(b"fcm-token"),
                None,
            )
            .await
            .expect("push");
        testkit::enqueue(pool, &address).await;
        testkit::enqueue(pool, &address).await;
        testkit::register(&state, &other, &other_address)
            .await
            .expect("cizí registrace");
        testkit::enqueue(pool, &other_address).await;

        let report = block(pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        assert_eq!(report.outcome, Outcome::New);
        assert_eq!(report.removed.envelopes, 2);
        assert_eq!(report.removed.push_tokens, 1);

        let device = registered.device_uuid.as_slice();
        for (sql, value) in [
            (
                "SELECT count(*) FROM identities WHERE account_id = $1",
                registered.account_id.as_slice(),
            ),
            (
                "SELECT count(*) FROM devices WHERE device_uuid = $1",
                device,
            ),
            (
                "SELECT count(*) FROM signed_prekeys WHERE device_uuid = $1",
                device,
            ),
            (
                "SELECT count(*) FROM kyber_prekeys WHERE device_uuid = $1",
                device,
            ),
            (
                "SELECT count(*) FROM one_time_prekeys WHERE device_uuid = $1",
                device,
            ),
            (
                "SELECT count(*) FROM push_tokens WHERE device_uuid = $1",
                device,
            ),
            (
                "SELECT count(*) FROM message_queue WHERE dst_address = $1",
                address.as_slice(),
            ),
        ] {
            assert_eq!(count(pool, sql, value).await, 0, "{sql}");
        }
        let other_left = count(
            pool,
            "SELECT count(*) FROM identities WHERE identity_key = $1",
            &other.key,
        )
        .await;
        assert_eq!(other_left, 1, "cizí identita zůstává");
        let other_queue = count(
            pool,
            "SELECT count(*) FROM message_queue WHERE dst_address = $1",
            &other_address,
        )
        .await;
        assert_eq!(other_queue, 1, "cizí fronta zůstává");

        let hash = addr_hash(&address);
        let (devices, hashes): (Vec<Vec<u8>>, Vec<[u8; 32]>) = sqlx::query_as(
            "SELECT device_uuids, address_hashes FROM blocked_identities WHERE fingerprint = $1",
        )
        .bind(identity.fingerprint.0)
        .fetch_one(pool)
        .await
        .expect("řádek blokace");
        assert_eq!(devices, vec![registered.device_uuid.clone()]);
        assert_eq!(hashes, vec![hash]);
        let (tag, expires_on): ([u8; 32], Option<NaiveDate>) = sqlx::query_as(
            "SELECT owner_tag, expires_on FROM retired_addresses WHERE addr_hash = $1",
        )
        .bind(hash)
        .fetch_one(pool)
        .await
        .expect("vyřazená adresa");
        assert_eq!(tag, owner_tag(&hash, &identity.fingerprint));
        assert_eq!(expires_on, None, "adresu drží blokace");

        testkit::forget(pool, &identity, &[&address]).await;
        testkit::forget(pool, &other, &[&other_address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_se_zajistenim_ulozi_snimek() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        state
            .register_push(
                &registered.device_uuid,
                crate::push::PLATFORM_APNS,
                Some(b"apns-token"),
                Some(b"voip-token"),
            )
            .await
            .expect("push");

        let report = block(pool, &identity.fingerprint, hold_options())
            .await
            .expect("blokace");
        let today = db_today(pool).await;
        let hold = report.hold.expect("zajištění");
        assert_eq!(hold.outcome, Outcome::New);
        assert_eq!(hold.held_on, today);
        assert_eq!(hold.hold_until, days_after(today, HOLD_MAX_DAYS));

        let (snapshot, hold_until): (String, NaiveDate) = sqlx::query_as(
            "SELECT snapshot::text, hold_until FROM identity_holds WHERE fingerprint = $1",
        )
        .bind(identity.fingerprint.0)
        .fetch_one(pool)
        .await
        .expect("snímek");
        assert_eq!(hold_until, days_after(today, HOLD_MAX_DAYS));
        let snapshot: serde_json::Value = serde_json::from_str(&snapshot).unwrap();
        assert_eq!(snapshot["v"], 1);
        assert_eq!(snapshot["identity_key"], hex::encode(&identity.key));
        assert_eq!(snapshot["account_id"], hex::encode(&registered.account_id));
        let devices = snapshot["devices"].as_array().expect("zařízení");
        assert_eq!(devices.len(), 1);
        assert_eq!(
            devices[0]["device_uuid"],
            hex::encode(&registered.device_uuid)
        );
        assert_eq!(devices[0]["delivery_address"], hex::encode(&address));
        assert_eq!(devices[0]["push_token"], hex::encode(b"apns-token"));
        assert_eq!(devices[0]["voip_token"], hex::encode(b"voip-token"));

        testkit::forget(pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_neznamy_otisk() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();

        let report = block(pool, &identity.fingerprint, hold_options())
            .await
            .expect("blokace");
        assert_eq!(report.outcome, Outcome::New);
        assert!(report.registration.is_none());
        assert!(report.hold.is_none(), "bez registrace není co zajistit");
        let fingerprint = identity.fingerprint.0;
        let holds = count(
            pool,
            "SELECT count(*) FROM identity_holds WHERE fingerprint = $1",
            &fingerprint,
        )
        .await;
        assert_eq!(holds, 0);

        let address = rand_bytes(32);
        let error = testkit::register(&state, &identity, &address)
            .await
            .expect_err("pozdější registrace");
        assert_eq!(error.status, StatusCode::FORBIDDEN);
        testkit::forget(pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_podruhe_jen_prodlouzi() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let fingerprint = identity.fingerprint;
        let address = rand_bytes(32);
        testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        let today = db_today(pool).await;

        let first_hold = hold(pool, &fingerprint, 10, false)
            .await
            .unwrap()
            .expect("zajištění");
        assert_eq!(first_hold.hold.outcome, Outcome::New);

        let options = |until: Option<NaiveDate>, hold: bool| BlockOptions {
            until,
            hold,
            dry_run: false,
        };
        let first = block(
            pool,
            &fingerprint,
            options(Some(days_after(today, 20)), true),
        )
        .await
        .expect("blokace");
        assert_eq!(first.outcome, Outcome::New);
        assert_eq!(first.blocked_until, days_after(today, 20));
        let held = first.hold.expect("zajištění s registrací");
        assert_eq!(held.outcome, Outcome::Extended);
        assert_eq!(held.held_on, today, "kopie z prvního dne");
        assert_eq!(held.hold_until, days_after(today, HOLD_MAX_DAYS));

        let longer = block(pool, &fingerprint, options(None, false))
            .await
            .expect("prodloužení");
        assert_eq!(longer.outcome, Outcome::Extended);
        assert_eq!(longer.blocked_until, days_after(today, BLOCK_DEFAULT_DAYS));

        let shorter = block(
            pool,
            &fingerprint,
            options(Some(days_after(today, 5)), false),
        )
        .await
        .expect("kratší konec");
        assert_eq!(shorter.outcome, Outcome::Unchanged);
        assert_eq!(shorter.blocked_until, days_after(today, BLOCK_DEFAULT_DAYS));

        let shorter_hold = hold(pool, &fingerprint, 5, false)
            .await
            .unwrap()
            .expect("zajištění trvá");
        assert_eq!(shorter_hold.hold.outcome, Outcome::Unchanged);
        assert_eq!(
            shorter_hold.hold.hold_until,
            days_after(today, HOLD_MAX_DAYS)
        );

        let (expires_on, hold_until): (NaiveDate, NaiveDate) = sqlx::query_as(
            "SELECT b.expires_on, h.hold_until FROM blocked_identities b
               JOIN identity_holds h USING (fingerprint) WHERE fingerprint = $1",
        )
        .bind(fingerprint.0)
        .fetch_one(pool)
        .await
        .unwrap();
        assert_eq!(expires_on, days_after(today, BLOCK_DEFAULT_DAYS));
        assert_eq!(hold_until, days_after(today, HOLD_MAX_DAYS));

        let out_of_range = block(pool, &fingerprint, options(Some(today), false)).await;
        assert!(
            matches!(out_of_range, Err(BlockError::UntilOutOfRange { .. })),
            "--do dnes nejde"
        );
        testkit::forget(pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovat_drzi_starsi_vyrazene_adresy() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let (older, current) = (rand_bytes(32), rand_bytes(32));
        let first = testkit::register(&state, &identity, &older)
            .await
            .expect("registrace");
        state
            .delete_identity(&first.account_id)
            .await
            .expect("smazání účtu");
        testkit::register(&state, &identity, &current)
            .await
            .expect("nová registrace");

        let report = block(pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        assert_eq!(report.older_addresses, 1);

        let older_hash = addr_hash(&older);
        let expires_on: Option<NaiveDate> =
            sqlx::query_scalar("SELECT expires_on FROM retired_addresses WHERE addr_hash = $1")
                .bind(older_hash)
                .fetch_one(pool)
                .await
                .unwrap();
        assert_eq!(expires_on, None, "starší adresu teď drží blokace");
        let mut hashes: Vec<[u8; 32]> = sqlx::query_scalar(
            "SELECT address_hashes FROM blocked_identities WHERE fingerprint = $1",
        )
        .bind(identity.fingerprint.0)
        .fetch_one(pool)
        .await
        .unwrap();
        hashes.sort();
        let mut expected = vec![older_hash, addr_hash(&current)];
        expected.sort();
        assert_eq!(hashes, expected);
        testkit::forget(pool, &identity, &[&older, &current]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn odblokovat_uvolni_adresy_a_registraci() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        block(pool, &identity.fingerprint, hold_options())
            .await
            .expect("blokace");
        let today = db_today(pool).await;

        let report = unblock(pool, &identity.fingerprint, false)
            .await
            .unwrap()
            .expect("blokace existovala");
        assert_eq!(report.addresses, 1);
        assert_eq!(
            report.addresses_until,
            days_after(today, RETIRED_ADDRESS_DAYS)
        );
        assert_eq!(report.hold_until, Some(days_after(today, HOLD_MAX_DAYS)));
        let expires_on: Option<NaiveDate> =
            sqlx::query_scalar("SELECT expires_on FROM retired_addresses WHERE addr_hash = $1")
                .bind(addr_hash(&address))
                .fetch_one(pool)
                .await
                .unwrap();
        assert_eq!(expires_on, Some(days_after(today, RETIRED_ADDRESS_DAYS)));

        testkit::register(&state, &identity, &address)
            .await
            .expect("registrace se starou adresou");
        let retired = count(
            pool,
            "SELECT count(*) FROM retired_addresses WHERE addr_hash = $1",
            &addr_hash(&address),
        )
        .await;
        assert_eq!(retired, 0);
        let fingerprint = identity.fingerprint.0;
        let holds = count(
            pool,
            "SELECT count(*) FROM identity_holds WHERE fingerprint = $1",
            &fingerprint,
        )
        .await;
        assert_eq!(holds, 1, "zajištění zůstává");
        testkit::forget(pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zajistit_bez_blokace_nemaze() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        let today = db_today(pool).await;

        let report = hold(pool, &identity.fingerprint, 30, false)
            .await
            .unwrap()
            .expect("zajištění");
        assert_eq!(report.hold.outcome, Outcome::New);
        assert_eq!(report.hold.hold_until, days_after(today, 30));
        assert!(report.registration.is_some());

        let fingerprint = identity.fingerprint.0;
        for (sql, value, expected) in [
            (
                "SELECT count(*) FROM devices WHERE device_uuid = $1",
                registered.device_uuid.as_slice(),
                1,
            ),
            (
                "SELECT count(*) FROM blocked_identities WHERE fingerprint = $1",
                fingerprint.as_slice(),
                0,
            ),
            (
                "SELECT count(*) FROM identity_holds WHERE fingerprint = $1",
                fingerprint.as_slice(),
                1,
            ),
        ] {
            assert_eq!(count(pool, sql, value).await, expected, "{sql}");
        }
        testkit::forget(pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn uvolnit_smaze_snimek() {
        let state = testkit::state().await;
        let pool = &state.pool;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        hold(pool, &identity.fingerprint, HOLD_MAX_DAYS, false)
            .await
            .unwrap()
            .expect("zajištění");

        let (_, hold_until) = release(pool, &identity.fingerprint, false)
            .await
            .unwrap()
            .expect("zajištění existovalo");
        assert_eq!(hold_until, days_after(db_today(pool).await, HOLD_MAX_DAYS));
        let fingerprint = identity.fingerprint.0;
        let holds = count(
            pool,
            "SELECT count(*) FROM identity_holds WHERE fingerprint = $1",
            &fingerprint,
        )
        .await;
        assert_eq!(holds, 0);
        assert!(release(pool, &identity.fingerprint, false)
            .await
            .unwrap()
            .is_none());
        testkit::forget(pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn udrzba_maze_prosle_zaznamy() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;
        let random = || -> [u8; 32] { rand_bytes(32).try_into().unwrap() };
        let (expired_block, active_block) = (random(), random());
        let (expired_hold, active_hold) = (random(), random());
        let (held_by_expired, held_by_active) = (random(), random());
        let (expired_address, live_address, tag) = (random(), random(), random());

        sqlx::query(
            "INSERT INTO blocked_identities (fingerprint, blocked_on, expires_on, address_hashes)
             VALUES ($1, current_date - 10, current_date - 1, ARRAY[$2::bytea]),
                    ($3, current_date, current_date + 10, ARRAY[$4::bytea])",
        )
        .bind(expired_block)
        .bind(held_by_expired)
        .bind(active_block)
        .bind(held_by_active)
        .execute(pool)
        .await
        .unwrap();
        // Adresy držené blokací nesou značku její identity: konec blokace
        // uvolní jen ty.
        let held_tag = |hash: &[u8; 32], block: [u8; 32]| owner_tag(hash, &Fingerprint(block));
        sqlx::query(
            "INSERT INTO retired_addresses (addr_hash, owner_tag, expires_on)
             VALUES ($1, $5, NULL), ($2, $6, NULL),
                    ($3, $7, current_date - 1), ($4, $7, current_date + 10)",
        )
        .bind(held_by_expired)
        .bind(held_by_active)
        .bind(expired_address)
        .bind(live_address)
        .bind(held_tag(&held_by_expired, expired_block))
        .bind(held_tag(&held_by_active, active_block))
        .bind(tag)
        .execute(pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO identity_holds (fingerprint, held_on, hold_until, snapshot)
             VALUES ($1, current_date - 10, current_date - 1, '{}'),
                    ($2, current_date, current_date + 10, '{}')",
        )
        .bind(expired_hold)
        .bind(active_hold)
        .execute(pool)
        .await
        .unwrap();

        state.maintain_blocks().await;

        let blocks: Vec<[u8; 32]> =
            sqlx::query_scalar("SELECT fingerprint FROM blocked_identities")
                .fetch_all(pool)
                .await
                .unwrap();
        assert_eq!(blocks, vec![active_block]);
        let holds: Vec<[u8; 32]> = sqlx::query_scalar("SELECT fingerprint FROM identity_holds")
            .fetch_all(pool)
            .await
            .unwrap();
        assert_eq!(holds, vec![active_hold]);
        let today = db_today(pool).await;
        let mut addresses: Vec<([u8; 32], Option<NaiveDate>)> =
            sqlx::query_as("SELECT addr_hash, expires_on FROM retired_addresses")
                .fetch_all(pool)
                .await
                .unwrap();
        addresses.sort();
        let mut expected = vec![
            (
                held_by_expired,
                Some(days_after(today, RETIRED_ADDRESS_DAYS)),
            ),
            (held_by_active, None),
            (live_address, Some(days_after(today, 10))),
        ];
        expected.sort();
        assert_eq!(addresses, expected);
        assert!(
            expire(pool).await.unwrap().is_empty(),
            "druhý běh nemá co dělat"
        );
        isolated.remove().await;
    }

    async fn retired_expiry(pool: &PgPool, hash: &[u8; 32]) -> Option<Option<NaiveDate>> {
        sqlx::query_scalar("SELECT expires_on FROM retired_addresses WHERE addr_hash = $1")
            .bind(hash)
            .fetch_optional(pool)
            .await
            .unwrap()
    }

    /// Adresu X drží blokace identity B. Identita A ji přesto má (obsadil ji
    /// starší image, který vyřazené adresy nezná). Blokace A ji nesmí vzít
    /// do svého seznamu a konec blokace A (odblokování i vypršení) ji nesmí
    /// uvolnit, ani když v seznamu je (zapsala ho starší verze).
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn konec_blokace_neuvolni_adresu_cizi_blokace() {
        let isolated = Isolated::new().await;
        let state = isolated.state().await;
        let pool = &isolated.pool;
        let (owner, squatter) = (TestIdentity::new(), TestIdentity::new());
        let (address_x, address_y) = (rand_bytes(32), rand_bytes(32));
        let hash_x = addr_hash(&address_x);

        testkit::register(&state, &owner, &address_x)
            .await
            .expect("registrace B");
        block(pool, &owner.fingerprint, BlockOptions::default())
            .await
            .expect("blokace B");
        assert_eq!(retired_expiry(pool, &hash_x).await, Some(None), "B drží X");

        testkit::register(&state, &squatter, &address_y)
            .await
            .expect("registrace A");
        sqlx::query("UPDATE devices SET delivery_address = $1 WHERE delivery_address = $2")
            .bind(&address_x)
            .bind(&address_y)
            .execute(pool)
            .await
            .unwrap();
        let report = block(pool, &squatter.fingerprint, BlockOptions::default())
            .await
            .expect("blokace A");
        assert!(!report.removed.retired.contains(&hash_x), "X nepatří A");
        let listed: Vec<[u8; 32]> = sqlx::query_scalar(
            "SELECT address_hashes FROM blocked_identities WHERE fingerprint = $1",
        )
        .bind(squatter.fingerprint.0)
        .fetch_one(pool)
        .await
        .unwrap();
        assert!(!listed.contains(&hash_x), "seznam blokace A bez X");

        let add_x_to_list = |expired: bool| {
            sqlx::query(
                "UPDATE blocked_identities
                    SET address_hashes = address_hashes || $2::bytea,
                        blocked_on = CASE WHEN $3 THEN current_date - 2 ELSE blocked_on END,
                        expires_on = CASE WHEN $3 THEN current_date - 1 ELSE expires_on END
                  WHERE fingerprint = $1",
            )
            .bind(squatter.fingerprint.0)
            .bind(hash_x)
            .bind(expired)
        };
        add_x_to_list(false).execute(pool).await.unwrap();
        let unblocked = unblock(pool, &squatter.fingerprint, false)
            .await
            .unwrap()
            .expect("blokace A");
        assert_eq!(unblocked.addresses, 0);
        assert_eq!(
            retired_expiry(pool, &hash_x).await,
            Some(None),
            "X drží dál B"
        );

        block(pool, &squatter.fingerprint, BlockOptions::default())
            .await
            .expect("blokace A podruhé");
        add_x_to_list(true).execute(pool).await.unwrap();
        let expired = expire(pool).await.unwrap();
        assert_eq!(expired.blocks, 1);
        assert_eq!(expired.addresses_released, 0);
        assert_eq!(
            retired_expiry(pool, &hash_x).await,
            Some(None),
            "X drží dál B"
        );
        assert!(is_blocked(pool, &owner.fingerprint).await.unwrap());
        isolated.remove().await;
    }

    /// Registrace jako od starší verze relaye: přímo SQL, bez kontroly
    /// blokace. Vrací (account_id, device_uuid, delivery_address).
    async fn insert_registration(
        pool: &PgPool,
        identity_key: &[u8],
    ) -> (Vec<u8>, Vec<u8>, Vec<u8>) {
        let (account_id, device_uuid, address) = (rand_bytes(16), rand_bytes(16), rand_bytes(32));
        sqlx::query("INSERT INTO identities (account_id, identity_key) VALUES ($1, $2)")
            .bind(&account_id)
            .bind(identity_key)
            .execute(pool)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO devices (device_uuid, account_id, device_id, registration_id, delivery_address)
             VALUES ($1, $2, 1, 1, $3)",
        )
        .bind(&device_uuid)
        .bind(&account_id)
        .bind(&address)
        .execute(pool)
        .await
        .unwrap();
        (account_id, device_uuid, address)
    }

    async fn insert_block(pool: &PgPool, fingerprint: &Fingerprint) {
        sqlx::query(
            "INSERT INTO blocked_identities (fingerprint, expires_on) VALUES ($1, current_date + 30)",
        )
        .bind(fingerprint.0)
        .execute(pool)
        .await
        .unwrap();
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn dorovnani_smaze_registraci_zablokovaneho() {
        let isolated = Isolated::new().await;
        let pool = &isolated.pool;

        // Bez blokací se dorovnání tabulky identit nedotkne: bez ní by dotaz
        // na ni selhal.
        sqlx::query("ALTER TABLE identities RENAME TO identities_mimo")
            .execute(pool)
            .await
            .unwrap();
        let idle = reconcile(pool).await.expect("prázdný seznam blokací");
        assert_eq!(idle.identities, 0);
        sqlx::query("ALTER TABLE identities_mimo RENAME TO identities")
            .execute(pool)
            .await
            .unwrap();

        let identity = TestIdentity::new();
        insert_block(pool, &identity.fingerprint).await;
        let (account_id, device_uuid, address) = insert_registration(pool, &identity.key).await;
        let reconciled = reconcile(pool).await.expect("dorovnání");
        assert_eq!(reconciled.identities, 1);
        assert_eq!(reconciled.device_uuids, vec![device_uuid.clone()]);
        let left = testkit::count(
            pool,
            "SELECT count(*) FROM identities WHERE account_id = $1",
            &account_id,
        )
        .await;
        assert_eq!(left, 0);
        let (devices, hashes): (Vec<Vec<u8>>, Vec<[u8; 32]>) = sqlx::query_as(
            "SELECT device_uuids, address_hashes FROM blocked_identities WHERE fingerprint = $1",
        )
        .bind(identity.fingerprint.0)
        .fetch_one(pool)
        .await
        .unwrap();
        assert_eq!(devices, vec![device_uuid]);
        assert_eq!(hashes, vec![addr_hash(&address)]);

        // Hodinová údržba totéž odpojí s 403.
        let state = isolated.state().await;
        let second = TestIdentity::new();
        insert_block(pool, &second.fingerprint).await;
        let (account_id, device_uuid, _) = insert_registration(pool, &second.key).await;
        let (_guard, mut kicked) = state.conns.add(device_uuid, second.fingerprint.0);
        state.maintain_blocks().await;
        assert_eq!(kicked.try_recv(), Ok(403));
        let left = testkit::count(
            pool,
            "SELECT count(*) FROM identities WHERE account_id = $1",
            &account_id,
        )
        .await;
        assert_eq!(left, 0);
        isolated.remove().await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn migrace_0005_idempotentni() {
        let isolated = Isolated::before_blocking().await;
        let pool = &isolated.pool;
        let (_, device_uuid, _) = insert_registration(pool, &rand_bytes(33)).await;
        sqlx::query(
            "INSERT INTO push_tokens (device_uuid, platform, token, updated_at)
             VALUES ($1, 1, 'token', '2026-11-05 10:37:12.345+00')",
        )
        .bind(&device_uuid)
        .execute(pool)
        .await
        .unwrap();

        sqlx::migrate!("./migrations")
            .run(pool)
            .await
            .expect("0005 nad daty starší verze");
        let rounded: bool = sqlx::query_scalar(
            "SELECT updated_at = date_trunc('hour', updated_at) FROM push_tokens
              WHERE device_uuid = $1",
        )
        .bind(&device_uuid)
        .fetch_one(pool)
        .await
        .unwrap();
        assert!(rounded, "updated_at zaokrouhlené na hodiny");

        let fingerprint = Fingerprint(rand_bytes(32).try_into().unwrap());
        insert_block(pool, &fingerprint).await;
        let state_before: (i64, String) = sqlx::query_as(
            "SELECT (SELECT count(*) FROM blocked_identities),
                    (SELECT updated_at::text FROM push_tokens WHERE device_uuid = $1)",
        )
        .bind(&device_uuid)
        .fetch_one(pool)
        .await
        .unwrap();
        sqlx::raw_sql(include_str!("../migrations/0005_blokace_identit.sql"))
            .execute(pool)
            .await
            .expect("0005 podruhé ručně");
        let state_after: (i64, String) = sqlx::query_as(
            "SELECT (SELECT count(*) FROM blocked_identities),
                    (SELECT updated_at::text FROM push_tokens WHERE device_uuid = $1)",
        )
        .bind(&device_uuid)
        .fetch_one(pool)
        .await
        .unwrap();
        assert_eq!(state_after, state_before, "druhý běh nic nezmění");
        isolated.remove().await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn navrat_na_stary_image_a_zpet() {
        let isolated = Isolated::new().await;
        let pool = &isolated.pool;
        let fingerprint = Fingerprint(rand_bytes(32).try_into().unwrap());
        insert_block(pool, &fingerprint).await;

        let old = testkit::old_migrator().await;
        // Migrátor po téhle chybě neuvolní svůj zámek (starý image pak
        // skončí a se spojením zanikne i zámek). Vlastní spojení, které se
        // zavře, jinak by zámek visel v poolu a další migrace čekala navždy.
        let mut conn = pool.acquire().await.unwrap().detach();
        match old.run(&mut conn).await {
            Err(MigrateError::VersionMissing(5)) => {}
            other => panic!("starý image má odmítnout DB s verzí 5: {other:?}"),
        }
        conn.close().await.unwrap();
        sqlx::query("DELETE FROM _sqlx_migrations WHERE version = 5")
            .execute(pool)
            .await
            .unwrap();
        old.run(pool)
            .await
            .expect("starý image po smazání verze 5 nastartuje");

        sqlx::migrate!("./migrations")
            .run(pool)
            .await
            .expect("nový image 0005 zopakuje");
        let blocks = count(
            pool,
            "SELECT count(*) FROM blocked_identities WHERE fingerprint = $1",
            &fingerprint.0,
        )
        .await;
        assert_eq!(blocks, 1, "blokace přežila návrat");
        let version: i64 = sqlx::query_scalar("SELECT max(version) FROM _sqlx_migrations")
            .fetch_one(pool)
            .await
            .unwrap();
        assert_eq!(version, 5);
        isolated.remove().await;
    }
}
