# Kafka Visibility - Master List

*What we can see about Kafka today across our container and managed deployments - and where the blind spots are. In a single table.*

**Scope note.** This list covers Kafka observability only - the signals actually available for our two Kafka footprints: (a) self-managed containerised Kafka on Kubernetes (Bitnami KRaft, the 3-node `kafka-kraft-controller` StatefulSet in the `backbone` namespace) surfaced through **kafka-ui**, and (b) AWS **MSK** provisioned cluster `ng-central-prd-msk` (af-south-1) surfaced through **CloudWatch**. JVM, OS and broker-internal signals are in scope where a source exposes them. Kubernetes pod/PVC signals are cross-referenced to the [Kubernetes Alerts Master List](kubernetes-alerts.md) rather than repeated here.

**Status:** `Available` = signal is exposed and usable today · `Available - fix` = exposed but coarse, partial or misconfigured · `To enable` = not surfaced today, needs turning on or building. Where the status is `Available - fix`, the **Gap / what's missing** column states the specific defect. **Priority:** P1 do first, P2 next, P3 backlog. The final column is blank for the implementation team to complete.

**Totals - 26 Kafka visibility signals.** Available: 10 · Available - fix: 3 · To enable: 13. Container Kafka has **no Prometheus/Grafana coverage at all** - kafka-ui (studio-demo only; not deployed on unified-dev) is the single, point-in-time window. On the managed side MSK exposes **44 CloudWatch metrics but has zero alarms**, no Prometheus Open Monitoring, and no broker-log delivery - metrics nobody is paged on.

| # | Signal / view | What it tells you | Source | Where to see it | Status | Gap / what's missing | Pri | Team notes |
|---|---|---|---|---|---|---|---|---|
| | **1 - CONTAINER KAFKA · kafka-ui interactive browse   (5 available · 2 to enable)** | | | | | | | |
| 1 | Cluster / broker overview | Broker count, online/offline, active controller, cluster name & health | kafka-ui | `studio-demo.digit.org/kafka-ui` | Available | Point-in-time only - no history, no trend | P3 | OAuth2-gated; read-only mode enabled |
| 2 | Topic inventory | Topics, partition count, replication factor, per-topic size | kafka-ui | kafka-ui console | Available | - | P3 |  |
| 3 | Consumer groups & lag | Per-group / per-topic offset lag, members, group state | kafka-ui | kafka-ui console | Available | Snapshot only - no alert when lag grows | P2 | Primary lag view for container Kafka |
| 4 | Message browse | Inspect messages per topic / partition | kafka-ui | kafka-ui console | Available | `readonly: true` → browse only, produce disabled | P3 |  |
| 5 | Broker & topic config / ISR | Live broker & topic configs, in-sync replica state | kafka-ui | kafka-ui console | Available | - | P3 |  |
| 6 | kafka-ui on unified-dev | Same views for the dev cluster's Kafka | kafka-ui | (none) | To enable | kafka-ui deployed only on studio-demo; unified-dev Kafka has no UI | P2 | bootstrap `kafka-kraft-controller-headless.backbone:9092` |
| 7 | Historical trends / dashboards | Throughput, lag, partition trends over time | metrics stack | (none) | To enable | kafka-ui is stateless / point-in-time - needs Prometheus + Grafana (see group 2) | P2 |  |
| | **2 - CONTAINER KAFKA · Prometheus / Grafana metrics & alerts   (0 available · 5 to enable · 2 to fix)** | | | | | | | |
| 8 | Broker JMX metrics → Prometheus | Throughput, request rates, ISR, controller, partition counts | JMX / kafka exporter | (none) | To enable | No metrics port or JMX exporter on the kafka-kraft pod; no ServiceMonitor | P1 | image `egovio/bitnami-kafka:3.6.0` |
| 9 | Consumer lag metric (scrapeable) | Alertable lag per group / topic | kafka-exporter | (none) | To enable | No kafka-exporter deployed - lag lives only in kafka-ui | P1 |  |
| 10 | Grafana Kafka dashboard | At-a-glance broker / cluster health over time | Grafana | (none) | To enable | No dashboard and no data source feeding one | P2 | kube-prometheus-stack Grafana present in `monitoring` ns |
| 11 | Under-replicated / offline partitions alert | Data-loss & availability risk | PrometheusRule | (none) | To enable | No Kafka PrometheusRule exists in the cluster | P1 |  |
| 12 | Broker down / controller-missing alert | Broker or KRaft controller unavailable | PrometheusRule | (none) | To enable | No Kafka PrometheusRule exists | P1 |  |
| 13 | Kafka pod restarts / crashloop | Controller pods restarting | kube-state-metrics | Grafana / K8s alerts | Available - fix | Generic pod alert, not Kafka-scoped; controllers already restarting (controller-0: 4, controller-1: 5 in 24h) | P2 | see [Kubernetes Alerts Master List](kubernetes-alerts.md) §2 |
| 14 | Kafka PVC / log-dir disk usage | Log directory volume filling up | kubelet / node-exporter | Grafana / K8s alerts | Available - fix | Generic PVC threshold, no Kafka retention-headroom tuning | P2 | see [Kubernetes Alerts Master List](kubernetes-alerts.md) §5 |
| | **3 - MANAGED KAFKA · AWS MSK · CloudWatch metrics, DEFAULT level   (5 available · 1 to enable)** | | | | | | | |
| 15 | Cluster health | `ActiveControllerCount`, `OfflinePartitionsCount`, `UnderReplicatedPartitions`, `UnderMinIsrPartitionCount` | CloudWatch `AWS/Kafka` | MSK console → Monitoring | Available | Metrics exist but nothing alarms on them (see group 5) | P1 | DEFAULT level exposes these |
| 16 | Partition / topic counts | `GlobalPartitionCount`, `GlobalTopicCount`, `PartitionCount`, `LeaderCount`, `UserPartitionExists` | CloudWatch | MSK console | Available | - | P3 |  |
| 17 | Throughput | `BytesInPerSec`, `BytesOutPerSec`, `MessagesInPerSec`, `RequestBytesMean` | CloudWatch | MSK console | Available | Cluster / broker level only - not per-topic (see next row) | P3 |  |
| 18 | Consumer lag | `MaxOffsetLag`, `SumOffsetLag`, `EstimatedMaxTimeLag`, `RollingEstimatedTimeLagMax` | CloudWatch | MSK console | Available | No alarm on lag | P2 |  |
| 19 | Broker resources | `Cpu User/System/Idle/IoWait`, `MemoryUsed/Free/Cached`, `HeapMemoryAfterGC`, `KafkaDataLogsDiskUsed`, FD & mmap usage, `BurstBalance` | CloudWatch | MSK console | Available | No alarm on disk / CPU / heap - disk fill = broker outage | P1 | 4× `kafka.m7g.2xlarge`, 800 GB EBS/broker |
| 20 | Per-topic / per-partition granularity | Which topic or partition drives load or lag | MSK enhanced monitoring | (none) | To enable | `EnhancedMonitoring = DEFAULT`; `PER_TOPIC_PER_BROKER` / `PER_TOPIC_PER_PARTITION` off - can't isolate a hot topic | P2 |  |
| | **4 - MANAGED KAFKA · AWS MSK · Prometheus Open Monitoring   (0 available · 2 to enable)** | | | | | | | |
| 21 | JMX Exporter (Prometheus) | Pull MSK broker metrics into our own Prometheus / Grafana | MSK Open Monitoring | (none) | To enable | `JmxExporter.EnabledInBroker = false` | P2 | CloudWatch is the only metric source today |
| 22 | Node Exporter (Prometheus) | Host-level OS metrics for the brokers | MSK Open Monitoring | (none) | To enable | `NodeExporter.EnabledInBroker = false` | P3 |  |
| | **5 - MANAGED KAFKA · AWS MSK · Logs & alerting   (0 available · 2 to enable)** | | | | | | | |
| 23 | Broker log delivery | Broker / controller / GC logs for troubleshooting | MSK LoggingInfo | (none) | To enable | CloudWatch Logs, Firehose and S3 all disabled - no broker logs delivered anywhere; blind during incidents | P1 |  |
| 24 | CloudWatch alarms | Page on offline partitions, under-replication, disk, lag | CloudWatch Alarms | (none) | To enable | Zero alarms on the cluster; 44 metrics exist but nothing alerts | P1 | metrics without alarms = dashboards nobody watches |
| | **6 - CROSS-CUTTING   (0 available · 1 to enable · 1 to fix)** | | | | | | | |
| 25 | Unified Kafka view (container + MSK) | Single pane across both footprints | Grafana | (none) | To enable | Two silos today - kafka-ui and the MSK console; no combined view or ownership | P3 |  |
| 26 | MSK access posture (visibility-adjacent) | Who / what can reach the brokers | MSK cluster config | MSK console → Properties | Available - fix | Unauthenticated access enabled, client-broker `PLAINTEXT`, in-cluster encryption off - surfaced while reviewing MSK monitoring | P1 | security gap, not a metric gap - route to the MSK/security owner |

---

### Sources

- **Container Kafka** - `kubectl` against `unified-dev`: `kafka-kraft-controller` StatefulSet (3 replicas, image `egovio/bitnami-kafka:3.6.0-debian-11-r0`) in `backbone`; no metrics port, no ServiceMonitor/PodMonitor, no Kafka PrometheusRule. kube-prometheus-stack present in `monitoring`.
- **kafka-ui** - DIGIT-DevOps `deploy-as-code/helm/environments/studio-demo.yaml` (`kafka-ui` block: `bootstrapServers: kafka-kraft-controller-headless.backbone:9092`, `readonly: true`) and `charts/backbone-services/kafka-ui` (image `provectuslabs/kafka-ui`, OAuth2, ingress path `/kafka-ui`).
- **AWS MSK** - `aws kafka describe-cluster-v2` + `cloudwatch list-metrics` / `describe-alarms` on `ng-central-prd-msk` (af-south-1, account 022499048165): Kafka 3.9.x KRaft, 4× `kafka.m7g.2xlarge`, 800 GB/broker, `EnhancedMonitoring=DEFAULT`, OpenMonitoring off, all broker logging disabled, 0 alarms.
