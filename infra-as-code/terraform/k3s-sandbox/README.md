# k3s sandbox

A single Azure VM running k3s, for verifying that a DIGIT core deployment comes
up — Deployments, StatefulSets and their PVCs — without standing up a managed
cluster. It is a correctness check, not a capacity or resilience test: there is
one node, no autoscaler, and nothing survives losing it.

## What it builds

| Resource | Value |
|---|---|
| VM | `Standard_D8as_v5` — 8 vCPU, 32 GiB |
| OS disk | 128 GiB Premium SSD (also backs every `local-path` PVC) |
| Image | Ubuntu 22.04 LTS (gen2) |
| Kubernetes | k3s, pinned to the `v1.35` channel |
| Region | `centralindia` |
| Resource group | `k3s-sandbox-rg` |

## Why these choices

**8 vCPU, not 4.** The 32 GiB was the requirement; the core stack starts roughly
twenty JVMs at once and on 4 vCPU that reads as random readiness-probe failures
during rollout.

**k3s pinned to `v1.35`.** The `stable` channel was 1.36 at the time of writing.
Pinning keeps the sandbox on the same Kubernetes minor as unified QA/UAT, so a
manifest that works here works there.

**Traefik disabled, ServiceLB kept.** DIGIT ships its own ingress-nginx and two
controllers contending for :80/:443 is a confusing failure. ServiceLB (klipper)
stays on so a `type=LoadBalancer` Service still resolves to an address, the way
it would against an ELB on EKS.

**`local-path` as the default StorageClass.** k3s's built-in provisioner binds
PVCs on first consumer, which is what makes `volumeClaimTemplates` work.

**`vm.max_map_count=262144` in cloud-init.** Elasticsearch will not start at the
Ubuntu default of 65530. Managed node images set this already; a stock image
does not.

## Usage

State lives in Azure Storage, bootstrapped separately because the backend
cannot create its own container:

```bash
cd remote-state
terraform init && terraform apply          # creates RG + storage account
# copy storage_account_name into the backend block in ../main.tf
```

Then the VM. The public key is passed in; the private key is never committed:

```bash
terraform init
terraform plan  -out=tfplan -var "ssh_public_key=$(cat ~/.ssh/k3s-sandbox-key.pub)"
terraform apply tfplan
```

Connect, or pull a kubeconfig for use from a laptop:

```bash
ssh -i ~/.ssh/k3s-sandbox-key azureuser@$(terraform output -raw public_ip)

ssh -i ~/.ssh/k3s-sandbox-key azureuser@$(terraform output -raw public_ip) \
  'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed "s|127.0.0.1|$(terraform output -raw public_ip)|" > k3s-sandbox.kubeconfig
```

k3s is started with `--tls-san` on the public IP, so that rewritten address is
covered by the API server certificate.

## Access and its limits

A single shared keypair is the only way in; password auth is disabled. That key
is shared by everyone who connects, so access cannot be revoked for one person
or attributed to one person. To fix that later, append each user's own public
key to `~azureuser/.ssh/authorized_keys` and retire the shared key.

`allowed_ssh_cidrs`, `allowed_api_cidrs` and `allowed_http_cidrs` all default to
`0.0.0.0/0`, because the consuming team's egress addresses were not known when
this was built. Narrow them once they are.

## Teardown

```bash
terraform destroy          # the VM and its network
cd remote-state && terraform destroy   # the RG and tfstate account
```
