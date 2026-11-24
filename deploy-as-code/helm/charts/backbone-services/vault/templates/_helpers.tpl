{{/*
Copyright (c) HashiCorp, Inc.
SPDX-License-Identifier: MPL-2.0
*/}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to
this (by the DNS naming spec). If release name contains chart name it will
be used as a full name.
*/}}
{{- define "vault.fullname" -}}
{{- if .Values.vault.fullnameOverride -}}
{{- .Values.vault.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.vault.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vault.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "vault.name" -}}
{{- default .Chart.Name .Values.vault.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Allow the release namespace to be overridden
*/}}
{{- define "vault.namespace" -}}
{{- default .Release.Namespace .Values.vault.global.namespace -}}
{{- end -}}

{{/*
Compute if the csi driver is enabled.
*/}}
{{- define "vault.csiEnabled" -}}
{{- $_ := set . "csiEnabled" (or
  (eq (.Values.vault.csi.enabled | toString) "true")
  (and (eq (.Values.vault.csi.enabled | toString) "-") (eq (.Values.vault.global.enabled | toString) "true"))) -}}
{{- end -}}

{{/*
Compute if the injector is enabled.
*/}}
{{- define "vault.injectorEnabled" -}}
{{- $_ := set . "injectorEnabled" (or
  (eq (.Values.vault.injector.enabled | toString) "true")
  (and (eq (.Values.vault.injector.enabled | toString) "-") (eq (.Values.vault.global.enabled | toString) "true"))) -}}
{{- end -}}

{{/*
Compute if the server is enabled.
*/}}
{{- define "vault.serverEnabled" -}}
{{- $_ := set . "serverEnabled" (or
  (eq (.Values.vault.server.enabled | toString) "true")
  (and (eq (.Values.vault.server.enabled | toString) "-") (eq (.Values.vault.global.enabled | toString) "true"))) -}}
{{- end -}}

{{/*
Compute if the server serviceaccount is enabled.
*/}}
{{- define "vault.serverServiceAccountEnabled" -}}
{{- $_ := set . "serverServiceAccountEnabled"
  (and
    (eq (.Values.vault.server.serviceAccount.create | toString) "true" )
    (or
      (eq (.Values.vault.server.enabled | toString) "true")
      (eq (.Values.vault.global.enabled | toString) "true"))) -}}
{{- end -}}

{{/*
Compute if the server serviceaccount should have a token created and mounted to the serviceaccount.
*/}}
{{- define "vault.serverServiceAccountSecretCreationEnabled" -}}
{{- $_ := set . "serverServiceAccountSecretCreationEnabled"
  (and
    (eq (.Values.vault.server.serviceAccount.create | toString) "true")
    (eq (.Values.vault.server.serviceAccount.createSecret | toString) "true")) -}}
{{- end -}}


{{/*
Compute if the server auth delegator serviceaccount is enabled.
*/}}
{{- define "vault.serverAuthDelegator" -}}
{{- $_ := set . "serverAuthDelegator"
  (and
    (eq (.Values.vault.server.authDelegator.enabled | toString) "true" )
    (or (eq (.Values.vault.server.serviceAccount.create | toString) "true")
        (not (eq .Values.vault.server.serviceAccount.name "")))
    (or
      (eq (.Values.vault.server.enabled | toString) "true")
      (eq (.Values.vault.global.enabled | toString) "true"))) -}}
{{- end -}}

{{/*
Compute if the server service is enabled.
*/}}
{{- define "vault.serverServiceEnabled" -}}
{{- template "vault.serverEnabled" . -}}
{{- $_ := set . "serverServiceEnabled" (and .serverEnabled (eq (.Values.vault.server.service.enabled | toString) "true")) -}}
{{- end -}}

{{/*
Compute if the ui is enabled.
*/}}
{{- define "vault.uiEnabled" -}}
{{- $_ := set . "uiEnabled" (or
  (eq (.Values.vault.ui.enabled | toString) "true")
  (and (eq (.Values.vault.ui.enabled | toString) "-") (eq (.Values.vault.global.enabled | toString) "true"))) -}}
{{- end -}}

{{/*
Compute the maximum number of unavailable replicas for the PodDisruptionBudget.
This defaults to (n/2)-1 where n is the number of members of the server cluster.
Add a special case for replicas=1, where it should default to 0 as well.
*/}}
{{- define "vault.pdb.maxUnavailable" -}}
{{- if eq (int .Values.vault.server.ha.replicas) 1 -}}
{{ 0 }}
{{- else if .Values.vault.server.ha.disruptionBudget.maxUnavailable -}}
{{ .Values.vault.server.ha.disruptionBudget.maxUnavailable -}}
{{- else -}}
{{- div (sub (div (mul (int .Values.vault.server.ha.replicas) 10) 2) 1) 10 -}}
{{- end -}}
{{- end -}}

{{/*
Set the variable 'mode' to the server mode requested by the user to simplify
template logic.
*/}}
{{- define "vault.mode" -}}
  {{- template "vault.serverEnabled" . -}}
  {{- if or (.Values.vault.injector.externalVaultAddr) (.Values.vault.global.externalVaultAddr) -}}
    {{- $_ := set . "mode" "external" -}}
  {{- else if not .serverEnabled -}}
    {{- $_ := set . "mode" "external" -}}
  {{- else if eq (.Values.vault.server.dev.enabled | toString) "true" -}}
    {{- $_ := set . "mode" "dev" -}}
  {{- else if eq (.Values.vault.server.ha.enabled | toString) "true" -}}
    {{- $_ := set . "mode" "ha" -}}
  {{- else if or (eq (.Values.vault.server.standalone.enabled | toString) "true") (eq (.Values.vault.server.standalone.enabled | toString) "-") -}}
    {{- $_ := set . "mode" "standalone" -}}
  {{- else -}}
    {{- $_ := set . "mode" "" -}}
  {{- end -}}
{{- end -}}

{{/*
Set's the replica count based on the different modes configured by user
*/}}
{{- define "vault.replicas" -}}
  {{ if eq .mode "standalone" }}
    {{- default 1 -}}
  {{ else if eq .mode "ha" }}
    {{- if or (kindIs "int64" .Values.vault.server.ha.replicas) (kindIs "float64" .Values.vault.server.ha.replicas) -}}
      {{- .Values.vault.server.ha.replicas -}}
    {{ else }}
      {{- 3 -}}
    {{- end -}}
  {{ else }}
    {{- default 1 -}}
  {{ end }}
{{- end -}}

{{/*
Set's up configmap mounts if this isn't a dev deployment and the user
defined a custom configuration.  Additionally iterates over any
extra volumes the user may have specified (such as a secret with TLS).
*/}}
{{- define "vault.volumes" -}}
  {{- if and (ne .mode "dev") (or (.Values.vault.server.standalone.config) (.Values.vault.server.ha.config) (.Values.vault.server.ha.raft.config)) }}
        - name: config
          configMap:
            name: {{ template "vault.fullname" . }}-config
  {{ end }}
  {{- range .Values.vault.server.extraVolumes }}
        - name: userconfig-{{ .name }}
          {{ .type }}:
          {{- if (eq .type "configMap") }}
            name: {{ .name }}
          {{- else if (eq .type "secret") }}
            secretName: {{ .name }}
          {{- end }}
            defaultMode: {{ .defaultMode | default 420 }}
  {{- end }}
  {{- if .Values.vault.server.volumes }}
    {{- toYaml .Values.vault.server.volumes | nindent 8}}
  {{- end }}
  {{- if (and .Values.vault.server.enterpriseLicense.secretName .Values.vault.server.enterpriseLicense.secretKey) }}
        - name: vault-license
          secret:
            secretName: {{ .Values.vault.server.enterpriseLicense.secretName }}
            defaultMode: 0440
  {{- end }}
{{- end -}}

{{/*
Set's the args for custom command to render the Vault configuration
file with IP addresses to make the out of box experience easier
for users looking to use this chart with Consul Helm.
*/}}
{{- define "vault.args" -}}
  {{ if or (eq .mode "standalone") (eq .mode "ha") }}
          - |
            cp /vault/config/extraconfig-from-values.hcl /tmp/storageconfig.hcl;
            [ -n "${HOST_IP}" ] && sed -Ei "s|HOST_IP|${HOST_IP?}|g" /tmp/storageconfig.hcl;
            [ -n "${POD_IP}" ] && sed -Ei "s|POD_IP|${POD_IP?}|g" /tmp/storageconfig.hcl;
            [ -n "${HOSTNAME}" ] && sed -Ei "s|HOSTNAME|${HOSTNAME?}|g" /tmp/storageconfig.hcl;
            [ -n "${API_ADDR}" ] && sed -Ei "s|API_ADDR|${API_ADDR?}|g" /tmp/storageconfig.hcl;
            [ -n "${TRANSIT_ADDR}" ] && sed -Ei "s|TRANSIT_ADDR|${TRANSIT_ADDR?}|g" /tmp/storageconfig.hcl;
            [ -n "${RAFT_ADDR}" ] && sed -Ei "s|RAFT_ADDR|${RAFT_ADDR?}|g" /tmp/storageconfig.hcl;
            /usr/local/bin/docker-entrypoint.sh vault server -config=/tmp/storageconfig.hcl {{ .Values.vault.server.extraArgs }}
   {{ else if eq .mode "dev" }}
          - |
            /usr/local/bin/docker-entrypoint.sh vault server -dev {{ .Values.vault.server.extraArgs }}
  {{ end }}
{{- end -}}

{{/*
Set's additional environment variables based on the mode.
*/}}
{{- define "vault.envs" -}}
  {{ if eq .mode "dev" }}
            - name: VAULT_DEV_ROOT_TOKEN_ID
              value: {{ .Values.vault.server.dev.devRootToken }}
            - name: VAULT_DEV_LISTEN_ADDRESS
              value: "[::]:8200"
  {{ end }}
{{- end -}}

{{/*
Set's which additional volumes should be mounted to the container
based on the mode configured.
*/}}
{{- define "vault.mounts" -}}
  {{ if eq (.Values.vault.server.auditStorage.enabled | toString) "true" }}
            - name: audit
              mountPath: {{ .Values.vault.server.auditStorage.mountPath }}
  {{ end }}
  {{ if or (eq .mode "standalone") (and (eq .mode "ha") (eq (.Values.vault.server.ha.raft.enabled | toString) "true"))  }}
    {{ if eq (.Values.vault.server.dataStorage.enabled | toString) "true" }}
            - name: data
              mountPath: {{ .Values.vault.server.dataStorage.mountPath }}
    {{ end }}
  {{ end }}
  {{ if and (ne .mode "dev") (or (.Values.vault.server.standalone.config)  (.Values.vault.server.ha.config)) }}
            - name: config
              mountPath: /vault/config
  {{ end }}
  {{- range .Values.vault.server.extraVolumes }}
            - name: userconfig-{{ .name }}
              readOnly: true
              mountPath: {{ .path | default "/vault/userconfig" }}/{{ .name }}
  {{- end }}
  {{- if .Values.vault.server.volumeMounts }}
    {{- toYaml .Values.vault.server.volumeMounts | nindent 12}}
  {{- end }}
  {{- if (and .Values.vault.server.enterpriseLicense.secretName .Values.vault.server.enterpriseLicense.secretKey) }}
            - name: vault-license
              mountPath: /vault/license
              readOnly: true
  {{- end }}
{{- end -}}

{{/*
Set's up the volumeClaimTemplates when data or audit storage is required.  HA
might not use data storage since Consul is likely it's backend, however, audit
storage might be desired by the user.
*/}}
{{- define "vault.volumeclaims" -}}
  {{- if and (ne .mode "dev") (or .Values.vault.server.dataStorage.enabled .Values.vault.server.auditStorage.enabled) }}
  volumeClaimTemplates:
      {{- if and (eq (.Values.vault.server.dataStorage.enabled | toString) "true") (or (eq .mode "standalone") (eq (.Values.vault.server.ha.raft.enabled | toString ) "true" )) }}
    - metadata:
        name: data
        {{- include "vault.dataVolumeClaim.annotations" . | nindent 6 }}
        {{- include "vault.dataVolumeClaim.labels" . | nindent 6 }}
      spec:
        accessModes:
          - {{ .Values.vault.server.dataStorage.accessMode | default "ReadWriteOnce" }}
        resources:
          requests:
            storage: {{ .Values.vault.server.dataStorage.size }}
          {{- if .Values.vault.server.dataStorage.storageClass }}
        storageClassName: {{ .Values.vault.server.dataStorage.storageClass }}
          {{- end }}
      {{ end }}
      {{- if eq (.Values.vault.server.auditStorage.enabled | toString) "true" }}
    - metadata:
        name: audit
        {{- include "vault.auditVolumeClaim.annotations" . | nindent 6 }}
        {{- include "vault.auditVolumeClaim.labels" . | nindent 6 }}
      spec:
        accessModes:
          - {{ .Values.vault.server.auditStorage.accessMode | default "ReadWriteOnce" }}
        resources:
          requests:
            storage: {{ .Values.vault.server.auditStorage.size }}
          {{- if .Values.vault.server.auditStorage.storageClass }}
        storageClassName: {{ .Values.vault.server.auditStorage.storageClass }}
          {{- end }}
      {{ end }}
  {{ end }}
{{- end -}}

{{/*
Set's the affinity for pod placement when running in standalone and HA modes.
*/}}
{{- define "vault.affinity" -}}
  {{- if and (ne .mode "dev") .Values.vault.server.affinity }}
      affinity:
        {{ $tp := typeOf .Values.vault.server.affinity }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.server.affinity . | nindent 8 | trim }}
        {{- else }}
          {{- toYaml .Values.vault.server.affinity | nindent 8 }}
        {{- end }}
  {{ end }}
{{- end -}}

{{/*
Sets the injector affinity for pod placement
*/}}
{{- define "injector.affinity" -}}
  {{- if .Values.vault.injector.affinity }}
      affinity:
        {{ $tp := typeOf .Values.vault.injector.affinity }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.injector.affinity . | nindent 8 | trim }}
        {{- else }}
          {{- toYaml .Values.vault.injector.affinity | nindent 8 }}
        {{- end }}
  {{ end }}
{{- end -}}

{{/*
Sets the topologySpreadConstraints when running in standalone and HA modes.
*/}}
{{- define "vault.topologySpreadConstraints" -}}
  {{- if and (ne .mode "dev") .Values.vault.server.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{ $tp := typeOf .Values.vault.server.topologySpreadConstraints }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.server.topologySpreadConstraints . | nindent 8 | trim }}
        {{- else }}
          {{- toYaml .Values.vault.server.topologySpreadConstraints | nindent 8 }}
        {{- end }}
  {{ end }}
{{- end -}}


{{/*
Sets the injector topologySpreadConstraints for pod placement
*/}}
{{- define "injector.topologySpreadConstraints" -}}
  {{- if .Values.vault.injector.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{ $tp := typeOf .Values.vault.injector.topologySpreadConstraints }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.injector.topologySpreadConstraints . | nindent 8 | trim }}
        {{- else }}
          {{- toYaml .Values.vault.injector.topologySpreadConstraints | nindent 8 }}
        {{- end }}
  {{ end }}
{{- end -}}

{{/*
Sets the toleration for pod placement when running in standalone and HA modes.
*/}}
{{- define "vault.tolerations" -}}
  {{- if and (ne .mode "dev") .Values.vault.server.tolerations }}
      tolerations:
      {{- $tp := typeOf .Values.vault.server.tolerations }}
      {{- if eq $tp "string" }}
        {{ tpl .Values.vault.server.tolerations . | nindent 8 | trim }}
      {{- else }}
        {{- toYaml .Values.vault.server.tolerations | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets the injector toleration for pod placement
*/}}
{{- define "injector.tolerations" -}}
  {{- if .Values.vault.injector.tolerations }}
      tolerations:
      {{- $tp := typeOf .Values.vault.injector.tolerations }}
      {{- if eq $tp "string" }}
        {{ tpl .Values.vault.injector.tolerations . | nindent 8 | trim }}
      {{- else }}
        {{- toYaml .Values.vault.injector.tolerations | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}

{{/*
Set's the node selector for pod placement when running in standalone and HA modes.
*/}}
{{- define "vault.nodeselector" -}}
  {{- if and (ne .mode "dev") .Values.vault.server.nodeSelector }}
      nodeSelector:
      {{- $tp := typeOf .Values.vault.server.nodeSelector }}
      {{- if eq $tp "string" }}
        {{ tpl .Values.vault.server.nodeSelector . | nindent 8 | trim }}
      {{- else }}
        {{- toYaml .Values.vault.server.nodeSelector | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets the injector node selector for pod placement
*/}}
{{- define "injector.nodeselector" -}}
  {{- if .Values.vault.injector.nodeSelector }}
      nodeSelector:
      {{- $tp := typeOf .Values.vault.injector.nodeSelector }}
      {{- if eq $tp "string" }}
        {{ tpl .Values.vault.injector.nodeSelector . | nindent 8 | trim }}
      {{- else }}
        {{- toYaml .Values.vault.injector.nodeSelector | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets the injector deployment update strategy
*/}}
{{- define "injector.strategy" -}}
  {{- if .Values.vault.injector.strategy }}
  strategy:
  {{- $tp := typeOf .Values.vault.injector.strategy }}
  {{- if eq $tp "string" }}
    {{ tpl .Values.vault.injector.strategy . | nindent 4 | trim }}
  {{- else }}
    {{- toYaml .Values.vault.injector.strategy | nindent 4 }}
  {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra pod annotations
*/}}
{{- define "vault.annotations" }}
      annotations:
  {{- if .Values.vault.server.includeConfigAnnotation }}
        vault.hashicorp.com/config-checksum: {{ include "vault.config" . | sha256sum }}
  {{- end }}
  {{- if .Values.vault.server.annotations }}
        {{- $tp := typeOf .Values.vault.server.annotations }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.server.annotations . | nindent 8 }}
        {{- else }}
          {{- toYaml .Values.vault.server.annotations | nindent 8 }}
        {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra injector pod annotations
*/}}
{{- define "injector.annotations" -}}
  {{- if .Values.vault.injector.annotations }}
      annotations:
        {{- $tp := typeOf .Values.vault.injector.annotations }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.injector.annotations . | nindent 8 }}
        {{- else }}
          {{- toYaml .Values.vault.injector.annotations | nindent 8 }}
        {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra injector service annotations
*/}}
{{- define "injector.service.annotations" -}}
  {{- if .Values.vault.injector.service.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.injector.service.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.injector.service.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.injector.service.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
securityContext for the injector pod level.
*/}}
{{- define "injector.securityContext.pod" -}}
  {{- if .Values.vault.injector.securityContext.pod }}
      securityContext:
        {{- $tp := typeOf .Values.vault.injector.securityContext.pod }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.injector.securityContext.pod . | nindent 8 }}
        {{- else }}
          {{- toYaml .Values.vault.injector.securityContext.pod | nindent 8 }}
        {{- end }}
  {{- else if not .Values.vault.global.openshift }}
      securityContext:
        runAsNonRoot: true
        runAsGroup: {{ .Values.vault.injector.gid | default 1000 }}
        runAsUser: {{ .Values.vault.injector.uid | default 100 }}
        fsGroup: {{ .Values.vault.injector.gid | default 1000 }}
  {{- end }}
{{- end -}}

{{/*
securityContext for the injector container level.
*/}}
{{- define "injector.securityContext.container" -}}
  {{- if .Values.vault.injector.securityContext.container}}
          securityContext:
            {{- $tp := typeOf .Values.vault.injector.securityContext.container }}
            {{- if eq $tp "string" }}
              {{- tpl .Values.vault.injector.securityContext.container . | nindent 12 }}
            {{- else }}
              {{- toYaml .Values.vault.injector.securityContext.container | nindent 12 }}
            {{- end }}
  {{- else if not .Values.vault.global.openshift }}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
  {{- end }}
{{- end -}}

{{/*
securityContext for the statefulset pod template.
*/}}
{{- define "server.statefulSet.securityContext.pod" -}}
  {{- if .Values.vault.server.statefulSet.securityContext.pod }}
      securityContext:
        {{- $tp := typeOf .Values.vault.server.statefulSet.securityContext.pod }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.server.statefulSet.securityContext.pod . | nindent 8 }}
        {{- else }}
          {{- toYaml .Values.vault.server.statefulSet.securityContext.pod | nindent 8 }}
        {{- end }}
  {{- else if not .Values.vault.global.openshift }}
      securityContext:
        runAsNonRoot: true
        runAsGroup: {{ .Values.vault.server.gid | default 1000 }}
        runAsUser: {{ .Values.vault.server.uid | default 100 }}
        fsGroup: {{ .Values.vault.server.gid | default 1000 }}
  {{- end }}
{{- end -}}

{{/*
securityContext for the statefulset vault container
*/}}
{{- define "server.statefulSet.securityContext.container" -}}
  {{- if .Values.vault.server.statefulSet.securityContext.container }}
          securityContext:
            {{- $tp := typeOf .Values.vault.server.statefulSet.securityContext.container }}
            {{- if eq $tp "string" }}
              {{- tpl .Values.vault.server.statefulSet.securityContext.container . | nindent 12 }}
            {{- else }}
              {{- toYaml .Values.vault.server.statefulSet.securityContext.container | nindent 12 }}
            {{- end }}
  {{- else if not .Values.vault.global.openshift }}
          securityContext:
            allowPrivilegeEscalation: false
  {{- end }}
{{- end -}}


{{/*
Sets extra injector service account annotations
*/}}
{{- define "injector.serviceAccount.annotations" -}}
  {{- if and (ne .mode "dev") .Values.vault.injector.serviceAccount.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.injector.serviceAccount.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.injector.serviceAccount.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.injector.serviceAccount.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra injector webhook annotations
*/}}
{{- define "injector.webhookAnnotations" -}}
  {{- if or (((.Values.vault.injector.webhook)).annotations) (.Values.vault.injector.webhookAnnotations)  }}
  annotations:
    {{- $tp := typeOf (or (((.Values.vault.injector.webhook)).annotations) (.Values.vault.injector.webhookAnnotations)) }}
    {{- if eq $tp "string" }}
      {{- tpl (((.Values.vault.injector.webhook)).annotations | default .Values.vault.injector.webhookAnnotations) . | nindent 4 }}
    {{- else }}
      {{- toYaml (((.Values.vault.injector.webhook)).annotations | default .Values.vault.injector.webhookAnnotations) | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Set's the injector webhook objectSelector
*/}}
{{- define "injector.objectSelector" -}}
  {{- $v := or (((.Values.vault.injector.webhook)).objectSelector) (.Values.vault.injector.objectSelector) -}}
  {{ if $v }}
    objectSelector:
    {{- $tp := typeOf $v -}}
    {{ if eq $tp "string" }}
      {{ tpl $v . | indent 6 | trim }}
    {{ else }}
      {{ toYaml $v | indent 6 | trim }}
    {{ end }}
  {{ end }}
{{ end }}

{{/*
Sets extra ui service annotations
*/}}
{{- define "vault.ui.annotations" -}}
  {{- if .Values.vault.ui.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.ui.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.ui.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.ui.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "vault.serviceAccount.name" -}}
{{- if .Values.vault.server.serviceAccount.create -}}
    {{ default (include "vault.fullname" .) .Values.vault.server.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.vault.server.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Sets extra service account annotations
*/}}
{{- define "vault.serviceAccount.annotations" -}}
  {{- if and (ne .mode "dev") .Values.vault.server.serviceAccount.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.server.serviceAccount.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.serviceAccount.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.serviceAccount.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra ingress annotations
*/}}
{{- define "vault.ingress.annotations" -}}
  {{- if .Values.vault.server.ingress.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.server.ingress.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.ingress.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.ingress.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra route annotations
*/}}
{{- define "vault.route.annotations" -}}
  {{- if .Values.vault.server.route.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.server.route.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.route.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.route.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra vault server Service annotations
*/}}
{{- define "vault.service.annotations" -}}
  {{- if .Values.vault.server.service.annotations }}
    {{- $tp := typeOf .Values.vault.server.service.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.service.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.service.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra vault server Service (active) annotations
*/}}
{{- define "vault.service.active.annotations" -}}
  {{- if .Values.vault.server.service.active.annotations }}
    {{- $tp := typeOf .Values.vault.server.service.active.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.service.active.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.service.active.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}
{{/*
Sets extra vault server Service annotations
*/}}
{{- define "vault.service.standby.annotations" -}}
  {{- if .Values.vault.server.service.standby.annotations }}
    {{- $tp := typeOf .Values.vault.server.service.standby.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.service.standby.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.service.standby.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets PodSecurityPolicy annotations
*/}}
{{- define "vault.psp.annotations" -}}
  {{- if .Values.vault.global.psp.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.global.psp.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.global.psp.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.global.psp.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra statefulset annotations
*/}}
{{- define "vault.statefulSet.annotations" -}}
  {{- if .Values.vault.server.statefulSet.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.server.statefulSet.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.statefulSet.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.statefulSet.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets VolumeClaim annotations for data volume
*/}}
{{- define "vault.dataVolumeClaim.annotations" -}}
  {{- if and (ne .mode "dev") (.Values.vault.server.dataStorage.enabled) (.Values.vault.server.dataStorage.annotations) }}
  annotations:
    {{- $tp := typeOf .Values.vault.server.dataStorage.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.dataStorage.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.dataStorage.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets VolumeClaim labels for data volume
*/}}
{{- define "vault.dataVolumeClaim.labels" -}}
  {{- if and (ne .mode "dev") (.Values.vault.server.dataStorage.enabled) (.Values.vault.server.dataStorage.labels) }}
  labels:
    {{- $tp := typeOf .Values.vault.server.dataStorage.labels }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.dataStorage.labels . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.dataStorage.labels | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets VolumeClaim annotations for audit volume
*/}}
{{- define "vault.auditVolumeClaim.annotations" -}}
  {{- if and (ne .mode "dev") (.Values.vault.server.auditStorage.enabled) (.Values.vault.server.auditStorage.annotations) }}
  annotations:
    {{- $tp := typeOf .Values.vault.server.auditStorage.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.auditStorage.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.auditStorage.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets VolumeClaim labels for audit volume
*/}}
{{- define "vault.auditVolumeClaim.labels" -}}
  {{- if and (ne .mode "dev") (.Values.vault.server.auditStorage.enabled) (.Values.vault.server.auditStorage.labels) }}
  labels:
    {{- $tp := typeOf .Values.vault.server.auditStorage.labels }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.server.auditStorage.labels . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.server.auditStorage.labels | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Set's the container resources if the user has set any.
*/}}
{{- define "vault.resources" -}}
  {{- if .Values.vault.server.resources -}}
          resources:
{{ toYaml .Values.vault.server.resources | indent 12}}
  {{ end }}
{{- end -}}

{{/*
Sets the container resources if the user has set any.
*/}}
{{- define "injector.resources" -}}
  {{- if .Values.vault.injector.resources -}}
          resources:
{{ toYaml .Values.vault.injector.resources | indent 12}}
  {{ end }}
{{- end -}}

{{/*
Sets the container resources if the user has set any.
*/}}
{{- define "csi.resources" -}}
  {{- if .Values.vault.csi.resources -}}
          resources:
{{ toYaml .Values.vault.csi.resources | indent 12}}
  {{ end }}
{{- end -}}

{{/*
Sets the container resources for CSI's Agent sidecar if the user has set any.
*/}}
{{- define "csi.agent.resources" -}}
  {{- if .Values.vault.csi.agent.resources -}}
          resources:
{{ toYaml .Values.vault.csi.agent.resources | indent 12}}
  {{ end }}
{{- end -}}

{{/*
Sets extra CSI daemonset annotations
*/}}
{{- define "csi.daemonSet.annotations" -}}
  {{- if .Values.vault.csi.daemonSet.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.csi.daemonSet.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.csi.daemonSet.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.csi.daemonSet.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets CSI daemonset securityContext for pod template
*/}}
{{- define "csi.daemonSet.securityContext.pod" -}}
  {{- if .Values.vault.csi.daemonSet.securityContext.pod }}
      securityContext:
    {{- $tp := typeOf .Values.vault.csi.daemonSet.securityContext.pod }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.csi.daemonSet.securityContext.pod . | nindent 8 }}
    {{- else }}
      {{- toYaml .Values.vault.csi.daemonSet.securityContext.pod | nindent 8 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets CSI daemonset securityContext for container
*/}}
{{- define "csi.daemonSet.securityContext.container" -}}
  {{- if .Values.vault.csi.daemonSet.securityContext.container }}
          securityContext:
    {{- $tp := typeOf .Values.vault.csi.daemonSet.securityContext.container }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.csi.daemonSet.securityContext.container . | nindent 12 }}
    {{- else }}
      {{- toYaml .Values.vault.csi.daemonSet.securityContext.container | nindent 12 }}
    {{- end }}
  {{- end }}
{{- end -}}


{{/*
Sets the injector toleration for pod placement
*/}}
{{- define "csi.pod.tolerations" -}}
  {{- if .Values.vault.csi.pod.tolerations }}
      tolerations:
      {{- $tp := typeOf .Values.vault.csi.pod.tolerations }}
      {{- if eq $tp "string" }}
        {{ tpl .Values.vault.csi.pod.tolerations . | nindent 8 | trim }}
      {{- else }}
        {{- toYaml .Values.vault.csi.pod.tolerations | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets the CSI provider nodeSelector for pod placement
*/}}
{{- define "csi.pod.nodeselector" -}}
  {{- if .Values.vault.csi.pod.nodeSelector }}
      nodeSelector:
      {{- $tp := typeOf .Values.vault.csi.pod.nodeSelector }}
      {{- if eq $tp "string" }}
        {{ tpl .Values.vault.csi.pod.nodeSelector . | nindent 8 | trim }}
      {{- else }}
        {{- toYaml .Values.vault.csi.pod.nodeSelector | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}
{{/*
Sets the CSI provider affinity for pod placement.
*/}}
{{- define "csi.pod.affinity" -}}
  {{- if .Values.vault.csi.pod.affinity }}
      affinity:
        {{ $tp := typeOf .Values.vault.csi.pod.affinity }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.vault.csi.pod.affinity . | nindent 8 | trim }}
        {{- else }}
          {{- toYaml .Values.vault.csi.pod.affinity | nindent 8 }}
        {{- end }}
  {{ end }}
{{- end -}}
{{/*
Sets extra CSI provider pod annotations
*/}}
{{- define "csi.pod.annotations" -}}
  {{- if .Values.vault.csi.pod.annotations }}
      annotations:
      {{- $tp := typeOf .Values.vault.csi.pod.annotations }}
      {{- if eq $tp "string" }}
        {{- tpl .Values.vault.csi.pod.annotations . | nindent 8 }}
      {{- else }}
        {{- toYaml .Values.vault.csi.pod.annotations | nindent 8 }}
      {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra CSI service account annotations
*/}}
{{- define "csi.serviceAccount.annotations" -}}
  {{- if .Values.vault.csi.serviceAccount.annotations }}
  annotations:
    {{- $tp := typeOf .Values.vault.csi.serviceAccount.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.vault.csi.serviceAccount.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.vault.csi.serviceAccount.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Inject extra environment vars in the format key:value, if populated
*/}}
{{- define "vault.extraEnvironmentVars" -}}
{{- if .extraEnvironmentVars -}}
{{- range $key, $value := .extraEnvironmentVars }}
- name: {{ printf "%s" $key | replace "." "_" | upper | quote }}
  value: {{ $value | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Inject extra environment populated by secrets, if populated
*/}}
{{- define "vault.extraSecretEnvironmentVars" -}}
{{- if .extraSecretEnvironmentVars -}}
{{- range .extraSecretEnvironmentVars }}
- name: {{ .envName }}
  valueFrom:
   secretKeyRef:
     name: {{ .secretName }}
     key: {{ .secretKey }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Scheme for health check and local endpoint */}}
{{- define "vault.scheme" -}}
{{- if .Values.vault.global.tlsDisable -}}
{{ "http" }}
{{- else -}}
{{ "https" }}
{{- end -}}
{{- end -}}

{{/*
imagePullSecrets generates pull secrets from either string or map values.
A map value must be indexable by the key 'name'.
*/}}
{{- define "imagePullSecrets" -}}
{{- with .Values.vault.global.imagePullSecrets -}}
imagePullSecrets:
{{- range . -}}
{{- if typeIs "string" . }}
  - name: {{ . }}
{{- else if index . "name" }}
  - name: {{ .name }}
{{- end }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
externalTrafficPolicy sets a Service's externalTrafficPolicy if applicable.
Supported inputs are Values.server.service and Values.ui
*/}}
{{- define "service.externalTrafficPolicy" -}}
{{- $type := "" -}}
{{- if .serviceType -}}
{{- $type = .serviceType -}}
{{- else if .type -}}
{{- $type = .type -}}
{{- end -}}
{{- if and .externalTrafficPolicy (or (eq $type "LoadBalancer") (eq $type "NodePort")) }}
  externalTrafficPolicy: {{ .externalTrafficPolicy }}
{{- else }}
{{- end }}
{{- end -}}

{{/*
loadBalancer configuration for the the UI service.
Supported inputs are Values.ui
*/}}
{{- define "service.loadBalancer" -}}
{{- if  eq (.serviceType | toString) "LoadBalancer" }}
{{- if .loadBalancerIP }}
  loadBalancerIP: {{ .loadBalancerIP }}
{{- end }}
{{- with .loadBalancerSourceRanges }}
  loadBalancerSourceRanges:
{{- range . }}
  - {{ . }}
{{- end }}
{{- end -}}
{{- end }}
{{- end -}}

{{/*
config file from values
*/}}
{{- define "vault.config" -}}
{{- if or (eq .mode "ha") (eq .mode "standalone") }}
{{- $config := (index .Values.vault.server .mode).config -}}
{{- if .Values.vault.server.ha.raft.enabled -}}
{{- $config = .Values.vault.server.ha.raft.config -}}
{{- end -}}
{{- $type := typeOf $config -}}
{{- if eq $type "string" -}}
{{/* Vault supports both HCL and JSON as its configuration format */}}
{{- $json := tpl $config . | fromJson -}}
{{/*
Helm's fromJson does not behave according to the corresponding sprig function nor Helm docs,
which claim that it should return empty string on invalid JSON, it actually returns
a map containing a single 'Error' element.
https://github.com/helm/helm/blob/50c22ed7f953fadb32755e5881ba95a92da852b2/pkg/engine/funcs.go#L158
 */}}
{{- if or (and (eq ($json | len) 1) (hasKey $json "Error")) (eq ($json | len) 0) -}}
{{- $config = printf "%s\n%s" $config "disable_mlock = true" -}}
{{- else -}}
{{- if not (hasKey $json "disable_mlock") -}}
{{- $_ := set $json "disable_mlock" true -}}
{{- end -}}
{{- $config = $json | mustToJson -}}
{{- end -}}
{{- else }}
{{- fail "structured server config is not supported, value must be a string"}}
{{- end }}
{{- tpl $config . | nindent 4 | trim }}
{{- end -}}
{{- end -}}
