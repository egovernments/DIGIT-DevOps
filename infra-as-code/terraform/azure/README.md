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

## What's New in Kubernetes 1.35

Kubernetes 1.35 ("Timbernetes") upstream highlights relevant to DIGIT workloads (verify feature availability against the AKS 1.35 support matrix before relying on any of them):

- **cgroup v1 support removed**: nodes must run cgroup v2. AKS satisfies this because upgrading to 1.35 or higher automatically migrates Ubuntu node pools to Ubuntu 24.04, which uses cgroup v2.
- **In-place Pod resource resize is GA**: adjust container CPU/memory without restarting the Pod.
- **PreferSameNode / PreferSameZone traffic distribution**: Services can prefer local endpoints first, reducing latency and cross-zone data cost.
- **kube-proxy IPVS mode deprecated**: nftables is the long-term replacement. The default AKS kube-proxy configuration is unaffected.
- **kubeadm v1beta3 config API removed**: not used by the AKS managed control plane.
- **DRAResourceHealth v1alpha1 deprecated** (removal targeted for 1.40).
- Note: ingress-nginx receives best-effort maintenance only until March 2026; plan a migration path if DIGIT ingress relies on it.

AKS added 1.35 in preview in February 2026 and reached GA in March 2026 (it is also an AKS LTS version); confirm it is available in your region and offering before upgrading.

Official release notes: https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/ · CHANGELOG: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.35.md · AKS supported versions: https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions

## Kubernetes 1.35 — Code Changes (AKS 1.34 → 1.35)

Code/config changes made for the 1.34 → 1.35 upgrade:

- `kubernetes_version` default set to `1.35` in `variables.tf`.
- The version is applied on the `azurerm_kubernetes_cluster` resource via `kubernetes_version = var.kubernetes_version`, which upgrades the AKS control plane.
- The `mainpool` user node pool tracks the control-plane version through `orchestrator_version = var.kubernetes_version`, so it rolls to 1.35 after the control plane. Expect the Ubuntu node image to migrate to Ubuntu 24.04 during this roll.

## Upgrading from 1.34 to 1.35

> AKS upgrades one minor version at a time. The cluster must already be on **1.34** before upgrading to **1.35**.

1. **Bump the version** — `kubernetes_version = "1.35"` (already the default in `variables.tf`).
2. **Upgrade the control plane**
   ```bash
   terraform init
   terraform plan  -var='db_password=<password>'
   terraform apply -var='db_password=<password>'
   ```
3. **Upgrade the node pool(s)** — the node pool `orchestrator_version` follows `kubernetes_version`, so nodes roll to 1.35 (and to the Ubuntu 24.04 node image) after the control plane. Drain/surge happens one node at a time.
4. **Validate**
   ```bash
   kubectl get nodes     # every node reports v1.35.x
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

- `kubernetes_version` defaults to `1.35`.
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
