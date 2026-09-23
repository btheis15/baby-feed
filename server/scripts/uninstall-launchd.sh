#!/bin/bash
# Removes the launchd jobs. Leaves ~/baby-feed-data — the database and the
# backups are the one thing this script must never take with it.
set -euo pipefail
UID_NUM="$(id -u)"
for LABEL in com.babyfeed.server com.babyfeed.backup; do
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
  echo "removed $LABEL"
done
echo "The database is still at ${BABYFEED_DATA_DIR:-$HOME/baby-feed-data} — delete it by hand if you mean to."
