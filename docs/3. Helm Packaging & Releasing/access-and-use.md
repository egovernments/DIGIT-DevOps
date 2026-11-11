# Access and use

How to consume a published chart, and the form-driven release process that governs how
charts get published.

## Consuming a published chart

Add the module as a Helm repo, then install any chart in it:

```bash
helm repo add digit3-core https://helm.digit.org/digit3/core
helm repo update
helm search repo digit3-core                      # list what the module publishes
helm install my-release digit3-core/localization -n core -f values.yaml
```

The per-project library is a repo too:

```bash
helm repo add digit3-common https://helm.digit.org/digit3/common
```

### Pin the chart version

Always pin an explicit chart version rather than taking the registry's latest, so a
deploy is reproducible:

```bash
helm install my-release digit3-core/localization --version 3.0.1 -n core -f values.yaml
```

### How Kargo and Argo CD consume these

On digit-lts you do not usually `helm install` by hand. The published charts feed the
GitOps pipeline:

- A **Kargo Warehouse** subscribes to a chart's registry URL (and the service image). When
  a new chart version or image tag appears, Kargo assembles **Freight**. Promoting the
  Freight writes the chosen chart version and image tag into the environment file in git.
  See [Kargo Promotions](<../4. Kargo Promotions/>).
- **Argo CD** reads that environment file, renders the pinned chart version, and applies it
  to the cluster. See [Argo CD](<../5. Argo CD/>).

So the chart version you publish here is the unit the rest of the platform promotes and
deploys. The chart repo registry URLs used on digit-lts are `helm.digit.org/digit3/crest`,
`helm.digit.org/digit3/studio` and `helm.digit.org/digit3/health`.

## The form-driven release process

You never run `helm package`, cut a version tag, or upload a `.tgz`. You open a PR, pick a
release type on an auto-injected form, and merge. Full mechanics in
[helm-charts/docs/packaging-and-releasing.md](https://github.com/egovernments/helm-charts/blob/master/docs/packaging-and-releasing.md).

### The Release selection form (automatic)

When you open or push to a PR, a workflow diffs your branch against `master`, finds the
`<project>/<module>` you changed, and appends a form to the PR description:

```
<!-- RELEASE-FORM:START -->
### Release selection
**Project**
- [x] digit3
**Module**
- [x] core
**Release**
- [ ] major
- [ ] minor
- [ ] patch
<!-- RELEASE-FORM:END -->
```

- Project and module are auto-ticked when only one was changed (the usual case).
- You tick exactly one Release option.
- Your pick is preserved if you push more commits.
- Do not delete the `<!-- RELEASE-FORM -->` block when editing the description; if you do,
  push any commit or reopen the PR and it is re-injected (ticks preserved).

### The gate and required checks

Three required status checks must be green before a chart PR can merge to `master`:

| Check | Passes when |
|-------|-------------|
| `require-label` | the PR changes exactly one project + one module and the form has exactly one Release option ticked (or the PR has no chart changes). |
| `lint-template` | `helm lint` + `helm template` succeed on every changed chart. |
| `image-check` | every image each changed chart references actually exists in its registry. |

`enforce_admins` is on; satisfy the checks like everyone else rather than disabling
protection. All three auto-pass on PRs with no chart changes.

### What happens on merge

CI resolves the targets from the changed paths, computes the version (first publish seeds
from `Chart.yaml`; later publishes bump the registry version by the release type), runs
`helm dependency build`, packages, re-indexes the module, updates the changelog and the
site, and cuts the traceability tag. Nothing to run by hand.

Next: [maintenance](maintenance.md) for cutting new versions and dependency ordering.
