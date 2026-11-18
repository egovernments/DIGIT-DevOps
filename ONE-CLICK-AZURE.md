# Install DIGIT on Azure in one click

You copy this project, change **one file**, add **one secret**, and click **one button**.
You do not need to install anything on your computer.

This guide has two parts:

- **Part 1 - Steps** (for people). Do them in order.
- **Part 2 - Reference** (exact rules for every file, setting and secret). Use it when you
  want more than the basics, or when an AI assistant prepares the files for you.

---

# Part 1 - Steps

## What you need

1. A **GitHub** account.
2. An **Azure** subscription where you are an **Owner**.
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
2. Copy this line, paste it into the window, and press **Enter**:

   ```bash
   az ad sp create-for-rbac --name digit-one-click --role Owner --scopes /subscriptions/$(az account show --query id -o tsv) --json-auth
   ```

3. It prints text that starts with `{` and ends with `}`. Copy **all** of it.

> Keep this text secret. Paste it only in step 4.

## Step 4. Save the key in your copy

1. In your copy, click **Settings**, then on the left **Secrets and variables**, then **Actions**.
2. Click **New repository secret**.
3. **Name:** `AZURE_CREDENTIALS`
4. **Secret:** paste the text from step 3.
5. Click **Add secret**.

## Step 5 (optional). Your own passwords and keys

Skip this step if you have none. You can do it later at any time.

Use it when DIGIT should use **your** SMS or e-mail account, a GitHub SSH key, a private image
registry, or passwords **you choose** for the admin screens (Keycloak, Grafana, Argo CD).

1. Same place as step 4: click **New repository secret**.
2. **Name:** `DIGIT_SECRETS`
3. **Secret:** write only what you want to set. Spaces at the start of a line matter. Example:

   ```yaml
   notification:
     smsUsername: my-sms-user
     smsPassword: my-sms-password
   grafana:
     adminPassword: choose-a-password
   keycloak:
     adminPassword: choose-a-password
   extra:
     git-ssh-key:                  # name of a new Kubernetes Secret
       ssh-privatekey: |
         -----BEGIN OPENSSH PRIVATE KEY-----
         ...
         -----END OPENSSH PRIVATE KEY-----
   ```

4. Click **Add secret**.

You never lock (encrypt) anything yourself. The workflow does it for you. All the names you
can use are in [Part 2, `DIGIT_SECRETS`](#digit_secrets).

> Set `keycloak.adminPassword` **before the first install**. Keycloak only reads it once.

## Step 6. Fill in your details

1. In your copy, open the file **`digit-config.yaml`** and click the **pencil** icon.
2. Change these 3 lines. Keep the quotes `" "`.

   ```yaml
   name: "team-a-digit"          # short name: small letters, numbers and -
   domain: "digit.example.com"   # your domain
   email: "you@example.com"      # your e-mail
   ```

3. **Choose how DIGIT is deployed** (you cannot change this after the install):

   ```yaml
   argocd:
     enabled: false     # false = helmfile (simple, the default)
                        # true  = Argo CD (adds a web screen that shows and syncs every service)
   ```

   Not sure? Keep `false`. See [Helmfile or Argo CD?](#helmfile-or-argo-cd).

4. Click **Commit changes**, then **Commit changes** again.

## Step 7. Install DIGIT

1. Click the **Actions** tab.
2. On the left, click **DIGIT one-click (Azure)**.
3. Click **Run workflow** (right side). Keep **install** selected. Click the green **Run workflow**.
4. Wait about **1 hour**. A green tick means it is done.

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
| `terraform:` or `location:` in `digit-config.yaml`, or the Terraform code | **infra** (Azure) only |
| anything else in `digit-config.yaml`, `digit-secrets.yaml`, or the helmfiles/values | **deploy** (DIGIT) only |
| both | **infra**, then **deploy** |
| anything else (docs, other folders, comments) | nothing |

| I want to... | Do this |
|---|---|
| change the machines (number or size) | Edit `terraform:` in `digit-config.yaml`, commit. |
| change a DIGIT setting | Edit any other part of `digit-config.yaml`, commit. |
| add or change a password or key | Edit the secret **`DIGIT_SECRETS`** (step 5), then **Actions → Run workflow → deploy**. (Changing a GitHub secret is not a commit, so it does not run by itself.) |
| run infra or deploy again by hand | **Actions → Run workflow**, choose **infra** or **deploy**. |
| get the newest DIGIT version | On your copy's main page click **Sync fork → Update branch**. It is applied by itself. |
| delete my DIGIT | **Run workflow** with **destroy**, type `delete` in **confirm**. |
| delete everything in Azure | After destroy, delete the resource group `<name>-rg` in the Azure portal. |

## Helmfile or Argo CD?

Both deploy exactly the same DIGIT (same charts, same settings, same passwords). Only the tool
that deploys differs. You choose once, in `digit-config.yaml`, before the first install.

| | Helmfile (`argocd.enabled: false`) | Argo CD (`argocd.enabled: true`) |
|---|---|---|
| Who deploys the services | the GitHub workflow runs helmfile | Argo CD, inside your cluster |
| After a commit | the workflow deploys the change | Argo CD pulls the change from your copy within ~3 minutes; the workflow waits and reports |
| A web screen of all services | no | yes: `https://<your domain>/argocd`, user `admin` |
| Someone changes a service by hand in the cluster | stays until the next deploy | Argo CD puts it back at once |
| Best for | trying DIGIT, simple setups | teams that run DIGIT for a long time |

**Argo CD login:** user `admin`, password = `argocd.adminPassword`. Set your own in
`DIGIT_SECRETS` (step 5), for example `argocd: {adminPassword: choose-a-password}`.

## If something goes wrong

Open the run with the red ❌ and click the red step. The red message says what to fix.

| The message says | Fix |
|---|---|
| `AZURE_CREDENTIALS is missing` / `is not valid` | Do steps 3 and 4 again. Copy **all** the text, from `{` to `}`. |
| `Fill in these lines first` | Do step 6. Change every line that still has `< >`. |
| `name ... is not allowed` | Small letters, numbers and `-` only, start with a letter, 3 to 20 characters. |
| `argocd.enabled must be true or false` | Write `true` or `false` without quotes. |
| `Do not run this in egovernments/DIGIT-DevOps` | You are in the original project. Use your own copy (step 1). |
| `already exists but was not created by this fork` | The name is taken in your Azure. Choose another `name`. |
| `It cannot be switched on a running DIGIT` | You changed `argocd.enabled` after the install. Change it back, or run **destroy** and then **install**. |
| `would delete or replace` | Your change would rebuild the cluster, database or storage and can lose data. Undo it. Only if you are sure, run **infra** by hand with `replace` in **confirm**. |
| `DIGIT_SECRETS: is not valid YAML` | Check the spaces at the start of each line of `DIGIT_SECRETS`. |
| `DIGIT_SECRETS: unknown keys` | A name is misspelled. Use the names in [Part 2](#digit_secrets), or put new secrets under `extra:`. |
| `DIGIT_SECRETS: these cannot be changed` | Remove `db`, `kafka` and `hmac` from `DIGIT_SECRETS`. |
| `locked by someone else's Key Vault` | Delete `digit-secrets.yaml` in your copy, then run **install** again. |
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
2. A team changes exactly **one file**, `digit-config.yaml` at the top of the repository, plus
   two GitHub **repository secrets**: `AZURE_CREDENTIALS` (required) and `DIGIT_SECRETS` (optional).
3. **Never** write a password, key or token into `digit-config.yaml` or any other file. The
   fork is public. Secrets go only into `DIGIT_SECRETS`.
4. **Never** create or edit `digit-secrets.yaml` by hand. The workflow creates it, locks it and
   commits it.
5. Do not edit anything under `deploy-as-code/`, `infra-as-code/` or `.github/`. Every
   setting there can be overridden from `digit-config.yaml` (see below).
6. `name` and `argocd.enabled` are fixed after the first install.

## Files

| Path | Who changes it | What it is |
|---|---|---|
| `digit-config.yaml` | the team | the only settings file |
| `digit-secrets.yaml` | the workflow only | generated passwords + `DIGIT_SECRETS`, SOPS-encrypted with the team's Azure Key Vault key |
| `deploy-as-code/helm/defaults.yaml` | nobody (read only) | every default; any key can be overridden in `digit-config.yaml` |
| `deploy-as-code/helm/secrets.template.yaml` | nobody (read only) | the list of secret names (`DIGIT_SECRETS` may set these) |
| `deploy-as-code/helm/digit-helmfile.yaml.gotmpl`, `helmfiles/`, `values/` | nobody | what is deployed and how |
| `infra-as-code/terraform/azure/` | nobody | Azure infrastructure |
| `.github/workflows/digit_install.yml` | nobody | the workflow |

## `digit-config.yaml`

Merged **over** `deploy-as-code/helm/defaults.yaml` (maps are merged key by key, lists replace).

| Key | Type | Required | Default | Change after install? | Effect |
|---|---|---|---|---|---|
| `name` | string, `^[a-z][a-z0-9-]{1,18}[a-z0-9]$`, no `--` | yes | - | **no** (a new name = a new environment) | AKS cluster name; resource group `<name>-rg`; DB server `<name>-server` (must be free in all of Azure) |
| `domain` | host name, e.g. `digit.example.com` (no `https://`, no `/`) | yes | - | yes (then update DNS) | public address of DIGIT |
| `email` | e-mail | yes | - | yes | Let's Encrypt account for HTTPS certificates |
| `location` | Azure region, e.g. `centralindia` | no | `centralindia` | **no** (rebuilds everything; blocked unless `confirm = replace`) | Azure region |
| `terraform.<var>` | scalar | no | see `infra-as-code/terraform/azure/variables.tf` | yes (runs **infra**) | Terraform variable, e.g. `node_count: 4`, `main_vm_size: "Standard_D8s_v3"` |
| `argocd.enabled` | `true` / `false` | no | `false` | **no** | `false` = helmfile deploys; `true` = Argo CD deploys everything |
| `components.elasticsearch` | bool | no | `true` | yes | Elasticsearch, Kibana (and Jaeger) |
| `components.monitoring` | bool | no | `true` | yes | Prometheus, Grafana, Loki, OpenTelemetry, Jaeger, blackbox |
| `releases.<release>.enabled` | bool | no | `true` | yes | turn one release off, e.g. `releases: {jaeger: {enabled: false}}` |
| `versions.<chart>` | chart version | no | `defaults.yaml` | yes | pin a chart version |
| `sizing.*` | see `defaults.yaml` | no | `defaults.yaml` | yes | replicas and disk sizes |
| `namespaces.*` | string | no | `egov`, `backbone`, `vault`, `monitoring` | **no** | Kubernetes namespaces |
| `imageMode` | `prod` / `dev` | no | `prod` | yes | `prod` = image tag from the chart; `dev` = `values.<svc>.image.tag` |
| `tls.issuer` | `letsencrypt-prod` / `letsencrypt-staging` | no | `letsencrypt-prod` | yes | certificate issuer |
| `values.<release>` | map | no | `{}` | yes | Helm values for one release (release name = chart name). **No secrets here.** |

Release names (for `releases.*` and `values.*`):

- backbone: `cluster-configs`, `cert-manager`, `ingress-nginx`, `redis`, `kafka-kraft`, `minio`,
  `vault`, `elasticsearch-master`, `elasticsearch-data`, `kibana`
- core: `keycloak`, `kong`, and every name in `coreServices` in `defaults.yaml`
  (e.g. `workflow`, `mdms-v2`, `filestore`, ...)
- monitoring: `kube-prometheus-stack`, `loki`, `grafana`, `open-telemetry`, `jaeger`, `blackbox`
- Argo CD mode: `argo-cd`

Complete example:

```yaml
name: "team-a-digit"
domain: "digit.team-a.example.org"
email: "ops@team-a.example.org"
location: "centralindia"
terraform:
  node_count: 4
argocd:
  enabled: true
components:
  monitoring: true
releases:
  jaeger: {enabled: false}
values:
  workflow:
    replicas: 2
```

## Secrets

### `AZURE_CREDENTIALS` (repository secret, required)

The full JSON printed by `az ad sp create-for-rbac ... --json-auth` (step 3). It must contain
`clientId`, `clientSecret`, `tenantId` and `subscriptionId`. The service principal needs **Owner**
on the subscription (it creates role assignments).

### `DIGIT_SECRETS`

Repository secret, optional. YAML. A top-level `secrets:` wrapper is allowed but not needed.
It may contain:

| Key | What it is | Notes |
|---|---|---|
| `notification.smsUsername`, `notification.smsPassword` | SMS provider login | default `not-configured` |
| `notification.mailUsername`, `notification.mailPassword` | e-mail sender login | default `not-configured` |
| `stripeSecretKey` | payment gateway key | default `not-configured` |
| `keycloak.adminUsername`, `keycloak.adminPassword` | Keycloak admin login | set **before** the first install |
| `keycloak.dbUsername`, `keycloak.dbPassword` | Keycloak database user | before the first install only |
| `keycloak.employeeIamClientSecret`, `keycloak.citizenBrokerClientSecret` | Keycloak client secrets | |
| `grafana.adminPassword` | Grafana `admin` login | |
| `argocd.adminPassword` | Argo CD `admin` login | Argo CD mode |
| `minio.username`, `minio.password` | MinIO root login | before the first install only |
| `elasticsearch.password` | Elasticsearch `elastic` user | before the first install only |
| `dockerConfigJson` | private image registry, a `.dockerconfigjson` string | goes to Secret `docker-registry-secret` |
| `extra.<secret-name>.<key>` | any other Kubernetes Secret | optional `extra.<secret-name>.namespace: [ns, ...]` (default: the core namespace `egov`) |

Not allowed, because changing them breaks existing data: `db`, `kafka`, `hmac`.
Any other name is rejected as a typo. `extra.<secret-name>` must not be the name of a
Secret the install already creates.

### How secrets are handled (nobody encrypts by hand)

1. **install** creates an Azure Key Vault `<name>…kv…` in `<name>-rg` with a key `sops`.
2. It generates a fresh random value for every `<placeholder>` in `secrets.template.yaml`.
3. It merges `DIGIT_SECRETS` over them, after checking the names.
4. It encrypts the result with SOPS and that Key Vault key, and commits `digit-secrets.yaml`
   to the fork (`[skip ci]`).
5. Every **deploy** repeats steps 3 and 4. If `secrets.template.yaml` gained a new key in a
   newer version, that key gets a random value. The file is committed only if something changed.
6. **Helmfile mode:** helm-secrets decrypts the file during the deploy with the workflow's
   Azure login.
7. **Argo CD mode:** the Argo CD plugin decrypts it with the cluster's own managed identity,
   which is allowed only to *get* and *decrypt* with that key.

## Workflow

`Actions → DIGIT one-click (Azure) → Run workflow`:

| `action` | Does | `confirm` |
|---|---|---|
| `install` | first time, or re-run a failed install: Azure resource group, state storage, Key Vault, secrets, Terraform, deploy | - |
| `infra` | Terraform only | `replace` only if it asks |
| `deploy` | deploy only (helmfile, or Argo CD) | - |
| `destroy` | Terraform destroy; keeps `<name>-rg` (state + Key Vault) | `delete` |

A commit to the fork's default branch runs the workflow automatically (see
[After the install](#after-the-install-you-only-commit)). The commit last applied is stored as
tags on `<name>-rg`: `digit-infra-sha`, `digit-deploy-sha`, `digit-state`
(`installed`/`destroyed`), `digit-deploy-mode` (`helmfile`/`argocd`). Ownership tags:
`managed-by=digit-one-click`, `digit-repo=<owner>/<repo>`, `digit-name=<name>`.

## Argo CD mode, in detail

- The workflow installs Argo CD (chart `argo-cd` from `helm.digit.org/digit3/backbone`) into
  namespace `argocd`, with a repo-server sidecar plugin `digit-helmfile`
  (`deploy-as-code/helm/scripts/argocd-plugin.sh`, image `argocd.pluginImage`).
- It creates **one** Application, `digit`, pointing at the fork
  (`deploy-as-code/helm`, default branch). The plugin turns it into **one Application per
  release**, with the same names, namespaces and values as helmfile mode. Sync waves follow
  the layers: `cluster-configs` → backbone → Keycloak → Kong → core services → monitoring.
- All Applications use automated sync with prune and self-heal. Turning a release off
  (`releases.<name>.enabled: false`) removes its Application and everything it deployed.
- Vault is unsealed by the workflow (`scripts/vault-bootstrap.sh`); it then unseals itself on restarts.
- UI: `https://<domain>/argocd`, user `admin`, password `argocd.adminPassword`.

## What gets created

- **Azure** (`<name>-rg`): AKS cluster `<name>`, PostgreSQL Flexible Server `<name>-server`,
  network, storage accounts (Terraform state, filestore), Key Vault.
- **Cluster**:
  - **backbone:** cluster-configs, cert-manager, ingress-nginx (gzip on), Redis, Kafka, MinIO,
    Vault, Elasticsearch, Kibana.
  - **core:** Keycloak, Kong, the DIGIT 3.0 services.
  - **monitoring:** Prometheus, Grafana, Loki, OpenTelemetry, Jaeger, blackbox exporter.
  - **Argo CD mode:** also Argo CD.
- All charts are packaged at https://helm.digit.org.

## Not automated yet

Creating tenants and seed data.
