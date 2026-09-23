#!/bin/bash
# Keeps Baby Feed's own DuckDNS hostname pointed at this house's public IP.
#
# Comcast rotates the residential IP. If the record goes stale, both phones stop
# syncing until it's fixed by hand — and the failure looks like "the app is
# broken", not "DNS moved", so this runs on a timer.
#
# Baby Feed's own script, own hostname, own launchd job, own .env. It shares
# nothing with any other dynamic-DNS updater on this machine.

set -uo pipefail

DATA_DIR="${BABYFEED_DATA_DIR:-$HOME/baby-feed-data}"
ENV_FILE="$DATA_DIR/.env"
LOG="$DATA_DIR/logs/duckdns.log"
mkdir -p "$(dirname "$LOG")"

# Read only the keys needed. Sourcing the whole file would execute it.
read_key() { grep -m1 "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' '; }

HOSTNAME_FULL=$(read_key BABYFEED_HOSTNAME)
TOKEN=$(read_key BABYFEED_DUCKDNS_TOKEN)
# DuckDNS wants the label only: "babyfeedsync", not "babyfeedsync.duckdns.org".
DOMAIN="${HOSTNAME_FULL%%.duckdns.org}"

stamp() { date "+%Y-%m-%dT%H:%M:%S%z"; }

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
  echo "$(stamp) ERROR: BABYFEED_HOSTNAME / BABYFEED_DUCKDNS_TOKEN missing from $ENV_FILE" >> "$LOG"
  exit 1
fi

# An empty `ip` lets DuckDNS use the requesting address, so this can't get the
# house's own public IP wrong.
RESP=$(curl -fsS --max-time 30 "https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ip=")
RC=$?

if [ $RC -ne 0 ]; then
  echo "$(stamp) FAIL curl rc=$RC: $RESP" >> "$LOG"
  exit 1
fi

case "$RESP" in
  OK*)
    # Only log a change, so this doesn't add a line every 5 minutes forever.
    CUR=$(dig +short "${DOMAIN}.duckdns.org" 2>/dev/null | head -1)
    LAST_FILE="$(dirname "$LOG")/.duckdns-last-ip"
    LAST=$(cat "$LAST_FILE" 2>/dev/null || echo "")
    if [ "$CUR" != "$LAST" ]; then
      echo "$(stamp) OK ${DOMAIN}.duckdns.org -> ${CUR:-unknown}" >> "$LOG"
      printf '%s' "$CUR" > "$LAST_FILE"
    fi
    ;;
  *)
    echo "$(stamp) DuckDNS refused the update (response: $RESP) — check the token" >> "$LOG"
    exit 1
    ;;
esac
