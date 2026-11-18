# Install DIGIT on Azure in one click

You copy this project, fill in **one file** (`one-click/input.yaml`), add **one secret**, and click **one button**.
You do not need to install anything on your computer.

This guide has two parts:

- **Part 1 - Steps** (for people). Do them in order.
- **Part 2 - Reference** (exact rules for every file, setting and secret). Use it when you
  want more than the basics, or when an AI assistant prepares the files for you.

---

# Part 1 - Steps

## What you need

1. A **GitHub** account.
2. An **Azure** subscription where you are an **Owner** (or **User Access Administrator**),
   so you can create the key in step 3. The key itself gets much less than Owner.
3. A **domain name** you own, for example `digit.example.com`. You must be able to add a
   DNS record for it at the website where you bought it.

## Step 1. Copy (fork) this project

1. Open https://github.com/egovernments/DIGIT-DevOps
2. Click **Fork** (top right), then **Create fork**.

You now have your own copy at `https://github.com/<your-name>/DIGIT-DevOps`.
**Do every next step in your own copy.** Never change the original project.

## Step 2. Turn on Actions in your copy

1. In your copy, click the **Actions** tab.
2. Click the green button **I understand my workflows, go ahead and enable them**.

## Step 3. Make a key for Azure

1. Open https://shell.azure.com and sign in. If it asks, choose **Bash**.
2. Copy this whole block, paste it into the window, and press **Enter**:

   ```bash
   SUB=$(az account show --query id -o tsv)
   CREDS=$(az ad sp create-for-rbac --name digit-one-click --role Contributor --scopes "/subscriptions/$SUB" --json-auth)
   APP=$(echo "$CREDS" | jq -r .clientId)
   for _ in 1 2 3 4 5 6 7 8 9 10; do OID=$(az ad sp show --id "$APP" --query id -o tsv 2>/dev/null) && [ -n "$OID" ] && break; sleep 10; done
   NC=$(az role definition list --name "Network Contributor" --query [0].name -o tsv)
   AKSC=$(az role definition list --name "Azure Kubernetes Service Contributor Role" --query [0].name -o tsv)
   COND="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$NC, $AKSC})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$NC, $AKSC}))"
   az role assignment create --assignee-object-id "$OID" --assignee-principal-type ServicePrincipal \
     --role "Role Based Access Control Administrator" --scope "/subscriptions/$SUB" \
     --condition "$COND" --condition-version 2.0 -o none && echo "$CREDS"
   ```

3. It prints text that starts with `{` and ends with `}`. Copy **all** of it.

> Keep this text secret. Paste it only in step 4.

What this key may do: create and change resources (**Contributor**), and give out only two
small roles that the install needs (**Network Contributor** and **Azure Kubernetes Service
Contributor Role**). It cannot make anyone Owner. Details: [Part 2, `AZURE_CREDENTIALS`](#azure_credentials-repository-secret-required).

If your Azure admin prefers one simple line, an **Owner** key also works:
`az ad sp create-for-rbac --name digit-one-click --role Owner --scopes /subscriptions/$(az account show --query id -o tsv) --json-auth`

## Step 4. Save the key in your copy

1. In your copy, click **Settings**, then on the left **Secrets and variables**, then **Actions**.
2. Click **New repository secret**.
3. **Name:** `AZURE_CREDENTIALS`
4. **Secret:** paste the text from step 3.
5. Click **Add secret**.

## Step 5. Fill in input.yaml

1. In your copy, open the folder **`one-click/`** and click **`input.yaml`**.
2. Click the **pencil** icon (Edit).
3. Change these 3 lines. Keep the quotes `" "`.

   ```yaml
   environment: "team-a-digit"       # a short name: 3-20 small letters, numbers or -
   domain: "digit.example.com"       # your domain
   email: "you@example.com"          # your e-mail
   ```

4. **Choose how DIGIT is deployed** (you cannot change this after the install):

   ```yaml
   argocd_enabled: "false"   # "false" = helmfile (simple, the default)
                             # "true"  = Argo CD (adds a web screen that shows and syncs every service)
   ```

   Not sure? Keep `"false"`. See [Helmfile or Argo CD?](#helmfile-or-argo-cd).

5. Click **Commit changes**, then **Commit changes** again.

That is the only file you fill in. On the first install the workflow creates your environment
file `one-click/<environment>.yaml` (from `digit-template.yaml`, the egov-demo layout) and puts
your values into it on every deploy.

## Step 6 (optional). Your own passwords and keys

Skip this step if you have none. You can do it later at any time.

Use it when DIGIT should use **your** SMS or e-mail account, a GitHub SSH key, a private image
registry, or passwords **you choose** for the admin screens (Keycloak, Grafana, Argo CD).

1. Same place as step 4: click **New repository secret**.
2. **Name:** `DIGIT_SECRETS`
3. **Secret:** write only what you want to set, in the same layout as the secrets file.
   Spaces at the start of a line matter. Example:

   ```yaml
   cluster-configs:
     secrets:
       egov-notification-sms:
         username: my-sms-user
         password: my-sms-password
       kc-admin:
         password: choose-a-password      # Keycloak admin
       grafana-admin:
         admin-password: choose-a-password
       git-ssh-key:                       # a new Kubernetes secret, any name
         ssh-privatekey: |
           -----BEGIN OPENSSH PRIVATE KEY-----
           ...
           -----END OPENSSH PRIVATE KEY-----
   ```

4. Click **Add secret**.

You never lock (encrypt) anything yourself. The workflow does it for you. All the names you
can use are in [Part 2, `DIGIT_SECRETS`](#digit_secrets).

> Set the Keycloak admin password **before the first install**. Keycloak only reads it once.

## Step 7. Install DIGIT

1. Click the **Actions** tab.
2. On the left, click **DIGIT one-click (Azure)**.
3. Click **Run workflow** (right side).
4. Keep **install** selected. Click the green **Run workflow**.
5. Wait about **1 hour**. A green tick means it is done.

The install also creates **`one-click/<environment>.yaml`** (your environment file) and
**`one-click/<environment>-secrets.yaml`** (your passwords, locked). Both are committed to your
copy for you.

## Step 8. Connect your domain

1. Click the finished run and scroll to the summary. It shows a **DNS record** with an **IP address**.
2. At the website where you bought your domain, add that record:
   **Type** `A`, **Name** your domain, **Value** the IP address.
3. Wait 5 to 30 minutes, then open `https://<your domain>`.

**You are done.**

---

## After the install: you only commit

Every commit to your copy starts the workflow by itself. It changes only what your commit changed:

| You commit a change to... | What runs by itself |
|---|---|
| `terraform_*` or `location` in `input.yaml`, or the Terraform code | **infra** (Azure) only |
| the rest of `input.yaml` (domain, e-mail, `helmfiles_ref`), your environment file, or your secrets file | **deploy** (DIGIT) only |
| both | **infra**, then **deploy** |
| anything else (docs, other folders, comments) | nothing |

| I want to... | Do this |
|---|---|
| change the domain or e-mail | Change that line in `input.yaml`, commit. Then update your DNS record. |
| change the machines (number or size) | Edit `terraform_node_count` (or add `terraform_main_vm_size`) in `input.yaml`, commit. |
| change a service (replicas, image, settings) | Edit that service's block in `one-click/<environment>.yaml`, commit. |
| turn a service off | Add `enabled: false` to its block, commit. |
| add a DIGIT service | Add a block with its name and `chart-version` (a chart from `helm.digit.org/digit3/core`), commit. |
| add or change a password or key | Edit the secret **`DIGIT_SECRETS`** (step 6), then **Actions → Run workflow → deploy**. (Changing a GitHub secret is not a commit, so it does not run by itself.) |
| run infra or deploy again by hand | **Actions → Run workflow**, choose **infra** or **deploy**. |
| get the newest DIGIT version | Update the `chart-version` lines you want in your environment file (and `helmfiles_ref` in `input.yaml` for newer helmfiles), commit. **Sync fork → Update branch** brings a newer workflow and templates. |
| delete my DIGIT | **Run workflow** with **destroy**, type `delete` in **confirm**. |
| delete everything in Azure | After destroy, delete the resource group `<your-name>-rg` in the Azure portal. |

## Helmfile or Argo CD?

Both deploy exactly the same DIGIT (same charts, same environment file, same passwords). Only
the tool that deploys differs. You choose once, with `argocd_enabled` in `input.yaml`, before the first install.

| | Helmfile (`argocd_enabled: "false"`) | Argo CD (`argocd_enabled: "true"`) |
|---|---|---|
| Who deploys the services | the GitHub workflow runs helmfile | Argo CD, inside your cluster |
| After a commit | the workflow deploys the change | Argo CD pulls the change from your copy within ~3 minutes; the workflow waits and reports |
| A web screen of all services | no | yes: `https://<your domain>/argocd`, user `admin` |
| Someone changes a service by hand in the cluster | stays until the next deploy | Argo CD puts it back at once |
| Best for | trying DIGIT, simple setups | teams that run DIGIT for a long time |

**Argo CD login:** user `admin`, password `cluster-configs.secrets.argocd-admin.password` from
your secrets file. Set your own in `DIGIT_SECRETS` (step 6):
`cluster-configs: {secrets: {argocd-admin: {password: choose-a-password}}}`.

## If something goes wrong

Open the run with the red ❌ and click the red step. The red message says what to fix.

| The message says | Fix |
|---|---|
| `AZURE_CREDENTIALS is missing` / `is not valid` | Do steps 3 and 4 again. Copy **all** the text, from `{` to `}`. |
| `Fill in these lines first` | Do step 5: fill in `environment`, `domain` and `email` in `input.yaml`. |
| `domain ... must be your web address` / `email ... must be your e-mail` | Fix that line in `input.yaml` (no `https://`, no `/`). |
| `environment ... is not allowed` | Small letters, numbers and `-` only, start with a letter, 3 to 20 characters. |
| `argocd_enabled must be "true" or "false"` | Write `"true"` or `"false"`. |
| `unfilled placeholders` | A line in your environment file has a `< >` placeholder the workflow cannot fill. Put your value there. |
| `chart-version is missing in the environment file` | Every service block needs a `chart-version:` line. |
| `Do not run this in egovernments/DIGIT-DevOps` | You are in the original project. Use your own copy (step 1). |
| `already exists but was not created by this fork` / `already used by someone else in Azure` | The name is taken. Choose another `environment` in `input.yaml` (before the first install). |
| `It cannot be switched on a running DIGIT` | You changed `argocd_enabled` after the install. Change it back, or run **destroy** and then **install**. |
| `would delete or replace` | Your change would rebuild the cluster, database or storage and can lose data. Undo it. Only if you are sure, run **infra** by hand with `replace` in **confirm**. |
| `DIGIT_SECRETS: is not valid YAML` | Check the spaces at the start of each line of `DIGIT_SECRETS`. |
| `DIGIT_SECRETS: unknown keys` | A name is misspelled. Use the paths in [Part 2](#digit_secrets). |
| `DIGIT_SECRETS: these cannot be changed` | Remove `db`, `kafka-kraft-cluster-id` and `hmac-secret` from `DIGIT_SECRETS`. |
| `locked by someone else's Key Vault` | Delete your `-secrets.yaml` file, then run **install** again. |
| `Nothing is installed` / `Run ... install first` | Run **install** first. |
| `Not installed (or destroyed) - this commit changes nothing` | Not an error: commits only update a running DIGIT. |
| `Argo CD did not finish within 60 minutes` | The message lists the services that are not ready. Open `https://<your domain>/argocd` to see why, then run **deploy** again. |
| anything else | Click **Re-run jobs → Re-run failed jobs**. If it fails again, share the red message with the DIGIT team. |

---

# Part 2 - Reference

Exact rules. Everything a team (or an AI assistant working for a team) may change is listed here.
Anything not listed here must not be changed.

## Rules (read first)

1. Work only in a **fork**. The workflow refuses to run in `egovernments/DIGIT-DevOps`.
2. A team fills in exactly **one file**, `one-click/input.yaml`, plus two GitHub **repository
   secrets**: `AZURE_CREDENTIALS` (required) and `DIGIT_SECRETS` (optional). Optionally it
   tunes release blocks in `one-click/<environment>.yaml` after the first install.
3. **Never** write a password, key or token into `input.yaml`, `<environment>.yaml` or any other
   file. The fork is public. Secrets go only into `DIGIT_SECRETS`.
4. **Never** create or edit `<environment>-secrets.yaml` by hand. The workflow creates it, locks it
   and commits it.
5. Do not edit `one-click/digit-template.yaml`, `one-click/digit-template-secrets.yaml`,
   `one-click/actions/`, `one-click/scripts/`, `.github/workflows/digit_install.yml` or
   `infra-as-code/`. The helmfiles are not in this repository: they live in
   [egovernments/helm-charts](https://github.com/egovernments/helm-charts/tree/master/helmfile/digit3-one-click)
   (`helmfile/digit3-one-click`), pinned by `helmfiles_ref` in `input.yaml`.
6. `environment`, `location` and `argocd_enabled` are fixed after the first install.
7. One environment per fork (the one named in `input.yaml`).

## Files

In this repository (DIGIT-DevOps) the one-click setup is only three places, easy to review:

```
one-click/                            everything one-click (this guide, input, templates, environment, actions, scripts)
.github/workflows/digit_install.yml   the workflow (GitHub requires workflows in .github/workflows)
infra-as-code/terraform/azure/        the Terraform code
```

The environment files have the same layout as `egov-demo.yaml` / `egov-demo-secrets.yaml`; the
helmfiles read **only** these two (the environment file with its placeholders filled in).

| Path | Who changes it | What it is |
|---|---|---|
| `one-click/input.yaml` | **the team** | the mandatory values (environment, domain, email) and the workflow settings |
| `one-click/README.md` | nobody | this guide |
| `one-click/digit-template.yaml` | nobody | the environment template (egov-demo layout, with placeholders) |
| `one-click/<environment>.yaml` | the workflow creates it; the team may tune release blocks | the environment: `global`, then one block per release |
| `one-click/<environment>-secrets.yaml` | the workflow only | passwords, SOPS-encrypted with the team's Azure Key Vault key |
| `one-click/digit-template-secrets.yaml` | nobody | the list of secrets and their layout (`DIGIT_SECRETS` may set these paths) |
| `one-click/actions/` | nobody | the workflow's steps: Azure login, input checks, sops, Terraform setup, `DIGIT_SECRETS`, committing to the fork |
| `one-click/scripts/` | nobody | secrets generation and `DIGIT_SECRETS` merge, commit-change detection |
| helm-charts `helmfile/digit3-one-click/` | nobody (pinned by `helmfiles_ref`) | the helmfiles; `scripts/render-env.sh` (fills the placeholders), Vault bootstrap, Argo CD plugin |
| `infra-as-code/terraform/azure/` | nobody | Azure infrastructure |
| `.github/workflows/digit_install.yml` | nobody | the workflow |

## `input.yaml`

Flat `key: "value"` lines, like `infra-as-code/terraform/azure/input.yaml`. Every value in double quotes.

| Key | Required | Default | Change after install? | Effect |
|---|---|---|---|---|
| `environment` | **yes** | - | **no** (a new name = a new environment) | AKS cluster `<environment>`; resource group `<environment>-rg`; DB server `<environment>-server` (must be free in all of Azure); files `one-click/<environment>.yaml` / `-secrets.yaml`. 3-20 small letters, numbers, `-`, starting with a letter |
| `domain` | **yes** | - | yes (runs **deploy**; then update DNS) | public address; fills `<domain>` |
| `email` | **yes** | - | yes (runs **deploy**) | Let's Encrypt account; fills `<email>` |
| `location` | no | `centralindia` | **no** (rebuilds everything; blocked unless `confirm = replace`) | Azure region |
| `argocd_enabled` | no | `"false"` | **no** | `"false"` = helmfile deploys; `"true"` = Argo CD deploys everything |
| `terraform_<var>` | no | see `infra-as-code/terraform/azure/variables.tf` | yes (runs **infra**) | Terraform variable `<var>`, e.g. `terraform_node_count: "4"`, `terraform_main_vm_size: "Standard_D8s_v3"`, `terraform_scheduling: "false"` |
| `helmfiles_repo` | no | `egovernments/helm-charts` | yes | where the helmfiles come from |
| `helmfiles_ref` | no | `master` | yes (runs **deploy**) | which version of the helmfiles deploys this environment: a branch, tag or **full** 40-character commit SHA. Pin it for a reproducible environment |

## `<environment>.yaml`

### Top-level blocks

| Block | What it is |
|---|---|
| `global` | given to every DIGIT chart: `domain` (`<domain>`), `mode` (`prod` = image tag from the chart, `dev` = `<release>.image.tag`), `containerRegistry`, `setup` |
| `cluster-configs` | namespaces and the shared ConfigMaps (`egov-config`, `egov-service-host`) |
| `<release>` | Helm values of that release, plus `chart-version` (required) and `enabled: false` (optional, do not deploy) |
| `argo-cd` | Argo CD itself (Argo CD mode only) |

### Placeholders, filled on every deploy

The placeholders stay in the file in git. On every deploy (helmfile mode and Argo CD mode alike)
`render-env.sh` writes a filled copy for helmfile:

| Placeholder | Filled with |
|---|---|
| `<domain>` | `domain` in `input.yaml` |
| `<email>` | `email` in `input.yaml` |
| `<env>` | `environment` in `input.yaml` |
| `<db_host>`, `<db_name>` | the PostgreSQL server Terraform created |

So changing the domain is one line in `input.yaml`. Any other `<...>` left in a value stops the
deploy (`unfilled placeholders`).

### Releases (block names)

| Layer | Namespace | Releases | Chart repository |
|---|---|---|---|
| backbone | `egov` | `cluster-configs` | helm.digit.org/digit3/cluster-configs |
| backbone | `backbone` | `cert-manager`, `ingress-nginx`, `redis`, `kafka-kraft`, `minio`, `elasticsearch-master`, `elasticsearch-data`, `kibana` | helm.digit.org/digit3/backbone |
| backbone | `vault` | `vault` | helm.digit.org/digit3/backbone |
| core | `egov` | `keycloak`, `kong`, and **every other block with a `chart-version`** (the DIGIT services: `account`, `workflow`, `mdms-v2`, ...) | helm.digit.org/digit3/core |
| monitoring | `monitoring` | `kube-prometheus-stack`, `loki`, `grafana`, `open-telemetry`, `jaeger`, `blackbox` | community repositories; blackbox from helm.digit.org/digit3/backbone |
| Argo CD mode | `argocd` | `argo-cd` | helm.digit.org/digit3/backbone |

- Each release gets its own block as Helm values (`chart-version` and `enabled` removed).
- DIGIT charts built on the common chart (core services, `keycloak`, `redis`, `minio`, `kibana`) also get `global`, with `global.namespace` set to the release namespace.
- Lists replace, maps merge.
- `jaeger` needs `elasticsearch-*`; turn them off together.

## Secrets

### `AZURE_CREDENTIALS` (repository secret, required)

The full JSON printed by `az ad sp create-for-rbac ... --json-auth` (step 3). It must contain
`clientId`, `clientSecret`, `tenantId` and `subscriptionId`.

**Permissions of the service principal** (least privilege, set by step 3), on the subscription:

| Role | Why |
|---|---|
| **Contributor** | creates `<name>-rg`, AKS, PostgreSQL, network, storage, Automation, the Key Vault and its access policies, and tags |
| **Role Based Access Control Administrator**, with a condition: may assign and remove **only** Network Contributor and Azure Kubernetes Service Contributor Role | Terraform creates these 3 role assignments (Contributor alone cannot): Network Contributor on the AKS subnet for the AKS identity (`infra-as-code/terraform/azure/main.tf`); Azure Kubernetes Service Contributor Role on the cluster and Network Contributor on the AKS subnet for the node-scaling Automation account (`modules/scheduling/azure`, only when `terraform_scheduling` is `"true"`, the default) |

**Owner** on the subscription also works but gives far more than needed.

Rules for this setup:

- The person who runs step 3 must be **Owner** or **User Access Administrator** and be allowed to create app registrations in Microsoft Entra ID.
- The Key Vault uses access policies (managed by Contributor). If an Azure Policy forces Key Vaults to use Azure RBAC, the install also needs Key Vault data roles, and those must be added to the condition.
- A new `azurerm_role_assignment` added to the Terraform code needs its role added to the condition.

### `DIGIT_SECRETS`

Repository secret, optional. YAML in the **same layout as the secrets file**
(`digit-template-secrets.yaml`). Only the paths you want to set.

The secrets file has **one format**: every secret is `cluster-configs.secrets.<name>`, a
Kubernetes Secret created in the listed namespaces, and charts read it by name. Every value
is written once (MinIO, Grafana and Jaeger read the shared Secrets, not a copy).

| Path | What it is | Notes |
|---|---|---|
| `cluster-configs.secrets.egov-notification-sms.{username,password}` | SMS provider login | default `not-configured` |
| `cluster-configs.secrets.egov-notification-mail.{mailsenderusername,mailsenderpassword}` | e-mail sender login | default `not-configured` |
| `cluster-configs.secrets.egov-pg-service.stripe-secret-key` | payment gateway key | default `not-configured` |
| `cluster-configs.secrets.kc-admin.{username,password}` | Keycloak admin login | before the first install |
| `cluster-configs.secrets.kc-db.password` | Keycloak database password | before the first install only |
| `cluster-configs.secrets.employee-iam-secret`, `citizen-broker-secret` | Keycloak client secrets | |
| `cluster-configs.secrets.docker-registry-secret.dockerconfigjson` | private image registry (`.dockerconfigjson` string) | |
| `cluster-configs.secrets.minio.{accesskey,secretkey}` | MinIO root login = filestore S3 key | before the first install only |
| `cluster-configs.secrets.elasticsearch-master-credentials.password` | Elasticsearch `elastic` user (Kibana, Jaeger too) | before the first install only |
| `cluster-configs.secrets.grafana-admin.{admin-user,admin-password}` | Grafana login | |
| `cluster-configs.secrets.argocd-admin.password` | Argo CD `admin` login | Argo CD mode |
| `cluster-configs.secrets.<new-name>.<key>` | any other Kubernetes Secret | `namespace: [ns, ...]` optional, default `[egov]` |

Not allowed, because changing them breaks existing data: `cluster-configs.secrets.db`,
`cluster-configs.secrets.kafka-kraft-cluster-id`, `cluster-configs.secrets.hmac-secret`.
Any other path not in the template is rejected as a typo.

### How secrets are handled (nobody encrypts by hand)

1. **install** creates an Azure Key Vault in `<environment>-rg` with a key `sops`.
2. It copies `digit-template-secrets.yaml` and gives every `<placeholder>` a fresh random value. The same placeholder gets the same value everywhere.
3. It merges `DIGIT_SECRETS` over it, after checking the paths.
4. It encrypts the result with SOPS and that Key Vault key, and commits `<environment>-secrets.yaml` (`[skip ci]`).
5. Every **deploy** repeats steps 3 and 4. A key added to the template in a newer version gets a random value. The file is committed only if something changed.
6. **Helmfile mode:** helm-secrets decrypts the file during the deploy with the workflow's Azure login.
7. **Argo CD mode:** the Argo CD plugin decrypts it with the cluster's own managed identity, which is allowed only to *get* and *decrypt* with that key.

## Workflow

`Actions → DIGIT one-click (Azure) → Run workflow` (the environment is the one in `input.yaml`):

| `action` | Does | `confirm` |
|---|---|---|
| `install` | first time, or re-run a failed install: resource group, state storage, Key Vault, environment file, secrets, Terraform, deploy | - |
| `infra` | Terraform only | `replace` only if it asks |
| `deploy` | deploy only (helmfile, or Argo CD), and applies `DIGIT_SECRETS` | - |
| `destroy` | Terraform destroy; keeps `<environment>-rg` (state + Key Vault) | `delete` |

**Commits run automatically.** A commit to `one-click/*.yaml` or the Terraform code on the fork's
default branch runs the workflow (see [After the install](#after-the-install-you-only-commit)).

**Tags on `<environment>-rg`.** The commit last applied is stored as tags:

| Tag | Meaning |
|---|---|
| `digit-infra-sha`, `digit-deploy-sha` | commit last applied for infra / deploy |
| `digit-state` | `installed` or `destroyed` |
| `digit-deploy-mode` | `helmfile` or `argocd` |
| `managed-by=digit-one-click`, `digit-repo=<owner>/<repo>`, `digit-name=<environment>` | ownership |

## Argo CD mode, in detail

- **Install.** The workflow installs Argo CD (chart `argo-cd`) into namespace `argocd`, with a repo-server sidecar plugin `digit-helmfile` (helm-charts `helmfile/digit3-one-click/scripts/argocd-plugin.sh`).
- **One root Application.** The workflow creates one Application, `digit`, pointing at the fork (`one-click/`, default branch; plugin env `DB_HOST`, `DB_NAME` from Terraform). The plugin reads `input.yaml` from the fork, fetches the helmfiles from helm-charts at `helmfiles_ref` (sparse, shallow), fills the environment file with `render-env.sh`, and renders. A commit to `input.yaml` or the environment file is picked up by Argo CD directly.
- **One Application per release.** The plugin turns the root into one Application per release, with the same names, namespaces and values as helmfile mode, because it is the same helmfiles reading the same two files.
- **Order.** Sync waves follow the layers: `cluster-configs` → backbone → Keycloak → Kong → core services → monitoring.
- **Sync.** All Applications use automated sync with prune and self-heal. `enabled: false` removes a release's Application and everything it deployed.
- **Vault.** The workflow unseals it (`scripts/vault-bootstrap.sh`); after that it unseals itself on restarts.
- **UI.** `https://<domain>/argocd`, user `admin`, password `cluster-configs.secrets.argocd-admin.password`.

## What gets created

- **Azure** (`<environment>-rg`):
  - AKS cluster `<environment>`;
  - PostgreSQL Flexible Server `<environment>-server`;
  - network;
  - storage accounts (Terraform state, filestore);
  - Key Vault.
- **Cluster:**
  - **backbone:** cluster-configs, cert-manager, ingress-nginx (gzip on), Redis, Kafka, MinIO, Vault, Elasticsearch, Kibana;
  - **core:** Keycloak, Kong, the DIGIT 3.0 services;
  - **monitoring:** Prometheus, Grafana, Loki, OpenTelemetry, Jaeger, blackbox exporter. Alertmanager sends nowhere until you add a receiver in the `kube-prometheus-stack` block.
  - **Argo CD mode:** Argo CD as well.
- DIGIT and backbone charts are packaged at https://helm.digit.org.

## Not automated yet

Creating tenants and seed data.
