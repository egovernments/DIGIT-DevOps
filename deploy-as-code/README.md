
# Digit Helm Deployment Common Chart

The common library chart has templates which eases deployment of a service on to Digit with recommended platform defaults which can further be customized to service or environment needs while abstracting the need to know kubernetes manifest syntax.

This helps us push defaults and changes to most, if not all, services deployed onto Digit.

## Requirements

The default values file [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml) has defaults for all manifest files, which can be overrides by service values file or environment override file.

The service template file [_service.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/templates/_service.yaml) used for generating a service manifest.

The ingress template file [_ingress.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/templates/_ingress.yaml) used for generating ingress manifest.

The deployment template file [_deployment.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/templates/_deployment.yaml) used for generating a deployment manifest.

## Values template

Parameter | Description | Default
--- | --- | ---
`namespace` | Default namespace for the service | `egov`
`replicas` | Number of Pods to be created | `1`
`httpPort` | Default port number for the service | `8080`
`appType` | Application Type to configure defaults for appType, "java-spring" only type with defaults for now. For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml) | ` `
`labels` | Labels for the service, for example, <br/>`app: "egov-mdms-service"`<br/>`group: "core"` | `''`
`ingress.enabled` | To add ingress controller for the service  | `false`
`ingress.zuul` | When ingress is enabled, routes the request via Zuul API gateway | `false` 
`ingress.context` | When ingress is enabled, exposes the following context path to the internet, example `user` | `` 
`ingress.waf.enabled` | When ingress is enabled, Enable Web Application Firewall for the service | `true`
`image.pullPolicy` |  To pull a Docker image from Docker repository, By default skip pulling an image if it already exists | `IfNotPresent`
`image.tag` | Docker image tag for the service | `latest`
`affinity.preferSpreadAcrossAZ` | To spread deployment replicas across multiple availability zones in cloud environment | `true`
`initContainers.dbMigration.enabled` | Add Flyway DB migration container for the service, requires schemaTable configuration! | `false`
`initContainers.dbMigration.schemaTable` | Schema table for the flyway db migration, required, if db migration enabled,  | `''`
`initContainers.dbMigration.image.pullPolicy` | Pulls the DB migration docker images from Docker repository | `IfNotPresent`
`initContainers.dbMigration.image.tag` | Docker image tag for the initcontainer | `latest`
`initContainers.dbMigration.env` | Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `env: \|` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `- name: "FLYWAY_USER"` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; `valueFrom:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `secretKeyRef:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `name: db` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `key: flyway-username` <br/> For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml)
`initContainers.gitSync.enabled` | To add a gitSync init container which clones a repository using configured ssh read token | `false`
`initContainers.gitSync.repo` | Git repository to be checked out, required, if gitSync enabled, example, `git@github.com:egovernments/egov-mdms-data`  | `''`
`initContainers.gitSync.branch` | Git repository branch to be checked out, required, if gitSync enabled, example, `master`  | `''`
`gitSync.image.repository` | Docker image of the gitSync init container  | `k8s.gcr.io/git-sync`
`gitSync.image.tag` | Docker image tag of the gitSync init container | `v3.1.1`
`gitSync.image.pullPolicy` |  Docker image pull policy for gitSync init container | `IfNotPresent`
`gitSync.env` | Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string |  `For Eg:` <br/> `env: \|` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `- name: "GIT_SYNC_REPO"` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; `value: "{{ .Values.initContainers.gitSync.repo }}"` <br/> For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml)
`healthChecks.enabled` | To enable/disable healthchecks [Liveness probes and Readiness probes] for a pod | `false`
`healthChecks.livenessProbe` | Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `livenessProbe: \|` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `httpGet:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `path: "{{ .Values.healthChecks.livenessProbePath }}"` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `initialDelaySeconds: 60` <br/> For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml)
`healthChecks.livenessProbe.httpGet.path` | Context path of the service to check the liveness of a pod | `{{ .Values.healthChecks.livenessProbePath }}`
`healthChecks.livenessProbe.httpGet.port` | Port number of the service to check the liveness of a pod | `{{ .Values.httpPort }}`
`healthChecks.readinessProbe` | Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `readinessProbe: \|` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `httpGet:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `path: "{{ .Values.healthChecks.readinessProbePath }}"` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `initialDelaySeconds: 60` <br/> For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml)
`healthChecks.readinessProbe.httpGet.path` | Context path of the service to check the readiness of a pod | `{{ .Values.healthChecks.readinessProbePath }}`
`healthChecks.readinessProbe.httpGet.port` | Port number of the service to check the readiness of a pod | `{{ .Values.httpPort }}`
`lifecycle.preStop.exec.command` | Executes the command in the pod before stopping | `- sh`<br/> `- -c` <br/> `- "sleep 10"`
`memory_limits` | To set the memory limit for the pod | `512Mi`
`resources` | To set the resource limits for the pod. Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `resources: \|` <br/> &nbsp;  &nbsp; `{{- if eq .Values.appType "java-spring" -}}` <br/> &nbsp;  &nbsp; `requests:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `memory: {{ .Values.memory_limits \| quote }}` <br/> &nbsp;  &nbsp; `limits:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `memory: {{ .Values.memory_limits \| quote }}` <br/> &nbsp;  &nbsp; `{{- end -}}`
`extraEnv.java` | Allows the specification of additional environment variables for Java. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `java: \|` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `- name: SPRING_DATASOURCE_URL` <br/> &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp;  &nbsp; `valueFrom:` <br/> &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `configMapKeyRef:` <br/> &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `name: egov-config` <br/> &nbsp;  &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; `key: db-url` <br/> For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml)
`jaeger` | Jaeger API tracing environment variables to send traces to Jaeger Agent.  Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `jaeger: \|` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; `- name: JAEGER_AGENT_PORT` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp;  &nbsp; `port: 6831` <br/> For more details check [values.yaml](https://github.com/egovernments/DIGIT-DevOps/blob/master/deploy-as-code/helm/charts/common/values.yaml)
`extraVolumes` | To add additional volumes to the service.  Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `extraVolumes: \|` <br/> &nbsp;  &nbsp; `- name: new-volume` <br/> &nbsp;  &nbsp; &nbsp; &nbsp; `configMap:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp;  &nbsp; `name: service-new-volume`
`extraVolumeMounts` | To mount additional volumes to the service in a desired mount path.  Allows the specification of additional environment variables. Passed through the tpl function and thus to be configured a string | `For Eg:` <br/> `extraVolumeMounts: \|` <br/> &nbsp;  &nbsp; `- mountPath: /opt/service-path/file.conf` <br/> &nbsp;  &nbsp; &nbsp; &nbsp; `configMap:` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp;  &nbsp; `name: new-volume` <br/> &nbsp;  &nbsp; &nbsp;  &nbsp; &nbsp;  &nbsp; `subPath: file.conf`
`extraInitContainers` | Additional init containers, e. g. for providing themes, etc. Passed through the `tpl` function and thus to be configured a string | `""`
`extraContainers` | Additional sidecar containers, e. g. for a database proxy, such as Google's cloudsql-proxy. Passed through the `tpl` function and thus to be configured a string | `""`

