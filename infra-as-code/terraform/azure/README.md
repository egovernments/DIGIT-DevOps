# Azure Terraform

This directory provisions the Azure infrastructure required for a DIGIT environment.


## Release Highlights

- Adds a provider-level Azure entrypoint in `main.tf`.
- Adds an Azure Storage backend configuration for Terraform state.
- Adds `remote-state/` resources for the resource group, storage account, and state container.
- Creates a virtual network with dedicated AKS and PostgreSQL subnets.
- Adds NAT gateway resources for outbound access from the AKS subnet.
- Provisions AKS through `../modules/kubernetes/azure`.
- Provisions PostgreSQL Flexible Server through `../modules/db/azure`.
- Adds private DNS zone wiring for PostgreSQL.
- Adds validation for Azure environment, resource group, database user, and database password inputs.

## What's New in Kubernetes 1.34

Upstream highlights relevant to DIGIT workloads (verify feature availability against the AKS 1.34 support matrix before relying on any of them):

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

## Kubernetes 1.34 — Code Changes (AKS 1.33 → 1.34)

Code/config changes made for the 1.33 → 1.34 upgrade:

- `kubernetes_version` default set to `1.34` in `variables.tf`.
- The version is applied on the `azurerm_kubernetes_cluster` resource via `kubernetes_version = var.kubernetes_version`, which upgrades the AKS control plane.
- The default node pool tracks the control-plane version; keep its `orchestrator_version` aligned with `kubernetes_version` (AKS upgrades the control plane first, then node pools).

## Upgrading from 1.33 to 1.34

> AKS upgrades one minor version at a time. The cluster must already be on **1.33** before upgrading to **1.34**.

1. **Bump the version** — `kubernetes_version = "1.34"` (already the default in `variables.tf`).
2. **Upgrade the control plane**
   ```bash
   terraform init
   terraform plan  -var='db_password=<password>'
   terraform apply -var='db_password=<password>'
   ```
3. **Upgrade the node pool(s)** — ensure the default node pool `orchestrator_version` is set to 1.34 so nodes roll to the new version after the control plane.
4. **Validate**
   ```bash
   kubectl get nodes     # every node reports v1.34.x
   kubectl version
   kubectl get pods -A
   ```

## Important Inputs

Update `input.yaml` first. The values are substituted into Terraform placeholders by the init helper.

Required values:

- `environment`: AKS cluster and environment name.
- `resource_group`: Azure resource group name.
- `location`: Azure region.
- `subscription_id`: Azure subscription ID.
- `db_user`: PostgreSQL admin user.

Review `variables.tf` for version and sizing defaults before applying:

- `kubernetes_version` defaults to `1.34`.
- `db_version` defaults to `15`.
- `vm_size` defaults to `standard_e2s_v3`.
- `node_count` defaults to `3`.
- `db_sku_name` defaults to `B_Standard_B2ms`.
- `db_storage_mb` defaults to `65536`.

`db_password` is intentionally not stored in `input.yaml`; provide it at plan or apply time.

## Usage

Run the init helper from this directory after updating `input.yaml`:

```bash
cd infra-as-code/terraform/azure
go run ../scripts/init.go
```

Create the remote-state resources first:

```bash
cd remote-state
terraform init
terraform plan
terraform apply
```

Use the generated storage account name from the remote-state output or Azure portal to update the backend placeholder in `main.tf` if needed, then provision the Azure infrastructure:

```bash
cd ..
terraform init
terraform plan -var='db_password=<password>'
terraform apply -var='db_password=<password>'
```

## Outputs

Key outputs include:

- `resource_group`
- `cluster_name`
- `azurerm_postgresql_flexible_server`
- `postgresql_flexible_server_database_name`
- `db_user`
