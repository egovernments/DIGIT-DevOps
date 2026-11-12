# Runs in the migrate Job right before bin/migrate (migrations.sessionsV3Reset).
#
# ClickHouse migration 0364_sessions_v3_more_ad_ids (PostHog >= 2026-10-28) creates the raw_sessions_v3
# materialized views again, with uniq states instead of uniqExact. Its CREATE ... IF NOT EXISTS keeps an
# existing table, so an install that created raw_sessions_v3 before the shape change (every install from
# before that date: 0178 had dropped the views, so the table stayed empty) would get views whose rows do
# not fit the table, and every insert into sharded_events would fail with them.
#
# Upstream's fix is to drop the v3 objects and create them again from sessions_v3.py. The earlier v3
# migrations create them on a fresh cluster, so for an empty old-shape table this drops the v3 objects and
# forgets that those migrations ran: bin/migrate then replays them with today's definitions, in order,
# before 0364. Forgetting alone is not enough: 0149 creates the tables IF NOT EXISTS (the old ones stay)
# and then replaces raw_sessions_v3_v with a view that uniqMerge()s them, which ClickHouse rejects for
# uniqExact states. A table that holds rows is left alone and the Job fails with the manual steps,
# because dropping it would lose data.
import os
import sys
import time

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "posthog.settings")

import django  # noqa: E402

django.setup()

from django.conf import settings  # noqa: E402

from posthog.clickhouse.client import sync_execute  # noqa: E402

PREFIX = "sessions-v3 reset:"
DB = settings.CLICKHOUSE_DATABASE
PACKAGE = "posthog.clickhouse.migrations"
V3_MIGRATIONS = (
    "0149_sessions_v3",
    "0158_sessions_v3_remake",
    "0164_sessions_v3_replay_events",
    "0167_sessions_v3_split_bounce_rate",
    "0168_sessions_v3_mvs",
    "0169_drop_sessions_v3_recordings_mv",
    "0170_sessions_v3_replay_events",
    "0171_sessions_v3_split_bounce_rate",
    "0172_sessions_v3_recordings_mvs",
    "0173_sessions_v3_mv",
    "0178_sessions_v3_insert_delay_settings_and_drop_mvs",
    "0180_sessions_v3_add_event_names",
    "0325_sessions_v3_flag_key_values",
    "0328_sessions_v3_ws_pipeline",
    "0364_sessions_v3_more_ad_ids",
)


def log(message: str) -> None:
    print(f"{PREFIX} {message}", flush=True)


for attempt in range(1, 61):
    try:
        sync_execute("SELECT 1")
        break
    except Exception as error:  # ClickHouse may still be starting (fresh install, version upgrade)
        # Reachable, but the posthog database does not exist yet: a fresh install, which bin/migrate sets up
        # from scratch with today's definitions. There is nothing to reset (the e2e on kind waited 10 minutes
        # for a database that only bin/migrate creates, then failed the Job).
        if "UnknownDatabase" in error.__class__.__name__ or "UNKNOWN_DATABASE" in str(error):
            log(f"database {DB} does not exist yet (fresh install), nothing to do")
            sys.exit(0)
        log(f"ClickHouse not reachable yet ({error.__class__.__name__}), attempt {attempt}/60")
        time.sleep(10)
else:
    sys.exit(f"{PREFIX} ClickHouse not reachable after 10 minutes")

rows = sync_execute(
    "SELECT create_table_query FROM system.tables WHERE database = %(db)s AND name = 'sharded_raw_sessions_v3'",
    {"db": DB},
)
if not rows:
    log("no sharded_raw_sessions_v3 yet (fresh install), nothing to do")
    sys.exit(0)
if "uniqExact" not in rows[0][0]:
    log("sharded_raw_sessions_v3 already has the current shape, nothing to do")
    sys.exit(0)

count = sync_execute(f"SELECT count() FROM {DB}.sharded_raw_sessions_v3")[0][0]
if count:
    sys.exit(
        f"{PREFIX} {DB}.sharded_raw_sessions_v3 has the old shape (uniqExact) and holds {count} rows. "
        "Migration 0364 would attach views that cannot write to it. Back the table up if you need it, "
        "drop raw_sessions_v3_mv, raw_sessions_v3_recordings_mv, raw_sessions_v3_v, raw_sessions_v3, "
        "writable_raw_sessions_v3 and sharded_raw_sessions_v3 (SYNC), then re-run this Job, or set "
        "migrations.sessionsV3Reset=false and follow the comment in 0364_sessions_v3_more_ad_ids.py."
    )

applied = [
    row[0]
    for row in sync_execute(
        f"SELECT module_name FROM {DB}.infi_clickhouse_orm_migrations "
        "WHERE package_name = %(package)s AND module_name IN %(modules)s",
        {"package": PACKAGE, "modules": V3_MIGRATIONS},
    )
]
# Views first, the replicated table last and SYNC, so its ZooKeeper replica is gone before 0149 creates it.
DROPS = (
    f"DROP TABLE IF EXISTS {DB}.raw_sessions_v3_mv",
    f"DROP TABLE IF EXISTS {DB}.raw_sessions_v3_recordings_mv",
    f"DROP VIEW IF EXISTS {DB}.raw_sessions_v3_v",
    f"DROP TABLE IF EXISTS {DB}.raw_sessions_v3",
    f"DROP TABLE IF EXISTS {DB}.writable_raw_sessions_v3",
    f"DROP TABLE IF EXISTS {DB}.sharded_raw_sessions_v3 SYNC",
)
if os.environ.get("SESSIONS_V3_RESET_DRY_RUN"):
    log(
        f"dry run: would drop the empty old-shape v3 objects and forget {len(applied)} applied v3 "
        f"migrations: {', '.join(sorted(applied)) or '-'}"
    )
    sys.exit(0)

for statement in DROPS:
    sync_execute(statement)
if applied:
    sync_execute(
        f"ALTER TABLE {DB}.infi_clickhouse_orm_migrations DELETE "
        "WHERE package_name = %(package)s AND module_name IN %(modules)s SETTINGS mutations_sync = 2",
        {"package": PACKAGE, "modules": V3_MIGRATIONS},
    )
log(
    f"sharded_raw_sessions_v3 was empty and in the old shape; dropped the v3 objects and forgot "
    f"{len(applied)} applied v3 migrations, so bin/migrate rebuilds raw_sessions_v3 in the current shape"
)
