# Kubernetes Alerts — Master List

*Configured alerts and alerts still to be configured, in a single table. Kubernetes-scope only.*

Platform-wide (the rule set is identical across all clusters) · v1.0 · 21 September 2026 · Confidential — internal

**Scope note.** This list covers Kubernetes alerts only — nodes, pods and containers, workloads, scheduling and cluster resources, persistent storage, control-plane components, certificates, and the health of the monitoring stack itself.

**Status:** `Configured` = rule exists and is sound · `Configured — fix` = rule exists but is ineffective or misconfigured · `To configure` = missing. Where the status is `Configured — fix`, the **What is misconfigured** column states the specific defect. **Priority:** P0 do first, P1 next, P2 backlog. The final column is blank for the implementation team to complete.

| # | Alert name | What it catches | Severity | Threshold / For | Status | What is misconfigured | Pri | Team notes |
|---|---|---|---|---|---|---|---|---|
| | **1 — NODES   (4 configured · 10 to configure)** | | | | | | | |
| 1 | KubernetesNodeNotReady | Node not in Ready state | critical | 5m | Configured | — | — |  |
| 2 | KubernetesNodeMemoryPressure | Kubelet reporting MemoryPressure | critical | 2m | Configured | — | — |  |
| 3 | KubernetesNodeDiskPressure | Kubelet reporting DiskPressure | critical | 2m | Configured | — | — |  |
| 4 | KubernetesNodeNetworkUnavailable | Node network unavailable | critical | 2m | Configured | — | — |  |
| 5 | NodeCPUHighUsage | Sustained node CPU saturation before pressure conditions trigger | warning | > 90% for 15m | To configure | — | P0 |  |
| 6 | NodeMemoryHighUtilization | Node memory nearing exhaustion — early warning before eviction | critical | > 90% for 15m | To configure | — | P0 |  |
| 7 | NodeFilesystemAlmostOutOfSpace | Node root or data disk nearly full | crit / warn | < 5% crit, < 15% warn | To configure | — | P0 |  |
| 8 | NodeFilesystemSpaceFillingUp | Predicted disk exhaustion from current fill rate | warning | predict_linear full in 24h | To configure | — | P0 |  |
| 9 | KubeNodeUnreachable | Node tainted unreachable by the controller | critical | 15m | To configure | — | P0 |  |
| 10 | NodeFilesystemFilesFillingUp | Inode exhaustion (disk shows free space but writes fail) | warning | < 5% inodes free | To configure | — | P1 |  |
| 11 | NodeDiskIOSaturation | Disk I/O saturated, causing latency across all pods on the node | warning | > 80% utilisation 30m | To configure | — | P1 |  |
| 12 | NodeNetworkReceiveErrs / TransmitErrs | NIC error rate indicating hardware or driver fault | warning | > 0.01 errors/s for 1h | To configure | — | P1 |  |
| 13 | NodeClockNotSynchronising | Clock drift breaking TLS validation and token expiry | warning | NTP unsynchronised 10m | To configure | — | P1 |  |
| 14 | NodeSystemdServiceFailed | A host-level systemd unit has failed | warning | Any failed unit 5m | To configure | — | P2 |  |
| | **2 — PODS & CONTAINERS   (6 configured · 5 to configure)** | | | | | | | |
| 15 | KubernetesContainerOomKiller | Container OOMKilled with an accompanying restart | critical | 1m | Configured — fix | Namespace exclusion `monitoring\|kube-system\|default\|logging` — OOMKills in those namespaces are never alerted at all. | P1 |  |
| 16 | KubernetesPodCrashLooping | Container in CrashLoopBackOff | critical | 1m | Configured — fix | Same namespace exclusion. Also duplicates KubePodCrashLooping, so one crashloop raises two alerts at conflicting severities (critical at 1m, warning at 15m). | P1 |  |
| 17 | KubernetesPodNotHealthy | Pod stuck Pending / Unknown / Failed | critical | 10m | Configured — fix | Same namespace exclusion. Also duplicates KubePodNotReady at a conflicting severity. | P1 |  |
| 18 | KubePodCrashLooping | Container in CrashLoopBackOff (duplicate of the above at lower severity) | warning | 15m | Configured — fix | Duplicate of KubernetesPodCrashLooping. Two alerts for one condition; severity-based routing becomes unreliable. | P1 |  |
| 19 | KubePodNotReady | Pod stuck Pending / Unknown / Failed (duplicate at lower severity) | warning | 15m | Configured — fix | Duplicate of KubernetesPodNotHealthy. Two alerts for one condition at conflicting severities. | P1 |  |
| 20 | KubeContainerWaiting | Container stuck in any waiting state | warning | 1h | Configured | — | — |  |
| 21 | ImagePullBackOff / ErrImagePull | Explicit image pull failure — today only caught generically after 1h | warning | Any pod 5m | To configure | — | P1 |  |
| 22 | KubePodEvicted | Pods evicted under node resource pressure | warning | Any eviction | To configure | — | P1 |  |
| 23 | ContainerLivenessProbeFailing | Liveness or readiness probes failing repeatedly | warning | > 3 failures in 5m | To configure | — | P1 |  |
| 24 | KubeContainerCPUThrottlingHigh | CPU limits actively throttling the workload | warning | > 25% of periods 15m | To configure | — | P1 |  |
| 25 | ContainerMemoryNearLimit | Container approaching its memory limit, OOMKill imminent | warning | > 90% of limit 10m | To configure | — | P1 |  |
| | **3 — WORKLOADS   Deployments, StatefulSets, DaemonSets, Jobs, HPA   (13 configured · 4 to configure)** | | | | | | | |
| 26 | KubeDeploymentGenerationMismatch | Deployment spec not observed by the controller | warning | 15m | Configured | — | — |  |
| 27 | KubeDeploymentReplicasMismatch | Replicas unavailable with no rollout progress | warning | 15m | Configured | — | — |  |
| 28 | KubeDeploymentRolloutStuck | Deployment Progressing condition false | warning | 15m | Configured | — | — |  |
| 29 | KubeStatefulSetReplicasMismatch | StatefulSet replicas not ready | warning | 15m | Configured | — | — |  |
| 30 | KubeStatefulSetGenerationMismatch | StatefulSet spec not observed | warning | 15m | Configured | — | — |  |
| 31 | KubeStatefulSetUpdateNotRolledOut | StatefulSet revision not rolled out | warning | 15m | Configured | — | — |  |
| 32 | KubeDaemonSetRolloutStuck | DaemonSet rollout incomplete | warning | 15m | Configured | — | — |  |
| 33 | KubeDaemonSetNotScheduled | DaemonSet pods not scheduled on all eligible nodes | warning | 10m | Configured | — | — |  |
| 34 | KubeDaemonSetMisScheduled | DaemonSet pods running on nodes they should not be | warning | 15m | Configured | — | — |  |
| 35 | KubeJobNotCompleted | Job running beyond its expected duration | warning | > 12h | Configured | — | — |  |
| 36 | KubeJobFailed | Job failed | warning | 15m | Configured | — | — |  |
| 37 | KubeHpaReplicasMismatch | HPA cannot reach its desired replica count | warning | 15m | Configured | — | — |  |
| 38 | KubeHpaMaxedOut | HPA pinned at maximum replicas — no headroom left | warning | 15m | Configured — fix | Severity is warning only. An HPA pinned at max in production is a capacity outage with no headroom and should page. | P1 |  |
| 39 | KubeDeploymentNoAvailableReplicas | Deployment at zero available replicas — a hard outage, not covered by the mismatch rules | critical | 0 available for 5m | To configure | — | P0 |  |
| 40 | KubeStatefulSetNoAvailableReplicas | StatefulSet at zero available replicas | critical | 0 available for 5m | To configure | — | P0 |  |
| 41 | PodDisruptionBudgetAtLimit | PDB blocking drains, or at its disruption limit | warning | 15m | To configure | — | P1 |  |
| 42 | KubeCronJobSuspendedOrMissed | CronJob suspended, or scheduled run missed | warning | Missed 1 schedule | To configure | — | P2 |  |
| | **4 — SCHEDULING & CLUSTER RESOURCES   (0 configured · 8 to configure)** | | | | | | | |
| 43 | KubePodPendingUnschedulable | Pods cannot be scheduled — no capacity or unsatisfiable constraints | critical | Pending > 15m | To configure | — | P0 |  |
| 44 | ClusterAutoscalerScaleUpFailed | Autoscaler unable to add nodes (quota, subnet, or instance capacity) | critical | Any failure 10m | To configure | — | P0 |  |
| 45 | KubeCPUOvercommit | Cluster cannot absorb a single node failure | warning | Requests > capacity − 1 node | To configure | — | P1 |  |
| 46 | KubeMemoryOvercommit | Memory requests exceed tolerable capacity | warning | Requests > capacity − 1 node | To configure | — | P1 |  |
| 47 | KubeQuotaAlmostFull | Namespace ResourceQuota nearing exhaustion | warning | > 90% of quota | To configure | — | P1 |  |
| 48 | KubeQuotaExceeded | Namespace ResourceQuota exhausted, admission failing | critical | 100% of quota | To configure | — | P1 |  |
| 49 | KubeletTooManyPods | Node approaching its maximum pod count | warning | > 95% of max pods | To configure | — | P1 |  |
| 50 | NamespaceTerminatingStuck | Namespace stuck Terminating on a finalizer | warning | > 1h | To configure | — | P2 |  |
| | **5 — PERSISTENT STORAGE   (2 configured · 5 to configure)** | | | | | | | |
| 51 | KubernetesVolumeOutOfDiskSpace | PVC below 20% free | critical | < 20% for 10m | Configured — fix | Single critical tier at 20% free, with no warning tier and no fill-rate prediction — there is no lead time before the volume is full. | P0 |  |
| 52 | KubernetesPersistentvolumeError | PersistentVolume in Failed or Pending phase | critical | 5m | Configured | — | — |  |
| 53 | KubePersistentVolumeFillingUp | Predicted PVC exhaustion from current fill rate | warning | predict_linear full in 4 days | To configure | — | P0 |  |
| 54 | PVC warning tier | Early warning ahead of the existing 20% critical threshold | warning | < 30% free | To configure | — | P0 |  |
| 55 | KubePersistentVolumeInodesFillingUp | PVC inode exhaustion | warning | < 3% inodes free | To configure | — | P1 |  |
| 56 | KubePersistentVolumeClaimPending | PVC unbound — provisioning failing | warning | Pending > 15m | To configure | — | P1 |  |
| 57 | CSIDriverUnhealthy / VolumeAttachmentFailed | CSI driver or attach or detach failures | warning | Any failure 10m | To configure | — | P2 |  |
| | **6 — CONTROL PLANE   API server, kubelet, scheduler, controller-manager, etcd, DNS   (0 configured · 20 to configure)** | | | | | | | |
| 58 | KubeAPIDown | API server unreachable — nothing in the cluster can reconcile | critical | 5m | To configure | — | P0 |  |
| 59 | KubeletDown | Kubelet not reporting; its node is effectively unmanaged | critical | 15m | To configure | — | P0 |  |
| 60 | CoreDNSDown | Cluster DNS unavailable — breaks service discovery estate-wide | critical | 5m | To configure | — | P0 |  |
| 61 | CoreDNSErrorsHigh | DNS resolution failures | critical | > 1% SERVFAIL 10m | To configure | — | P0 |  |
| 62 | etcdMembersDown | etcd member unavailable (self-managed control planes only) | critical | Any member 5m | To configure | — | P0 |  |
| 63 | etcdNoLeader | etcd has no leader — cluster writes blocked | critical | 1m | To configure | — | P0 |  |
| 64 | KubeAPIErrorBudgetBurn | API server SLO burn across fast and slow windows | critical | 14.4x / 6x / 1x burn | To configure | — | P1 |  |
| 65 | KubeAPITerminatedRequests | API server shedding load via priority and fairness | warning | > 20% terminated 5m | To configure | — | P1 |  |
| 66 | KubeAPIHighLatency | API server request latency degradation | warning | p99 > 1s for 10m | To configure | — | P1 |  |
| 67 | KubeAPIErrorsHigh | API server 5xx rate | warning | > 3% of requests 10m | To configure | — | P1 |  |
| 68 | etcdHighCommitDurations | etcd write latency degrading the whole control plane | warning | p99 > 250ms 10m | To configure | — | P1 |  |
| 69 | etcdDatabaseQuotaLowSpace | etcd approaching its storage quota | critical | > 80% of quota | To configure | — | P1 |  |
| 70 | KubeSchedulerDown | Scheduler unavailable — no new pods placed (may be unexposed on managed clusters) | critical | 15m | To configure | — | P1 |  |
| 71 | KubeControllerManagerDown | Controller manager unavailable (may be unexposed on managed clusters) | critical | 15m | To configure | — | P1 |  |
| 72 | KubeProxyDown | kube-proxy unavailable — service routing degrades on that node | warning | 15m | To configure | — | P1 |  |
| 73 | KubeStateMetricsListErrors | kube-state-metrics degraded — silently breaks most alerts in this list | critical | > 1% list or watch errors | To configure | — | P1 |  |
| 74 | KubeNodeReadinessFlapping | Node oscillating between Ready and NotReady | warning | > 2 transitions in 15m | To configure | — | P1 |  |
| 75 | KubeletPlegDurationHigh | Container runtime degraded on a node | warning | PLEG p99 > 10s | To configure | — | P2 |  |
| 76 | KubeletPodStartUpLatencyHigh | Pods slow to start | warning | p99 > 60s | To configure | — | P2 |  |
| 77 | KubeVersionMismatch | Mixed Kubernetes component versions across the cluster | warning | 15m | To configure | — | P2 |  |
| | **7 — CERTIFICATES   (2 configured · 4 to configure)** | | | | | | | |
| 78 | SSLCertificateExpiringSoon | Certificate expiring within 2 days | critical | < 2 days | Configured — fix | Two defects. (1) Threshold is 2 days, against a mandated 30 / 14 / 7 — too late to renew through change control. (2) Selector `job="blackbox", instance="prometheus-blackbox-exporter:9115"` does not match the job or instance labels the operator generates from Probe CRs, so the rule most likely never fires. Verify with `count(probe_ssl_earliest_cert_expiry{job="blackbox"})`. | P0 |  |
| 79 | SSLCertificateExpired | Certificate already expired | critical | < 0 | Configured — fix | Same non-matching selector as above — the rule is most likely inert, while giving the impression that expiry is covered. | P0 |  |
| 80 | SSLCertExpiring — 30 / 14 / 7 day tiers | Graduated warning; replaces the single 2-day rule, which leaves no time to renew | info / warn / crit | 30d / 14d / 7d | To configure | — | P0 |  |
| 81 | CertManagerCertificateNotReady | cert-manager Certificate resource not Ready | critical | > 1h | To configure | — | P0 |  |
| 82 | CertManagerACMEChallengeFailed | HTTP01 challenge or ACME order failing — renewal will not complete | warning | Any failure 30m | To configure | — | P1 |  |
| 83 | KubeClientCertificateExpiration | Kubernetes client certificates nearing expiry | crit / warn | < 7d crit, < 30d warn | To configure | — | P1 |  |
| | **8 — MONITORING STACK SELF-HEALTH   the alerting pipeline itself   (8 configured · 8 to configure)** | | | | | | | |
| 84 | AlertmanagerFailedReload | Alertmanager configuration failed to load | critical | 10m | Configured | — | — |  |
| 85 | AlertmanagerFailedToSendAlerts | Notification delivery failing | warning | > 1% failures 5m | Configured — fix | Severity is warning only. This rule watches the notification path itself; when it fires, alerts are not reaching anyone. It should be critical. | P0 |  |
| 86 | AlertmanagerClusterFailedToSendAlerts | All notification integrations failing | critical | > 1% failures 5m | Configured | — | — |  |
| 87 | AlertmanagerClusterFailedToSendAlerts (2nd) | Duplicate rule name with an inverse matcher | warning | > 1% failures 5m | Configured — fix | Duplicate rule name with an inverse integration matcher. The two rules shadow each other and make the firing state ambiguous. | P2 |  |
| 88 | AlertmanagerMembersInconsistent | Cluster members below peak | critical | 15m | Configured — fix | Quorum alert evaluated against a single-replica Alertmanager — the condition can never be satisfied. Fix by scaling Alertmanager to 3 replicas. | P1 |  |
| 89 | AlertmanagerConfigInconsistent | Config hash differs across replicas | critical | 20m | Configured — fix | Compares config hashes across replicas; with one replica there is nothing to compare. Inert until Alertmanager is scaled out. | P1 |  |
| 90 | AlertmanagerClusterDown | Half or more replicas down | critical | 5m | Configured — fix | Triggers when at least half the replicas are down; with one replica the whole pipeline is already gone before this can help. Inert until scaled out. | P1 |  |
| 91 | AlertmanagerClusterCrashlooping | Half or more replicas restarting | critical | 5m | Configured — fix | Same single-replica limitation — cannot fire meaningfully at the current replica count. | P1 |  |
| 92 | Watchdog | Always-firing heartbeat proving the pipeline is alive; wire to an external dead-man's switch | none | Always on | To configure | — | P0 |  |
| 93 | TargetDown | A scrape target has disappeared — its alerts silently stop evaluating | warning | > 10% of a job down 5m | To configure | — | P0 |  |
| 94 | PrometheusDown | Prometheus unavailable | critical | 5m | To configure | — | P0 |  |
| 95 | PrometheusNotIngestingSamples | Prometheus has stopped ingesting data | critical | Rate = 0 for 10m | To configure | — | P0 |  |
| 96 | PrometheusRuleFailures | Rule evaluation erroring — affected alerts never fire | critical | Any failure 15m | To configure | — | P0 |  |
| 97 | PrometheusErrorSendingAlertsToAlertmanager | Prometheus cannot reach Alertmanager | critical | > 1% failures 5m | To configure | — | P0 |  |
| 98 | PrometheusTSDBCompactionsFailing | Storage layer degrading; data loss risk | warning | Any failure 4h | To configure | — | P1 |  |
| 99 | ConfigReloaderSidecarErrors | Rule or config reload sidecar failing — changes never take effect | warning | 10m | To configure | — | P1 |  |

**Totals — 99 Kubernetes alerts.** Configured and sound: 20 · Configured but needs fixing: 15 · To configure: 64. Of the 35 rules currently deployed, 15 are ineffective, duplicated, or wrongly scoped.

Applies to all rules in the four custom groups (nodes, pods, certificates, volumes): each carries a `repeat_interval: 30m` label. `repeat_interval` is an Alertmanager route setting, not an alert label, so unless the route tree matches on it explicitly this adds label cardinality without effect.

The largest single gap is the control plane: 20 alerts, none configured, including API server, kubelet, CoreDNS and etcd availability. The second is scheduling and cluster resources at 8, none configured. Items marked "may be unexposed on managed clusters" (scheduler, controller-manager, etcd) may legitimately be answered N/A on EKS and AKS.
