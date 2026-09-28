#!/bin/bash
# One-time setup on the Mac mini. Safe to re-run: it never overwrites existing
# settings or the database.
#
# Creates ~/baby-feed-data (config, database, backups, logs) and writes the
# settings. There is no code to print: a phone on the same Wi-Fi sets itself
# up, and every phone after that joins by scanning a QR on one that has the log.

set -euo pipefail

DATA_DIR="${BABYFEED_DATA_DIR:-$HOME/baby-feed-data}"
ENV_FILE="$DATA_DIR/.env"

mkdir -p "$DATA_DIR/backups" "$DATA_DIR/logs"
chmod 700 "$DATA_DIR"

if [ -f "$ENV_FILE" ]; then
  echo "Settings already exist at $ENV_FILE — leaving them alone."
else
  cat > "$ENV_FILE" <<'SETTINGS'
# Baby Feed server settings. Never in git — this file lives outside the repo.

# Listen on the home network, because the phones talk to it directly over the
# Wi-Fi. Set 127.0.0.1 only if every phone reaches it through Caddy instead.
BABYFEED_BIND=0.0.0.0
BABYFEED_PORT=8791

# How a brand-new phone gets on. "lan": a phone on this Wi-Fi sets itself up
# with nothing typed (never through Caddy, never from the internet). "off":
# only by invite or recovery phrase.
BABYFEED_ENROLL=lan
SETTINGS
  chmod 600 "$ENV_FILE"
  echo
  echo "  No code to type. Open Baby Feed on an iPhone on this Wi-Fi and add your baby;"
  echo "  it sets itself up and shows the recovery phrase to write down."
  echo
fi

echo "Data directory: $DATA_DIR"
