# egovio/superset

`ghcr.io/care-ecosystem/superset` plus the six Python packages Superset needs
here, baked into `/python-packages` (first on `PYTHONPATH`).

Previously a `install-python-packages` init container ran `pip install` on every
pod start, so `superset-web`, `superset-worker`, `superset-beat` and the init
Job could not start unless `pypi.org` was reachable at that moment. On
2026-11-20 PyPI blocked unified-dev's egress IP (`20.198.126.49`) and all of
them hung in `Init:1/2` — silently, because a hung init container neither
crash-loops nor increments a restart counter, so nothing alerted.

## Rebuild

```bash
docker build --platform linux/amd64 -t egovio/superset:care-<YYYYMMDD> .
docker push egovio/superset:care-<YYYYMMDD>
```

Then bump `image.tag` in `../values.yaml`. Use a dated tag, never `:latest`.

Current: `egovio/superset:care-20261120`,
digest `sha256:abaac10d173af8b34efdc00fd6aff9720be0a4df6f30ec07b0c5dc1501fb4ff9`.

## Verifying a build

```bash
docker run --rm --platform linux/amd64 --entrypoint sh egovio/superset:care-<tag> -c '
  export PYTHONPATH="/python-packages:/app/pythonpath:$PYTHONPATH"
  python -c "
import psycopg2, clickhouse_connect, lz4, backports.zstd, joserfc, sqlalchemy
from authlib.integrations.flask_client import OAuth
assert sqlalchemy.__version__ == \"1.4.54\", sqlalchemy.__version__
print(\"ok\", sqlalchemy.__version__)"'
```

SQLAlchemy must stay **1.4.54**. The packages are installed `--no-deps` and
pinned precisely so `clickhouse-connect[sqlalchemy]` cannot pull 2.x over the
version Superset is built against.
