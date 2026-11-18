# Install DIGIT on Azure in one click

You will copy this project, change **one file**, add **one secret**, and click **one button**.
You do not need to install anything on your computer.

## Before you start, you need

1. A **GitHub** account.
2. An **Azure** account where you are an **Owner** of the subscription.
3. A **domain name** you own, for example `digit.example.com`.
   You must be able to add a DNS record for it at the website where you bought it.

---

## Step 1. Copy (fork) this project

1. Open https://github.com/egovernments/DIGIT-DevOps
2. Click **Fork** (top right).
3. Click **Create fork**.

Now you have your own copy at `https://github.com/<your-name>/DIGIT-DevOps`.
**Do every next step in your own copy.**

## Step 2. Turn on Actions in your copy

1. In your copy, click the **Actions** tab.
2. Click the green button **I understand my workflows, go ahead and enable them**.

## Step 3. Make a key for Azure

1. Open https://shell.azure.com and sign in. If it asks, choose **Bash**.
2. Copy this line, paste it into the black window, and press **Enter**:

   ```bash
   az ad sp create-for-rbac --name digit-one-click --role Owner --scopes /subscriptions/$(az account show --query id -o tsv) --json-auth
   ```

3. It prints some text that starts with `{` and ends with `}`.
   Select **all** of it, from `{` to `}`, and copy it.

> Keep this text secret. Do not paste it anywhere except the next step.

## Step 4. Save the key in your copy

1. In your copy on GitHub, click **Settings**.
2. On the left, click **Secrets and variables**, then **Actions**.
3. Click **New repository secret**.
4. In **Name**, type: `AZURE_CREDENTIALS`
5. In **Secret**, paste the text you copied in step 3.
6. Click **Add secret**.

### Step 4b (optional). Add your own passwords and keys

Skip this if you do not have any yet. You can add them at any time later.

If DIGIT should use your own SMS or email account, a GitHub SSH key, a private image
registry, or any other credential:

1. In the same place as step 4, click **New repository secret** again.
2. In **Name**, type: `DIGIT_SECRETS`
3. In **Secret**, type only what you want to set, like this (spaces at the start of a line matter):

   ```yaml
   notification:
     smsUsername: my-sms-user
     smsPassword: my-sms-password
     mailUsername: me@example.com
     mailPassword: my-mail-password
   extra:
     git-ssh-key:                  # name of a new Kubernetes secret
       ssh-privatekey: |
         -----BEGIN OPENSSH PRIVATE KEY-----
         ...
         -----END OPENSSH PRIVATE KEY-----
   ```

4. Click **Add secret**.

You never lock (encrypt) anything yourself. The workflow does it: it adds these values to
your locked passwords file, locks it again with your own Azure key, and uses them in the deploy.

## Step 5. Fill in your details

1. In your copy, click the file **`digit-config.yaml`**.
2. Click the **pencil** icon (Edit).
3. Change only these 3 lines. Keep the quotes `" "`.

   ```yaml
   name: "team-a-digit"          # a short name, small letters, numbers and -
   domain: "digit.example.com"   # your domain
   email: "you@example.com"      # your email
   ```

4. Click **Commit changes**, then **Commit changes** again.

## Step 6. Install DIGIT

1. Click the **Actions** tab.
2. On the left, click **DIGIT one-click (Azure)**.
3. Click **Run workflow** (on the right).
4. Keep **install** selected, and click the green **Run workflow** button.
5. Wait. It takes about **1 hour**. When it shows a green tick, it is done.

## Step 7. Connect your domain

1. Click the finished run.
2. Scroll down to the summary. It shows a **DNS record** with an **IP address**.
3. Go to the website where you bought your domain, and add that record:
   **Type** `A`, **Name** your domain, **Value** the IP address.
4. Wait 5 to 30 minutes, then open `https://<your domain>` in your browser.

**You are done.**

---

## Later

After the first install, **you only commit**. Every commit to your copy starts the workflow by
itself, and it changes only what your commit changed:

| You commit a change to... | What runs by itself |
|---|---|
| the `terraform:` or `location:` part of `digit-config.yaml`, or the Terraform code | **infra** only (Azure). DIGIT is not redeployed. |
| any other part of `digit-config.yaml`, `digit-secrets.yaml`, or the helmfiles / values | **deploy** only (DIGIT). Azure is not touched. |
| both | **infra**, then **deploy** |
| anything else (docs, other folders, comments) | nothing |

The workflow remembers which commit is running in Azure, so it never misses a change, even
if you commit several times quickly.

| I want to... | Do this |
|---|---|
| change the machines (number or size) | Edit the `terraform:` part of `digit-config.yaml` and commit. |
| change a DIGIT setting | Edit any other part of `digit-config.yaml` and commit. |
| run infra or deploy again by hand | Actions, then **Run workflow**, choose **infra** or **deploy**. |
| add or change a password or key (SMS, mail, SSH key, ...) | **Settings → Secrets and variables → Actions**, edit **`DIGIT_SECRETS`** (step 4b). Then run the workflow with **deploy**. Changing a GitHub secret is not a commit, so it does not run by itself. |
| delete my DIGIT | Run the workflow with **destroy**, and type `delete` in the **confirm** box. |
| delete everything in Azure | After **destroy**, delete the resource group `<name>-rg` in the Azure portal. |
| get the newest version | On your copy's main page, click **Sync fork**, then **Update branch**. The new versions are applied by themselves. |

## If something goes wrong

Click the run with the red ❌, then click the red step. The red message tells you what to fix.

| The message says | Fix |
|---|---|
| `AZURE_CREDENTIALS is missing` or `is not valid` | Do steps 3 and 4 again. Copy **all** the text, from `{` to `}`. |
| `Fill in these lines first` | Do step 5. Change every line that still has `< >`. |
| `name ... is not allowed` | Use only small letters, numbers and `-`. Start with a letter. 3 to 20 characters. |
| `Do not run this in egovernments/DIGIT-DevOps` | You are in the original project. Do step 1 and use your own copy. |
| `locked by someone else's Key Vault` | Delete `digit-secrets.yaml` in your copy, then run **install** again. |
| `does not exist yet. Run ... install first` or `Nothing is installed` | Run the workflow with **install** before **infra** or **deploy**. |
| `already exists but was not created by this fork` | That name is taken in your Azure. Pick a new `name` in `digit-config.yaml`. |
| `would delete or replace` | Your change would rebuild the cluster, database or storage and can lose data. Undo the change (commit it back). Only if you are sure, run **infra** by hand with `replace` in the **confirm** box. |
| `DIGIT_SECRETS: is not valid YAML` | Check the spaces at the start of each line in `DIGIT_SECRETS` (step 4b). |
| `DIGIT_SECRETS: unknown keys` | A name is misspelled. Use the names from step 4b, or put new secrets under `extra:`. |
| `DIGIT_SECRETS: these cannot be changed` | `db`, `kafka` and `hmac` are made by the install and changing them would break your data. Remove them from `DIGIT_SECRETS`. |
| `Not installed (or destroyed) - this commit changes nothing` | Not an error. Commits only update a running DIGIT. Run **install** first. |
| anything else | Click **Re-run jobs**, then **Re-run failed jobs**. If it fails again, ask the DIGIT team and share the red message. |

---

## For the curious (you can skip this)

- **What gets created.** In Azure: a resource group `<name>-rg` with an AKS cluster, a PostgreSQL server, storage and a Key Vault. On the cluster: DIGIT core 3.0, its backbone (Kafka, Redis, MinIO, Vault, Elasticsearch, Kibana, ingress, cert-manager) and monitoring (Prometheus, Grafana, Loki, OpenTelemetry, Jaeger). Everything comes from packaged Helm charts at https://helm.digit.org, deployed with helmfile from `deploy-as-code/helm/`.
- **Passwords - how they work.** You never make or lock passwords yourself, and you never need a key on your computer.
  1. The first **install** creates your own Azure Key Vault and a key inside it. Only your Azure login (`AZURE_CREDENTIALS`) can use it.
  2. It makes new random passwords just for you (database, Keycloak, MinIO, Grafana, ...).
  3. It adds your own values from `DIGIT_SECRETS`, if you set it.
  4. It locks everything (SOPS encryption with the Key Vault key) and saves it in your copy as `digit-secrets.yaml`.
  5. Every **deploy** adds any new `DIGIT_SECRETS` values, locks the file again if something changed, and gives the values to DIGIT (helm-secrets unlocks them with the same key).

  Your copy is public, but the locked file is safe: only your Azure key can open it. No two teams share a password or a key.
- **Always a new environment.** Everything the install creates in Azure is labelled with your copy and your `name`. The workflow only reuses Azure things that carry your label, from an earlier run of the same copy and name. If something with that name already exists and is not yours, it stops and changes nothing.
- **Read a password, or edit the file directly** (experts only; needs the Azure CLI and `sops` on your computer). Values that are also in `DIGIT_SECRETS` are put back from `DIGIT_SECRETS` on the next deploy.
  ```bash
  az login
  az keyvault set-policy -n <key-vault-name> --upn <your-azure-email> --key-permissions get encrypt decrypt
  sops digit-secrets.yaml      # opens the file unlocked in an editor, locks it again on save
  ```
  The Key Vault name is shown in the resource group `<name>-rg`. Commit the file, then run **deploy**.
- **More settings.** Everything in `deploy-as-code/helm/defaults.yaml` (versions, sizes, what to install) can be changed from `digit-config.yaml`. The optional part of that file shows examples.
- **Tenant data.** The install does not create tenants or seed data yet.
