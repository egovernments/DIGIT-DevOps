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

| I want to... | Do this |
|---|---|
| change a setting | Edit `digit-config.yaml` (step 5), then run the workflow with **deploy** (step 6). |
| delete my DIGIT | Run the workflow with **destroy**, and type `delete` in the **confirm** box. |
| delete everything in Azure | After **destroy**, delete the resource group `<name>-rg` in the Azure portal. |
| get the newest version | On your copy's main page, click **Sync fork**, then **Update branch**. Then run **deploy**. |

## If something goes wrong

Click the run with the red ❌, then click the red step. The red message tells you what to fix.

| The message says | Fix |
|---|---|
| `AZURE_CREDENTIALS is missing` or `is not valid` | Do steps 3 and 4 again. Copy **all** the text, from `{` to `}`. |
| `Fill in these lines first` | Do step 5. Change every line that still has `< >`. |
| `name ... is not allowed` | Use only small letters, numbers and `-`. Start with a letter. 3 to 20 characters. |
| `Do not run this in egovernments/DIGIT-DevOps` | You are in the original project. Do step 1 and use your own copy. |
| `locked by someone else's Key Vault` | Delete `digit-secrets.yaml` in your copy, then run **install** again. |
| `does not exist yet. Run ... install first` | Run the workflow with **install** before **deploy**. |
| anything else | Click **Re-run jobs**, then **Re-run failed jobs**. If it fails again, ask the DIGIT team and share the red message. |

---

## For the curious (you can skip this)

- **What gets created.** In Azure: a resource group `<name>-rg` with an AKS cluster, a PostgreSQL server, storage and a Key Vault. On the cluster: DIGIT core 3.0, its backbone (Kafka, Redis, MinIO, Vault, Elasticsearch, Kibana, ingress, cert-manager) and monitoring (Prometheus, Grafana, Loki, OpenTelemetry, Jaeger). Everything comes from packaged Helm charts at https://helm.digit.org, deployed with helmfile from `deploy-as-code/helm/`.
- **Passwords.** The first install makes new random passwords just for you. It locks them (SOPS encryption with your own Azure Key Vault key) and saves them as `digit-secrets.yaml` in your copy. Your copy is public, but the locked file is safe: only your Azure key can open it. No two teams share a password or a key.
- **Read or change a password** (needs the Azure CLI and `sops` on your computer):
  ```bash
  az login
  az keyvault set-policy -n <key-vault-name> --upn <your-azure-email> --key-permissions get encrypt decrypt
  sops digit-secrets.yaml      # opens the file unlocked in an editor, locks it again on save
  ```
  The Key Vault name is shown in the resource group `<name>-rg`. Commit the file, then run **deploy**.
- **More settings.** Everything in `deploy-as-code/helm/defaults.yaml` (versions, sizes, what to install) can be changed from `digit-config.yaml`. The optional part of that file shows examples.
- **Tenant data.** The install does not create tenants or seed data yet.
