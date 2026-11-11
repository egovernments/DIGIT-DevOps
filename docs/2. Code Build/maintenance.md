# Code Build: maintenance

Who owns what, how to change the engine, and how to debug a failed build.

## Engine versioning

Callers pin the engine with `@reusable-build-v1` (a moving major tag). An
immutable snapshot `@reusable-build-v1.0.<N>` also exists for pinning a specific
build.

The moving tag is maintained **automatically** by
[`promote-reusable-tag.yaml`](../../.github/workflows/promote-reusable-tag.yaml):
when a change to any of these lands on `master`, it moves `reusable-build-v1` to
the new `master` tip and cuts the next `reusable-build-v1.0.<N>`:

- `.github/workflows/reusable-build.yaml`
- `.github/workflows/reusable-setup.yaml`
- `templates/consumer/**`

So the normal flow to ship an engine fix is: **merge to `master` -> the promote
workflow moves the tag -> every caller on `@reusable-build-v1` picks it up on its
next run.** There is no manual `git tag` step and no per-repo change.

Only flip a caller's pinned ref (the `@reusable-build-v1` part) when you
intentionally introduce a breaking engine change and cut a new major; routine
fixes ride the moving v1 tag.

## Change the scan policy

- **Which branches are gated** - edit the `TRIVY_SCAN_BRANCHES` repo variable in
  each service repo (Settings -> Secrets and variables -> Actions -> Variables),
  one branch per line. The caller passes it as `scan_branches`; unset = default
  branch only. No workflow edit needed.
- **Turn scanning off for a repo** - pass `enable_trivy: false` from the caller
  (for a repo without the Trivy toolkit). The build then runs straight after
  resolve-config with no gate.
- **Severity / scanners** - these live in the engine
  (`reusable-build.yaml`): Trivy reports `CRITICAL,HIGH,MEDIUM` and only CRITICAL
  blocks. Change there and let the promote workflow roll it to all callers.

## Keep a repo's dropdowns and toolkit current

- **New service not showing in the picker** - run **Build - Setup** with
  `mode: sync` (optionally `sync_branch: <feature-branch>` to pull in services
  not yet merged). The `/actions` UI reads the list live and needs no sync.
- **Upgrade the dashboard toolkit / re-provision** - run **Build - Setup** with
  `mode: full`. It re-scaffolds `.trivy/dashboard/` and the Pages site.
- The GitHub App must stay installed and on the default-branch ruleset bypass
  list, or Setup cannot push. See [../workflows/setup.md](<../1. Workflows/setup.md>).

## Common build failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Push blocked, "code scan blocked" or "image scan blocked" | A CRITICAL Trivy finding on a scanned branch | Open the report under `/security/trivy/`, fix or upgrade the flagged dependency / base image, rebuild. A gate working is not a bug. |
| arm64 leg very slow or timing out | Multi-arch push builds `linux/arm64` under QEMU emulation on an amd64 runner | Expected to be slower; let it finish, or for a fast iteration build a feature branch (unscanned) or temporarily narrow `platforms`. Do not drop arm64 from release branches. |
| Build fails during image build with test errors | The Dockerfile runs unit/integration tests at image-build time | Move tests to a separate CI job; the image build should only compile and package. |
| "login failed" / denied push | `DOCKER_USERNAME` variable or `DOCKER_ACCESS_TOKEN` secret missing or expired | Re-add them in the repo's Actions secrets/variables. |
| Setup cannot push to the default branch | GitHub App not on the ruleset bypass list, or not installed | Add the App to the bypass list and confirm installation. |
| `build-config.yml not found` / `no services found` | Wrong branch, or the config missing on the build branch | Check `build/build-config.yml` exists on the **Build from Branch** you picked. |
| Service missing from the dropdown | Dropdowns not resynced after a config edit | Run Build - Setup `mode: sync`, or use the `/actions` UI (reads live). |

## Debug a failed build

1. Open **Actions -> Build - Code** and the failing run. With "All services" on,
   find the red matrix leg; each service is isolated.
2. Read the **job summary** first: it names the stage that failed (code-scan,
   image-scan, build, or push) and links the scan report.
3. For a scan block, open `https://<owner>.github.io/<repo>/security/trivy/` and
   drill into the service to see the exact finding.
4. Reproduce a build step locally if needed:
   ```bash
   docker buildx build --platform linux/amd64 \
     --build-arg WORK_DIR=<work-dir> \
     -f <dockerfile> -t local-scan/<service>:test .
   trivy image local-scan/<service>:test --severity CRITICAL,HIGH,MEDIUM
   ```
5. If the engine itself is at fault, fix `reusable-build.yaml` on a branch, test
   against one caller, then merge to `master` so the tag promotes to all.

Deep reference for the pipeline internals: [../workflows/build.md](<../1. Workflows/build.md>).
