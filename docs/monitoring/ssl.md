# SSL / TLS Monitoring Visibility - Master List

*What we can see about our TLS certificates and HTTPS endpoints today via blackbox-exporter + Prometheus + Grafana - and where the blind spots are. In a single table.*

**Scope note.** This list covers SSL/TLS certificate and HTTPS-endpoint observability only, as delivered by the **prometheus-blackbox-exporter** probing public endpoints, the **Prometheus** scrape job `blackbox` + the `sslalerts` rule group, and the Grafana dashboard **"Blackbox Exporter (HTTP prober)"** (`uid NEzutrbMk`). Certificate *issuance/renewal* (cert-manager / Let's Encrypt) and node-clock skew that breaks TLS validation are out of scope here - the latter is in the [Kubernetes Alerts Master List](kubernetes-alerts.md).

**Status:** `Available` = signal is exposed and usable today · `Available - fix` = exposed but coarse, partial or misconfigured · `To enable` = not surfaced today, needs turning on or building. Where the status is `Available - fix`, the **Gap / what's missing** column states the specific defect. **Priority:** P1 do first, P2 next, P3 backlog. The final column is blank for the implementation team to complete.

**Totals - 18 SSL/TLS visibility signals.** Available: 9 · Available - fix: 4 · To enable: 5. The dashboard visibility is good - days-to-expiry, TLS version and probe latency are all charted per endpoint - **but the alerting is effectively dead**: both SSL cert-expiry rules select `instance="prometheus-blackbox-exporter:9115"`, a label value that the relabeled probe series never carries (after relabeling `instance` = the probed URL), so **neither alert can ever fire**. Even if fixed, the only threshold is 2 days - no renewal runway.

| # | Signal / view | What it tells you | Source (metric / component) | Where to see it | Status | Gap / what's missing | Pri | Team notes |
|---|---|---|---|---|---|---|---|---|
| | **1 - PROBE COVERAGE   (2 available · 1 to fix)** | | | | | | | |
| 1 | HTTPS endpoint probing | Per-endpoint up/down (reachability + 2xx) | blackbox module `http_2xx` → `probe_success` | Grafana "HTTP Probe Overview" | Available | Module is `http_2xx` only - SSL metrics are a side-effect of probing HTTPS URLs; no dedicated `tls`/`ssl` module, no `fail_if_*` / `tls_config` set | P3 | 7 targets on unified-demo: digit-ui, core-ui, sanitation-ui, workbench-ui, kafka-ui, kibana, pgadmin |
| 2 | Target list maintenance | Which hosts are watched | Prometheus `blackbox` scrape job (`static_configs`) | `prometheus.yaml` / env override | Available - fix | Static, hand-maintained list; no ingress/DNS service discovery - a new host or domain is silently unmonitored. Chart default target is a placeholder (`http://demo.com`); real targets come from the env override | P2 | targets set in `central-instance.yaml` |
| 3 | Exporter self-health | Whether blackbox-exporter itself is up | job `blackbox_exporter` (operational metrics) | Prometheus | Available | 1 replica, ServiceMonitor disabled - single point of failure, no alert if the prober dies | P3 | image `quay.io/prometheus/blackbox-exporter`, port 9115 |
| | **2 - SSL / TLS METRICS (emitted per HTTPS probe)   (4 available · 1 to fix · 1 to enable)** | | | | | | | |
| 4 | Certificate days-to-expiry | Time until the earliest cert in the chain expires | `probe_ssl_earliest_cert_expiry` | Grafana table + `sslalerts` | Available | The core SSL signal; charted correctly - but the alert on it is broken (see #14) | P1 | value is a unix timestamp of earliest expiry |
| 5 | Full-chain expiry | Expiry of the last cert in the chain (intermediate/root) | `probe_ssl_last_chain_expiry_timestamp_seconds` | (metric only) | Available - fix | Emitted but not on any dashboard panel and not alerted | P3 |  |
| 6 | TLS version in use | Negotiated TLS protocol version per endpoint | `probe_tls_version_info` | Grafana table | Available | No alert on weak/deprecated TLS (< 1.2) - see #17 | P3 |  |
| 7 | HTTPS in use | Whether the final response was served over TLS | `probe_http_ssl` | Grafana table | Available | - | P3 |  |
| 8 | Handshake / connect latency | Per-phase timing incl. the TLS handshake | `probe_http_duration_seconds{phase="tls"/"connect"/"resolve"/...}` | Grafana "HTTP Probe Phases Duration" | Available | - | P3 |  |
| 9 | Cert issuer / SAN / chain validity | Which CA, hostname match, trust of the chain | - | (none) | To enable | `http_2xx` does not expose issuer/SAN, and no `tls_config`/`fail_if_*` is set - a mismatched or untrusted cert can still probe 2xx and go unnoticed | P2 |  |
| | **3 - GRAFANA DASHBOARD · Blackbox Exporter (HTTP prober), uid NEzutrbMk   (3 available · 1 to enable)** | | | | | | | |
| 10 | SSL expiry per endpoint (days) | At-a-glance days-to-expiry per URL | Grafana | `/monitoring/d/NEzutrbMk` | Available | Plain table value - no threshold colouring, no link to an alert | P3 | expr `(probe_ssl_earliest_cert_expiry - time()) / 86400` |
| 11 | HTTP Probe Overview table | success, status code, HTTPS, TLS version, avg duration, DNS lookup - per instance | Grafana | same dashboard | Available | - | P3 |  |
| 12 | Probe duration & phases | Total probe duration and per-phase breakdown (resolve/connect/tls/processing/transfer) | Grafana | same dashboard | Available | - | P3 |  |
| 13 | Broader SSL views | Expiry heatmap, issuer breakdown, multi-env cert board | Grafana | (none) | To enable | Single dashboard scoped to one env's endpoints; no fleet/cert-inventory view | P3 |  |
| | **4 - ALERTING · Prometheus rule group `sslalerts`   (0 available · 2 to fix · 3 to enable)** | | | | | | | |
| 14 | SSLCertificateExpiringSoon | Page when a cert is about to expire | PrometheusRule `sslalerts` | Alertmanager | Available - fix | **Never fires:** selector pins `instance="prometheus-blackbox-exporter:9115"`, but after relabeling `instance` = the probed URL, so it matches zero series. Also the threshold is only **2 days** - no renewal runway | P1 | expr `probe_ssl_earliest_cert_expiry{job="blackbox", instance="prometheus-blackbox-exporter:9115"} - time() < 2*24*3600`; fix: drop the `instance=` matcher (keep `job="blackbox"`), add 21/14/7-day tiers |
| 15 | SSLCertificateExpired | Page when a cert has already expired | PrometheusRule `sslalerts` | Alertmanager | Available - fix | **Never fires:** same wrong `instance` selector as #14 | P1 | expr `... instance="prometheus-blackbox-exporter:9115" ... - time() < 0` |
| 16 | Tiered expiry warnings (21 / 14 / 7 d) | Early, escalating renewal runway | PrometheusRule | (none) | To enable | Only a single 2-day rule exists (and it's broken); needs graduated warning tiers per endpoint | P1 |  |
| 17 | Weak-TLS / invalid-chain alert | Deprecated protocol or untrusted/mismatched cert | PrometheusRule | (none) | To enable | No alert on `probe_tls_version_info` < 1.2 or on chain/hostname validation failures | P2 |  |
| 18 | Endpoint-down alert (`probe_success == 0`) | HTTPS endpoint unreachable / non-2xx | PrometheusRule | (none) | To enable | The `blackbox` targets have no `probe_success` alert - an endpoint can be down with nothing paging | P1 |  |

---

### Sources

- **blackbox-exporter** - DIGIT-DevOps `deploy-as-code/helm/charts/monitoring/values/blackbox-exporter.yaml`: modules `http_2xx` (GET, ip4) and `http_post_2xx`; image `quay.io/prometheus/blackbox-exporter:9115`, 1 replica, ServiceMonitor disabled.
- **Probe targets** - `central-instance.yaml` `blackbox` scrape job: 7 HTTPS endpoints on `unified-demo.digit.org` (digit-ui, core-ui, sanitation-ui, workbench-ui, kafka-ui, kibana, pgadmin), `module: [http_2xx]`, relabel `__param_target → instance`, `__address__ → blackbox-prometheus-blackbox-exporter:9115`.
- **Alert rules** - `monitoring/values/prometheus.yaml`, `additionalPrometheusRules` group `sslalerts` (`SSLCertificateExpiringSoon`, `SSLCertificateExpired`).
- **Dashboard** - `grafana.yaml` provisions "BlackBox" from `github.com/egovernments/configs/.../monitoring-dashboards/blackbox.json`; live at `https://unified-demo.digit.org/monitoring/d/NEzutrbMk/blackbox-exporter-http-prober` (panels: HTTP Probe Overview, HTTP Probe Duration, per-instance HTTP Probe Phases Duration).
