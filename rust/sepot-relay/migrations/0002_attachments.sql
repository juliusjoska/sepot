-- Přílohy: opaque šifrované bloby mimo message_queue.
-- Relay vidí jen blob_id + velikost + expiraci. ŽÁDNÁ vazba na účet,
-- zařízení ani zprávu — kdo blob nahrál/stáhl se neukládá (privacy).
-- Samotná data leží na disku (SEPOT_ATTACHMENTS_DIR), v DB jen metadata
-- kvůli TTL úklidu.

CREATE TABLE attachments (
    blob_id     BYTEA PRIMARY KEY,
    size_bytes  BIGINT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    CHECK (octet_length(blob_id) = 16),
    CHECK (size_bytes > 0)
);

CREATE INDEX idx_attachments_expiry ON attachments(expires_at);
