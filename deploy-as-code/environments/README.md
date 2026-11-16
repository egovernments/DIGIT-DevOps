# DIGIT environments (Azure one-click)

One folder per team or product environment, holding **two files**. A team edits only `env.yaml`. `secrets.yaml` is generated for them and kept encrypted.

```
deploy-as-code/environments/
  _template/          starting point - placeholders only, never deployed
  <env>/
    env.yaml          THE file you edit: domain, chart repo, Azure names, sizing, Helm overrides
    secrets.yaml      generated, SOPS-encrypted with your team's own age key
```

The **folder name is the environment name**: it becomes the AKS cluster name and the Terraform state container prefix, and it must match the GitHub Environment name.

## Rules

- **No shared keys.** Each environment has its own age key, Azure service principal and generated secrets. `new-environment.sh` creates fresh passwords, encryption keys and an SSH deploy key for every environment. Never copy `secrets.yaml` between environments.
- **One value, one place.** Values are never duplicated across files:

  | Value | Single source |
  |---|---|
  | environment / cluster name | folder name |
  | domain, chart repository, Azure names, sizing, Helm overrides | `env.yaml` |
  | Azure subscription | GitHub Environment secret `ARM_SUBSCRIPTION_ID` |
  | DB admin user + password, all other secrets | `secrets.yaml` (encrypted) |
  | DB host, DB name, filestore container | Terraform outputs, passed to helmfile at deploy time |

- **Secrets are only ever committed encrypted.** The workflow refuses to run if `secrets.yaml` is plaintext or still has `<placeholders>`.

## Create an environment

```bash
# 1. Your team's own age key. Keep the private key safe and never commit it.
age-keygen -o ~/.config/sops/age/<env>.txt        # prints "Public key: age1..."

# 2. Scaffold <env>/ with generated, encrypted secrets
deploy-as-code/environments/new-environment.sh <env> <age-public-key> [db-admin-user]

# 3. Edit <env>/env.yaml (the only file you change), then commit the folder
```

4. In GitHub, go to **Settings → Environments → New environment** and create `<env>`. Add these secrets: `SOPS_AGE_KEY` (the `AGE-SECRET-KEY-1...` line), `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID`. Optionally add required reviewers or restrict which branches can deploy.
5. Add the printed git-sync public key as a read-only deploy key on your MDMS/config repository.
6. Go to **Actions → DIGIT-Install workflow (Azure) → Run workflow** and pick `environment=<env>`:

| action | does |
|---|---|
| `install` | Terraform (state, AKS, PostgreSQL, filestore storage), then the helmfile deploy |
| `deploy` | helmfile deploy only, against existing infra (after changing `env.yaml`) |
| `destroy` | `terraform destroy`. Set `confirmDestroy` to the environment name. The resource group and state account are kept. |

To change a secret, for example real SMS provider credentials, run `export SOPS_AGE_KEY_FILE=~/.config/sops/age/<env>.txt` and then `sops deploy-as-code/environments/<env>/secrets.yaml`. Your key is recorded inside the file, so no `.sops.yaml` is needed. To rotate keys, run `sops rotate -i --add-age <new> --rm-age <old> <env>/secrets.yaml`, then update `SOPS_AGE_KEY`.
