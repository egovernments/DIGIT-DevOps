# ZooKeeper

[ZooKeeper](https://zookeeper.apache.org/) is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services. All of these kinds of services are used in some form or other by distributed applications.

## TL;DR

```console
$ helm repo add bitnami https://charts.bitnami.com/bitnami
$ helm install my-release bitnami/zookeeper
```

## Introduction

This chart bootstraps a [ZooKeeper](https://github.com/bitnami/bitnami-docker-zookeeper) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

Bitnami charts can be used with [Kubeapps](https://kubeapps.com/) for deployment and management of Helm Charts in clusters. This Helm chart has been tested on top of [Bitnami Kubernetes Production Runtime](https://kubeprod.io/) (BKPR). Deploy BKPR to get automated TLS certificates, logging and monitoring for your applications.

## Prerequisites

- Kubernetes 1.12+
- Helm 3.1.0
- PV provisioner support in the underlying infrastructure

## Installing the Chart

To install the chart with the release name `my-release`:

```console
$ helm repo add bitnami https://charts.bitnami.com/bitnami
$ helm install my-release bitnami/zookeeper
```

These commands deploy ZooKeeper on the Kubernetes cluster in the default configuration. The [Parameters](#parameters) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```console
$ helm delete my-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Parameters

The following tables lists the configurable parameters of the ZooKeeper chart and their default values per section/component:

| Parameter                 | Description                                     | Default                                                 |
|---------------------------|-------------------------------------------------|---------------------------------------------------------|
| `global.imageRegistry`    | Global Docker image registry                    | `nil`                                                   |
| `global.imagePullSecrets` | Global Docker registry secret names as an array | `[]` (does not add image pull secrets to deployed pods) |
| `global.storageClass`     | Global storage class for dynamic provisioning   | `nil`                                                   |

### Common parameters

| Parameter           | Description                                        | Default                           |
|---------------------|----------------------------------------------------|-----------------------------------|
| `nameOverride`      | String to partially override common.names.fullname | `nil`                             |
| `fullnameOverride`  | String to fully override common.names.fullname     | `nil`                             |
| `clusterDomain`     | Default Kubernetes cluster domain                  | `cluster.local`                   |
| `extraDeploy`       | Array of extra objects to deploy with the release  | `[]` (evaluated as a template)    |
| `commonLabels`      | Labels to add to all deployed objects              | `{}`                              |
| `commonAnnotations` | Annotations to add to all deployed objects         | `{}`                              |
| `schedulerName`     | Kubernetes pod scheduler registry                  | `nil` (use the default-scheduler) |

### Zookeeper chart parameters

| Parameter                   | Description                                                                                 | Default                                                 |
|-----------------------------|---------------------------------------------------------------------------------------------|---------------------------------------------------------|
| `image.registry`            | ZooKeeper image registry                                                                    | `docker.io`                                             |
| `image.repository`          | ZooKeeper Image name                                                                        | `bitnami/zookeeper`                                     |
| `image.tag`                 | ZooKeeper Image tag                                                                         | `{TAG_NAME}`                                            |
| `image.pullPolicy`          | ZooKeeper image pull policy                                                                 | `IfNotPresent`                                          |
| `image.pullSecrets`         | Specify docker-registry secret names as an array                                            | `[]` (does not add image pull secrets to deployed pods) |
| `image.debug`               | Specify if debug values should be set                                                       | `false`                                                 |
| `tickTime`                  | Basic time unit in milliseconds used by ZooKeeper for heartbeats                            | `2000`                                                  |
| `initLimit`                 | Time the ZooKeeper servers in quorum have to connect to a leader                            | `10`                                                    |
| `syncLimit`                 | How far out of date a server can be from a leader                                           | `5`                                                     |
| `maxClientCnxns`            | Number of concurrent connections that a single client may make to a single member           | `60`                                                    |
| `maxSessionTimeout`         | Maximum session timeout in milliseconds that the server will allow the client to negotiate. | `40000`                                                 |
| `autopurge.snapRetainCount` | Number of retains snapshots for autopurge                                                   | `3`                                                     |
| `autopurge.purgeInterval`   | The time interval in hours for which the purge task has to be triggered                     | `0`                                                     |
| `fourlwCommandsWhitelist`   | A list of comma separated Four Letter Words commands to use                                 | `srvr, mntr`                                            |
| `listenOnAllIPs`            | Allow Zookeeper to listen for connections from its peers on all available IP addresses.     | `false`                                                 |
| `allowAnonymousLogin`       | Allow to accept connections from unauthenticated users                                      | `yes`                                                   |
| `auth.existingSecret`       | Use existing secret (ignores previous password)                                             | `nil`                                                   |
| `auth.enabled`              | Enable ZooKeeper auth                                                                       | `false`                                                 |
| `auth.clientUser`           | User that will use ZooKeeper clients to auth                                                | `nil`                                                   |
| `auth.clientPassword`       | Password that will use ZooKeeper clients to auth                                            | `nil`                                                   |
| `auth.serverUsers`          | List of user to be created                                                                  | `nil`                                                   |
| `auth.serverPasswords`      | List of passwords to assign to users when created                                           | `nil`                                                   |
| `hostAliases`               | Add deployment host aliases                                                                 | `[]`                                                    |
| `heapSize`                  | Size in MB for the Java Heap options (Xmx and XMs)                                          | `[]`                                                    |
| `logLevel`                  | Log level of ZooKeeper server                                                               | `ERROR`                                                 |
| `jvmFlags`                  | Default JVMFLAGS for the ZooKeeper process                                                  | `nil`                                                   |
| `config`                    | Configure ZooKeeper with a custom zoo.conf file                                             | `nil`                                                   |
| `dataLogDir`                | Data log directory                                                                          | `""`                                                    |
| `namespaceOverride`         | Namespace for ZooKeeper resources. Overrides the release namespace.                         | The Release Namespace                                   |

### Statefulset parameters

| Parameter                            | Description                                                                               | Default                        |
|:-------------------------------------|:------------------------------------------------------------------------------------------|:-------------------------------|
| `replicaCount`                       | Number of ZooKeeper nodes                                                                 | `1`                            |
| `minServerId`                        | Minimal SERVER_ID value, nodes increment their IDs respectively                           | `1`                            |
| `updateStrategy`                     | Update strategy for the statefulset                                                       | `RollingUpdate`                |
| `rollingUpdatePartition`             | Partition update strategy                                                                 | `nil`                          |
| `podManagementPolicy`                | Pod management policy                                                                     | `Parallel`                     |
| `podLabels`                          | ZooKeeper pod labels                                                                      | `{}` (evaluated as a template) |
| `podAnnotations`                     | ZooKeeper Pod annotations                                                                 | `{}` (evaluated as a template) |
| `podAffinityPreset`                  | Pod affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`       | `""`                           |
| `podAntiAffinityPreset`              | Pod anti-affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`  | `soft`                         |
| `nodeAffinityPreset.type`            | Node affinity preset type. Ignored if `affinity` is set. Allowed values: `soft` or `hard` | `""`                           |
| `nodeAffinityPreset.key`             | Node label key to match Ignored if `affinity` is set.                                     | `""`                           |
| `nodeAffinityPreset.values`          | Node label values to match. Ignored if `affinity` is set.                                 | `[]`                           |
| `affinity`                           | Affinity for pod assignment                                                               | `{}` (evaluated as a template) |
| `nodeSelector`                       | Node labels for pod assignment                                                            | `{}` (evaluated as a template) |
| `tolerations`                        | Tolerations for pod assignment                                                            | `[]` (evaluated as a template) |
| `priorityClassName`                  | Name of the existing priority class to be used by ZooKeeper pods                          | `""`                           |
| `securityContext.enabled`            | Enable security context (ZooKeeper master pod)                                            | `true`                         |
| `securityContext.fsGroup`            | Group ID for the container (ZooKeeper master pod)                                         | `1001`                         |
| `securityContext.runAsUser`          | User ID for the container (ZooKeeper master pod)                                          | `1001`                         |
| `resources`                          | CPU/Memory resource requests/limits                                                       | Memory: `256Mi`, CPU: `250m`   |
| `livenessProbe`                      | Liveness probe configuration for ZooKeeper                                                | Check `values.yaml` file       |
| `readinessProbe`                     | Readiness probe configuration for ZooKeeper                                               | Check `values.yaml` file       |
| `customLivenessProbe`                | Override default liveness probe                                                           | `nil`                          |
| `customReadinessProbe`               | Override default readiness probe                                                          | `nil`                          |
| `extraVolumes`                       | Extra volumes                                                                             | `nil`                          |
| `extraVolumeMounts`                  | Mount extra volume(s)                                                                     | `nil`                          |
| `initContainers`                     | Extra init container to add to the statefulset                                            | `nil`                          |
| `podDisruptionBudget.maxUnavailable` | Max number of pods down simultaneously                                                    | `1`                            |

### Exposure parameters

| Parameter                                | Description                                                                                        | Default                                              |
|------------------------------------------|----------------------------------------------------------------------------------------------------|------------------------------------------------------|
| `service.type`                           | Kubernetes Service type                                                                            | `ClusterIP`                                          |
| `service.loadBalancerIP`                 | Use with service.type `LoadBalancer` to assign static IP to Load Balancer instance                 | `""`                                                 |
| `service.port`                           | ZooKeeper port                                                                                     | `2181`                                               |
| `service.followerPort`                   | ZooKeeper follower port                                                                            | `2888`                                               |
| `service.electionPort`                   | ZooKeeper election port                                                                            | `3888`                                               |
| `service.nodePorts.client`               | Nodeport for client connections                                                                    | `""`                                                 |
| `service.nodePorts.clientTls`            | Nodeport for tls client connections                                                                | `""`                                                 | 
| `service.publishNotReadyAddresses`       | If the ZooKeeper headless service should publish DNS records for not ready pods                    | `true`                                               |
| `serviceAccount.create`                  | Enable creation of ServiceAccount for zookeeper pod                                                | `false`                                              |
| `serviceAccount.name`                    | The name of the service account to use. If not set and `create` is `true`, a name is generated     | Generated using the `common.names.fullname` template |
| `serviceAccount.automountServiceAccountToken` | Enable/Disable automountServiceAccountToken  for Service Account                                   | `true`                                               |
| `service.disableBaseClientPort`               | Remove client port from service definitions.                                                       | `false`                                              |
| `service.tlsClientPort`                       | Service port for tls client connections                                                            | `3181`                                               |
| `service.annotations`                    | Annotations for the Service                                                                        | `{}`                                                 |
| `service.headless.annotations`           | Annotations for the Headless Service                                                               | `{}`                                                 |
| `networkPolicy.enabled`                  | Enable NetworkPolicy                                                                               | `false`                                              |
| `networkPolicy.allowExternal`            | Don't require client label for connections                                                         | `true`                                               |

### Persistence parameters

| Parameter                              | Description                                                                    | Default                         |
|----------------------------------------|--------------------------------------------------------------------------------|---------------------------------|
| `persistence.enabled`                  | Enable Zookeeper data persistence using PVC                                    | `true`                          |
| `persistence.existingClaim`            | Provide an existing `PersistentVolumeClaim`                                    | `nil` (evaluated as a template) |
| `persistence.storageClass`             | PVC Storage Class for ZooKeeper data volume                                    | `nil`                           |
| `persistence.accessMode`               | PVC Access Mode for ZooKeeper data volume                                      | `ReadWriteOnce`                 |
| `persistence.size`                     | PVC Storage Request for ZooKeeper data volume                                  | `8Gi`                           |
| `persistence.annotations`              | Annotations for the PVC                                                        | `{}` (evaluated as a template)  |
| `persistence.selector`                 | Selector to match an existing Persistent Volume for Zookeeper's data PVC. If set, the PVC can't have a PV dynamically provisioned for it                                                                        | `{}` (evaluated as a template)  |
| `persistence.dataLogDir.size`          | PVC Storage Request for ZooKeeper's Data log directory                         | `8Gi`                           |
| `persistence.dataLogDir.existingClaim` | Provide an existing `PersistentVolumeClaim` for Zookeeper's Data log directory | `nil` (evaluated as a template) |
| `persistence.dataLogDir.selector`      | Selector to match an existing Persistent Volume for Zookeeper's Data log PVC. If set, the PVC can't have a PV dynamically provisioned for it                                                                    | `{}` (evaluated as a template)  |

### Volume Permissions parameters

| Parameter                            | Description                                                                                                          | Default                 |
|--------------------------------------|----------------------------------------------------------------------------------------------------------------------|-------------------------|
| `volumePermissions.enabled`          | Enable init container that changes the owner and group of the persistent volume(s) mountpoint to `runAsUser:fsGroup` | `false`                 |
| `volumePermissions.image.registry`   | Init container volume-permissions image registry                                                                     | `docker.io`             |
| `volumePermissions.image.repository` | Init container volume-permissions image name                                                                         | `bitnami/bitnami-shell` |
| `volumePermissions.image.tag`        | Init container volume-permissions image tag                                                                          | `"10"`                  |
| `volumePermissions.image.pullPolicy` | Init container volume-permissions image pull policy                                                                  | `Always`                |
| `volumePermissions.resources`        | Init container resource requests/limit                                                                               | `nil`                   |

### Metrics parameters

| Parameter                              | Description                                                                                                                               | Default                                                      |
|----------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------|
| `metrics.enabled`                      | Enable prometheus to access zookeeper metrics endpoint                                                                                    | `false`                                                      |
| `metrics.containerPort`                | Port where a Jetty server will expose Prometheus metrics                                                                                  | `9141`                                                       |
| `metrics.service.type`                 | Kubernetes service type (`ClusterIP`, `NodePort` or `LoadBalancer`) for Jetty server exposing Prometheus metrics                          | `ClusterIP`                                                  |
| `metrics.service.port`                 | Prometheus metrics service port                                                                                                           | `9141`                                                       |
| `metrics.service.annotations`          | Service annotations for Prometheus to auto-discover the metrics endpoint                                                                  | `{prometheus.io/scrape: "true", prometheus.io/port: "9141"}` |
| `metrics.serviceMonitor.enabled`       | if `true`, creates a Prometheus Operator ServiceMonitor (also requires `metrics.enabled` to be `true`)                                    | `false`                                                      |
| `metrics.serviceMonitor.namespace`     | Namespace for the ServiceMonitor Resource                                                                                                 | The Release Namespace                                        |
| `metrics.serviceMonitor.interval`      | Interval at which metrics should be scraped.                                                                                              | `nil` (Prometheus Operator default value)                    |
| `metrics.serviceMonitor.scrapeTimeout` | Timeout after which the scrape is ended                                                                                                   | `nil` (Prometheus Operator default value)                    |
| `metrics.serviceMonitor.selector`      | Prometheus instance selector labels                                                                                                       | `nil`                                                        |
| `metrics.prometheusRule.enabled`       | if `true`, creates a Prometheus Operator PrometheusRule (also requires `metrics.enabled` to be `true` and `metrics.prometheusRule.rules`) | `false`                                                      |
| `metrics.prometheusRule.namespace`     | Namespace for the PrometheusRule Resource                                                                                                 | The Release Namespace                                        |
| `metrics.prometheusRule.selector`      | Prometheus instance selector labels                                                                                                       | `nil`                                                        |
| `metrics.prometheusRule.rules`         | Prometheus Rule definitions (see values.yaml for examples)                                                                                | `[]`                                                         |

### TLS/SSL parameters

| Parameter                        | Description                                                                                                                        | Default                                                               |
|----------------------------------|------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| `tls.client.enabled`             | Enable TLS for client connections                                                                                                  | `false`                                                               |
| `tls.client.autoGenerated`       | Generate automatically self-signed TLS certificates for Zookeeper client communications. Currently only supports PEM certificates. | `false`                                                               |
| `tls.client.existingSecret`      | Name of the existing secret containing the TLS certificates for Zookeper client communications                                     | `nil`                                                                 |
| `tls.client.keystorePath`        | Location of the KeyStore file used for Client connections                                                                          | `/opt/bitnami/zookeeper/config/certs/client/zookeeper.keystore.jks`   |
| `tls.client.truststorePath`      | Location of the TrustStore file used for Client connections                                                                        | `/opt/bitnami/zookeeper/config/certs/client/zookeeper.truststore.jks` |
| `tls.client.keystorePassword`    | Password to access KeyStore if needed                                                                                              | `nil`                                                                 |
| `tls.client.truststorePassword`  | Password to access TrustStore if needed                                                                                            | `nil`                                                                 |
| `tls.quorum.enabled`             | Enable TLS for quorum protocol                                                                                                     | `false`                                                               |
| `tls.quorum.autoGenerated`       | Generate automatically self-signed TLS certificates for Zookeeper quorum protocol. Currently only supports PEM certificates.       | `false`                                                               |
| `tls.quorum.existingSecret`      | Name of the existing secret containing the TLS certificates for Zookeper quorum protocol                                           | `nil`                                                                 |
| `tls.quorum.keystorePath`        | Location of the KeyStore file used for Quorum protocol                                                                             | `/opt/bitnami/zookeeper/config/certs/quorum/zookeeper.keystore.jks`   |
| `tls.quorum.truststorePath`      | Location of the TrustStore file used for Quorum protocol                                                                           | `/opt/bitnami/zookeeper/config/certs/quorum/zookeeper.truststore.jks` |
| `tls.quorum.keystorePassword`    | Password to access KeyStore if needed                                                                                              | `nil`                                                                 |
| `tls.quorum.truststorePassword`  | Password to access TrustStore if needed                                                                                            | `nil`                                                                 |
| `tls.resources.limits`           | The resources limits for the TLS init container                                                                                    | `{}`                                                                  |
| `tls.resources.requests`         | The requested resources for the TLS init container                                                                                 | `{}`                                                                  |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
$ helm install my-release \
  --set auth.clientUser=newUser \
    bitnami/zookeeper
```

The above command sets the ZooKeeper user to `newUser`.

> NOTE: Once this chart is deployed, it is not possible to change the application's access credentials, such as usernames or passwords, using Helm. To change these application credentials after deployment, delete any persistent volumes (PVs) used by the chart and re-deploy it, or use the application's built-in administrative tools if available.

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart. For example,

```console
$ helm install my-release -f values.yaml bitnami/zookeeper
```

> **Tip**: You can use the default [values.yaml](values.yaml)

## Configuration and installation details

### [Rolling vs Immutable tags](https://docs.bitnami.com/containers/how-to/understand-rolling-tags-containers/)

It is strongly recommended to use immutable tags in a production environment. This ensures your deployment does not change automatically if the same tag is updated with a different image.

Bitnami will release a new chart updating its containers if a new version of the main container, significant changes, or critical vulnerabilities exist.

### Configure log level

You can configure the ZooKeeper log level using the `ZOO_LOG_LEVEL` environment variable. By default, it is set to `ERROR` because of each readiness probe produce an `INFO` message on connection and a `WARN` message on disconnection.

## Persistence

The [Bitnami ZooKeeper](https://github.com/bitnami/bitnami-docker-zookeeper) image stores the ZooKeeper data and configurations at the `/bitnami/zookeeper` path of the container.

Persistent Volume Claims are used to keep the data across deployments. This is known to work in GCE, AWS, and minikube. See the [Parameters](#parameters) section to configure the PVC or to disable persistence.

If you encounter errors when working with persistent volumes, refer to our [troubleshooting guide for persistent volumes](https://docs.bitnami.com/kubernetes/faq/troubleshooting/troubleshooting-persistence-volumes/).

### Adjust permissions of persistent volume mountpoint

As the image run as non-root by default, it is necessary to adjust the ownership of the persistent volume so that the container can write data into it.

By default, the chart is configured to use Kubernetes Security Context to automatically change the ownership of the volume. However, this feature does not work in all Kubernetes distributions.
As an alternative, this chart supports using an initContainer to change the ownership of the volume before mounting it in the final destination.

You can enable this initContainer by setting `volumePermissions.enabled` to `true`.

### Configure the data log directory

You can use a dedicated device for logs (instead of using the data directory) to help avoiding competition between logging and snaphots. To do so, set the `dataLogDir` parameter with the path to be used for writing transaction logs. Alternatively, set this parameter with an empty string and it will result in the log being written to the data directory (Zookeeper's default behavior).

When using a dedicated device for logs, you can use a PVC to persist the logs. To do so, set `persistence.enabled` to `true`. See the [Persistence Parameters](#persistence-parameters) section for more information.

### Set pod affinity

This chart allows you to set custom pod affinity using the `affinity` parameter. Find more information about pod affinity in the [Kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity).

As an alternative, you can use any of the preset configurations for pod affinity, pod anti-affinity, and node affinity available at the [bitnami/common](https://github.com/bitnami/charts/tree/master/bitnami/common#affinities) chart. To do so, set the `podAffinityPreset`, `podAntiAffinityPreset`, or `nodeAffinityPreset` parameters.

## Troubleshooting

Find more information about how to deal with common errors related to Bitnami’s Helm charts in [this troubleshooting guide](https://docs.bitnami.com/general/how-to/troubleshoot-helm-chart-issues).

## Upgrading

### To 7.0.0

This new version renames the parameters used to configure TLS for both client and quorum.

- `service.tls.disable_base_client_port` is renamed to `service.disableBaseClientPort`
- `service.tls.client_port` is renamed to `service.tlsClientPort`
- `service.tls.client_enable` is renamed to `tls.client.enabled`
- `service.tls.client_keystore_path` is renamed to `tls.client.keystorePath`
- `service.tls.client_truststore_path` is renamed to `tls.client.truststorePath`
- `service.tls.client_keystore_password` is renamed to `tls.client.keystorePassword`
- `service.tls.client_truststore_password` is renamed to `tls.client.truststorePassword`
- `service.tls.quorum_enable` is renamed to `tls.quorum.enabled`
- `service.tls.quorum_keystore_path` is renamed to `tls.quorum.keystorePath`
- `service.tls.quorum_truststore_path` is renamed to `tls.quorum.truststorePath`
- `service.tls.quorum_keystore_password` is renamed to `tls.quorum.keystorePassword`
- `service.tls.quorum_truststore_password` is renamed to `tls.quorum.truststorePassword`

### 6.1.0

This version introduces `bitnami/common`, a [library chart](https://helm.sh/docs/topics/library_charts/#helm) as a dependency. More documentation about this new utility could be found [here](https://github.com/bitnami/charts/tree/master/bitnami/common#bitnami-common-library-chart). Please, make sure that you have updated the chart dependencies before executing any upgrade.

### To 6.0.0

[On November 13, 2020, Helm v2 support was formally finished](https://github.com/helm/charts#status-of-the-project), this major version is the result of the required changes applied to the Helm Chart to be able to incorporate the different features added in Helm v3 and to be consistent with the Helm project itself regarding the Helm v2 EOL.

[Learn more about this change and related upgrade considerations](https://docs.bitnami.com/kubernetes/infrastructure/zookeeper/administration/upgrade-helm3/).

### To 5.21.0

A couple of parameters related to Zookeeper metrics were renamed or disappeared in favor of new ones:

- `metrics.port` is renamed to `metrics.containerPort`.
- `metrics.annotations` is deprecated in favor of `metrics.service.annotations`.

### To 3.0.0

This new version of the chart includes the new ZooKeeper major version 3.5.5. Note that to perform an automatic upgrade
of the application, each node will need to have at least one snapshot file created in the data directory. If not, the
new version of the application won't be able to start the service. Please refer to [ZOOKEEPER-3056](https://issues.apache.org/jira/browse/ZOOKEEPER-3056)
in order to find ways to workaround this issue in case you are facing it.

### To 2.0.0

Backwards compatibility is not guaranteed unless you modify the labels used on the chart's statefulsets.
Use the workaround below to upgrade from versions previous to 2.0.0. The following example assumes that the release name is `zookeeper`:

```console
$ kubectl delete statefulset zookeeper-zookeeper --cascade=false
```

### To 1.0.0

Backwards compatibility is not guaranteed unless you modify the labels used on the chart's deployments.
Use the workaround below to upgrade from versions previous to 1.0.0. The following example assumes that the release name is zookeeper:

```console
$ kubectl delete statefulset zookeeper-zookeeper --cascade=false
```
