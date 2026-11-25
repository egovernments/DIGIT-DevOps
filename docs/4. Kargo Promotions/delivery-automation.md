# Delivery automation (build -> deliver)

Make a merge ship itself. When a service is built from `develop` (or `master`), the
reusable **deliver** workflow uses the `kargo` CLI to promote the freshly built image to a
target environment's Kargo stage, so it reaches the cluster without a manual promote click.

It is generic and multi-environment: every environment's Kargo project, URL, API key and
kubeconfig come from the consumer repo's own variables and secrets.

## The reusable workflow

`egovernments/DIGIT-DevOps/.github/workflows/reusable-deliver.yaml@reusable-build-v1`

| Input | From | Meaning |
|---|---|---|
| `service` | the build | service/chart name; promotes the `<service>-<stage>` Kargo stage |
| `image_tag` | the build output | **required**; the Freight carrying this exact tag is promoted (not the latest) |
| `environment` | the caller | which env in `KARGO_STAGES` to deliver to (e.g. `DEV`) |
| `stage` | optional | stage suffix; empty = lowercased `environment` |
| `kargo_url` | `vars.KARGO_URL` | default Kargo API URL |
| `kargo_stages` | `vars.KARGO_STAGES` | JSON map of envs (below) |
| `kargo_version` | optional | Kargo CLI version; match the server (default `v1.11.4`) |

## Repo configuration

**Variables**

- `DELIVERY_MODE` - repo switch: `automatic` enables auto build+deliver on a push to
  develop/master (and auto-deliver after a dispatched build); anything else (default) is
  `manual` - a merge does nothing and a dispatched build only builds, you promote in Kargo.
- `KARGO_URL` - default Kargo API URL, e.g. `https://kargo.digit.org`.
- `KARGO_STAGES` - JSON mapping each environment to its Kargo project and an optional
  per-env URL override (empty = use `KARGO_URL`):

  ```json
  {
    "DEV": { "kargo-project": "hcm-3-0", "kargo-url": "" },
    "QA":  { "kargo-project": "hcm-3-0", "kargo-url": "" },
    "UAT": { "kargo-project": "hcm-3-0", "kargo-url": "" }
  }
  ```

**Secrets**

- `<ENV>_API_KEY` - the Kargo API bearer token for that env (e.g. `DEV_API_KEY`).
  If unset, `KARGO_API_KEY` is used as the default.
- `<ENV>_KUBECONFIG` - a read kubeconfig for that env's cluster, used to verify the rollout
  after promotion. **No default**; the verify step is skipped if it is absent.

`DEV`, `QA` and `UAT` are wired. (Actions cannot index a secret by a computed name, so the
env secrets are declared explicitly; add another environment by extending the workflow's
`secrets`/`env` the same way.)

## How it runs

1. Resolves the environment: `kargo-project` + URL from `KARGO_STAGES`, the API key
   (`<ENV>_API_KEY` else `KARGO_API_KEY`), and the kubeconfig (`<ENV>_KUBECONFIG`).
2. Authenticates the `kargo` CLI with env vars `KARGO_API_ADDRESS` + `KARGO_API_TOKEN`
   (there is no `--token` login flag). The token is a Kargo API bearer token - a Kubernetes
   ServiceAccount token (e.g. `github-actions-promoter` in the `kargo` namespace) with
   promote RBAC.
3. `kargo refresh warehouse <service>`, then selects the Freight from that Warehouse whose
   image artifact equals `image_tag` and `kargo promote --freight <name> --stage <service>-<stage>`.
   It promotes **the Freight carrying this build's image** - never the latest or a manually
   assembled one - and retries while discovery catches up.
4. If a kubeconfig was provided, waits for the Deployment to roll out on that cluster.

Kargo writes the promoted image + chart version into the module's `environments/digit-3.0/`
values file; Argo CD then reconciles the cluster. Promotion is linear - `dev` takes from the
Warehouse, `qa` only from `dev`, `uat` only from `qa`.

> **Warehouses must mint Freight automatically.** `--warehouse` promotes the latest Freight, so
> the service Warehouses need `freightCreationPolicy: Automatic` in the Kargo project
> (`charts/kargo/config/projects/<ns>.yaml`). With the default `Manual`, a build is discovered
> but no Freight is created, so there is nothing to promote.

## Wiring it into a build (the generic template)

Add a `deliver` job to the consumer's build workflow, gated on the ship branches, that runs
after the build and passes the built tag through. `secrets: inherit` forwards the env keys
and kubeconfigs.

```yaml
  deliver:
    needs: build
    if: ${{ github.ref_name == 'develop' || github.ref_name == 'master' }}
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-deliver.yaml@reusable-build-v1
    with:
      service: ${{ inputs.service }}
      image_tag: ${{ needs.build.outputs.docker_image }}   # or its tag portion
      environment: DEV                                      # develop/master -> unified-dev
      kargo_url: ${{ vars.KARGO_URL }}
      kargo_stages: ${{ vars.KARGO_STAGES }}
    secrets: inherit
```

## First-run checklist

- [ ] `KARGO_URL` + `KARGO_STAGES` set as repo variables.
- [ ] `KARGO_API_KEY` (or `<ENV>_API_KEY`) set as a secret.
- [ ] `<ENV>_KUBECONFIG` set if you want the rollout verified.
- [ ] The Kargo project exists and has a `<service>` Warehouse and `<service>-<stage>` Stage.
- [ ] Confirm the `kargo` CLI version matches the server (`kubectl -n kargo get deploy kargo-api -o jsonpath='{.spec.template.spec.containers[0].image}'`).
