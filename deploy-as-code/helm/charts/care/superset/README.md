# Care Analytics Helm Chart

Apache Superset analytics platform for CARE HMIS, deployed with `/analytics` context path.

## Quick Start

```bash
# 1. Update dependencies
helm dependency update

# 2. Create secrets
kubectl create secret generic care-analytics-secret -n care \
  --from-literal=SECRET_KEY="$(openssl rand -base64 42)" \
  --from-literal=ADMIN_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=SQLALCHEMY_DATABASE_URI="postgresql://superset:pass@host:5432/superset" \
  --from-literal=DB_HOST="postgres-care-rw.care.svc.cluster.local" \
  --from-literal=DB_PORT="5432" \
  --from-literal=REDIS_HOST="redis.backbone.svc.cluster.local" \
  --from-literal=REDIS_PORT="6379"

# 3. Install chart
helm install care-analytics . --namespace care --values custom-values.yaml
```

## Documentation

Full installation and configuration guide: `/Users/jagankumar/Office/Work/repo/Care/care-learnings/care_superset/helm-chart-guide.md`

## Components

- **Web**: Superset Flask app with Gunicorn + Nginx sidecar
- **Worker**: Celery async query execution
- **Beat**: Celery scheduled tasks
- **Init Job**: Database setup and migrations

## Configuration

Default context path: `/analytics`

Edit `values.yaml` or create `custom-values.yaml` to customize:
- Context path
- Resource limits
- Replicas
- Ingress settings
- Features flags

## Support

- [Apache Superset Docs](https://superset.apache.org/docs/intro)
- [CARE Learnings](~/Office/Work/repo/Care/care-learnings/care_superset/)
