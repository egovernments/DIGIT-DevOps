# DIGIT 3.0 on the unified environments

This folder explains, in plain language, how DIGIT 3.0 is deployed on the Azure AKS
`unified-dev` cluster and how to add new things to it. Read this page first. It gives
you the whole picture and the rules; the other pages are step-by-step runbooks.

## What you can do with these docs

| I want to... | Read |
|---|---|
| Understand how it all fits together | This page |
| See the wiring diagrams (architecture + flows) | [architecture.md](architecture.md) |
| See the exact files and what each one does | [structure.md](structure.md) |
| Add a whole new product (like `hcm-3.0`, `cms-3.0`, `studio-3.0`) | [add-a-new-product.md](add-a-new-product.md) |
| Add a new service to an existing product | [add-a-new-service.md](add-a-new-service.md) |
| Understand promotions, syncing, and fixing problems | [operate-argocd-and-kargo.md](operate-argocd-and-kargo.md) |

## The one-paragraph summary

DIGIT 3.0 runs as a set of **products** (core, backbone, and later health, cms, studio, ...).
Each product is one **module**. Everything a module runs is a prebuilt, published Helm chart
pulled from `helm.digit.org` - we never keep copies of those charts in this repository. Two
tools drive everything: **Argo CD** installs and keeps the charts running on the cluster, and
**Kargo** decides which image and chart version each service should move to, and promotes that
choice from `dev` to `qa` to `uat`. All the per-environment settings for a module live in one
values file. To change the platform you change text files in this repository and open a pull
request; a person merges it; Argo CD and Kargo then make the cluster match.

## The mental model (learn these five ideas)

1. **A product is a module, and a module is a namespace.**
   `core-3.0` is a product. On the cluster it is a Kubernetes namespace. Namespaces cannot
   contain a dot, so the namespace is written `core-3-0` (dash). Folders and values files keep
   the readable dotted name (`core-3.0`); live Kubernetes objects use the dashed name
   (`core-3-0`). Both names always refer to the same thing.

2. **Charts are published, never copied here.**
   Every service, plus kong, keycloak, postgresql and vault, is a chart on
   `helm.digit.org/digit3/<module>` (for example `helm.digit.org/digit3/core`). This repository
   holds **no** chart templates for DIGIT 3.0 - only three kinds of text: Kargo pipeline config,
   Argo CD project definitions, and per-environment values files. If you find yourself editing a
   chart's templates to onboard something, stop: that is the wrong approach here.

3. **Argo CD = "keep it running". Kargo = "decide and move the version".**
   - *Argo CD* takes a chart + a values file and makes sure that exact thing is running in the
     right namespace. It never picks versions.
   - *Kargo* watches Docker Hub and the Helm repository, bundles "image tag + chart version"
     into a unit called **Freight**, and when a person promotes that Freight it writes the chosen
     versions into the module's values file. Argo CD then rolls the change out.

4. **One values file per module holds everything.**
   `deploy-as-code/helm/environments/digit-3.0/<module>-3.0.yaml` holds every setting for that
   module, for every service, for all of dev/qa/uat (the stage's branch decides which values are
   live). Secrets for the module live next to it in `<module>-3.0-secrets.yaml`, encrypted.

5. **Nothing happens automatically, and nothing bypasses review.**
   Freight is assembled by hand and every promotion is a deliberate click by a person. Every
   change to this repository goes in through a pull request that a person merges. You never push
   straight to a shared branch, and you never merge your own pull request.

## Golden rules (do not break these)

These rules exist so that changes are safe, reviewable, and repeatable. Treat them as hard
constraints, not suggestions.

- **Rule 1 - Charts stay published.** Zero chart-template changes in this repository for
  DIGIT 3.0. Onboarding is only: Kargo config, Argo CD project config, and values files. If a
  chart genuinely needs a change, that change is made in the `helm-charts` repository, released
  as a new chart version, and then referenced here by version.
- **Rule 2 - Namespaces are dash, folders and values are dot.** `core-3.0` the product,
  `core-3-0` the namespace. Never put a dot in a namespace. Never invent a third spelling.
- **Rule 3 - A Kargo project is a namespace.** The pipeline and the workloads for a module
  share one namespace. The module's Argo CD AppProject must list that namespace as an allowed
  destination, or the sync is refused.
- **Rule 4 - One values file per module.** All of a module's settings go in its
  `<module>-3.0.yaml`. Do not scatter module settings into `unified-dev.yaml`; the only module
  entries in `unified-dev.yaml` are the namespace registration and the Kargo project list.
- **Rule 5 - `global.mode: prod` for anything but active development.** In `prod` mode every
  service uses the image tag baked into its chart (the released image); per-service `image.tag`
  overrides are ignored. In `dev` mode the per-service `image.tag` wins. Use `prod` unless you
  are deliberately testing an unreleased build.
- **Rule 6 - Chart versions come from the published index, newest first.** The authoritative
  list is `helm.digit.org/digit3/<module>/index.yaml`. Do not guess a version.
- **Rule 7 - Never hand-edit the generated Applications or the kargo-managed ApplicationSets
  per service.** Services are generated from the Kargo project file. You add a service by adding
  it to that file, not by writing an Application by hand.
- **Rule 8 - Every change via pull request; a person merges.** No direct pushes to shared
  branches. No self-merges. Do not run destructive cluster commands (deleting namespaces,
  databases, secrets) without an explicit instruction and a check of what is about to be removed.
- **Rule 9 - Verify before you call it done.** After any change, run the checks in the runbook
  (render the templates, grep for leftover old names, confirm the Argo CD apps are Synced and
  Healthy). A change that has not been verified is not finished.

## Glossary

- **Module / product** - one DIGIT 3.0 area (core, backbone, health, cms, studio, ...). Lives in
  its own namespace.
- **Namespace** - the isolated space on the cluster where a module's objects run (`core-3-0`).
- **Chart** - a packaged, versioned Helm application pulled from `helm.digit.org`.
- **Argo CD** - the tool that installs charts and continuously makes the cluster match the repo.
- **Application (Argo CD)** - one running chart that Argo CD manages (for example `digit3-account`).
- **ApplicationSet** - a template that generates many Applications from a list. The DIGIT 3.0
  services are generated this way from the Kargo project file.
- **AppProject (Argo CD)** - a guardrail that says which repositories an app may pull from and
  which namespaces it may deploy into.
- **Kargo** - the tool that discovers new image/chart versions and promotes them dev -> qa -> uat.
- **Kargo Project** - a Kargo pipeline; it is also a Kubernetes namespace.
- **Warehouse (Kargo)** - watches a source (an image repo or a Helm chart) for new versions.
- **Freight (Kargo)** - one promotable bundle: an image tag plus a chart version.
- **Stage (Kargo)** - dev, qa, or uat. Promotion moves Freight from one stage to the next.
- **Layout** - how a chart receives its values: `common`, `root`, or `configs` (see
  [structure.md](structure.md)).
- **Values file** - the per-module settings file `environments/digit-3.0/<module>-3.0.yaml`.
- **SOPS** - the tool that encrypts the secrets file so it can live safely in git.
