# Delivery layer (Helm / Kargo / Argo CD)

Scaffolded when a repo is set up with `profile: delivery`. These layers package
the built images into Helm charts, promote them through environments with Kargo,
and sync them to clusters with Argo CD.

Status: being added incrementally.
- Helm release caller + `devops/environments/*`  — Phase 2
- Kargo project / warehouse registration          — Phase 3
- Argo CD application                             — Phase 3

A repo set up as `build-only` can adopt these later by re-running Setup with
`profile: delivery`; the build layer is left untouched.
