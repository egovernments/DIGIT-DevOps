# Maintenance

Cutting a new chart version, ordering dependency releases, and fixing a stuck release.
This summarises the chart repo's
[release-sop.md](https://github.com/egovernments/helm-charts/blob/master/docs/release-sop.md),
[packaging-and-releasing.md](https://github.com/egovernments/helm-charts/blob/master/docs/packaging-and-releasing.md)
and [troubleshooting.md](https://github.com/egovernments/helm-charts/blob/master/docs/troubleshooting.md).

## Golden rules

- One project + one module per PR (multiple service charts inside that module is fine).
- Branch off the latest `master`; a stale branch makes the form list the wrong charts.
- Publish dependencies first (bump `common` before the charts that depend on it, and point
  the dependent's `dependencies[].version` at a version that already exists).
- Everything goes through a PR. No direct pushes to `master`, no manual packaging or
  tagging.
- Leave the release form alone (the `<!-- RELEASE-FORM -->` block is workflow-managed).

## Cutting a new version

```bash
git checkout master && git pull
git checkout -b <type>/<short-name>
# edit the chart under charts/<project>/<module>/...
# (recommended) helm dependency build . && helm lint . && helm template test .
git commit -am "<change>"
git push -u origin <type>/<short-name>
```

Then open the PR, let the bot add the form, tick exactly one Release option, get the three
checks green, and merge.

### Choosing the release type

| You changed... | Pick |
|----------------|------|
| New chart, first publish | the type matching your seed intent (commonly `major` for a 1.0.0-style baseline) |
| New feature, values, or template addition, backwards compatible | `minor` |
| Bug fix, image tag bump, config tweak | `patch` |
| Breaking change (removed/renamed values, incompatible template) | `major` |

How the number is computed:

- **First publish** seeds from `Chart.yaml` `version` as-is (for digit3 that is the
  `3.0.0` seed); the release type is recorded but does not change the first number.
- **Later releases** bump the published version from the registry `index.yaml` by the
  release type. Editing `Chart.yaml` `version` by hand on a later release does **not**
  override the computed bump.

### Post-release verification

```bash
helm repo add <project>-<module> https://helm.digit.org/<project>/<module>
helm repo update
helm search repo <project>-<module>                                    # new version listed
curl -sI https://helm.digit.org/<project>/<module>/<svc>/<svc>-<ver>.tgz   # HTTP 200
```

Confirm the version shows in `helm search repo`, the `.tgz` returns HTTP 200, the chart and
a changelog entry appear on `helm.digit.org/<project>/<module>/`, and the traceability tag
`"<project>/<module>/PR-<number>"` exists.

## Dependency-ordered releases (e.g. updating `common`)

1. PR 1: change `charts/<project>/common`, release it (module = `common`). Note the new
   version.
2. PR 2: bump `dependencies[].version` to the new `common` version in each dependent chart
   and release them. `helm dependency build` only finds the new `common` after PR 1 is
   published.

## Deleting or keeping published versions

- **Do not delete a published version that a deployed environment still references.** On
  digit-lts a chart version is pinned in an environment file and consumed by Kargo and
  Argo CD (see [access-and-use.md](access-and-use.md)); removing its `.tgz` breaks the next
  sync. Publish a new version instead of mutating an old one.
- A **wrong-named** chart (published as `digit-<name>`) is the one case for a manual fix:
  correct `name:` in `Chart.yaml`, delete the `digit-<name>` entry and its `.tgz` from the
  module `index.yaml` on `gh-pages`, then re-release so it first-publishes under the correct
  name at the seed version.
- `gh-pages` is machine-managed; hand-edit only for one-off recovery.

## Common release failures

| Symptom | Cause and fix |
|---------|---------------|
| Form lists charts you did not change | branch off a stale `master`; `git fetch origin master && git rebase origin/master && git push --force-with-lease`. |
| `require-label` red | no Release ticked, two ticked, or two modules/projects in one PR; tick exactly one and split per module. |
| `helm dependency build` 404 for `common` | the pinned `common` version is not published or the `repository:` URL is wrong; publish `common` first and pin a real version. |
| Deploys the wrong image tag (or `1.16.0`) | `appVersion` left at the `helm create` default; set it to the real CI build tag. |
| Published under `digit-<name>` | the `Chart.yaml` `name:` kept the `digit-` prefix; strip it (see above). |
| Health probe `/<context>/<context>/health` | the context was baked into the probe path; set both probe paths to just `/health`. |
| Write-back to `master` fails with `protected branch hook declined` | the release bot's `GITHUB_TOKEN` cannot pass required checks; the version bump write-back needs a GitHub App / PAT bypass actor. Versioning itself still works (computed from the registry). |

Full troubleshooting (including the CloudNativePG reconciler and bulk tag deletion) is in
[helm-charts/docs/troubleshooting.md](https://github.com/egovernments/helm-charts/blob/master/docs/troubleshooting.md).
