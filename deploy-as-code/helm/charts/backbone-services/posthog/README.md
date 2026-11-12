# posthog

Self-hosted PostHog for the unified environments.

PostHog dropped Kubernetes support in 2023 and archived its own chart
(PostHog/charts-clickhouse) in May 2026. This chart is vendored from the
community chart [enricofranke/posthog-k8s](https://github.com/enricofranke/posthog-k8s)
(Apache-2.0, see `LICENSE`), which is generated from PostHog's hobby
docker-compose. It runs only PostHog's official images (`posthog/posthog`,
`ghcr.io/posthog/...`), pinned by digest in `upstream.yaml`.

| | |
|---|---|
| Source | enricofranke/posthog-k8s `v0.2.1` (commit `6bc9fee952b52f79cc4a8a69885c9df63f0c1f4f`) |
| PostHog | upstream commit `4ba4b09d38a141f971591eb6b3e91848e0d0fdb9` (`upstream.lock`) |
| Removed | `ci/` (public test secrets), `tests/`, `README.md.gotmpl` |
| Local changes | none (vendored as-is in `charts/posthog`) |

The vendored chart does not render through the `common` chart, so it reads the
top-level keys of whatever values file it gets. This directory is a thin
wrapper with the vendored chart as a subchart: Helm hands it only the
`posthog:` block of `environments/unified-<env>.yaml`, and the env file's other
top-level keys (`redis`, `clickhouse`, `minio`, ...) never reach it. Only
`global` is shared; the vendored chart reads `global.imageRegistry` and
`global.imagePullSecrets` from it, so do not set those there.

## Shared Kafka

unified-dev points PostHog at the shared `kafka-kraft` in `backbone`
(`posthog.kafka.external`). The vendored chart then drops its Redpanda and with
it the sidecar that pre-creates PostHog's topics, so this wrapper adds
`templates/kafka-topics-job.yaml`: an Argo CD sync-wave -1 Job that creates
`files/kafka-topics.txt` + `kafkaTopics.extraTopics` and (re)applies
`kafkaTopics.config` retention to them on every change. Topics PostHog creates
later through broker auto-create get the broker defaults (7 days, unbounded);
check for them after upgrades.

## Upgrading

Do not edit `charts/posthog`. Re-vendor a newer release instead:

```bash
git clone --depth 1 --branch <tag> https://github.com/enricofranke/posthog-k8s.git /tmp/posthog-k8s
rsync -a --delete --exclude LICENSE \
  --exclude ci --exclude tests --exclude README.md.gotmpl \
  /tmp/posthog-k8s/charts/posthog/ charts/posthog/
```

and re-copy the topic list the wrapper's kafka-topics Job uses (Helm does not
let the parent chart read a subchart's files):

```bash
cp charts/posthog/files/upstream/docker/kafka/topics.txt files/kafka-topics.txt
```

Then update the table above, read the upstream CHANGELOG, and render with the
env file before merging. Schema migrations run in the `migrate` Job and cannot
be rolled back: back up PostgreSQL (and `ENCRYPTION_SALT_KEYS`) first.
