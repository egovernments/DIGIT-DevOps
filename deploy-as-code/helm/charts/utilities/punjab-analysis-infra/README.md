# Punjab Analysis Infrastructure Chart

## Overview

This Helm chart creates the Kubernetes infrastructure resources required for the Punjab Property Tax Analysis pipeline that runs on Airflow.

## What This Chart Creates

### 1. ServiceAccount

- **Name**: `airflow-worker`
- **Namespace**: `egov`
- **Purpose**: Used by Airflow KubernetesPodOperator to create pods in the egov namespace

### 2. RBAC (Role-Based Access Control)

- **Role**: `airflow-worker-role` - Grants permissions to:
  - Create, list, watch, delete pods
  - Access pod logs and exec into pods
  - Read PVCs, ConfigMaps, and Secrets
- **RoleBindings**:
  - `airflow-worker-rolebinding` - Binds the role to airflow-worker ServiceAccount
  - `airflow-to-egov-binding` - Allows Airflow scheduler (in airflow namespace) to create pods in egov namespace

### 3. Persistent Volume Claims (PVCs)

- **punjab-data-pvc** (10Gi, ReadWriteMany)
  - Stores extracted data from PostgreSQL
  - Shared across extract and analyze tasks
- **punjab-output-pvc** (5Gi, ReadWriteMany)
  - Stores generated Excel reports
  - Shared across analyze and upload tasks
- **punjab-secrets-pvc** (1Gi, ReadWriteOnce)
  - Stores database configuration (db_config.yaml)
  - Mounted by all analysis pods

### 4. ConfigMap (Optional)

- **punjab-analysis-config** - Contains database and filestore configuration
- **Note**: Disabled by default (`createConfigMap: false`)
- **Recommendation**: Use PVC-based configuration for better security

## Configuration

### Enable/Disable Chart

```yaml
punjab-analysis-infra:
  enabled: true # Set to false to skip resource creation
```

### Namespace Configuration

```yaml
punjab-analysis-infra:
  namespace: egov # Change this if using a different namespace
```

### PVC Storage Configuration

```yaml
punjab-analysis-infra:
  persistentVolumes:
    punjab-data-pvc:
      size: 10Gi # Adjust based on data volume
      storageClassName: gp3 # Change based on your cluster
      accessModes:
        - ReadWriteMany # Required for multi-pod access
```

## Deployment

### Using Helmfile (Recommended)

1. **Update environment file** (`environments/unified-dev.yaml`):

```yaml
punjab-analysis-infra:
  enabled: true
```

2. **Deploy using helmfile**:

```bash
cd deploy-as-code/helm
helmfile -e unified-dev sync
```

### Using Helm Directly

```bash
cd deploy-as-code/helm/charts/utilities/punjab-analysis-infra

# Install
helm install punjab-analysis-infra . \
  --namespace egov \
  --create-namespace \
  --values values.yaml

# Upgrade
helm upgrade punjab-analysis-infra . \
  --namespace egov \
  --values values.yaml
```

## Verification

After deployment, verify resources were created:

```bash
# Check ServiceAccount
kubectl get sa airflow-worker -n egov

# Check RBAC
kubectl get role airflow-worker-role -n egov
kubectl get rolebinding -n egov | grep airflow

# Check PVCs
kubectl get pvc -n egov | grep punjab

# Expected output:
# punjab-data-pvc     Bound    ...   10Gi   RWX   gp3
# punjab-output-pvc   Bound    ...   5Gi    RWX   gp3
# punjab-secrets-pvc  Bound    ...   1Gi    RWO   gp3
```

## Post-Deployment Steps

### 1. Upload Database Configuration

Create `db_config.yaml` with your database credentials:

```yaml
database:
  host: "unified-dev-db-new.czvokiourya9.ap-south-1.rds.amazonaws.com"
  port: 5432
  database: "unifieddevdb"
  username: "your_username"
  password: "your_password"

filestore:
  service_url: "http://egov-filestore.egov:8080/"
  upload_endpoint: "/filestore/v1/files"
  auth_token: ""
  tenant_id: "pb"
  module: "punjab-analysis"

tenants:
  - pb.adampur
  - pb.samana
  # ... add all tenants
```

Upload to PVC:

```bash
# Create uploader pod
kubectl run config-uploader --image=busybox \
  --restart=Never -n egov \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "uploader",
      "image": "busybox",
      "command": ["sleep", "3600"],
      "volumeMounts": [{
        "name": "secrets",
        "mountPath": "/secrets"
      }]
    }],
    "volumes": [{
      "name": "secrets",
      "persistentVolumeClaim": {
        "claimName": "punjab-secrets-pvc"
      }
    }]
  }
}'

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/config-uploader -n egov

# Copy config
kubectl cp db_config.yaml egov/config-uploader:/secrets/db_config.yaml

# Verify
kubectl exec -n egov config-uploader -- cat /secrets/db_config.yaml

# Cleanup
kubectl delete pod config-uploader -n egov
```

### 2. Deploy Airflow DAG

Upload the Punjab Analysis DAG to Airflow:

```bash
# Get scheduler pod
SCHEDULER_POD=$(kubectl get pods -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}')

# Copy DAG file
kubectl cp punjab_analysis_kubernetes_dag.py airflow/$SCHEDULER_POD:/opt/airflow/dags/ -c scheduler

# Set Airflow variables
kubectl exec -n airflow $SCHEDULER_POD -c scheduler -- \
  airflow variables set punjab_analysis_image "egovio/punjab-analysis:latest"

kubectl exec -n airflow $SCHEDULER_POD -c scheduler -- \
  airflow variables set punjab_analysis_namespace "egov"
```

## Troubleshooting

### PVCs Not Binding

**Issue**: PVCs stuck in `Pending` state

**Check**:

```bash
kubectl describe pvc punjab-data-pvc -n egov
```

**Common Causes**:

- Storage class `gp3` not available in your cluster
- No available storage provisioner
- Insufficient storage capacity

**Solution**:

```yaml
# Change storageClassName in values.yaml or environment config
persistentVolumes:
  punjab-data-pvc:
    storageClassName: standard # or your cluster's default
```

### Permission Denied When Creating Pods

**Issue**: Airflow cannot create pods in egov namespace

**Check**:

```bash
kubectl auth can-i create pods \
  --as=system:serviceaccount:airflow:airflow-scheduler \
  -n egov
```

**Solution**: Ensure cross-namespace RoleBinding was created:

```bash
kubectl get rolebinding airflow-to-egov-binding -n egov
```

### Config File Not Found

**Issue**: Analysis pods cannot find `/secrets/db_config.yaml`

**Check**:

```bash
# Verify config exists in PVC
kubectl run -it --rm debug --image=busybox -n egov \
  --overrides='...' -- cat /secrets/db_config.yaml
```

**Solution**: Upload config file following Post-Deployment Steps above

## Related Documentation

- **Application Code**: `health-campaign-services/utilities/analysis-report/`
- **Airflow DAG**: `health-campaign-services/utilities/airflow-dags/dags/punjab_analysis_kubernetes_dag.py`
- **Docker Image**: `egovio/punjab-analysis`

## Support

For issues or questions:

1. Check Airflow scheduler logs: `kubectl logs -n airflow $SCHEDULER_POD -c scheduler`
2. Check analysis pod logs: `kubectl logs -n egov <pod-name>`
3. Verify RBAC permissions
4. Ensure all PVCs are bound

## Maintainers

- DIGIT DevOps Team
