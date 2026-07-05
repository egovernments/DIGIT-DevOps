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
