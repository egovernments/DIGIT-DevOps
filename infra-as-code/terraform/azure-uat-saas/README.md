# Azure Terraform

This directory provisions the Azure infrastructure required for a DIGIT environment.


## Release Highlights

- Adds a provider-level Azure entrypoint in `main.tf`.
- Adds an Azure Storage backend configuration for Terraform state.
- Adds `remote-state/` resources for the resource group, storage account, and state container.
- Creates a virtual network with a dedicated AKS subnet.
- Adds NAT gateway resources for outbound access from the AKS subnet.
- Provisions AKS through `../modules/kubernetes/azure`, with the OIDC issuer and
  workload identity enabled (ArgoCD SOPS decryption and Vault auto-unseal depend on them).
- Adds validation for the Azure environment and resource group inputs.

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
   terraform plan
   terraform apply
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

Review `variables.tf` for version and sizing defaults before applying:

- `kubernetes_version` defaults to `1.34`.
- `vm_size` defaults to `Standard_D4as_v5`.
- `node_count` defaults to `4`.
- `os_disk_size_gb` defaults to `64`.

## Usage

Run the init helper from this directory after updating `input.yaml`:

```bash
cd infra-as-code/terraform/azure-uat-saas
go run ../scripts/init.go
```

The remote-state resources already exist for this environment and their state is
stored in the backend, so just initialise against it:

```bash
cd remote-state
terraform init
terraform plan    # expect: No changes
```

> For a brand-new environment only: comment out the `backend "azurerm"` block in
> `remote-state/main.tf`, run `terraform init && terraform apply` against the local
> backend to create the resource group, storage account, and container, then restore
> the block with the generated storage account name and run
> `terraform init -migrate-state` to move the state into it.

Then provision the Azure infrastructure:

```bash
cd ..
terraform init
terraform plan
terraform apply
```

## Authentication

Terraform runs against this environment as the **`uat-saas-admin`** service principal
(app ID `96b68946-6a6b-4112-99bf-8fd07ec9b423`), following the same per-environment
convention as `digit-lts-admin`.

```bash
export ARM_CLIENT_ID=96b68946-6a6b-4112-99bf-8fd07ec9b423
export ARM_CLIENT_SECRET=<from vault>
export ARM_TENANT_ID=593ce202-d1a9-4760-ba26-ae35417c00cb
export ARM_SUBSCRIPTION_ID=777e3e4b-0998-4759-adc2-e7b5b19a6b28
```

Role assignments, both scoped to the `uat-saas` resource group rather than the
subscription, so the credential cannot reach other environments:

| Role | Why |
| --- | --- |
| `Contributor` | Manages the resources, and supplies `listKeys` for backend auth |
| `User Access Administrator` | Required by `azurerm_role_assignment.aks_subnet_network_contributor` |

Because the grant is resource-group scoped, this principal **cannot create the resource
group itself** — a from-scratch bootstrap needs a subscription-scoped identity.

> The client secret expires **2027-11-10**. Rotate before then; an expired credential
> fails with an opaque authentication error rather than an expiry message.

The identity is never recorded in Terraform state, so switching between this service
principal and a user account is purely a matter of which environment variables are set.
It requires no state changes and disturbs no resources.

## Outputs

Key outputs include:

- `resource_group`
- `cluster_name`

The `remote-state` configuration outputs `azure_storage_account`.

## State layout

Both configurations share one container, under distinct keys:

| Configuration | Backend key |
| --- | --- |
| `azure-uat-saas/` | `terraform.tfstate` |
| `azure-uat-saas/remote-state/` | `bootstrap.tfstate` |

Container `uat-saas-container` in storage account `tfstate0znm8` (resource group `uat-saas`).

Because the bootstrap state lives inside the storage account it manages, never run
`terraform destroy` in `remote-state/` — it would delete the account holding its own state.
