# inji-config

Property files served by the Inji `config-server` to eSignet, Inji Certify and
Mimoto. This directory is the config repo — `config-server` clones
`egovernments/DIGIT-DevOps` at branch `digit-lts` and reads from here via
`gitRepo.searchFolders`, configured in
`deploy-as-code/helm/charts/inji-services/values/test-lts/config-server.yaml`.

Chosen over forking `inji/inji-config` so there is one repo and one set of
credentials. The trade-off is that upstream property changes have to be diffed
in by hand on each Inji version bump, rather than merged.

## Layout

**One file here is ours: `application-default.properties`.** Everything else is
a verbatim upstream copy, kept unmodified so it stays diffable against upstream
on an Inji version bump. All environment-specific values are concentrated in
that one file.

| Source | Files |
|---|---|
| `inji/inji-config@2952358` (2026-04-27) | `certify-default`, `mimoto-default`, `certify-mock-identity`, `certify-postgres-*`, `data-share-*`, the `.json` and `.html` assets |
| `mosip/mosip-config@v1.2.0.1-B3` | `esignet-default.properties` — **not** in inji-config, which is why it has to be sourced separately |
| ours | `application-default.properties` |

Spring Cloud Config serves `application-<profile>.properties` to *every*
application, which is what makes one shared override file possible.

## Why application-default.properties exists

The upstream defaults assume a complete MOSIP platform and reference
placeholders they never define — Spring fails at startup on an unresolved
`${...}`, so each one must resolve even when the feature behind it is unused.
Enumerated by diffing referenced `${...}` tokens against defined keys across
the served files: **26 undefined from certify+mimoto, 11 more from esignet.**

Current state: **83 placeholders referenced, 387 defined, 0 unresolved.** Six
come from env vars (`db.dbuser.password`, the two softhsm PINs,
`mimoto.oidc.keystore.password`, `redis.password`, `softhsm.idp.pin`) and eight
from Spring or the chart (`server.servlet.path`, `active_profile_env`,
`spring_config_url_env`, …).

No credential is defined here — this is a public repo. Passwords reach the
modules as env vars from the `inji-db` and `softhsm-*` secrets; Spring's
relaxed binding maps e.g. `DB_DBUSER_PASSWORD` onto `${db.dbuser.password}`.

## Outstanding decision: the Certify plugin profile

`certify-default.properties` carries only core settings. Which credential
Certify actually issues, and from what data source, comes from a plugin-usecase
profile — one of:

| Profile | Data source |
|---|---|
| `certify-mock-identity.properties` | mock plugin; fastest end-to-end proof |
| `certify-postgres-university.properties` | Postgres data-provider plugin, reading a table |
| `certify-postgres-landregistry.properties` | Postgres data-provider plugin, land records |
| `certify-mosipid-identity.properties` | a real MOSIP ID system (not present here) |

The profile name is the filename suffix, so it has to be added to Certify's
active profile list. `mock-identity` is the sensible bring-up choice; the
postgres data-provider is the interesting target for DIGIT, since it can issue
credentials straight from a DIGIT table. `mosip.certify.data-provider-plugin.did-url`
and `.id-field-prefix-uri` in `application-default.properties` are
intentionally empty until this is chosen.

## Where the values actually live

See `application-default.properties` — it is commented section by section
(hostnames, shared DIGIT infrastructure, Certify, Mimoto, eSignet) with the
reasoning for each value, including which upstream default it overrides and
why.

## Related

- `deploy-as-code/helm/charts/argo-cd/inji/inji-applications.yaml` — the module Applications and their bring-up order
- `deploy-as-code/helm/charts/inji-services/` — local charts (`inji-db-init`, `inji-stack-config`, `inji-ingress`)
- `deploy-as-code/helm/charts/inji-services/values/test-lts/` — per-module values overrides
