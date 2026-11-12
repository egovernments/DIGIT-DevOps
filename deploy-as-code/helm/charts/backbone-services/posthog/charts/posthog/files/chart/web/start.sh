#!/bin/bash
# Chart-managed start script for the web service. Mirrors upstream bin/docker-server (vendored
# next to this chart under files/upstream/bin/docker-server) except that it does not call
# setpriv: the pod already runs as an unprivileged user, and setpriv fails without root.
# The generator's test suite checks that the GRANIAN defaults below match upstream.
set -e

./bin/migrate-check

# prometheus_client needs a shared directory to aggregate metrics across workers.
export PROMETHEUS_MULTIPROC_DIR=$(mktemp -d)
chmod -R 777 "$PROMETHEUS_MULTIPROC_DIR"

export PROMETHEUS_METRICS_EXPORT_PORT=8001
export STATSD_PORT=${STATSD_PORT:-8125}

export GRANIAN_INTERFACE=${GRANIAN_INTERFACE:-asgi}
export GRANIAN_HOST=${GRANIAN_HOST:-0.0.0.0}
export GRANIAN_WORKERS=${GRANIAN_WORKERS:-4}
export GRANIAN_LOG_LEVEL=${GRANIAN_LOG_LEVEL:-warning}
export GRANIAN_LOG_ACCESS_ENABLED=${GRANIAN_LOG_ACCESS_ENABLED:-true}
export GRANIAN_RESPAWN_FAILED_WORKERS=${GRANIAN_RESPAWN_FAILED_WORKERS:-true}
export GRANIAN_METRICS_ENABLED=${GRANIAN_METRICS_ENABLED:-true}
export GRANIAN_METRICS_PORT=${GRANIAN_METRICS_PORT:-9090}

if [ "$GRANIAN_INTERFACE" = "wsgi" ]; then
    APP_TARGET="posthog.wsgi:application"
else
    APP_TARGET="posthog.asgi:application"
    export GRANIAN_LOOP=${GRANIAN_LOOP:-uvloop}
fi

python ./bin/granian_metrics.py &
METRICS_PID=$!
trap 'kill $METRICS_PID 2>/dev/null; rm -rf "$PROMETHEUS_MULTIPROC_DIR"' EXIT

# One listen socket shared by all workers, for pools that run one request per
# worker. See bin/granian_shared_socket.py.
if [ "${POSTHOG_GRANIAN_SHARED_SOCKET:-false}" = "true" ]; then
    exec python ./bin/granian_shared_socket.py "$APP_TARGET"
fi

exec granian "$APP_TARGET"
