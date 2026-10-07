# LnP load test (k6)

Core lifecycle = apply → verify → inbox search → VERIFY_DOCUMENTS, one iteration per lifecycle. Metrics: lifecycles/s, per-endpoint
TPS and p50/p95/p99, error rate. Run from the generator VM (same region), never from a laptop or a VM under test.

1. target VM into load-test mode: `unlimit-cpu.sh <key> <host> <targets...>` (drops CPU limits), Business License verification mode
   NONE, notification SMS/SMTP pointed at the test sinks; check with `preflight.sh` (read-only, exits 1 on any gap).
2. laptop: `seed.sh <scripts> <admin> <capture> 1000 seed.json` then `mint-tokens.sh <scripts> <admin> <capture> <users.env> secrets.json`.
   `seed.sh ... 0 seed.json` re-uploads the ID document only and keeps the individuals already in seed.json.
3. `scp core.js seed.json secrets.json run-ladder.sh azureuser@loadgen:lnp-load/` (secrets.json stays mode 600).
4. generator: start the ladder detached (`nohup setsid bash run-ladder.sh https://<domain> <label> "<steps>" 10m > <label>.log &`)
   so a laptop network drop cannot kill it; laptop: `collect.sh <kubeconfig> <label>` for pod CPU/memory samples.
5. results/<label>/core-<vus>.json + samples.csv → `summarize.py` (Little's law check: users ÷ rate = measured lifecycle).
6. done: `restore-after-load.sh` (real providers, sinks deleted, OTP mode back), restore the chart resources, delete the
   load-generated data, remove secrets.json everywhere.

Stop rule: error rate ≥ MAX_ERR (default 0.01 = 1%); the p95 thresholds stay in the report but do not end the ladder.
Fair comparisons start every shape from the same data volume: the inbox search counts open applications on every call.
Tokens live about 4 h: re-mint before long runs.
