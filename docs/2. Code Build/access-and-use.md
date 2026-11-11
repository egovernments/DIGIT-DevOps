# Code Build: access and use

How to trigger builds, find the images they produce, and read the results.

## Trigger a build

Each onboarded repo has a **Build - Code** workflow (from
[`code-build.yaml`](../../templates/consumer/.github/workflows/code-build.yaml)).

1. Open the repo on GitHub -> **Actions** -> **Build - Code** -> **Run workflow**.
2. Leave GitHub's **"Use workflow from"** on the default branch. The workflow
   itself lives only there; you choose the code to build with the input below.
3. Set the inputs:
   - **Build from Branch** (`build_branch`) - the branch whose code is checked
     out and built. This, not "Use workflow from", decides what is built, and it
     feeds the image tag `<branch>-<short-sha>`.
   - **All services** (`all_services`) - on = build every service in
     `build-config.yml` from that branch, as a parallel matrix; off = build the
     single service picked below.
   - **Service** (`service`) - the one image to build when "All services" is off.
4. Run it.

There is also an **`/actions`** dispatcher on the repo's GitHub Pages site that
does the same thing from a web UI and reads the service list live. See
[../workflows/actions-ui.md](<../1. Workflows/actions-ui.md>).

The branch and service dropdowns are kept current by **Build - Setup**
(`mode: sync`); do not hand-edit the option lists in the workflow file.

## Where the images land

A successful build pushes to Docker Hub under the `egovio` namespace:

```
docker.io/egovio/<service>:<branch>-<short-sha>
docker.io/egovio/<service>-db:<branch>-<short-sha>   # only if the service has a -db entry
```

For example a `master` build of `collection-service` at commit `1a2b3c4`
produces `egovio/collection-service:master-1a2b3c4` (plus the `-db` image if
present). Pull and inspect:

```bash
docker pull egovio/collection-service:master-1a2b3c4
```

The engine also exposes the pushed references as workflow outputs `docker_image`
and `db_image`, which a caller can forward downstream.

## The migration (`-db`) image

When a service declares a `<service>-db` entry, its migration image is built,
scanned and pushed in the same run and tagged identically
(`<branch>-<short-sha>`). It carries the DB migrations (for example Flyway) that
the service chart runs as an init/migration step before the app starts. The app
and its `-db` image are always a matched pair at the same tag, so deploy them
together; Kargo discovers and promotes them under the one service (the
`dbMigration` flag in a Kargo project config marks services that have one).

## Verify a signature

Pushed images are signed cosign keyless. To verify provenance:

```bash
cosign verify egovio/<service>:<branch>-<short-sha> \
  --certificate-identity-regexp 'https://github.com/<org>/<repo>/.github/workflows/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Read build status and scan results

- **The run itself** - Actions -> Build - Code. With "All services" on, each
  service is a separate matrix job (`fail-fast: false`); a red leg means that one
  service's build or Trivy gate failed while the others still ran. The job
  summary lists the pushed image reference(s) and links the scan report.
- **The security dashboard** - every image scan publishes to the repo's GitHub
  Pages at `https://<owner>.github.io/<repo>/security/trivy/`, with the app and
  `-db` findings combined under one service, regardless of whether the gate
  passed. The landing page at `https://<owner>.github.io/<repo>/` links it.
- **Gate behaviour** - on a scanned branch (listed in `TRIVY_SCAN_BRANCHES`, or
  the default branch) a CRITICAL finding at the code or image stage blocks the
  push; the report still publishes so you can see what to fix. On an unscanned
  branch the build pushes without a gate.

## What to do next with an image

An image existing in the registry is the trigger for the rest of the pipeline:

- it must have a packaged chart version to deploy - see
  [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/>);
- Kargo discovers the new tag as Freight and promotes it - see
  [Kargo Promotions](<../4. Kargo Promotions/>);
- Argo CD reconciles the promoted branch onto the cluster - see
  [Argo CD](<../5. Argo CD/>).
