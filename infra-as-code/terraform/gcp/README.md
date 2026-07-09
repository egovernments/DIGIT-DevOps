# GCP Terraform

This directory provisions the GCP infrastructure required for a DIGIT environment.

## Release Highlights

- Adds a GCS backend configuration for Terraform state.
- Adds `remote-state/` resources for the Terraform state bucket.
- Enables required GCP APIs for Compute Engine, GKE, Service Networking, and Cloud SQL.
- Provisions a VPC, public subnet, private subnet, private service access, and firewall rules through `../modules/network/gcp`.
- Provisions private Cloud SQL for PostgreSQL through `../modules/db/gcp`.
- Provisions GKE through `../modules/kubernetes/gcp`.
- Enables Workload Identity and creates a managed GKE node pool.
- Adds CMEK resources and a Kubernetes storage class for GKE persistent disks.
- Creates an S3-compatible GCS service account and HMAC key flow for applications that use AWS SDK style storage access.

## What's New in Kubernetes 1.34

Upstream highlights relevant to DIGIT workloads (verify feature availability against the GKE 1.34 support matrix before relying on any of them):

- **Dynamic Resource Allocation (DRA) core is GA** — standardized requesting and sharing of GPUs and other specialized devices.
- **In-place Pod vertical resource resize** continues to mature — adjust container CPU/memory without a restart.
- **Pod-level resource requests and limits** — resources can be declared at the Pod scope, not only per container.
- **Structured authentication configuration** graduated — cleaner multi-issuer / OIDC auth.
- **Ordered (orderly) namespace deletion** — safer teardown order for namespaced objects.
- **Fine-grained SupplementalGroups control** for Pod security.
- **KYAML** — a stricter, safer YAML output format available in `kubectl`.
- **`.kuberc`** — user-level `kubectl` preferences file.
- Continued API deprecations/removals; the in-tree cloud provider is no longer used (external cloud controllers are standard).

Official release notes: https://kubernetes.io/blog/2025/08/27/kubernetes-v1-34-release/ · CHANGELOG: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.34.md

## Kubernetes 1.34 — Code Changes (GKE → 1.34)

Code/config changes made for the 1.34 upgrade:

- `gke_version` default bumped from `1.32.2-gke.1182003` to `1.34.8-gke.1000000` in `variables.tf`.
- The version is passed through to the GKE module as `k8s_version`, which sets `min_master_version` on the `google_container_cluster` resource. Node pools follow the control-plane version.

## Upgrading from 1.33 to 1.34

> GKE upgrades one minor version at a time. A cluster must be on **1.33** before moving to **1.34**. Note the previous baseline here was `1.32.x`, so a `1.32 → 1.33 → 1.34` sequence is required — do not jump straight to 1.34.

1. **Bump the version** — set `gke_version` to a valid 1.34 patch (default `1.34.8-gke.1000000`). If stepping up from 1.32, apply an intermediate 1.33 patch first.
2. **Upgrade the control plane**
   ```bash
   terraform init
   terraform plan  -var='db_password=<password>'
   terraform apply -var='db_password=<password>'
   ```
3. **Upgrade the node pool(s)** — after `min_master_version` is raised, roll the managed node pool to the matching 1.34 `node_version`.
5. **Validate**
   ```bash
   kubectl get nodes     # every node reports v1.34.x
   kubectl version
   kubectl get pods -A
   ```

## Important Inputs

Update `input.yaml` first. The values are substituted into Terraform placeholders by the init helper.

Required values:

- `GCP_PROJECT_ID`: GCP project ID.
- `GCP_REGION`: GCP region.
- `GCP_AVAILABILITY_ZONE`: GCP zone.
- `ENVIRONMENT_NAME`: GKE cluster and environment name.
- `DATABASE_NAME`: PostgreSQL database name.
- `DATABASE_USERNAME`: PostgreSQL admin user.
- `terraform_state_bucket_name`: GCS bucket used for Terraform state.

Review `variables.tf` for version and sizing defaults before applying:

- `gke_version` defaults to `1.34.8-gke.1000000`.
- `db_version` defaults to `POSTGRES_15`.
- `node_machine_type` defaults to `n2d-highmem-2`.
- `desired_node_count` defaults to `3`.
- `min_node_count` defaults to `3`.
- `max_node_count` defaults to `4`.
- `gke_cmek_storage_class_name` defaults to `gke-cmek-rwo`.

`db_password` is intentionally not stored in `input.yaml`; provide it at plan or apply time.

## Usage

Run the init helper from this directory after updating `input.yaml`:

```bash
cd infra-as-code/terraform/gcp
go run ../scripts/init.go
```

Create the remote-state resources first:

```bash
cd remote-state
terraform init
terraform plan
terraform apply
```

Then provision the GCP infrastructure:

```bash
cd ..
terraform init
terraform plan -var='db_password=<password>'
terraform apply -var='db_password=<password>'
```

The GCP apply creates local key files for the S3-compatible GCS flow:

- `hmac-key.json`
- `gcs-hmac-key.json`

Treat these files as secrets.

## Outputs

Key outputs include:

- `cluster_name`
- `cluster_endpoint`
- `db_instance_name`
- `db_instance_private_ip`
- `db_name`
- `db_username`
