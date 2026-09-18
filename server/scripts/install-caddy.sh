#!/bin/bash
# Installs Baby Feed's own Caddy as a launchd job. Run this only after putting
# a real hostname in caddy/Caddyfile — Caddy will otherwise sit there failing
# to get a certificate for babyfeed.example.org.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CADDY="$(command -v caddy)"
UID_NUM="$(id -u)"
[ -n "$CADDY" ] || { echo "caddy is not installed (brew install caddy)"; exit 1; }

if grep -q 'babyfeed.example.org' "$REPO/caddy/Caddyfile"; then
  echo "caddy/Caddyfile still has the placeholder hostname. Edit it first."
  exit 1
fi

caddy validate --config "$REPO/caddy/Caddyfile"

mkdir -p "$HOME/baby-feed-data/caddy"
TARGET="$HOME/Library/LaunchAgents/com.babyfeed.caddy.plist"
sed -e "s|__HOME__|$HOME|g" -e "s|__CADDY__|$CADDY|g" \
  "$REPO/launchd/com.babyfeed.caddy.plist" > "$TARGET"

launchctl bootout "gui/$UID_NUM/com.babyfeed.caddy" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$TARGET"
echo "loaded com.babyfeed.caddy — watch $HOME/baby-feed-data/logs/caddy.error.log for the certificate"
