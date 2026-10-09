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
| `environments/azure-k3s-lnp.yaml.gotmpl` | every URL from `DOMAIN`; catalogue hosts looked up in the shape's generated `egov-service-host` map (`environments/generated/<DIGIT_SHAPE>-service-hosts.yaml`), so idgen resolves to `idgen`, `dev-bundle` or `admin-bundle` as the shape dictates |
| `lnp/kong-routes.json` | the 12 Kong routes (exported from test-lts); replayed by digit3's `kong/setup.py` via `KONG_EXTRA_ROUTES` — `/license`, `/calculator`, `/pdf-v3`, `/schema`, `/credential` carry `dynamic-jwt`+`header-enrichment`, `/mdms-v2` the full chain, the regex routes are public |
| `lnp/exports/` | the phase-0 captures (tags, routes, realm diff, BASETENANT master rows) — reference and fallback, not applied |
| `scripts/09-lnp.sh` | the phase script (below) |

## What 09-lnp.sh does
1. **Secrets** — adds `cluster-configs.secrets.license-certificate` (OTP bypass code, Keycloak client secret) to this environment's sops file if absent (`02-secrets.sh` writes it for new environments), re-syncs `cluster-configs` through the shape's helmfile so the Secret exists.
2. **Master tenant** — `07-seed.sh "BASETENANT" <email>` → code **`BASETENANT`** (name == code: the LnP UIs look the tenant up by name), the schema LnP's master catalogue expects (`MASTER_TENANT_SCHEMA`). The admin password is printed once by 07 and captured to `~/lnp-seed-<domain>.log` (mode 600): store it, then `shred -u` it. The realm's `auth-server` client secret is read from Keycloak into sops (never printed).
3. **Overlay** — `DOMAIN=… DIGIT_SHAPE=… ./deploy.sh -f lnp-helmfile.yaml sync`, then waits for the 11 rollouts.
4. **Kong** — `setup.py` with `KONG_EXTRA_ROUTES`; the catalogue routes are re-applied as a no-op.
5. **Onboarding** — `POST /license/onboarding/_onboard-tenant` as the BASETENANT admin. LnP provisions its own master data (certificate types, calculator rules, schemas, PDF templates, MDMS theme/access data, localisation, idgen formats, VC tenant) and `_inflate`s its sibling services — the services' own seeding path; the SQL in `lnp/exports/db/` is only a reference for diffing. Read the `steps` map it prints.
6. **Smoke** — `/license/certificate-types` through Kong (the run fails unless it answers 200), the four UIs through the ingress.

Re-running is safe: 07 reports "tenant already exists", the overlay converges, routes are PUT by
name. A re-run after the capture was shredded needs `LNP_ADMIN_PASSWORD=<the one 07 printed>`.

## Keycloak policies
The test-lts account build widens five read permissions to the CITIZEN/EMPLOYEE policies
(`billing-v3-bills-get`, `billing-v3-business-services-code-get`, `filestore-v3-document-categories-get`,
`filestore-v3-canonical-document-categories-get`, `registry-v3-code-data-registry-get`) — the LnP
citizen/employee flows hit exactly those. digit3 branch `feat/modulith-lnp-overlay` carries that
change in `account/realm_config.json`; deploy the shape with an image tag built from it (`lnp/exports/realm-policy-summary.txt`).

## Custom groupings
`09-lnp.sh` follows `scripts/.last-shape`, so a custom grouping installed with
`install.sh --shape <path>/<name>.package.yaml` (CUSTOM-BUNDLING.md) works as is: it uses the generated
`<name>-helmfile.yaml` and `environments/generated/<name>-service-hosts.yaml`, and programs Kong from
`<digit3>/src/bundles/<name>.package.yaml` — it stops before deploying anything if that manifest is
missing from the digit3 checkout passed to it.

## Testing
`lnp/test/` (test-only, never part of the overlay):
- `mk-employees.sh` — the four officers through LnP's own `_provision-employees` (verifier
  `priya.verma`, inspector `arjun.rao`, approver `meera.nair`, counter `ravi.kumar`, all
  `@<domain>`) plus the citizen `lnp-citizen@<domain>`; passwords go to the users file, never printed.
- `scenario.sh` — the end-to-end API scenario (59 checks) as those users; Business License applies
  without a category (the taxonomy is off).
- `ui/build-ui.sh` + `ui/deploy-local-ui.sh` — the published UI images compile in uat-lts's Keycloak
  URL, so officer/admin sign-in on any other VM needs per-VM images: build them for the domain and
  import them after every install (a later `lnp-helmfile.yaml` sync reverts to the published tags).

## Gotchas seen so far
| Symptom | Cause / fix |
|---|---|
| `template: … bad character` rendering the overlay | Go templates cannot dot into keys with dashes — the gotmpl uses `index … "cluster-configs"`; keep it that way |
| license-certificate pod `CreateContainerConfigError: secret "license-certificate" not found` | step 1 did not run / cluster-configs not re-synced — `./deploy.sh -f <shape>-helmfile.yaml -l name=cluster-configs sync` |
| certificate type saved but the API answers 502 "building its dashboard failed" | no Metabase in the overlay — expected; the type is saved |
| `/license/*` 401 through Kong | token not issued by the in-cluster Keycloak URL / not via `auth-server` — mint with `08-token.sh` |
| schema-registry / vc `Init:CrashLoopBackOff`, V2 fails with `relation "schema_definition" does not exist` | the LnP `-db` images run Flyway with `-baselineOnMigrate=true` and no `-baselineVersion` against `public`, which is never empty on a shared DIGIT database → Flyway baselines at 1 and skips `V1__init_table.sql` (every LnP history table shows `1 \| << Flyway Baseline >>`; test-lts only works because its `public` already had the tables). The overlay sets `FLYWAY_BASELINE_VERSION=0` on the init containers. A cluster that already hit it: `kubectl scale deploy <svc> -n egov --replicas=0` first (a crash-looping old pod re-baselines the moment the table is gone), drop the baseline-only history tables (`schema_registry_schema`, `vc_schema`, `calculator_schema`, `pdf_v3_schema`), scale back to 1 and re-run 09. Upstream fix belongs in the monorepo's `migrate.sh` (`-baselineVersion=0`). |
| `license-certificate` → `POST /accounts/v3/tenants` fails with `PKIX path building failed` | the service was calling the platform through the public URL while the VM served a Let's Encrypt-rate-limited (fake) cert. The overlay points `domain`/`keycloak-host`/`individual-host` at the in-cluster Kong and Keycloak; keep it that way |
| onboarding step `individual-config` / employee provisioning: Tomcat 404 from individual | LnP (built against the test-lts platform) calls `/individuals/v3/…` and `/accounts/v3/…`; modulith serves `/individual`, `/account`. `lnp/kong-routes.json` carries two `strip_path` alias routes that loop the plural path back through Kong at the singular one |
| `_provision-employees` → `DOWNSTREAM_ERROR: failed to validate user ID` | the `digit3/employee` chart hardcoded `KEYCLOAK_BASE_URL=https://digit-lts.digit.org/keycloak`; it now defaults to the in-cluster Keycloak (`keycloak-base-url` value) |
| apply → 502, otp says `Notification.Unavailable` | (a) notification template `sms-otp-generic` missing — `07-seed.sh` seeds only `sms-otp-login`; LnP's OTP purpose maps to the generic template. (b) the SMS provider is a placeholder on the VMs — for tests point `SMS_PROVIDER_URL` at a 200-sink (`lnp/test/`), or configure a real provider. Also: a failed lookup falls back to tenant `global`, which has no schema → `BadSqlGrammarException` noise in notification's log |
| `_verify` → `otp.code: size must be between 0 and 20` | the bypass code in sops was 24 chars; `02-secrets.sh`/`09-lnp.sh` now generate 16 |
| after `ISSUE_LICENSE` the application sits in `PAYMENT_SETUP_PENDING`; calculator says `Billing.Rejected … UNKNOWN_TAX_HEAD` | the tax heads the calculator rules reference must exist in billing for that business service — the test-lts export covered four of the six types. `_retry-payment-setup` resumes the application once they exist |
| apply → `idgen rejected … template '<TYPE>-app-basetenant'` | each certificate type names its own idgen templates (`idFormatConfig.*TemplateCode`); `_onboard-tenant` seeds the billing/individual ones only — create `<TYPE>-app-basetenant` and `<TYPE>-cert-basetenant` per type |
| paid bill does not move the application to `PENDING_ISSUANCE` (API payment, or the counter's **Pay License Fee → Record cash payment** in the employee UI: bill turns `PAID`, application stays *Pending Payment*) | **resolved from digit3 `36a5a8e8`** (billing-bill-pdf-filestore imported): billing publishes `PAYMENT_CREATE` on `billing-create-payment` with the receipt PDF's `fileStoreId`; license-certificate runs `PAY_LICENSE_FEE` itself and attaches a `PAYMENT_RECEIPT` document. Verified on mx-mono by API and by the counter's UI cash payment. Images older than that still need the manual `PAY_LICENSE_FEE` transition |
| workflow `POST /process/definition` → `Invalid input data` | modulith's workflow takes a flat body (`code,name,…,states[{…,actions[{code,label,nextState,roles}]}]`) with state **codes**, not the test-lts export's `{process,states}` with state ids — see `lnp/test/wf-transform.py` |
| employee portal hides a certificate type (e.g. Business License) although `/license/certificate-types` lists it and its PermissionActions exist | the type was imported by SQL, so license-certificate's create-time menu provisioning (`CertificateTypeMenuProvisioningService`, derives `LC_<CODE>_{MODULE,REPORTS,INBOX,SEARCH,APPLY}` into mdms `access.UIActions`/`access.PermissionActions`) never ran, and `_provision-ui-actions` only ships a static manifest naming `TRADE_LICENSE`, not `BUSINESS_LICENSE`. `lnp/seed-master-data.sh` now derives and writes the ten records for every type that lacks `LC_<CODE>_MODULE` |
| newly created mdms records (menus, themes, actions) do not show up in searches for up to an hour, while a lookup by a single `uniqueIdentifiers` value finds them | the deployed `egovio/mdms-v2:mdms-pagination-fix-*` caches every search response in Redis (`redis.backbone`, key = SHA-256 of the criteria incl. identifier order, TTL `spring.redis.cache.expiration.hours=1`) and the create path has its cache invalidation commented out (only update invalidates). Wait for the TTL or clear the `mdms:*` / `inverse:*` keys in Redis after seeding |
| citizen UI: submitting an application fails after the OTP with "That code is incorrect or has expired"; license-certificate logs `400 … category is required: certificate type '<TYPE>' has a category taxonomy configured` | LnP UI/data, same images and config as test-lts, two causes: (a) `BUSINESS_LICENSE` has `categoryConfig.enabled=true` but its form config has no `cascading_dropdown` control, so nothing collects a category; (b) `FOOD_LICENSE` does collect one (`activityPath`, string-typed), but the citizen payload builder (`deriveCategoryPath` in `packages/shared/src/flow/applicationPayload.ts`) only recognises the `{ selected: [] }` object shape, so the flat-string path is never sent as `category`. Citizen submits work through the API with `category` set; employee flows were tested on an API-created application |
| employee portal console: `Tenant bootstrap failed: could not load tenant account/config TypeError: Failed to fetch` on every page | benign — the `/accounts/v3/config` fetch is aborted by the Keycloak redirect during login and retried successfully afterwards (visible as `net::ERR_ABORTED` then `200`) |
| validator app: console shows `GET /accounts/v3/v3/tenants … 400` and `/accounts/v3/v3/config 400` (branding falls back to defaults; verification itself works) | LnP UI (`dev`): `VALIDATOR_API_PATHS.accounts` already ends in `/v3` and `tenantAccountClient.ts` appends `/v3/…` again. Same code on test-lts |
| admin studio → Deployment page: "Could not load boundary hierarchies from the server" | the page calls `GET /boundary/v3/hierarchy` with no `hierarchyType`, which modulith's boundary rejects (`400 Missing hierarchyType query parameter`); the LnP tenant has no boundary hierarchy anyway (`boundaryConfig.enabled=false` on every type). test-lts runs boundary `1e262352` (branch `boundary-exemplar`), which makes `hierarchyType` optional and clears the tenant search cache on create — digit3 fix to cherry-pick into the modulith branch |
| citizen UI shows no profile / "My Applications" for a citizen created through the API (e.g. `lnp/test/mk-user.sh`), and calls `/individuals/v3/individuals?mobileNumber=<email>` | the citizen app treats the Keycloak `preferred_username` as the mobile number; citizens must be registered with the mobile number as username (the UI registration does this). Add a `mobileNumber` attribute AND a mobile-number username when creating citizens for UI tests |
| after redeploying at a new tag, tenant calls fail with `BadSqlGrammarException` / `column … does not exist` (workflow `is_active`, billing `bills.filestore_id`), while public works | the init containers migrate only `public`; existing tenant schemas are migrated only when a tenant-created event arrives, so new migrations never reach them. Per service with new migrations and per existing tenant: `curl -XPOST http://localhost:8080/<svc>/internal/migrate -H 'X-Tenant-ID: <TENANT>' -d '{"tenantId":"<TENANT>"}'` (from inside the pod). A platform-level upgrade step is still missing |
| redeploy init container fails Flyway validate with a checksum mismatch on workflow `V20250909143{1,3,4,6,7}00` / registry `V2025103000{2..5}` | those shipped migrations were edited (now byte-identical to master). On a database migrated before that, update `checksum` in every `<schema>.workflow_schema` / `registry_schema` row to the new Flyway checksum (CRC32 over lines) — what `flyway repair` does; fresh databases are unaffected |
| `deploy.sh … sync` → `UPGRADE FAILED: conflict … with "kubectl-set"` | a test-only `kubectl set env/image` (SMS/SMTP sinks on notification, local UI images) owns those fields and Helm's server-side apply refuses to take them. Remove the env (`kubectl set env … NAME-`) or drop the `kubectl-set` entry from `.metadata.managedFields`, sync, then re-apply the test-only change |
| after `06-deploy.sh` re-runs on a VM that already has the overlay, LnP calls get Kong `404 no Route matched` (`/individuals`, `/accounts`, the public workflow read) | fixed: 06 now re-applies `lnp/kong-routes.json` itself when `license-certificate` is deployed, with the in-cluster proxy hostnames. With an older checkout, re-run `09-lnp.sh` step 4 (`setup.py` with `KONG_EXTRA_ROUTES=lnp/kong-routes.json`) after every 06 |
| bundle shapes: in-bundle tenant migration | one `POST http://localhost:8080/internal/migrate` (no service prefix) migrates every bundled member for that tenant |
| single-container / domain-bundles: UI login → Keycloak "Invalid parameter: redirect_uri"; realm clients allow only `https://modulith.digit.org/*` | the account chart hardcoded `CLIENT_REDIRECT_URL` / `FIRST_LOGIN_URLS` for modulith.digit.org (per-service too); it now takes them from `global.domain`. A realm created before the fix keeps the wrong URIs — update its admin/citizen/employee clients (`redirectUris`, `webOrigins`, `post.logout.redirect.uris`) |
| bundle shapes: `_provision-employees` → every employee `DOWNSTREAM_ERROR: failed to validate individual ID` | the charts set `INDIVIDUAL_ENABLED=true`, but the bundle manifests had no loopback for `employee.individual.host`, so employee called the standalone default `localhost:8086`. Both manifests now loop it back — fixed in bundle images from digit3 `d555d07` (verified on mx-test and mx-split). Older bundle images need `INDIVIDUAL_HOST=http://localhost:8080/` on the bundle |
| bundle shapes: bill PDF deferred / receipt PDF skipped with `Bad authority` | the billing chart's relative filestore paths were harvested into the bundle chart while the bundle host has no trailing slash (`http://localhost:8080filestore/…`). `bundler/merge-rules.yaml` now pins `BILLING_FILESTORE_{UPLOAD,DOWNLOAD}_PATH` to billing's leading-slash form, like its idgen/apportion paths |
| fresh tenant: employee-portal menus `SCHEMA_DEFINITION_NOT_FOUND_ERR` | the menu step ran before access control created the mdms `access.*` schemas; `09-lnp.sh` now seeds `data` before 5c and `menus` after it (5d) |
| domain-split: LnP UIs (then backends) stay `Pending` — `0/1 nodes are available: Insufficient cpu`, while `kubectl top` shows the VM ~5% busy | CPU *requests*, not usage: four bundle JVMs + Postgres reserve 2.5 of the 4 vCPUs, and the charts asked 100-200m per LnP pod (idle at 2-6m). The overlay now requests 20m per UI and 50m per LnP backend (memory and limits unchanged) |
| any rollout on a node with no CPU-request headroom never finishes (`exceeded its progress deadline`, old and new pod both held) | the shared chart pins `maxUnavailable: 0` for single-replica Deployments, so the new pod must schedule before the old one stops. One-time unblock: delete the Deployment's old ReplicaSets (`kubectl delete rs <old>`; the new ReplicaSet stays). Hit on mx-split for the LnP releases and for `notification-bundle` (500m) after a `kubectl set env` |
| with a real SMTP provider, every admin login ends in "Invalid username or password" although the OTP mail arrives seconds later; Keycloak logs `OTP generate failed HTTP 503 … request timed out` | the e-mail/SMS OTP authenticator calls otp → notification → provider synchronously (`NOTIFY_ASYNC=false`) and a Gmail send measures 5-7s, longer than Keycloak's `HTTP_CLIENT_REQUEST_TIMEOUT_MS=5000`. The keycloak chart now sets 14000 (below otp's own 15s notify timeout) |
| test-lts logins accept `123456` | test-lts sets `OTP_EMAIL_DEFAULT_OTP`, `OTP_SMS_DEFAULT_OTP` and `OTP_REGISTRATION_DEFAULT_OTP` on Keycloak. The SPI accepts that code at verification for any user ("Default OTP bypass accepted") — a master code, not a fallback for failed sends. Deliberately NOT set on the modulith VMs; a demo-only decision if ever enabled |
| citizen app shows `LPMS_CIT_UNABLE_TO_LOAD_TENANT … (404)` right after a `06-deploy.sh` run | the `/accounts` alias route is gone until the LnP Kong step re-runs (same cause as the row above about 06 dropping overlay routes — fixed the same way) |
| SMS OTPs never arrive although notification logs `SMSCountry response: SMS message(s) sent` | India's DLT rules: the operator delivers only the registered template text. The seeded `sms-otp-login` / `sms-otp-generic` wording was not it; both templates must carry the approved text exactly — `Dear Citizen, Your Login OTP is {{.otp}}` + two line breaks + `EGOVS` (07-seed and seed-master-data now create it so). Changing an existing template: `PUT` only adds a new version while otp always requests `v1`, so delete every version (`DELETE …?templateId=&version=`) and `POST` again; check with `POST /notification/v3/template/preview`. Verified delivered to a real handset on 2026-10-03 |
| citizen online payment (Stripe) — what is needed for it to work | pg-service must read `STRIPE_SECRET_KEY` from the `egov-pg-service` secret (chart fix) with a Stripe **test-mode** key in sops; the citizen must be a Keycloak user whose username is the mobile number (UI registration) with the profile step done; the application must be at Pending Payment. Verified 2026-10-03 on single-container: Pay Now → Stripe Checkout (sandbox, card 4242…) → callback → `PAYMENT_CREATE` event → `PAY_LICENSE_FEE` → Pending Issuance, receipt PDF on the application |
