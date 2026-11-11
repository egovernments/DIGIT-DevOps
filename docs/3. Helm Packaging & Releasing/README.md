# Helm Packaging and Releasing

<sub>Stage 3 of 5 - [Workflows](<../1. Workflows/README.md>) -> [Code Build](<../2. Code Build/README.md>) -> **Helm Packaging & Releasing** -> [Kargo Promotions](<../4. Kargo Promotions/README.md>) -> [Argo CD](<../5. Argo CD/README.md>)</sub>

How DIGIT services become versioned, published Helm charts that the rest of the
platform can consume. This section is the DIGIT-DevOps view of the process; the
authoritative, workflow-level reference lives in the chart repository itself.

## Where this sits in the pipeline

- [Code Build](<../2. Code Build/>) produces the container image and its CI build tag.
- **Helm Packaging and Releasing** (this section) turns a chart source into a
  versioned package on the registry, so a deploy references a chart version, not a
  branch.
- [Kargo Promotions](<../4. Kargo Promotions/>) subscribe to those published charts (plus
  the images), assemble Freight, and write the chosen versions into an environment
  file.
- [Argo CD](<../5. Argo CD/>) renders the chart at the pinned version and applies it to the
  cluster.

## Where the charts live

All charts are maintained in **[egovernments/helm-charts](https://github.com/egovernments/helm-charts)**
and published to the registry at **[helm.digit.org](https://helm.digit.org)**. They are
organised as `project -> module -> service` and served per module:

```
https://helm.digit.org/<project>/<module>/index.yaml
https://helm.digit.org/<project>/<module>/<chart>/<chart>-<version>.tgz
```

For `digit3` the published modules include:

| Module | Registry | Holds |
|--------|----------|-------|
| `common` | `helm.digit.org/digit3/common` | the per-project library chart every service depends on |
| `core` | `helm.digit.org/digit3/core` | DIGIT core services |
| `crest` | `helm.digit.org/digit3/crest` | CREST services (`crest`, `crest-ui`) |
| `studio` | `helm.digit.org/digit3/studio` | DIGIT Studio services |
| `health` | `helm.digit.org/digit3/health` | health services Studio and others depend on |
| `backbone` | `helm.digit.org/digit3/backbone` | vendored infra (vault, postgresql) |
| `cluster-configs` | `helm.digit.org/digit3/cluster-configs` | shared `egov-config` / `egov-service-host` / Secret declarations |

## The 30-second version

1. Chart sources live under `charts/<project>/<module>/<service>/`.
2. You open a PR with your chart change (one project + one module per PR).
3. A bot appends a **Release selection** form to the PR description; you tick one of
   `major` / `minor` / `patch`.
4. On merge, CI versions, packages and publishes the chart to
   `helm.digit.org/<project>/<module>/<service>`. You never run `helm package` or cut a
   tag by hand.

## This section

| Doc | Read it when you want to... |
|-----|------------------------------|
| [getting-started.md](getting-started.md) | understand the layout, the registry, the `common` library, and how versions are derived. |
| [onboarding-a-service.md](onboarding-a-service.md) | add a new service chart (digit3 conventions: version seed, context-path, ingress gateway, image mode). |
| [access-and-use.md](access-and-use.md) | consume a published chart and understand the form-driven release gate. |
| [maintenance.md](maintenance.md) | cut a new version, order dependency releases, and fix a stuck release. |

## Authoritative reference (helm-charts/docs)

This section summarises and links. The source of truth for the mechanism is the
chart repository documentation:

- [README](https://github.com/egovernments/helm-charts/blob/master/docs/README.md)
- [architecture.md](https://github.com/egovernments/helm-charts/blob/master/docs/architecture.md)
- [packaging-and-releasing.md](https://github.com/egovernments/helm-charts/blob/master/docs/packaging-and-releasing.md)
- [onboarding-a-service.md](https://github.com/egovernments/helm-charts/blob/master/docs/onboarding-a-service.md)
- [release-sop.md](https://github.com/egovernments/helm-charts/blob/master/docs/release-sop.md)
- [troubleshooting.md](https://github.com/egovernments/helm-charts/blob/master/docs/troubleshooting.md)
