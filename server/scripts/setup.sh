#!/bin/bash
# One-time setup on the Mac mini. Safe to re-run: it never overwrites an
# existing secret or database.
#
# Creates ~/baby-feed-data (config, database, backups, logs), generates the
# setup secret the first iPhone pairs with, and prints it once.

set -euo pipefail

DATA_DIR="${BABYFEED_DATA_DIR:-$HOME/baby-feed-data}"
ENV_FILE="$DATA_DIR/.env"

mkdir -p "$DATA_DIR/backups" "$DATA_DIR/logs"
chmod 700 "$DATA_DIR"

if [ -f "$ENV_FILE" ]; then
  echo "Settings already exist at $ENV_FILE — leaving them alone."
else
  # openssl rather than tr < /dev/urandom | head: that pipeline dies of SIGPIPE
  # under `set -o pipefail`, which is a silent failure in a setup script.
  SECRET=$(openssl rand -base64 24 | LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' | cut -c1-10)
  cat > "$ENV_FILE" <<SETTINGS
# Baby Feed server settings. Never in git — this file lives outside the repo.

# The code the FIRST iPhone types in to pair. Every phone after that joins with
# a six-character invite code from that phone, so this is used once.
BABYFEED_SETUP_SECRET=$SECRET

# Loopback only: Caddy in front of this terminates TLS. Set 0.0.0.0 to reach it
# directly over the home network while trying it out.
BABYFEED_BIND=127.0.0.1
BABYFEED_PORT=8791
SETTINGS
  chmod 600 "$ENV_FILE"
  echo
  echo "  Setup code for the first iPhone:  $SECRET"
  echo
  echo "  It's saved in $ENV_FILE. You only need it once."
fi

echo "Data directory: $DATA_DIR"
