{{/* vim: set filetype=mustache: */}}

{{/* Chart name */}}
{{- define "temporal.name" -}}
temporal
{{- end -}}

{{/* Namespace */}}
{{- define "temporal.namespace" -}}
{{- .Values.temporal.namespace -}}
{{- end -}}

{{/* Common labels */}}
{{- define "temporal.labels" -}}
app: {{ .Values.temporal.labels.app }}
{{- if .Values.temporal.labels.group }}
group: {{ .Values.temporal.labels.group }}
{{- end }}
{{- end -}}

{{/* Per-component selector labels. Pass (list $ "<role>"). */}}
{{- define "temporal.selectorLabels" -}}
{{- $root := index . 0 -}}
{{- $component := index . 1 -}}
app: {{ $root.Values.temporal.labels.app }}
component: {{ $component }}
{{- end -}}

{{/*
Shared environment for every temporal-server (split) container.
Uses the env-var contract baked into the temporalio/server image's
config_template.yaml. Per-role SERVICES is added by the deployment template.
Host comes from a ConfigMap, credentials from Secrets (reused from cluster-configs).
*/}}
{{- define "temporal.serverEnv" -}}
{{- $t := .Values.temporal -}}
{{- $pg := $t.persistence.postgres -}}
{{- $es := $t.elasticsearch -}}
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
# Bind on all interfaces; the image entrypoint broadcasts the pod IP.
- name: BIND_ON_IP
  value: "0.0.0.0"
- name: TEMPORAL_BROADCAST_ADDRESS
  value: "$(POD_IP)"
- name: NUM_HISTORY_SHARDS
  value: {{ $t.numHistoryShards | quote }}
{{- if $t.server.versionCheckDisabled }}
- name: TEMPORAL_VERSION_CHECK_DISABLED
  value: "1"
{{- end }}
# ---- Default store: PostgreSQL ----
- name: DB
  value: {{ $pg.driver | quote }}
- name: POSTGRES_SEEDS
  valueFrom:
    configMapKeyRef:
      name: {{ $pg.hostConfigMap.name }}
      key: {{ $pg.hostConfigMap.key }}
- name: DB_PORT
  value: {{ $pg.port | quote }}
- name: DBNAME
  value: {{ $pg.database | quote }}
- name: VISIBILITY_DBNAME
  value: {{ $pg.database | quote }}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ $pg.credentialsSecret.name }}
      key: {{ $pg.credentialsSecret.userKey }}
- name: POSTGRES_PWD
  valueFrom:
    secretKeyRef:
      name: {{ $pg.credentialsSecret.name }}
      key: {{ $pg.credentialsSecret.passwordKey }}
- name: SQL_TLS_ENABLED
  value: {{ $pg.tls.enabled | quote }}
- name: SQL_HOST_VERIFICATION
  value: {{ not $pg.tls.disableHostVerification | quote }}
# ---- Visibility store: Elasticsearch ----
- name: ENABLE_ES
  value: {{ $es.enabled | quote }}
{{- if $es.enabled }}
- name: ES_SCHEME
  value: {{ $es.scheme | quote }}
- name: ES_SEEDS
  value: {{ $es.host | quote }}
- name: ES_PORT
  value: {{ $es.port | quote }}
- name: ES_VERSION
  value: {{ $es.version | quote }}
- name: ES_VIS_INDEX
  value: {{ $es.visibilityIndex | quote }}
{{- if $es.auth.enabled }}
- name: ES_USER
  valueFrom:
    secretKeyRef:
      name: {{ $es.auth.credentialsSecret.name }}
      key: {{ $es.auth.credentialsSecret.userKey }}
- name: ES_PWD
  valueFrom:
    secretKeyRef:
      name: {{ $es.auth.credentialsSecret.name }}
      key: {{ $es.auth.credentialsSecret.passwordKey }}
{{- end }}
{{- end }}
{{- end -}}

{{/* Environment for `temporal-sql-tool` (postgres schema setup). */}}
{{- define "temporal.sqlToolEnv" -}}
{{- $pg := .Values.temporal.persistence.postgres -}}
- name: SQL_PLUGIN
  value: {{ $pg.driver | quote }}
- name: SQL_HOST
  valueFrom:
    configMapKeyRef:
      name: {{ $pg.hostConfigMap.name }}
      key: {{ $pg.hostConfigMap.key }}
- name: SQL_PORT
  value: {{ $pg.port | quote }}
- name: SQL_DATABASE
  value: {{ $pg.database | quote }}
- name: SQL_USER
  valueFrom:
    secretKeyRef:
      name: {{ $pg.credentialsSecret.name }}
      key: {{ $pg.credentialsSecret.userKey }}
- name: SQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $pg.credentialsSecret.name }}
      key: {{ $pg.credentialsSecret.passwordKey }}
- name: SQL_TLS
  value: {{ $pg.tls.enabled | quote }}
- name: SQL_TLS_DISABLE_HOST_VERIFICATION
  value: {{ $pg.tls.disableHostVerification | quote }}
{{- end -}}

{{/*
Environment for `temporal-elasticsearch-tool` (visibility index setup).
ES_SERVER is composed at runtime in the container shell because the host is
injected from a ConfigMap.
*/}}
{{- define "temporal.esToolEnv" -}}
{{- $es := .Values.temporal.elasticsearch -}}
- name: ES_SCHEME
  value: {{ $es.scheme | quote }}
- name: ES_HOST
  value: {{ $es.host | quote }}
- name: ES_PORT
  value: {{ $es.port | quote }}
- name: ES_VERSION
  value: {{ $es.version | quote }}
- name: ES_VISIBILITY_INDEX
  value: {{ $es.visibilityIndex | quote }}
{{- if $es.auth.enabled }}
- name: ES_USER
  valueFrom:
    secretKeyRef:
      name: {{ $es.auth.credentialsSecret.name }}
      key: {{ $es.auth.credentialsSecret.userKey }}
- name: ES_PWD
  valueFrom:
    secretKeyRef:
      name: {{ $es.auth.credentialsSecret.name }}
      key: {{ $es.auth.credentialsSecret.passwordKey }}
{{- end }}
{{- end -}}
