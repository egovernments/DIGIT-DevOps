# Deployment Guide: Packaged Helm Charts with Kargo and Argo CD

This guide describes how applications are **released**, **promoted** and **deployed** across environments using:

- **Packaged Helm charts**, published to a Helm repository (`https://helm.digit.org`);
- **Kargo**, which promotes a release (an image tag and a chart version) from one environment to the next;
- **Argo CD**, which deploys whatever each environment's git branch describes.

The approach is used across our projects. It can be adopted **in full** (Kargo + Argo CD) or **with Argo CD alone**.

## Who this is for

| Reader | Start with |
|---|---|
| Anyone new to the approach | [01 Overview](01-overview.md), then [11 Glossary](11-glossary.md) |
| Platform engineers setting up an environment | [02 Prerequisites and Installation](02-prerequisites-and-installation.md), [03 Repository Layout and Conventions](03-repository-layout-and-conventions.md) |
| Teams onboarding an application | [04 Kargo Guide](04-kargo-guide.md) and/or [05 Argo CD Guide](05-argocd-guide.md) |
| Everyone making changes | [09 SOP and Guardrails](09-sop-and-guardrails.md) |
| On-call and release operators | [08 Operations Runbook](08-operations-runbook.md), [10 Troubleshooting](10-troubleshooting.md) |

## Contents

| # | Document | Covers |
|---|---|---|
| 01 | [Overview](01-overview.md) | Architecture, the release flow, the two adoption models |
| 02 | [Prerequisites and Installation](02-prerequisites-and-installation.md) | Tools, clusters, registries, installing Argo CD, Kargo and secrets tooling |
| 03 | [Repository Layout and Conventions](03-repository-layout-and-conventions.md) | Branches, folders, file naming, env files, placeholders |
| 04 | [Kargo Guide](04-kargo-guide.md) | Warehouses, Freight, Stages, promotion; onboarding applications and projects |
| 05 | [Argo CD Guide](05-argocd-guide.md) | Bootstrap, AppProjects, ApplicationSets, values layouts; chart version flow; onboarding |
| 06 | [Configuration and Secrets](06-configuration-and-secrets.md) | Module configuration, where each value belongs, SOPS-encrypted secrets |
| 07 | [Access Control](07-access-control.md) | Kargo teams and roles, Argo CD projects, cluster and database read access |
| 08 | [Operations Runbook](08-operations-runbook.md) | Day-to-day procedures: promote, roll back, add an environment, hand over ownership |
| 09 | [SOP and Guardrails](09-sop-and-guardrails.md) | The rules every change follows, checklists, approval levels |
| 10 | [Troubleshooting](10-troubleshooting.md) | Symptoms, causes and fixes |
| 11 | [Glossary](11-glossary.md) | Terms used throughout |
| — | [Templates](templates/README.md) | Ready-to-copy manifests and files |

## Choosing an adoption model

| | Kargo + Argo CD | Argo CD only |
|---|---|---|
| Who sets the version an environment runs | Kargo, through a recorded promotion | An engineer, through a pull request |
| Moving a release dev → qa → uat | Promotion in the Kargo UI, gated per stage | One pull request per environment branch |
| Adding an application | One entry in the Kargo project config | One ApplicationSet entry and its versions in the env file |
| Read | 01–11 | 01, 02 (Argo CD parts), 03, 05, 06, 07, 08–11 |

## Placeholders

Examples use placeholders in angle brackets. Replace them with your values.

| Placeholder | Meaning | Example |
|---|---|---|
| `<org>/<repo>` | Git repository holding deployment configuration | `acme/deploy-config` |
| `<env>` | Environment name | `dev`, `qa`, `uat` |
| `<env-branch>` | Git branch describing that environment | `env-dev` |
| `<module>` | A group of services released together | `payments` |
| `<project>` | Kargo project for a module | `payments` |
| `<service>` | One application (also its chart name) | `invoice-service` |
| `<namespace>` | Kubernetes namespace | `payments` |
| `<app-prefix>` | Prefix of Argo CD Application names | `payments-` |
| `<registry-org>` | Container registry organisation | `acme` (`docker.io/acme/<service>`) |
| `<environments-dir>` | Folder holding env files | `deploy/environments` |
| Helm repository | Where packaged charts are published | `https://helm.digit.org` (add the sub-path if your charts are published under one) |
