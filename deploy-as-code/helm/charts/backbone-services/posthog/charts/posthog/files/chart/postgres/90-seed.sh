#!/bin/bash
# Fast first start: restore a pre-migrated schema dump (produced by e2e/export-seed.sh or a
# chart release) into the fresh database before PostHog's migrate job runs. Executed by the
# postgres image's initdb hook, i.e. only when the data directory is empty.
set -euo pipefail
SEED="${POSTHOG_SEED_DIR:-/seed}/posthog.pgdump"
if [ -f "$SEED" ]; then
    echo "seed: restoring $SEED into $POSTGRES_DB"
    pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-owner --no-privileges --exit-on-error "$SEED"
    echo "seed: done"
else
    echo "seed: no dump at $SEED, skipping"
fi
