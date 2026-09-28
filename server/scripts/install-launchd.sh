#!/bin/bash
# Installs (or reinstalls) the two launchd jobs: the server and the nightly
# backup. Idempotent — run it again after pulling a change to restart cleanly.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
NODE="$(command -v node)"
UID_NUM="$(id -u)"

[ -n "$NODE" ] || { echo "node is not on PATH"; exit 1; }
mkdir -p "$AGENTS"

"$REPO/scripts/setup.sh"

for LABEL in com.babyfeed.server com.babyfeed.backup; do
  TARGET="$AGENTS/$LABEL.plist"
  sed -e "s|__HOME__|$HOME|g" -e "s|__NODE__|$NODE|g" \
    "$REPO/launchd/$LABEL.plist" > "$TARGET"

  # bootout before bootstrap, or a reinstall silently keeps the old copy.
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$TARGET"
  echo "loaded $LABEL"
done

launchctl kickstart -k "gui/$UID_NUM/com.babyfeed.server"
sleep 1
PORT=$(grep -m1 '^BABYFEED_PORT=' "${BABYFEED_DATA_DIR:-$HOME/baby-feed-data}/.env" | cut -d= -f2 || echo 8791)
echo
curl -fsS "http://127.0.0.1:${PORT:-8791}/v1/health" && echo || echo "Server isn't answering yet — check ~/baby-feed-data/logs/server.error.log"
