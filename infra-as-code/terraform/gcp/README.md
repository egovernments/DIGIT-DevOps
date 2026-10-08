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

## What's New in Kubernetes 1.35

Kubernetes 1.35 ("Timbernetes") upstream highlights relevant to DIGIT workloads (verify feature availability against the GKE 1.35 support matrix before relying on any of them):

- **cgroup v1 support removed**: nodes must run cgroup v2. GKE nodes use the `COS_CONTAINERD` image, which already runs cgroup v2, so default node pools need no action.
- **In-place Pod resource resize is GA**: adjust container CPU/memory without restarting the Pod.
- **PreferSameNode / PreferSameZone traffic distribution**: Services can prefer local endpoints first, reducing latency and cross-zone data cost.
- **kube-proxy IPVS mode deprecated**: nftables is the long-term replacement. GKE's default dataplane is unaffected.
- **kubeadm v1beta3 config API removed**: not used by the GKE managed control plane.
- **DRAResourceHealth v1alpha1 deprecated** (removal targeted for 1.40).
- Note: ingress-nginx receives best-effort maintenance only until March 2026; plan a migration path if DIGIT ingress relies on it.

Official release notes: https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/ · CHANGELOG: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.35.md · GKE Regular channel notes: https://docs.cloud.google.com/kubernetes-engine/docs/release-notes-regular

## Kubernetes 1.35 — Code Changes (GKE 1.34 → 1.35)

Code/config changes made for the 1.34 → 1.35 upgrade:

- `gke_version` default bumped from `1.34.8-gke.1000000` to `1.35.8-gke.1225000` in `variables.tf` (the GKE Regular channel default for 1.35 as of this change; a patch version must be used, not a bare `1.35`).
- The version is passed through to the GKE module as `k8s_version`, which sets `min_master_version` on the `google_container_cluster` resource. Node pools follow the control-plane version.
- Confirm the exact patch is still offered in your zones before applying; GKE rolls patch versions out over several days. Pick the current Regular channel 1.35 patch from the release notes if `1.35.8-gke.1225000` is no longer available.

## Upgrading from 1.34 to 1.35

> GKE upgrades one minor version at a time. A cluster must be on **1.34** before moving to **1.35**.

1. **Bump the version** — set `gke_version` to a valid 1.35 patch (default `1.35.8-gke.1225000`).
2. **Upgrade the control plane**
   ```bash
   terraform init
   terraform plan  -var='db_password=<password>'
   terraform apply -var='db_password=<password>'
   ```
3. **Upgrade the node pool(s)** — after `min_master_version` is raised, roll the managed node pool to the matching 1.35 node version.
4. **Validate**
   ```bash
   kubectl get nodes     # every node reports v1.35.x
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

- `gke_version` defaults to `1.35.8-gke.1225000`.
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
