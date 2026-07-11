-- Šepot relay — init schéma.
-- Klíče Curve25519 mají 33 B (libsignal serializace s type bytem 0x05),
-- ne 32 B. ŽÁDNÝ sloupec pro IP, user-agent ani jinou PII.

CREATE TABLE identities (
    account_id     BYTEA PRIMARY KEY,
    identity_key   BYTEA NOT NULL UNIQUE,
    registered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (octet_length(identity_key) = 33),
    CHECK (octet_length(account_id) = 16)
);

CREATE TABLE devices (
    device_uuid       BYTEA PRIMARY KEY,
    account_id        BYTEA NOT NULL REFERENCES identities(account_id) ON DELETE CASCADE,
    device_id         INTEGER NOT NULL,
    registration_id   INTEGER NOT NULL,
    delivery_address  BYTEA NOT NULL UNIQUE,
    last_seen_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, device_id),
    CHECK (octet_length(delivery_address) = 32),
    CHECK (octet_length(device_uuid) = 16)
);

CREATE INDEX idx_devices_account ON devices(account_id);

CREATE TABLE signed_prekeys (
    device_uuid    BYTEA NOT NULL REFERENCES devices(device_uuid) ON DELETE CASCADE,
    key_id         INTEGER NOT NULL,
    public_key     BYTEA NOT NULL,
    signature      BYTEA NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_uuid, key_id),
    CHECK (octet_length(public_key) = 33),
    CHECK (octet_length(signature) = 64)
);

CREATE TABLE kyber_prekeys (
    device_uuid    BYTEA NOT NULL REFERENCES devices(device_uuid) ON DELETE CASCADE,
    key_id         INTEGER NOT NULL,
    public_key     BYTEA NOT NULL,
    signature      BYTEA NOT NULL,
    is_last_resort BOOLEAN NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_uuid, key_id),
    CHECK (octet_length(signature) = 64),
    CHECK (octet_length(public_key) <= 2048)
);

CREATE TABLE one_time_prekeys (
    device_uuid    BYTEA NOT NULL REFERENCES devices(device_uuid) ON DELETE CASCADE,
    key_id         INTEGER NOT NULL,
    public_key     BYTEA NOT NULL,
    PRIMARY KEY (device_uuid, key_id),
    CHECK (octet_length(public_key) = 33)
);

CREATE INDEX idx_otp_device ON one_time_prekeys(device_uuid);

CREATE TABLE message_queue (
    msg_uuid          BYTEA PRIMARY KEY,
    dst_address       BYTEA NOT NULL,
    envelope          BYTEA NOT NULL,
    enqueued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ NOT NULL,
    CHECK (octet_length(envelope) <= 262144),
    CHECK (octet_length(msg_uuid) = 16)
);
-- Pozn.: žádný sloupec delivered_at — ACK klienta = okamžitý hard-delete
-- řádku, fronta se po doručení nedrží.

CREATE INDEX idx_queue_dst ON message_queue(dst_address, enqueued_at);
CREATE INDEX idx_queue_expiry ON message_queue(expires_at);

CREATE TABLE push_tokens (
    device_uuid    BYTEA PRIMARY KEY REFERENCES devices(device_uuid) ON DELETE CASCADE,
    platform       SMALLINT NOT NULL,
    token          BYTEA,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Klíče relaye pro sealed sender (trust root + server certificate).
-- Trust root keypair i server keypair se generují a ukládají sem při prvním
-- startu relaye. Sloupec trust_root_private tedy reálně obsahuje privátní
-- klíč trust rootu. Pro produkci se doporučuje po vygenerování privátní klíč
-- trust rootu z DB odstranit (nastavit na NULL) a jeho zálohu držet offline —
-- k běžnému provozu relaye stačí trust_root_public, server keypair a cert.
CREATE TABLE relay_keys (
    id                  SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    trust_root_public   BYTEA NOT NULL,
    trust_root_private  BYTEA,
    server_public       BYTEA NOT NULL,
    server_private      BYTEA NOT NULL,
    server_certificate  BYTEA NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
