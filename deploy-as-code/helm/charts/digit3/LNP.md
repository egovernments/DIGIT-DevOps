# License & Permits (LnP) on a digit3 VM — the overlay

LnP is a business use-case built on the 16 catalogue services. On the `digit-lts`/test-lts cluster it
runs as hand-applied Deployments; here it is an **additive Helm overlay** that sits on top of
whichever shape `06-deploy.sh` installed (per-service, single-container or domain-bundles) and never
touches the shape's own releases.

```bash
cd deploy-as-code/helm/charts/digit3/scripts
./09-lnp.sh <path-to-digit3-repo> <master-tenant-admin-email>     # after 01…07 (any shape)
```

## What is deployed

| Release | Image (snapshot) | Role |
|---|---|---|
| `license-certificate` | `egovio/license-certificate` | the LnP backend (`/license`), Flyway history `public.license_certificate_schema`, business tables per tenant |
| `license-admin` `license-citizen` `license-employee` `license-validator` | nginx UIs | `/license/admin`, `/license/citizen`, `/license/employee`, `/license/validator`; API calls go to the in-cluster Kong |
| `calculator` `schema-registry` `pdf-v3` `vc` | same monorepo (`digitnxt/license-certificate`, branch `dev`) | fee rules, form/checklist schemas, PDF rendering, verifiable credentials |
| `walt` | `waltid/issuer-api` | VC issuer used by `vc` |
| `mdms-v2` | `egovio/mdms-v2` | master data for themes / UI actions |

Deliberately **not** included: `notify` (a platform choice for OTP/mail — the shapes already send OTPs
through `notification`), `metabase` (dashboards only; `CERTIFICATE_DASHBOARD_REFRESH_ENABLED=false`,
the Metabase secret refs are optional, so creating a certificate type from a template logs a
"dashboard failed" upstream warning and still saves), `oauth2-proxy` (unrelated GitHub login proxy),
OTEL export (no collector on the VMs).

## The moving parts

| File | Purpose |
|---|---|
| `lnp-helmfile.yaml` | the 11 releases; `needs:` orders walt → vc → license-certificate → UIs |
| `environments/azure-k3s-lnp-tags.yaml` | image tags, **generated** by `scripts/lnp-tags.sh` from the LnP team's `test-lts.yaml` on `origin/digit-lts` (they move daily — re-run, review, commit) |
| `environments/azure-k3s-lnp.yaml.gotmpl` | every URL from `DOMAIN`; catalogue hosts looked up in the shape overlay's `egov-service-host` map (`DIGIT_SHAPE`), so idgen resolves to `idgen`, `dev-bundle` or `admin-bundle` as the shape dictates |
| `lnp/kong-routes.json` | the 12 Kong routes (exported from test-lts); replayed by digit3's `kong/setup.py` via `KONG_EXTRA_ROUTES` — `/license`, `/calculator`, `/pdf-v3`, `/schema`, `/credential` carry `dynamic-jwt`+`header-enrichment`, `/mdms-v2` the full chain, the regex routes are public |
| `lnp/exports/` | the phase-0 captures (tags, routes, realm diff, BASETENANT master rows) — reference and fallback, not applied |
| `scripts/09-lnp.sh` | the phase script (below) |

## What 09-lnp.sh does
1. **Secrets** — adds `cluster-configs.secrets.license-certificate` (OTP bypass code, Keycloak client secret) to this environment's sops file if absent (`02-secrets.sh` writes it for new environments), re-syncs `cluster-configs` through the shape's helmfile so the Secret exists.
2. **Master tenant** — `07-seed.sh "Base Tenant" <email>` → code **`BASETENANT`**, the schema LnP's master catalogue expects (`MASTER_TENANT_SCHEMA`). The admin password is printed once by 07 and captured to `~/lnp-seed-<domain>.log` (mode 600): store it, then `shred -u` it. The realm's `auth-server` client secret is read from Keycloak into sops (never printed).
3. **Overlay** — `DOMAIN=… DIGIT_SHAPE=… ./deploy.sh -f lnp-helmfile.yaml sync`, then waits for the 11 rollouts.
4. **Kong** — `setup.py` with `KONG_EXTRA_ROUTES`; the catalogue routes are re-applied as a no-op.
5. **Onboarding** — `POST /license/onboarding/_onboard-tenant` as the BASETENANT admin. LnP provisions its own master data (certificate types, calculator rules, schemas, PDF templates, MDMS theme/access data, localisation, idgen formats, VC tenant) and `_inflate`s its sibling services — the services' own seeding path; the SQL in `lnp/exports/db/` is only a reference for diffing. Read the `steps` map it prints.
6. **Smoke** — `/license/certificate-types` through Kong, the four UIs through the ingress.

Re-running is safe: 07 reports "tenant already exists", the overlay converges, routes are PUT by
name. A re-run after the capture was shredded needs `LNP_ADMIN_PASSWORD=<the one 07 printed>`.

## Keycloak policies
The test-lts account build widens five read permissions to the CITIZEN/EMPLOYEE policies
(`billing-v3-bills-get`, `billing-v3-business-services-code-get`, `filestore-v3-document-categories-get`,
`filestore-v3-canonical-document-categories-get`, `registry-v3-code-data-registry-get`) — the LnP
citizen/employee flows hit exactly those. digit3 branch `feat/modulith-lnp-overlay` carries that
change in `account/realm_config.json`; deploy the shape with an image tag built from it (`lnp/exports/realm-policy-summary.txt`).

## Custom groupings
`09-lnp.sh` follows `scripts/.last-shape` and needs the matching `<shape>-helmfile.yaml` for the
`cluster-configs` re-sync and the host map. For a custom grouping (CUSTOM-BUNDLING.md) point
`DIGIT_SHAPE` at an `environments/azure-k3s-<name>.yaml` that carries the full `egov-service-host`
map and run the steps by hand.

## Gotchas seen so far
| Symptom | Cause / fix |
|---|---|
| `template: … bad character` rendering the overlay | Go templates cannot dot into keys with dashes — the gotmpl uses `index … "cluster-configs"`; keep it that way |
| license-certificate pod `CreateContainerConfigError: secret "license-certificate" not found` | step 1 did not run / cluster-configs not re-synced — `./deploy.sh -f <shape>-helmfile.yaml -l name=cluster-configs sync` |
| certificate type saved but the API answers 502 "building its dashboard failed" | no Metabase in the overlay — expected; the type is saved |
| `/license/*` 401 through Kong | token not issued by the in-cluster Keycloak URL / not via `auth-server` — mint with `08-token.sh` |
