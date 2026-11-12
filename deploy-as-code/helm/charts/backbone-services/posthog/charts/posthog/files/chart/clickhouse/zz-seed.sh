#!/bin/bash
# Fast first start: restore a pre-migrated ClickHouse schema (native BACKUP of the posthog
# database, produced by e2e/export-seed.sh or a chart release). Runs from the image's initdb
# hook, i.e. only on an empty data directory, after upstream's init-db.sh.
set -euo pipefail
SRC="${POSTHOG_SEED_DIR:-/seed}/clickhouse/seed"
DST=/var/lib/clickhouse/backups/seed
if [ -d "$SRC" ]; then
    echo "seed: restoring ClickHouse database posthog from $SRC"
    mkdir -p "$(dirname "$DST")"
    cp -r "$SRC" "$DST"
    clickhouse client --query "RESTORE DATABASE posthog FROM File('$DST') SETTINGS allow_non_empty_tables=true"
    rm -rf "$DST"
    echo "seed: done"
else
    echo "seed: no backup at $SRC, skipping"
fi
