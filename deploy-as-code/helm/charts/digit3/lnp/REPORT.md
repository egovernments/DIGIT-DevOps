# LnP on the modulith platform — phase 4 report

Ticket: [digitnxt/digit3#1113](https://github.com/digitnxt/digit3/issues/1113) · Date: 2026-10-02
Branches: `feat/modulith-lnp-overlay` in digit3 (15 commits on `modulith`) and DIGIT-DevOps (21 commits on `modulith`).

## 1. Outcome

License & Permits (LnP) runs end to end on all three modulith shapes, as an additive overlay on the
platform with no change to LnP's own code or images.

| VM | Shape | Platform images | API scenario | UI checks |
|---|---|---|---|---|
| mx-mono `modulith.digit.org` | per-service | `modulith-lnp-overlay-6a0bb58` | 59/59 | pass |
| mx-test `modulith-test.digit.org` | single-container (dev-bundle) | `modulith-lnp-overlay-d555d07` | 59/59 | pass |
| mx-split `domain-split.digit.org` | domain-bundles (4 bundles) | `modulith-lnp-overlay-d555d07` | 59/59 | pass |

The UI checks on every VM are:
- employee login and dashboard, all five services shown;
- the Business License review path: verify documents, complete inspection, issue the license;
- the counter cash payment advancing the application on its own, with a `PAYMENT_RECEIPT` PDF attached;
- the validator app showing the issued credential's QR as Active;
- admin studio login with e-mail OTP, the dashboard, Users & Access, and the Deployment page.

mx-split also proves the cross-bundle wiring. The billing bundle uploaded the receipt PDF to filestore in the admin
bundle and read the PDF header details from account in the identity bundle.

The LnP images are those test-lts runs, snapshotted from `origin/digit-lts`:

| Component | Tag |
|---|---|
| license-certificate | `dev-57eff95-65` |
| calculator | `dev-012afac-15` |
| schema-registry | `dev-cd093ce-1` |
| pdf-v3 | `dev-0abe325-8` |
| vc | `dev-c1dd782-2` |
| walt | `0.23.0` |
| mdms-v2 | `mdms-pagination-fix-ffb69a4` |

The four UIs ran as local per-VM builds of `dev` (`019cfc5`), because the published UI images bake test-lts URLs in at
build time (§5).

## 2. Core services: test-lts versus modulith

LnP calls the `-java` flavour of every core service on test-lts. Each image tag was mapped to its digit3 commit and
diffed against the branch. keycloak and mdms-v2 run identical images on both. accesscontrol is unused by LnP and was
already removed from digit3. Everything else differed only by bundle packing, except these imports:

| Service | What came in | Source | Why it matters for LnP |
|---|---|---|---|
| billing | payment-created event; bill and receipt PDFs uploaded to filestore | `billing-bill-pdf-filestore` up to `74873b34` | without it a paid application stays at Pending Payment |
| boundary | hierarchy search without `hierarchyType`; cache cleared on create | master `1e262352` | the admin studio Deployment page failed |
| account | realm SMTP and password reset, logout redirect URIs, `admin` client, labelled first-login URLs, signup `country`, `admin` as default actor | master | parity with the test-lts realm |
| workflow | process `isActive` flag; migrations matched to master byte for byte | master `8a3e5549`, `f3719a58` | parity; migration checksums |
| registry | schema-qualified UUID generator | master `64c76543` | tenant schemas |
| filestore | `MODULE_MANDATORY` (upload without a module) | `2725764` | billing uploads its PDFs without a module |
| otp | configurable send timeout; 503 on a notification failure | `6305193a`, `fced6fb6`, ported | parity |
| kong | `regex_priority` on routes | master `a92eee2e`, generic part only | LnP's public regex routes |

These were deliberately not imported:
- every switch to the `notify` service, in otp, account and the seed docs. Our OTP, login and e-mail path runs on
  `notification`, and no bundle runs `notify`;
- otp's self-seeding of OTP configs, which only works paired with account's removal of its own seeding.

## 3. digit3 changes beyond the imports

| Commit | Change |
|---|---|
| `02a5b3e5` | account realm: five read permissions opened to CITIZEN/EMPLOYEE, matching test-lts |
| `40fd7509`, `39d0b198` | kong `setup.py` overlay hook (`KONG_EXTRA_ROUTES`): extra services and routes, `strip_path`, `regex_priority`, and routes that attach to an existing service without re-pointing it |
| `6c159928` | billing's accounts client uses `/account` (the normalised context path), not test-lts's `/accounts` |
| `a3c36d63`, `6a0bb58c`, `d555d07d` | bundle manifests: billing PDF hosts per shape, non-fatal PDF generation, employee to individual loopback; bundles regenerated |
| `83639160` | workflow, employee, notification: an explicit `null` for a boolean or number reads as false/zero again. Jackson 3 rejects it by default; Jackson 2 and the Go originals accepted it |

All touched services build, and their unit tests pass; billing alone runs 163.

## 4. DIGIT-DevOps changes

- **Overlay.** `lnp-helmfile.yaml` adds 11 releases on any shape. `azure-k3s-lnp.yaml.gotmpl` derives every URL from
  `DOMAIN` and the shape's service-host map, calls the platform through in-cluster Kong and Keycloak, and requests CPU
  in line with actual use: 20m per UI, 50m per backend.
- **`scripts/09-lnp.sh`.**
  1. Secrets.
  2. BASETENANT via `07-seed.sh`; the one-time password goes to a 600 capture file and is never printed.
  3. Overlay sync.
  4. Kong overlay routes.
  5. LnP onboarding (5); master data (5b); access control (5c); employee-portal menus (5d).
  6. Smoke checks.
- **`lnp/seed-master-data.sh`.** Idempotent, in `all`, `data` or `menus` mode. It seeds everything onboarding does not
  provision: certificate types, workflows, billing business services and tax heads, idgen templates, OTP templates,
  document categories and employee-portal menus.
- **Shape and bundler fixes.**
  - Per-domain realm redirect and first-login URLs in the bundle overlays.
  - Billing's filestore paths pinned in `bundler/merge-rules.yaml`.
  - Billing chart PDF wiring.
- **`lnp/test/`.** API scenario, Keycloak helper, OTP fetchers for the Mailpit and SMS sinks, and a Playwright step
  driver with the local UI build/import helper.
- **`LNP.md`.** Every symptom met, with cause and fix.

## 5. Findings for the LnP team

These reproduce on test-lts too. None blocks the API flows.

1. **Citizen UI cannot submit applications for types with a category taxonomy.** Business License's form config has no
   category control. Food License collects one, but the citizen payload builder only recognises the `{selected: []}`
   shape and drops its flat-string value. The backend answers `400 category is required`, and the UI shows it as an
   OTP error.
2. **SQL-imported certificate types get no employee-portal menu.** Menus are created only on the create API, and the
   static manifest knows `TRADE_LICENSE` rather than `BUSINESS_LICENSE`. Our seed derives them.
3. **Service paths are hardcoded.** The UIs and the backend call `/accounts/v3` and `/individuals/v3` in code; the
   backend only lets the host be configured. Configurable paths would let Kong drop its two alias routes.
4. **UI images bake environment URLs at build time.** Each VM needs its own build. The `feat/move-envs-to-runtime`
   branch is 54 commits behind `dev`.
5. **Validator app calls `/accounts/v3/v3/...` for branding.** The path prefix is doubled; it falls back to defaults.
6. **Citizens must have the mobile number as their Keycloak username**, or the citizen app cannot find their profile.
7. **The logged-out citizen catalogue returns 400** because `X-User-Id` is required.

## 6. Platform findings

These are not LnP-specific, but LnP exposed them.

| Finding | Status |
|---|---|
| A redeploy migrates only `public`. Existing tenant schemas never receive new migrations; they are migrated only on a tenant-created event | worked around: `POST /internal/migrate` per tenant (per service in per-service, once per bundle). Needs a platform upgrade step |
| Edited shipped migrations (workflow, registry) fail Flyway validation on databases migrated before the edit | repaired in place on all three VMs (checksum update, verified against the old files). Fresh databases are unaffected |
| `06-deploy.sh` re-programs Kong from the catalogue only and drops overlay routes | documented: run `09-lnp.sh` (or its Kong step) after every `06` |
| The account chart hardcodes `modulith.digit.org` for realm redirect and first-login URLs | fixed in the bundle overlays. Realms created before the fix keep the wrong URIs |
| mdms-v2 (`mdms-pagination-fix`) caches searches in Redis for 1 hour and does not invalidate on create | documented: new mdms rows appear late. The cache is not flushed automatically |
| The charts' CPU requests far exceed use; single-replica Deployments roll out with `maxUnavailable: 0` | the overlay requests less. On a full node, delete the old ReplicaSet once to unblock a rollout |
| Manual `kubectl set env/image` edits block the next Helm server-side apply | documented: drop the `kubectl-set` field owner before syncing |

## 7. Test-only state left on the VMs

These are not part of the overlay, and a sync reverts or is blocked by them (see `LNP.md`):
- **mailpit and the SMS echo sink**, each with notification pointed at it via `kubectl set env`;
- **the four UI Deployments** pointed at local per-VM images;
- **test users**, whose passwords are in `~/lnp-test-users.<domain>.env` (mode 600).

## 8. Next steps

1. PRs from `feat/modulith-lnp-overlay` into `modulith` in both repos.
2. Raise §5 with the LnP team, items 1–3 first.
3. Decide on a platform tenant-migration step for upgrades (§6, first row).
4. Remove the test-only state from the VMs, or keep it for demos.
