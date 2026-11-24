# Kargo-managed Applications on unified-qa

Applications for services promoted by Kargo are generated from the **Kargo project
config** (`charts/kargo/config/projects/<project>.yaml`, authored on `unified-dev`).
A service is declared once, there, and appears in Argo CD here after its first
promotion to the `qa` stage. No ApplicationSet edit is needed per service.

Each ApplicationSet is a matrix over every project config with `kargo.argocd` set,
that project's env file for the `qa` stage on **this** branch (normally the
cluster-wide `environments/unified-qa.yaml`), and one element per service whose
`<valuesKey>.chart-version` exists in that file. A project that has not been
promoted to `qa` contributes nothing: Kargo writes that key on the first
promotion, so until then there is no Application.

See `charts/argo-cd/unified-dev/kargo-managed/README.md` for the full description
of the layouts and how to add a service or a project.

## Only the `cluster` layout is here

unified-dev also carries `common`, `root` and `configs`. They are deliberately
not copied yet: the only project promoted to this environment today is
`unified-security`, and adding the other three would mean deciding that
`digit-core3-0` should deploy here as soon as it is promoted. That is a separate
call. Add them when that is the intent -- they are environment-agnostic apart
from the branch and the stage name.
