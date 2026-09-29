-- Počítadlo pokusů o doručení obálky (strop MAX_DELIVERY_ATTEMPTS v state.rs).
-- Obálka, jejíž ACK se ztratil, se jinak posílá při každém připojení až do TTL,
-- ačkoli ji klient podruhé dešifrovat nedokáže. IF NOT EXISTS: instalace, které
-- sloupec už mají ze starší verze init schématu, projdou beze změny.
ALTER TABLE message_queue ADD COLUMN IF NOT EXISTS attempt_count SMALLINT NOT NULL DEFAULT 0;
