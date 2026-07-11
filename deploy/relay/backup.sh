#!/usr/bin/env bash
# Denní záloha sepot-relay — KRITICKÉ.
#
#   db-data  → drží relay_keys = trust root CA sealed senderu. Klienti ho
#              pinují; ztráta/regenerace = všichni klienti tvrdě odmítnou
#              relay ("trust root se změnil").
#   tor-keys → onion identita (hs_ed25519_secret_key). Ztráta = nová onion
#              adresa pro všechny.
#
# Obojí obsahuje TAJNÉ klíče → zálohy jen chmod 700, umask 077.
# Nasazení cronu: viz README.md „Zálohy".
set -euo pipefail
umask 077

BACKUP_DIR=/opt/backups/sepot-relay
KEEP_DAYS=14
STAMP=$(date +%F_%H%M)

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

db_file="$BACKUP_DIR/db_${STAMP}.sql.gz"
tor_file="$BACKUP_DIR/tor-keys_${STAMP}.tgz"

# 1) Postgres dump (relay_keys = trust root CA)
docker exec sepot-relay-db pg_dump -U sepot sepot_relay | gzip > "$db_file"

# 2) Tor onion identita — jen podadresář hidden service (hostname +
#    hs_ed25519_*). Zbytek DataDirectory (cache konsenzu) je regenerovatelný
#    a jen by churnoval. Read-only mount, ať se běžícímu toru nic nerozbije.
docker run --rm -v sepot-relay_tor-keys:/k:ro -v "$BACKUP_DIR":/b alpine \
  tar czf "/b/tor-keys_${STAMP}.tgz" -C /k sepot
# docker run vytvoří soubor s umaskou kontejneru (ne skriptu) → obsahuje
# TAJNÝ onion klíč, natvrdo zamknout
chmod 600 "$tor_file"

# 3) Integrita — prázdný/rozbitý dump je horší než žádný (maskuje selhání)
if [ ! -s "$db_file" ] || ! gzip -t "$db_file" 2>/dev/null; then
  echo "$(date -Is) CHYBA: DB dump prázdný nebo poškozený ($db_file)" >&2
  rm -f "$db_file"
  exit 1
fi
if [ ! -s "$tor_file" ]; then
  echo "$(date -Is) CHYBA: tor-keys archiv prázdný ($tor_file)" >&2
  exit 1
fi

# 4) Rotace — držet posledních KEEP_DAYS dní
find "$BACKUP_DIR" -maxdepth 1 -name 'db_*.sql.gz'    -mtime +"$KEEP_DAYS" -delete
find "$BACKUP_DIR" -maxdepth 1 -name 'tor-keys_*.tgz' -mtime +"$KEEP_DAYS" -delete

echo "$(date -Is) OK db=$(du -h "$db_file" | cut -f1) tor=$(du -h "$tor_file" | cut -f1)"
