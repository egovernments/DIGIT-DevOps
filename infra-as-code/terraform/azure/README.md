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
