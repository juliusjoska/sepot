-- iOS PushKit token pro příchozí hovory. Vedle běžného tokenu, ne místo něj:
-- VoIP push smí nést jen hovor (iOS jinak appce VoIP pushe zastaví), zprávy
-- dál budí běžný APNs.
ALTER TABLE push_tokens ADD COLUMN voip_token BYTEA;
