#!/bin/bash
# A nightly copy of the database.
#
# sqlite3's .backup, not cp: the database runs in WAL mode, so copying the file
# while the server is writing can capture a torn snapshot. .backup takes a
# consistent one from a live database without stopping anything.
#
# Fourteen days of dailies. The whole thing is a few megabytes at newborn
# volumes; the point is being able to go back past the day a mistake was made.

set -euo pipefail

DATA_DIR="${BABYFEED_DATA_DIR:-$HOME/baby-feed-data}"
DB="${BABYFEED_DB:-$DATA_DIR/babyfeed.db}"
DEST="$DATA_DIR/backups"
KEEP_DAYS=14

[ -f "$DB" ] || { echo "No database at $DB yet — nothing to back up."; exit 0; }
mkdir -p "$DEST"

STAMP=$(date +%Y-%m-%d)
OUT="$DEST/babyfeed-$STAMP.db"
sqlite3 "$DB" ".backup '$OUT'"
gzip -f "$OUT"

find "$DEST" -name 'babyfeed-*.db.gz' -mtime "+$KEEP_DAYS" -delete
echo "$(date -Iseconds) backed up to $OUT.gz ($(du -h "$OUT.gz" | cut -f1))"
