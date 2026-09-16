# DIGIT 3 Single Modulith on k3s — Installation Steps

The complete install as a 30-step runbook for the **single modulith
(dev-bundle) shape with Vault PII encryption** — every command, `cd`, and file
edit in order. Background, alternatives (per-service / domain bundles), and
the troubleshooting table live in [INSTALL.md](INSTALL.md); section references
below point there.

Placeholders: `<key>` = SSH private key, `<domain>` = the VM's DNS name,
`<TENANT>` = your (UPPERCASE) tenant code.

## Phase 0 — Workstation setup

**1.** Install the toolchain: `kubectl`, `helm` (v4), `helmfile` (v1.7+),
`sops`, `age`, `docker` with buildx, JDK 25 (Temurin), Maven 3.9+, and
`python3` with `pyyaml` + `requests`.

**2.** Clone both repos side by side:

```bash
cd ~/Documents
git clone -b modulith-vault https://github.com/egovernments/DIGIT-DevOps.git
git clone -b modulith https://github.com/digitnxt/digit3.git
```

## Phase 1 — VM and cluster (§1.1–1.3)

**3.** Provision an Ubuntu 22.04 VM (8 vCPU, 16–32 GB RAM, 100 GB disk), map
its public IP to `<domain>`, open port 22 only (defer 80/443 until you need
Let's Encrypt).

**4.** Install k3s on the VM:

```bash
ssh -i <key> azureuser@<domain>
curl -sfL https://get.k3s.io | sh -s - --disable traefik
sudo k3s kubectl get nodes    # wait for Ready, then exit
```

**5.** Open the SSH tunnel from the workstation:

```bash
ssh -f -N -L 16443:127.0.0.1:6443 -i <key> azureuser@<domain>
```

**6.** Fetch the kubeconfig and **point it at the tunnel port** (skipping the
`sed` gives `connection refused 127.0.0.1:6443`):

```bash
ssh -i <key> azureuser@<domain> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/modulith-kubeconfig.yaml
sed -i '' 's|server: https://127.0.0.1:6443|server: https://127.0.0.1:16443|' ~/modulith-kubeconfig.yaml   # macOS; drop '' on Linux
export KUBECONFIG=~/modulith-kubeconfig.yaml
kubectl get nodes
```

## Phase 2 — Secrets and environment (§1.4–1.5)

**7.** Create the age key — or reuse an existing one — and **back it up**
off-machine (it is the only key to the secrets):

```bash
age-keygen -o ~/.config/sops/age/keys.txt
# "file exists" → reuse it; print the recipient: age-keygen -y ~/.config/sops/age/keys.txt
mkdir -p ~/Library/Application\ Support/sops/age    # macOS only
ln -sf ~/.config/sops/age/keys.txt ~/Library/Application\ Support/sops/age/keys.txt
```

**8.** Edit `DIGIT-DevOps/deploy-as-code/helm/.sops.yaml`: add a creation rule
with your age recipient for `environments/azure-k3s-secrets.yaml`.

**9.** Create `environments/azure-k3s-secrets.yaml` (same YAML shape as
`test-lts-secrets.yaml`: `cluster-configs.secrets.*` for db, minio, kc-db,
kc-admin, hmac, citizen-broker, employee-iam, kafka-kraft `kraft-cluster-id`,
plus SMTP/SMS/Stripe placeholders) with fresh passwords, then encrypt in
place:

```bash
cd ~/Documents/DIGIT-DevOps/deploy-as-code/helm
sops -e -i environments/azure-k3s-secrets.yaml
```

**10.** Edit `environments/azure-k3s.yaml`: set `global.domain`, the
namespace list, `db-host` (host-only) plus the full JDBC URL, Kafka brokers
(`release-name-kafka-controller-headless.backbone:9092`), and pinned image
tags for every backbone release (chart defaults resolve to `:latest`, which
does not exist).

## Phase 3 — Backbone and Keycloak DB (§1.6–1.7)

**11.** Deploy the backbone — always `sync`, never `apply` (helm-diff is
broken on helm v4):

```bash
cd charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml sync
```

**12.** Create the Keycloak database **and role** (the role half is what
crash-loops Keycloak with `password authentication failed` when skipped):

```bash
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE new_keycloak"
U=$(kubectl get secret kc-db -n keycloak -o jsonpath='{.data.username}' | base64 -d)
P=$(kubectl get secret kc-db -n keycloak -o jsonpath='{.data.password}' | base64 -d)
printf "CREATE ROLE %s LOGIN PASSWORD '%s';
GRANT ALL PRIVILEGES ON DATABASE new_keycloak TO %s;
ALTER DATABASE new_keycloak OWNER TO %s;\n" "$U" "$P" "$U" "$U" | \
  kubectl exec -i -n egov postgresql-lts-0 -- psql -U postgres
```

## Phase 4 — Vault (§1.8)

**13.** Deploy Vault:

```bash
./deploy.sh -f backboneservices-helmfile.yaml -l name=vault sync
```

**14.** Initialize and unseal — the in-pod command reads the key on stdin, so
pipe it (run bare it sits waiting and looks stuck):

```bash
kubectl exec vault-0 -n vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json > init.json
jq -r '.unseal_keys_b64[0]' init.json | \
  kubectl exec -i vault-0 -n vault -- sh -c 'read -r K; vault operator unseal "$K"'
```

**15.** Store `unseal_keys_b64[0]` and `root_token` under `vault-operator:`
in the sops file, **then** delete the plaintext:

```bash
sops ../../environments/azure-k3s-secrets.yaml
rm init.json
```

**16.** Enable transit + AppRole as root inside the pod:

```bash
kubectl exec -it vault-0 -n vault -- sh
vault login                      # paste the root token
vault secrets enable transit
vault auth enable approle
vault policy write digit-transit - <<'EOF'
path "transit/encrypt/*" { capabilities = ["create","update"] }
path "transit/decrypt/*" { capabilities = ["update"] }
EOF
vault write auth/approle/role/individual token_policies=digit-transit token_ttl=1h token_max_ttl=4h
vault read -field=role_id  auth/approle/role/individual/role-id
vault write -f -field=secret_id auth/approle/role/individual/secret-id   # run ONCE — each call mints a new one
exit
```

**17.** Store both ids under `cluster-configs.secrets.vault-approle`
(`role-id` / `secret-id`) in the sops file, then re-render the k8s secret:

```bash
sops ../../environments/azure-k3s-secrets.yaml
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync
```

## Phase 5 — Build the bundle

**18.** Generate the bundle module from the manifest:

```bash
cd ~/Documents/digit3
python3 src/bundles/generate_bundle.py src/bundles/dev-bundle.package.yaml
# must print "no unresolved property conflicts" — never ignore that warning
```

**19.** Build the app image:

```bash
TAG=modulith-$(git rev-parse --short HEAD)
docker buildx build --platform linux/amd64 --load -t egovio/dev-bundle:$TAG \
  -f src/bundles/dev-bundle/Dockerfile .
```

**20.** Build the db-migration image — same source tree, same `$TAG`
(a mismatched pair fails Flyway checksum validation):

```bash
docker buildx build --platform linux/amd64 --load -t egovio/dev-bundle-db:$TAG \
  src/bundles/dev-bundle/src/main/resources/db
```

**21.** Load both images straight into the node's containerd (no registry):

```bash
docker save egovio/dev-bundle:$TAG    | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
docker save egovio/dev-bundle-db:$TAG | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
```

## Phase 6 — Chart and database (§4.2)

**22.** Generate the bundle chart:

```bash
cd ~/Documents/DIGIT-DevOps/deploy-as-code/helm/bundler
python3 generate_bundle_chart.py --manifest ~/Documents/digit3/src/bundles/dev-bundle.package.yaml
# → charts/bundles/dev-bundle ; read the generation report
```

**23.** Create the bundle's database:

```bash
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE bundle_db"
```

## Phase 7 — Wire the environment (§4.3)

**24.** Edit the `dev-bundle:` block in `environments/azure-k3s.yaml`:

- `image.tag` **and** `dbMigrations.combined.image.tag` = `$TAG` — the tag
  only; `db` belongs in the repository name (`dev-bundle-db:<TAG>`), never in
  the tag — plus `pullPolicy: IfNotPresent`
- `env`: `DB_NAME: bundle_db`, `TENANT_MIGRATION_ENABLED: "true"`,
  `KEYCLOAK_PUBLIC_BASE_URL: https://<domain>/keycloak`, minio S3 overrides
  (`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the minio secret,
  `S3_ENDPOINT: minio.backbone.svc.cluster.local:9000`, `S3_USE_SSL: "false"`)
- `dbMigrationOrder: [combined]` and a `dbMigrations.combined` entry with
  `DB_URL` pointing at `bundle_db`
- repoint the bundled services' `egov-service-host` keys at
  `http://dev-bundle.egov.svc.cluster.local:8080/`
- Vault on: `VAULT_ENABLED: "true"` (the `vault-approle`/`hmac-secret`
  refs ship as chart defaults)

## Phase 8 — Deploy and route (§4.4)

**25.** Deploy the services and wait for the bundle:

```bash
cd ../charts/digit3
./deploy.sh -f digit3services-helmfile.yaml sync
kubectl get pods -n egov -l app=dev-bundle    # 1/1 Running
```

**26.** Program Kong from the same manifest:

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd ~/Documents/digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
```

## Phase 9 — Verify (§1.8 Verify)

In-cluster calls are most reliable from the VM
(`ssh <vm> 'curl http://<ClusterIP>:8080/…'`); get the bundle's ClusterIP with
`kubectl get svc dev-bundle -n egov`.

**27.** Create a tenant — this creates the Keycloak realm and fires the
Kafka tenant-migration event (no manual `/internal/migrate` needed):

```bash
curl -X POST http://<dev-bundle-ip>:8080/account/v3/tenants \
  -H 'Content-Type: application/json' \
  -d '{"name":"My Tenant","email":"admin@example.org","phone":"+91XXXXXXXXXX"}'
# 201; tenant code derives UPPERCASE from the name; phone must be E.164
```

**28.** Register the tenant's `individual` idgen template (individuals fail
with `idgen returned status=404 "template not found"` without it):

```bash
curl -X POST http://<dev-bundle-ip>:8080/idgen/v3/template \
  -H 'Content-Type: application/json' -H 'X-Tenant-ID: <TENANT>' -H 'X-User-ID: admin' \
  -d '{"templateCode":"individual","config":{"template":"IND-{DATE:yyyy}-{SEQ}",
       "sequence":{"scope":"GLOBAL","start":1,"padding":{"length":6,"char":"0"}}}}'
```

**29.** Create an individual with a mobile number — the 201 response returns
it in plaintext:

```bash
curl -X POST http://<dev-bundle-ip>:8080/individual/v3/individuals \
  -H 'Content-Type: application/json' -H 'X-Tenant-ID: <TENANT>' -H 'X-User-ID: admin' \
  -d '{"givenName":"First","familyName":"Person","mobileNumber":"9876543210","gender":"OTHER"}'
```

**30.** Verify the encryption end to end:

```bash
# DB holds ciphertext + a keyed blind index, not the number
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -d bundle_db \
  -c "SELECT individualid, mobilenumber, hashedmobilenumber FROM \"<TENANT>\".individual_v3"
# mobilenumber = vault:v1:… ; hashedmobilenumber = HMAC hex

# per-tenant transit key was auto-created on first encrypt
sops -d --extract '["vault-operator"]["root-token"]' ../../environments/azure-k3s-secrets.yaml | \
  kubectl exec -i vault-0 -n vault -- sh -c 'read -r T; VAULT_TOKEN="$T" vault list transit/keys'
```

## Ongoing operations

- **After every Vault pod restart** the seal closes; re-unseal from the sops
  file (key never displayed):

  ```bash
  sops -d --extract '["vault-operator"]["unseal-key"]' environments/azure-k3s-secrets.yaml | \
    kubectl exec -i vault-0 -n vault -- sh -c 'read -r K; vault operator unseal "$K"'
  ```

- **After VM reboots** (or when kubectl starts timing out), re-open the SSH
  tunnel from step 5.
- Anything failing? Start with the **gotchas table** at the end of
  [INSTALL.md](INSTALL.md) — it maps symptoms to fixes.
