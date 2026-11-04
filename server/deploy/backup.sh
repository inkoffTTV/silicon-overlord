#!/bin/sh
# Consistent online backup of the game database (safe while the server is running).
# Usage: sudo /opt/silicon-overlord/server/deploy/backup.sh [/var/backups/silicon-overlord] [days-to-keep]
set -eu
APP="${APP:-/opt/silicon-overlord}"
DB="$APP/server/data/silicon.db"
DEST="${1:-/var/backups/silicon-overlord}"
KEEP="${2:-14}"
mkdir -p "$DEST"
OUT="$DEST/silicon-$(date +%Y%m%d-%H%M).db"
"$APP/venv/bin/python" - "$DB" "$OUT" <<'PY'
import sqlite3, sys
src = sqlite3.connect(sys.argv[1])
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
dst.close()
src.close()
PY
gzip -f "$OUT"
find "$DEST" -name 'silicon-*.db.gz' -mtime +"$KEEP" -delete
echo "backup written: $OUT.gz"
