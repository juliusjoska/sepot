-- Blokace identit, zajištění údajů a vyřazené doručovací adresy.
--
-- Klíčem blokace je otisk identity: BLAKE2b-256 serializovaného veřejného
-- identity klíče (33 B). Je to totéž číslo, které uživatel vidí v aplikaci
-- a které nese hlášení zneužití. Postgres BLAKE2b neumí, otisk počítá server.
-- Blokace proto platí i pro identitu, která zrovna registrovaná není:
-- smazání účtu ani úklid ji neobejdou.
--
-- Registrace zablokované identity se maže, v tabulkách identities a devices
-- tedy není a dotazy, které spoléhají na existenci řádku, se nemění.
-- Důvod blokace se neukládá.
--
-- IF NOT EXISTS: po návratu na starší verzi serveru a smazání řádku verze 5
-- z _sqlx_migrations musí opakované spuštění projít beze změny.

CREATE TABLE IF NOT EXISTS blocked_identities (
    fingerprint     BYTEA PRIMARY KEY,
    blocked_on      DATE NOT NULL DEFAULT current_date,
    -- Poslední den platnosti. Seznam se nedrží déle, než je potřeba;
    -- prodloužení je nové rozhodnutí.
    expires_on      DATE NOT NULL,
    -- Zařízení, která blokace smazala. Jejich další pokus o přihlášení dostane
    -- "zablokováno" místo "neregistrováno"; device_uuid zná jen zařízení samo.
    device_uuids    BYTEA[] NOT NULL DEFAULT '{}',
    -- Vyřazené adresy této identity, které blokace drží (retired_addresses).
    address_hashes  BYTEA[] NOT NULL DEFAULT '{}',
    CHECK (octet_length(fingerprint) = 32),
    CHECK (expires_on >= blocked_on)
);
CREATE INDEX IF NOT EXISTS idx_blocked_identities_expires
    ON blocked_identities (expires_on);

-- Doručovací adresy zrušených registrací (smazání účtu, převzetí jiným
-- zařízením, blokace, úklid). Adresu volí klient a zná ji každý kontakt.
-- Bez této evidence by si ji kdokoli zaregistroval a přijímal nečitelné
-- obálky určené původnímu majiteli, zatímco odesílatelé vidí "doručeno".
-- Ukládá se jen jednosměrný hash adresy a značka vlastníka; znovu ji smí
-- zaregistrovat jen tatáž identita:
--   addr_hash = SHA-256("sepot-adresa-v1" || 0x00 || adresa)
--   owner_tag = SHA-256("sepot-vlastnik-v1" || 0x00 || addr_hash || otisk)
CREATE TABLE IF NOT EXISTS retired_addresses (
    addr_hash   BYTEA PRIMARY KEY,
    owner_tag   BYTEA NOT NULL,
    -- NULL = adresu drží blokace vlastníka; jinak poslední den platnosti.
    expires_on  DATE,
    CHECK (octet_length(addr_hash) = 32),
    CHECK (octet_length(owner_tag) = 32)
);
CREATE INDEX IF NOT EXISTS idx_retired_addresses_expires
    ON retired_addresses (expires_on) WHERE expires_on IS NOT NULL;

-- Zajištěné údaje: kopie registrace v okamžiku zajištění (identita,
-- zařízení, push tokeny; bez předklíčů a bez fronty). Kopie přežije smazání
-- registrace a po hold_until ji smaže hodinová údržba.
CREATE TABLE IF NOT EXISTS identity_holds (
    fingerprint  BYTEA PRIMARY KEY,
    held_on      DATE NOT NULL DEFAULT current_date,
    hold_until   DATE NOT NULL,
    snapshot     JSONB NOT NULL,
    CHECK (octet_length(fingerprint) = 32),
    CHECK (hold_until >= held_on)
);

-- push_tokens.updated_at nikdo nečte a nesl přesný čas připojení, zatímco
-- devices.last_seen_at se ukládá po hodinách. Sjednoceno na hodiny; nový kód
-- zapisuje rovnou zaokrouhlený čas.
UPDATE push_tokens SET updated_at = date_trunc('hour', updated_at)
 WHERE updated_at <> date_trunc('hour', updated_at);
