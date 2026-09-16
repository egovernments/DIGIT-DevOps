# inji-config

Property files served by the Inji `config-server` to eSignet, Inji Certify and
Mimoto. This directory is the config repo — `config-server` clones
`egovernments/DIGIT-DevOps` at branch `digit-lts` and reads from here via
`gitRepo.searchFolders`, configured in
`deploy-as-code/helm/charts/inji-services/values/test-lts/config-server.yaml`.

Chosen over forking `inji/inji-config` so there is one repo and one set of
credentials. The trade-off is that upstream property changes have to be diffed
in by hand on each Inji version bump, rather than merged.

## Status: not yet populated

`config-server` will start and serve an empty property set until the files
below exist, and the modules that depend on it will fail at startup with
missing-property errors. This is the remaining blocker for eSignet, Certify and
Mimoto — `injiweb` does not read config-server.

## Files required

Seed each from the matching file upstream, then apply the digit-lts values:

| File | Upstream source |
|---|---|
| `application-default.properties` | `inji/inji-config@master` |
| `esignet-default.properties` | `mosip/esignet` `db_scripts`/config docs |
| `certify-default.properties` | `inji/inji-config@master` |
| `mimoto-default.properties` | `inji/inji-config@master` |

`activeProfileEnv` is set to `default,inji-default,standalone`, so
`*-default.properties` is the profile actually read. A file named for a profile
that is not in that list is silently ignored — a common cause of "the property
is right there but the service says it is missing".

## digit-lts values to apply

Hostnames come from the `inji-stack-config` ConfigMap where possible rather
than being hardcoded here.

```properties
# Databases — one role per module on postgres.egov, NOT postgresql-lts
# (postgresql-lts is being decommissioned).
mosip.certify.database.url=jdbc:postgresql://postgres.egov:5432/inji_certify?currentSchema=certify
mosip.certify.database.username=certifyuser

# eSignet, reachable at its own hostname
mosip.certify.authorization.url=https://esignet.test-lts.digit.org
mosip.certify.authn.issuer-uri=https://esignet.test-lts.digit.org/v1/esignet
mosip.certify.authn.jwk-set-uri=https://esignet.test-lts.digit.org/v1/esignet/oauth/.well-known/jwks.json

# Credential issuer identity. Deliberately a bare host with no path segment:
# OIDC4VCI locates issuer metadata by inserting
# /.well-known/openid-credential-issuer between host and path, so a path
# component would put the metadata somewhere clients disagree about.
mosip.certify.domain.url=https://injicertify.test-lts.digit.org
mosip.certify.identifier=https://injicertify.test-lts.digit.org

# Shared DIGIT infrastructure
mosip.certify.redis.host=redis.backbone
mosip.certify.redis.port=6379
object.store.s3.url=http://minio.backbone:9000
```

Passwords are **not** set here. They come from the `inji-db` Kubernetes secret
(created by `cluster-configs` from SOPS-encrypted values in
`test-lts-secrets.yaml`) and are injected as `SPRING_DATASOURCE_PASSWORD` by
each module's values file. Never commit a credential to this directory — it is
a public repo and `config-server` is deliberately not exposed through an
Ingress for the same reason.

## Related

- `deploy-as-code/helm/charts/argo-cd/inji/inji-applications.yaml` — the module Applications and their bring-up order
- `deploy-as-code/helm/charts/inji-services/` — local charts (`inji-db-init`, `inji-stack-config`, `inji-ingress`)
- `deploy-as-code/helm/charts/inji-services/values/test-lts/` — per-module values overrides
