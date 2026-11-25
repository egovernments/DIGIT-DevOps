# DIGIT 3.0 architecture: how everything is wired

This page shows the moving parts and how they connect. The diagrams render on GitHub. Read
[README.md](README.md) for the plain-language model; this page is the picture behind it.

## 1. The whole system at a glance

Three sources of truth feed the cluster: this **git repository** (settings and structure), the
published **Helm repository** (the charts and their released images), and **Docker Hub** (the
images). **Argo CD** turns charts + settings into running pods. **Kargo** decides which versions
to use and writes them back into the repository.

```mermaid
flowchart LR
  subgraph SRC["Sources of truth"]
    GIT["Git repo DIGIT-DevOps\nKargo config + Argo projects + values files"]
    HELM["helm.digit.org/digit3/*\npublished charts"]
    HUB["Docker Hub egovio/*\nimages"]
  end

  subgraph ARGO["Argo CD  (keep it running)"]
    BOOT["app-of-apps\nunified-dev-bootstrap"]
    APPSETS["kargo-managed ApplicationSets\ncommon / root / configs / cluster"]
    APPS["Applications\ndigit3-<service>"]
  end

  subgraph KARGO["Kargo  (decide + move versions)"]
    WH["Warehouses\nwatch images + charts"]
    FR["Freight\nimage tag + chart version"]
    STG["Stages\ndev -> qa -> uat"]
  end

  subgraph CLUSTER["AKS unified-dev"]
    NS1["namespace core-3-0\nservices, kong, keycloak"]
    NS2["namespace backbone-3-0\npostgresql-18, vault"]
  end

  GIT --> BOOT --> APPSETS --> APPS
  HELM --> APPS
  HUB --> APPS
  APPS --> NS1
  APPS --> NS2

  HUB --> WH
  HELM --> WH
  WH --> FR --> STG
  STG -->|"promotion writes chart-version + image.tag"| GIT

  NS1 -. "depends on" .-> NS2
```

Read it as: **Kargo writes versions into git; Argo CD reads git and makes the cluster match.**
The two never talk to each other directly - the git repository is the hand-off point.

## 2. From a file in the repo to a running pod

Every running service traces back through these layers. Each arrow is plain text you can open.

```mermaid
flowchart TD
  A["helm.digit.org/digit3/core/<service>\npublished chart + released image"] --> B
  B["charts/kargo/config/projects/core-3-0.yaml\nservice listed here"] -->|"a promotion merges\nchart-version + image.tag"| C
  C["environments/digit-3.0/core-3.0.yaml\nthe live settings (+ secrets file, SOPS)"] --> D
  D["kargo-managed ApplicationSet\n(picks the layout: common / root / configs)"] --> E
  E["Argo CD Application  digit3-<service>"] --> F["running pods in namespace core-3-0"]
```

## 3. How versions are promoted (dev -> qa -> uat)

Discovery is automatic; every promotion is a person's decision. Promotion is linear - a stage can
only take what the stage before it already has.

```mermaid
flowchart LR
  subgraph DISCOVER["Automatic"]
    W["Warehouse re-scans\nevery 5 min"] --> AV["available Freight\n(image + chart)"]
  end
  subgraph HUMAN["Manual (a person clicks)"]
    AV --> P1{"promote to dev"}
    P1 --> DEV["dev\nbranch unified-dev"]
    DEV --> V["verify: Deployment runs\nthe promoted tag + healthy"]
    V --> P2{"promote dev -> qa"}
    P2 --> QA["qa\nbranch unified-qa"]
    QA --> P3{"promote qa -> uat"}
    P3 --> UAT["uat\nbranch unified-uat\n(master-* builds only)"]
  end
  DEV -->|"writes versions into"| EF["environments/digit-3.0/core-3.0.yaml\non the stage's branch"]
  QA --> EF
  UAT --> EF
```

Each stage writes to the **same** values file but on its **own branch** (`unified-dev`,
`unified-qa`, `unified-uat`), so the branch decides which versions are live where.

## 4. How a request reaches a service at runtime

Public traffic enters through one wildcard hostname and is routed by the API gateway to the right
service; services use the module's own database and vault.

```mermaid
flowchart LR
  U["user / client"] -->|"https://<product>-3.unified-dev.digit.org/<path>"| DNS["*.unified-dev.digit.org\nwildcard DNS"]
  DNS --> NGINX["nginx ingress controller"]
  NGINX --> KONG["kong (API gateway)\napp digit3-kong"]
  KONG -->|"route + auth"| SVC["service pod\nin namespace core-3-0"]
  SVC --> PG["postgresql-18\nbackbone-3-0"]
  SVC --> VAULT["vault\nbackbone-3-0"]
```

A protected route returns **401** without a token (reachable, auth required); an open route
returns **200**. A **404** or **502** means the route or the service is not up.

## 5. What you create when you onboard a product

Onboarding is adding text in a few known places, opening a pull request, and letting the system
reconcile. Nothing is created directly on the cluster by hand.

```mermaid
sequenceDiagram
  participant You
  participant Repo as Git repo (PR)
  participant Rev as Reviewer
  participant Argo as Argo CD
  participant Kargo
  participant K8s as AKS unified-dev

  You->>Repo: add Kargo project file (config/projects/<ns>.yaml)
  You->>Repo: register it (kargo-app-set-pipelines + kargo-app-project)
  You->>Repo: add Argo AppProject (digit-3.0/<module>/<ns>-app-project.yaml)
  You->>Repo: add values + secrets (environments/digit-3.0/<module>.yaml)
  You->>Repo: register namespace + project (unified-dev.yaml)
  You->>Rev: open pull request against unified-dev
  Rev->>Repo: review and merge (never self-merge)
  Repo-->>Argo: webhook refresh
  Argo->>K8s: create namespace, AppProject, (empty) module
  Repo-->>Kargo: project appears
  You->>Kargo: assemble Freight, promote to dev
  Kargo->>Repo: write chart-version + image.tag into values file
  Repo-->>Argo: webhook refresh
  Argo->>K8s: install digit3-<service> charts
  K8s-->>You: pods Running, route answers (401 protected / 200 open)
```

## 6. The three value layouts (how a chart receives its settings)

A service's values section is handed to its chart in one of three shapes. The Kargo project file
picks the layout; the kargo-managed ApplicationSet applies it.

```mermaid
flowchart TB
  EF["environments/digit-3.0/<module>.yaml"]
  EF --> C["common layout\n-> chart gets { global, <service> }\n(most DIGIT services)"]
  EF --> R["root layout\n-> chart gets the <service> section\n(minus chart-version) as top-level values\n(kong, vault, postgresql)"]
  EF --> G["configs layout\n-> cluster-configs chart gets the whole\nvalues file + secrets, renders ConfigMaps/Secrets"]
```

Use **common** for ordinary services, **root** for third-party-style charts that expect plain
values, and **configs** only for `cluster-configs`.

## Where to go next

- Add a product: [add-a-new-product.md](add-a-new-product.md)
- Add a service: [add-a-new-service.md](add-a-new-service.md)
- Operate and troubleshoot: [operate-argocd-and-kargo.md](operate-argocd-and-kargo.md)
- File-by-file reference: [structure.md](structure.md)
