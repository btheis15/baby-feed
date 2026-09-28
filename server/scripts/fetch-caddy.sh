#!/bin/bash
# Downloads Baby Feed's own Caddy — a build that includes the DuckDNS DNS
# provider, which the Homebrew one does not.
#
# It lives in this project's own bin/ and is never installed system-wide, so
# `brew upgrade caddy` can't replace it and removing this project takes it with
# it. Not committed: it's 46 MB of binary.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] && ARCH="amd64" || ARCH="arm64"

mkdir -p "$REPO/bin"
echo "Downloading Caddy with the DuckDNS module (darwin/$ARCH)…"
curl -fsSL -o "$REPO/bin/caddy" \
  "https://caddyserver.com/api/download?os=darwin&arch=$ARCH&p=github.com%2Fcaddy-dns%2Fduckdns"
chmod +x "$REPO/bin/caddy"

"$REPO/bin/caddy" list-modules | grep -q 'dns.providers.duckdns' \
  || { echo "That build has no DuckDNS module — not using it."; rm -f "$REPO/bin/caddy"; exit 1; }

echo "Ready: $REPO/bin/caddy ($("$REPO/bin/caddy" version | cut -d' ' -f1))"
