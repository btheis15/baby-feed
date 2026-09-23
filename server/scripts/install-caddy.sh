#!/bin/bash
# Puts HTTPS in front of the sync server, so the phones sync from anywhere.
#
# Before running this, three things that aren't on this machine:
#   1. A DuckDNS hostname (any name), and its token.
#   2. Those two in ~/baby-feed-data/.env as BABYFEED_HOSTNAME and
#      BABYFEED_DUCKDNS_TOKEN.
#   3. A port-forward on the router: external 4443 -> this Mac, port 9444.
#
# Step 3 isn't needed for the certificate — the DNS challenge doesn't care — so
# this script will happily get a certificate before the router is set up, and
# the phones simply can't reach it until that's done.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${BABYFEED_DATA_DIR:-$HOME/baby-feed-data}"
ENV_FILE="$DATA_DIR/.env"
CADDY="$REPO/bin/caddy"
UID_NUM="$(id -u)"

[ -x "$CADDY" ] || { echo "Baby Feed's Caddy is missing from $CADDY"; exit 1; }

read_key() { grep -m1 "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' '; }
HOSTNAME_FULL="$(read_key BABYFEED_HOSTNAME)"
DUCKDNS_TOKEN="$(read_key BABYFEED_DUCKDNS_TOKEN)"

if [ -z "$HOSTNAME_FULL" ] || [ -z "$DUCKDNS_TOKEN" ]; then
  cat <<MSG
Add these two lines to $ENV_FILE first:

  BABYFEED_HOSTNAME=yourname.duckdns.org
  BABYFEED_DUCKDNS_TOKEN=<the token from duckdns.org>

MSG
  exit 1
fi

BABYFEED_HOSTNAME="$HOSTNAME_FULL" BABYFEED_DUCKDNS_TOKEN="$DUCKDNS_TOKEN" \
  "$CADDY" validate --config "$REPO/caddy/Caddyfile"

mkdir -p "$DATA_DIR/caddy"
TARGET="$HOME/Library/LaunchAgents/com.babyfeed.caddy.plist"
# The token goes into a file only this user can read, never into the repo.
sed -e "s|__HOME__|$HOME|g" \
    -e "s|__HOSTNAME__|$HOSTNAME_FULL|g" \
    -e "s|__DUCKDNS_TOKEN__|$DUCKDNS_TOKEN|g" \
  "$REPO/launchd/com.babyfeed.caddy.plist" > "$TARGET"
chmod 600 "$TARGET"

DUCK="$HOME/Library/LaunchAgents/com.babyfeed.duckdns.plist"
sed -e "s|__HOME__|$HOME|g" "$REPO/launchd/com.babyfeed.duckdns.plist" > "$DUCK"

for LABEL in com.babyfeed.duckdns com.babyfeed.caddy; do
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$HOME/Library/LaunchAgents/$LABEL.plist"
  echo "loaded $LABEL"
done

echo
echo "Getting a certificate for $HOSTNAME_FULL — this takes a minute or two."
# --resolve so this asks THIS machine directly. Going out to the hostname would
# leave the house, come back through the router, and fail on a router that
# doesn't do hairpin NAT — reporting a problem with the certificate that isn't
# one. The port-forward is checked from a phone, not from here.
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 --resolve "$HOSTNAME_FULL:9444:127.0.0.1" \
       "https://$HOSTNAME_FULL:9444/v1/health" >/dev/null 2>&1; then
    echo
    echo "  Ready. Use this as the server address in the app:"
    echo
    echo "      https://$HOSTNAME_FULL:4443"
    echo
    echo "  (4443 is the external port you forwarded to 9444.)"
    exit 0
  fi
  sleep 5
done

echo "Not answering yet. Watch: tail -f $DATA_DIR/logs/caddy.error.log"
