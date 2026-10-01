# LnP exports from test-lts — phase 0 snapshot (2026-10-01)

Read-only captures from the `digit-lts` cluster (namespace `egov`), taken as the source of truth for the
LnP overlay. Nothing here is applied automatically; `09-lnp.sh` prefers the services' own
`_onboard-tenant` / `_inflate` provisioning and uses the SQL only as a fallback/reference.

| File | What | Provenance |
|---|---|---|
| `lnp-tags.from-test-lts.yaml` | image + db-migration tags per LnP workload | `origin/digit-lts:deploy-as-code/helm/environments/test-lts.yaml` @ 80c138170 |
| `kong-lnp-routes.json` | the 12 Kong routes (+ per-route/service plugins, secret-like config values redacted) fronting license-certificate, calculator, pdf-v3, schema-registry, vc, mdms-v2 | Kong admin API, read-only |
| `realm-policy.diff`, `realm-policy-summary.txt` | account `realm_config.json`: `origin/modulith` vs `origin/performance-changes` (the build test-lts runs); 5 permissions widened to CITIZEN/EMPLOYEE | digit3 git |
| `db/basetenant-lnp-config.sql` | BASETENANT master rows: calculation_rule, certificate_category, certificate_type, credential_types, attribute_path_registry, schema_definition, ui_config, pdf_v3_templates, tenant_configs | `pg_dump --data-only` on postgres-0 |
| `db/public-lnp-config.sql` | public.certificate_type template skeletons (3 rows) | same |
| `db/mdms-data.BASETENANT.tsv`, `db/mdms-schema.BASETENANT.tsv` | MDMS v2 rows for BASETENANT (access.PermissionActions, access.UIActions, common-masters.Theme) | `COPY … TO STDOUT` |
| `test-lts-deploys.json`, `test-lts-ingress.json` | raw Deployment/Ingress specs for parity review (env values are `valueFrom` refs, no secret values) | `kubectl get -o json` |
