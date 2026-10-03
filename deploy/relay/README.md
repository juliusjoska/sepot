# sepot-relay — self-hosting

Relay je „hloupý" doručovací server: přijímá a doručuje opaque sealed-sender
obálky, drží offline frontu (TTL) a šifrované bloby příloh. **Nevidí obsah ani
odesílatele, neváže identitu na telefon/e-mail a neloguje IP.**

Stack: `sepot-relay` (Rust/axum) + PostgreSQL + volitelný Tor onion.

## Rychlý start

```bash
cd deploy/relay
cp .env.example .env
# vyplň POSTGRES_PASSWORD, např.:  openssl rand -base64 24
docker compose build
docker compose up -d
```

TLS/WSS neterminuje relay sám — postav před něj reverzní proxy (Caddy, Traefik,
nginx…) s platným certifikátem, která forwarduje na `sepot-relay:8470`. Uvnitř
sítě jede plain WS (proxy dělá TLS termination). Klient se pak připojuje na
`wss://<tvoje-doména>`.

### Ověření

```bash
curl -s http://127.0.0.1:8470/v1/health        # {"status":"ok"}
curl -s http://127.0.0.1:8470/v1/server-info    # capabilities + trust_root
```

### Tor onion (volitelné)

Compose obsahuje kontejner `tor`, který relay vystaví jako onion hidden service.
Adresu zjistíš po startu:

```bash
docker exec sepot-relay-tor cat /var/lib/tor/sepot/hostname
```

Tuhle `.onion` adresu pak nastav v klientu (`app/lib/core/constants/app_constants.dart`,
`AppConstants.relayOnion`) pro svůj vlastní build.

## Konfigurace (`.env`)

| Proměnná | Popis |
|---|---|
| `POSTGRES_PASSWORD` | heslo DB — **povinné**, nikdy necommituj |
| `SEPOT_APNS_*` | volitelné, jen pro iOS APNs push (Key ID, Team ID, cesta ke klíči) |
| FCM service account | volitelné, pro Android budíčky přes FCM (mimo repo) |
| `SEPOT_TURN_URLS` | volitelné, pro hovory: čárkou oddělené `turn:`/`turns:` adresy vašeho coturnu |
| `SEPOT_TURN_SECRET_FILE` / `SEPOT_TURN_SECRET` | sdílené tajemství coturnu (`use-auth-secret`, aspoň 32 znaků); bez něj relay TURN údaje nevydává a hovory jdou jen napřímo |

Push je volitelný. Bez něj appka funguje přes UnifiedPush (degooglované) nebo
si zprávy stáhne po otevření.

## Persistentní data a zálohy

Zálohuj **dvě** volumes, obě obsahují kritické tajné klíče (`chmod 600`):

- **`db-data`** — kromě dat drží `relay_keys` = **trust root CA** sealed
  senderu. Klienti si ho pinují. Jeho ztráta / regenerace = všichni klienti
  tvrdě odmítnou komunikovat („Trust root se změnil").
- **`tor-keys`** — onion identita (`hs_ed25519_secret_key`). Ztráta = nová
  onion adresa pro všechny.

```bash
# DB dump:   docker exec sepot-relay-db pg_dump -U sepot sepot_relay | gzip > db.sql.gz
# Tor klíče: docker run --rm -v sepot-relay_tor-keys:/k -v "$PWD":/o alpine tar czf /o/tor-keys.tgz -C /k .
```

## Privacy — Definition of Done

- Relay neloguje obsah, odesílatele ani IP (vynuceno v kódu, ověřeno testem).
- Access log reverzní proxy pro relay endpoint drž **vypnutý**.
- Rate limity jsou in-memory token buckety — nikdy se nezapisují na disk.
- DB nemá IP/PII sloupce; offline fronta má TTL, ACK = hard delete.
