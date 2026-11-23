#!/bin/sh
# Superset functional check (digit3/analytics/superset), run by Kargo verification
# after a promotion and on every "Reverify".
#
# Env:  NS               namespace of the release
#       RELEASE          Deployment prefix (default superset -> superset-web/-worker/-beat)
#       EXPECTED_TAG     image tag the promotion wrote ("" = do not wait for a tag)
#       TIMEOUT          seconds for the whole check
#       PUBLIC_URL       https://<host> of the ingress ("" = skip the external checks)
#       CLICKHOUSE_URL   http://<svc>:8123 Superset must reach ("" = skip)
#       ADMIN_USERNAME   account the init job creates ("" = skip)
#
# Read-only: it reads Deployments/Pods/ConfigMaps and execs short Python snippets in the
# web container. Nothing that loads the Superset app runs in a pod (that needs ~700 MB
# and would OOM a worker), and no secret is read or printed -- the snippets use the
# container's own environment.
set -u
REL=${RELEASE:-superset}
TIMEOUT=${TIMEOUT:-600}
deadline=$(( $(date +%s) + TIMEOUT ))
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
left() { r=$(( deadline - $(date +%s) )); [ "$r" -lt 10 ] && r=10; echo "$r"; }

echo "== Superset in namespace $NS (release $REL)"

# 1. Every Deployment runs the promoted image and has fully rolled out.
for c in web worker beat; do
  d="$REL-$c"
  if [ -n "${EXPECTED_TAG:-}" ]; then
    while :; do
      img=$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
      img=${img%%@*}
      [ "${img##*:}" = "$EXPECTED_TAG" ] && break
      [ "$(date +%s)" -ge "$deadline" ] && break
      sleep 10
    done
    [ "${img##*:}" = "$EXPECTED_TAG" ] || { fail "$d runs '${img:-<missing>}', expected tag $EXPECTED_TAG"; continue; }
  fi
  if kubectl -n "$NS" rollout status "deploy/$d" --timeout="$(left)s" >/dev/null 2>&1; then
    pass "$d rolled out ($(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.status.availableReplicas}') available)"
  else
    fail "$d did not finish rolling out"
  fi
done
[ "$fails" -eq 0 ] || { echo "RESULT: $fails check(s) failed"; exit 1; }

# 2. Inside the web container: the app, its metadata DB, Redis, Celery, drivers, ClickHouse.
celery_db=$(kubectl -n "$NS" get cm "$REL-config" -o jsonpath='{.data.superset_config\.py}' 2>/dev/null \
  | sed -n 's/^REDIS_CELERY_DB *= *"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' | head -1)
# Python on stdin; a function keeps the here-document out of $(...).
inpod() { cat <<'PY'
import glob, importlib.util, os, re, urllib.request

def res(ok, msg):
    print(("PASS: " if ok else "FAIL: ") + msg)

def get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, r.read(4000).decode(errors="replace").strip()

# gunicorn health endpoint (SUPERSET_PORT can be a Service link like tcp://..., so check it)
port = os.environ.get("SUPERSET_PORT", "8088")
port = port if port.isdigit() else "8088"
try:
    s, b = get(f"http://127.0.0.1:{port}/health")
    res(s == 200 and b == "OK", f"web /health -> {s} {b[:20]}")
except Exception as e:
    res(False, f"web /health: {e}")

# metadata database: reachable, migrated to the image's head revision, initialised
try:
    import sqlalchemy as sa
    spec = importlib.util.find_spec("superset")
    vdir = os.path.join(list(spec.submodule_search_locations)[0], "migrations", "versions")
    revs, downs = set(), set()
    for f in glob.glob(vdir + "/*.py"):
        t = open(f, encoding="utf-8").read()
        m = re.search(r'^revision\s*=\s*["\'](\w+)["\']', t, re.M)
        if m:
            revs.add(m.group(1))
            d = re.search(r'^down_revision\s*=\s*(.+)$', t, re.M)
            if d:
                downs.update(re.findall(r'["\'](\w+)["\']', d.group(1)))
    heads = revs - downs
    eng = sa.create_engine(os.environ["SQLALCHEMY_DATABASE_URI"], pool_pre_ping=True)
    with eng.connect() as c:
        cur = set(c.execute(sa.text("select version_num from alembic_version")).scalars())
        res(bool(cur) and cur == heads,
            f"metadata DB migrated: at {sorted(cur)}, image head {sorted(heads)}")
        roles = {r[0] for r in c.execute(sa.text("select name from ab_role"))}
        need = {"Admin", "Alpha", "Gamma", "sql_lab"}
        res(need <= roles, f"superset init ran: roles {sorted(roles)}")
        u = os.environ.get("ADMIN_USERNAME")
        if u:
            n = c.execute(sa.text("select count(*) from ab_user where username = :u and active"), {"u": u}).scalar()
            res(n == 1, f"admin account '{u}' exists and is active")
except Exception as e:
    res(False, f"metadata DB: {type(e).__name__}: {str(e).splitlines()[0][:200]}")

# Redis (cache, results, Celery broker)
try:
    import redis
    r = redis.Redis(host=os.environ["REDIS_HOST"], port=int(os.environ["REDIS_PORT"]),
                    password=os.environ.get("REDIS_PASSWORD") or None, socket_timeout=5)
    res(r.ping(), f"Redis {os.environ['REDIS_HOST']}:{os.environ['REDIS_PORT']} answers PING")
except Exception as e:
    res(False, f"Redis: {e}")

# Celery: a worker answers on the broker (plain Celery client, does not load Superset)
try:
    from celery import Celery
    auth = f":{os.environ['REDIS_PASSWORD']}@" if os.environ.get("REDIS_PASSWORD") else ""
    app = Celery(broker=f"redis://{auth}{os.environ['REDIS_HOST']}:{os.environ['REDIS_PORT']}/{os.environ['CELERY_DB']}")
    replies = app.control.ping(timeout=5) or []
    res(len(replies) > 0, f"Celery workers answering: {len(replies)}")
except Exception as e:
    res(False, f"Celery ping: {e}")

# database drivers baked into the image
for mod in ("psycopg2", "clickhouse_connect"):
    try:
        __import__(mod)
        res(True, f"driver {mod} importable")
    except Exception as e:
        res(False, f"driver {mod}: {e}")
try:
    from sqlalchemy.dialects import registry
    registry.load("clickhousedb")
    res(True, "SQLAlchemy dialect clickhousedb:// registered")
except Exception as e:
    res(False, f"dialect clickhousedb: {e}")

# ClickHouse reachable from Superset over HTTP
ch = os.environ.get("CH_URL")
if ch:
    try:
        s, b = get(ch.rstrip("/") + "/ping")
        res(s == 200 and b == "Ok.", f"ClickHouse {ch} /ping -> {s} {b}")
    except Exception as e:
        res(False, f"ClickHouse {ch}: {e}")
PY
}
out=$(inpod | kubectl -n "$NS" exec -i "deploy/$REL-web" -c superset -- \
  env CELERY_DB="${celery_db:-0}" CH_URL="${CLICKHOUSE_URL:-}" ADMIN_USERNAME="${ADMIN_USERNAME:-}" \
  sh -c 'PY=/app/.venv/bin/python3; [ -x "$PY" ] || PY=python3; [ -d /python-packages ] && export PYTHONPATH="/python-packages:${PYTHONPATH:-}"; exec "$PY" -' 2>&1)
echo "$out"
fails=$(( fails + $(echo "$out" | grep -c '^FAIL:') ))
echo "$out" | grep -q '^PASS: web /health' || fail "the in-pod checks did not run"

# 3. From outside the cluster network path: ingress, TLS, login page, API auth.
if [ -n "${PUBLIC_URL:-}" ]; then
  u=${PUBLIC_URL%/}
  b=$(curl -sS --max-time 15 "$u/health" 2>&1); s=$?
  [ $s -eq 0 ] && [ "$b" = "OK" ] && pass "$u/health -> OK (valid TLS)" || fail "$u/health -> curl exit $s: $(echo "$b" | head -c 120)"
  c=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$u/login/" 2>/dev/null)
  [ "$c" = "200" ] && pass "$u/login/ -> 200" || fail "$u/login/ -> $c"
  c=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$u/api/v1/database/" 2>/dev/null)
  [ "$c" = "401" ] && pass "$u/api/v1/database/ without a session -> 401 (auth enforced)" || fail "$u/api/v1/database/ without a session -> $c, expected 401"
fi

if [ "$fails" -eq 0 ]; then echo "RESULT: Superset is configured and ready to use"; exit 0; fi
echo "RESULT: $fails check(s) failed"; exit 1
