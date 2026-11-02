# GitOps with Kargo and Argo CD

How applications are released and deployed with **packaged Helm charts**, **Kargo** (promotion) and **Argo CD** (deployment). Written for any project in the organisation; the DIGIT 3.0 core module (Kargo project `digit-core3-0`) is the worked example.

| Doc | Read it to |
|---|---|
| [1. Kargo: Setup and Onboarding](1.%20Kargo%20-%20Setup%20and%20Onboarding.md) | Understand Warehouses, Freight (image tag + chart version) and Stages, and onboard an application or project for promotion |
| [2. Argo CD: Setup and Onboarding](2.%20Argo%20CD%20-%20Setup%20and%20Onboarding.md) | Understand how a chart version in an env file becomes a running Deployment, and onboard an application or module, with or without Kargo |
| [3. SOP and Guardrails](3.%20SOP%20and%20Guardrails.md) | Follow the rules for every change: ownership, checks before and after merge, approvals, recovery |

**Which setup do I need?**

- **Kargo + Argo CD:** builds are promoted dev → qa → uat with gated, recorded promotions. Read 1, 2 and 3.
- **Argo CD only:** versions are set in env files by PR. Read 2 (layout B) and 3 (including 3.15).

Related: the existing [Kargo docs](../kargo/1.%20Overview.md) (control plane, credentials, access) and [Deploying Services in Unified Environments](../argocd/Deploying%20Services%20in%20Unified%20Environments.md) (the older model, where charts come from git paths).
