# Reusable Build engine

`reusable-build.yaml` (`on: workflow_call`) is the central Docker build engine
shared by eGov service repositories: build + push a service image (and its
optional `-db`) multi-arch, with a **Trivy gate on the default branch** and
**cosign keyless** signing of the pushed digests.

Callers pin `@reusable-build-v1` (moving major) or `@reusable-build-v1.x.y`
(immutable). The tag moves **automatically** when the engine or the consumer
templates change on `master` — see `promote-reusable-tag.yaml`. There is no
manual `git tag` step.

## Full documentation

To avoid a second source of truth that drifts, the details live in one place —
[`docs/workflows/`](../../docs/workflows/):

- [README](../../docs/workflows/README.md) — how the pieces fit, onboarding, versioning
- [build.md](../../docs/workflows/build.md) — pipeline, scan policy, cosign, inputs
- [setup.md](../../docs/workflows/setup.md) — the GitHub App + provisioning (full) and dropdown sync (sync)
- [actions-ui.md](../../docs/workflows/actions-ui.md) — landing page + `/actions` dispatcher
