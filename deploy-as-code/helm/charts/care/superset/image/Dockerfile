# egovio/superset -- ghcr.io/care-ecosystem/superset with the six Python
# packages the Helm chart used to pip-install at pod start, baked in.
#
# Why: the chart's install-python-packages init container ran
#   pip install --target=/python-packages --no-deps <packages>
# on EVERY pod start, so web/worker/beat could not start unless pypi.org was
# reachable at that moment. On 2026-11-20 unified-dev's egress IP
# (20.198.126.49) was blocked by PyPI and all three pods hung in Init:1/2 with
# no crash-loop and no alert. Baking removes the startup dependency on a third
# party and makes the image reproducible.
#
# Built FROM the pinned digest below, not :latest, so this image is rebuildable.
FROM ghcr.io/care-ecosystem/superset@sha256:6a64c08b13838b6caa3b69f6a33f66772106cb3b2065cb4aec8340ecaf0927e5

USER root

# Installed with the SYSTEM pip (/usr/local/bin/pip, python 3.11) into
# /python-packages -- identical to what the init container produced. The venv
# at /app/.venv is uv-built and ships no pip; both interpreters are 3.11, so
# the --target layout is importable from either.
#
# --no-deps and the pins are load-bearing: clickhouse-connect[sqlalchemy]
# would otherwise pull SQLAlchemy 2.x over the 1.4.54 Superset is built
# against. lz4 and backports.zstd are clickhouse-connect's compression codecs.
# authlib + joserfc are required by AUTH_TYPE = AUTH_OAUTH (FAB's
# BaseSecurityManager imports authlib.integrations.flask_client at init).
RUN pip install --no-cache-dir --target=/python-packages --no-deps \
      psycopg2-binary==2.9.13 \
      clickhouse-connect==1.13.0 \
      lz4==4.4.5 \
      backports.zstd==1.8.0 \
      authlib==1.9.8 \
      joserfc==1.8.0 \
 && chown -R 1000:1000 /python-packages

USER superset
