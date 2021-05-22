{{/* vim: set filetype=mustache: */}}
{{- define "name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}


{{/*
Set the variable 'mode' to the server mode requested by the user to simplify
template logic.
*/}}
{{- define "vault.mode" -}}
  {{- if .Values.injector.externalVaultAddr -}}
    {{- $_ := set . "mode" "external" -}}
  {{- else if ne (.Values.server.enabled | toString) "true" -}}
    {{- $_ := set . "mode" "external" -}}
  {{- else if eq (.Values.server.dev.enabled | toString) "true" -}}
    {{- $_ := set . "mode" "dev" -}}
  {{- else if eq (.Values.server.ha.enabled | toString) "true" -}}
    {{- $_ := set . "mode" "ha" -}}
  {{- else if or (eq (.Values.server.standalone.enabled | toString) "true") (eq (.Values.server.standalone.enabled | toString) "-") -}}
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
    {{- .Values.server.ha.replicas | default 3 -}}
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
  {{- if and (ne .mode "dev") (or (.Values.server.standalone.config) (.Values.server.ha.config)) }}
        - name: config
          configMap:
            name: {{ template "name" . }}-config
  {{ end }}
  {{- range .Values.server.extraVolumes }}
        - name: userconfig-{{ .name }}
          {{ .type }}:
          {{- if (eq .type "configMap") }}
            name: {{ .name }}
          {{- else if (eq .type "secret") }}
            secretName: {{ .name }}
          {{- end }}
            defaultMode: {{ .defaultMode | default 420 }}
  {{- end }}
  {{- if .Values.server.volumes }}
    {{- toYaml .Values.server.volumes | nindent 8}}
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
            /usr/local/bin/docker-entrypoint.sh vault server -config=/tmp/storageconfig.hcl {{ .Values.server.extraArgs }}
   {{ else if eq .mode "dev" }}
          - |
            /usr/local/bin/docker-entrypoint.sh vault server -dev {{ .Values.server.extraArgs }}
  {{ end }}
{{- end -}}

{{/*
Set's additional environment variables based on the mode.
*/}}
{{- define "vault.envs" -}}
  {{ if eq .mode "dev" }}
            - name: VAULT_DEV_ROOT_TOKEN_ID
              value: {{ .Values.server.dev.devRootToken }}
            - name: VAULT_DEV_LISTEN_ADDRESS
              value: "[::]:8200"
  {{ end }}
{{- end -}}

{{/*
Set's which additional volumes should be mounted to the container
based on the mode configured.
*/}}
{{- define "vault.mounts" -}}
  {{ if eq (.Values.server.auditStorage.enabled | toString) "true" }}
            - name: audit
              mountPath: {{ .Values.server.auditStorage.mountPath }}
  {{ end }}
  {{ if or (eq .mode "standalone") (and (eq .mode "ha") (eq (.Values.server.ha.raft.enabled | toString) "true"))  }}
    {{ if eq (.Values.server.dataStorage.enabled | toString) "true" }}
            - name: data
              mountPath: {{ .Values.server.dataStorage.mountPath }}
    {{ end }}
  {{ end }}
  {{ if and (ne .mode "dev") (or (.Values.server.standalone.config)  (.Values.server.ha.config)) }}
            - name: config
              mountPath: /vault/config
  {{ end }}
  {{- range .Values.server.extraVolumes }}
            - name: userconfig-{{ .name }}
              readOnly: true
              mountPath: {{ .path | default "/vault/userconfig" }}/{{ .name }}
  {{- end }}
  {{- if .Values.server.volumeMounts }}
    {{- toYaml .Values.server.volumeMounts | nindent 12}}
  {{- end }}
{{- end -}}

{{/*
Set's up the volumeClaimTemplates when data or audit storage is required.  HA
might not use data storage since Consul is likely it's backend, however, audit
storage might be desired by the user.
*/}}
{{- define "vault.volumeclaims" -}}
  {{- if and (ne .mode "dev") (or .Values.server.dataStorage.enabled .Values.server.auditStorage.enabled) }}
  volumeClaimTemplates:
      {{- if and (eq (.Values.server.dataStorage.enabled | toString) "true") (or (eq .mode "standalone") (eq (.Values.server.ha.raft.enabled | toString ) "true" )) }}
    - metadata:
        name: data
        {{- include "vault.dataVolumeClaim.annotations" . | nindent 6 }}
      spec:
        accessModes:
          - {{ .Values.server.dataStorage.accessMode | default "ReadWriteOnce" }}
        resources:
          requests:
            storage: {{ .Values.server.dataStorage.size }}
          {{- if .Values.server.dataStorage.storageClass }}
        storageClassName: {{ .Values.server.dataStorage.storageClass }}
          {{- end }}
      {{ end }}
      {{- if eq (.Values.server.auditStorage.enabled | toString) "true" }}
    - metadata:
        name: audit
        {{- include "vault.auditVolumeClaim.annotations" . | nindent 6 }}
      spec:
        accessModes:
          - {{ .Values.server.auditStorage.accessMode | default "ReadWriteOnce" }}
        resources:
          requests:
            storage: {{ .Values.server.auditStorage.size }}
          {{- if .Values.server.auditStorage.storageClass }}
        storageClassName: {{ .Values.server.auditStorage.storageClass }}
          {{- end }}
      {{ end }}
  {{ end }}
{{- end -}}

{{/*
Set's the affinity for pod placement when running in standalone and HA modes.
*/}}
{{- define "vault.affinity" -}}
  {{- if and (ne .mode "dev") .Values.server.affinity }}
      affinity:
        {{ tpl .Values.server.affinity . | nindent 8 | trim }}
  {{ end }}
{{- end -}}

{{/*
Sets the injector affinity for pod placement
*/}}
{{- define "injector.affinity" -}}
  {{- if .Values.injector.affinity }}
      affinity:
        {{ tpl .Values.injector.affinity . | nindent 8 | trim }}
  {{ end }}
{{- end -}}

{{/*
Set's the toleration for pod placement when running in standalone and HA modes.
*/}}
{{- define "vault.tolerations" -}}
  {{- if and (ne .mode "dev") .Values.server.tolerations }}
      tolerations:
        {{ tpl .Values.server.tolerations . | nindent 8 | trim }}
  {{- end }}
{{- end -}}

{{/*
Sets the injector toleration for pod placement
*/}}
{{- define "injector.tolerations" -}}
  {{- if .Values.injector.tolerations }}
      tolerations:
        {{ tpl .Values.injector.tolerations . | nindent 8 | trim }}
  {{- end }}
{{- end -}}

{{/*
Set's the node selector for pod placement when running in standalone and HA modes.
*/}}
{{- define "vault.nodeselector" -}}
  {{- if and (ne .mode "dev") .Values.server.nodeSelector }}
      nodeSelector:
        {{ tpl .Values.server.nodeSelector . | indent 8 | trim }}
  {{- end }}
{{- end -}}

{{/*
Sets the injector node selector for pod placement
*/}}
{{- define "injector.nodeselector" -}}
  {{- if .Values.injector.nodeSelector }}
      nodeSelector:
        {{ tpl .Values.injector.nodeSelector . | indent 8 | trim }}
  {{- end }}
{{- end -}}



{{/*
Sets extra injector pod annotations
*/}}
{{- define "injector.annotations" -}}
  {{- if .Values.injector.annotations }}
      annotations:
        {{- $tp := typeOf .Values.injector.annotations }}
        {{- if eq $tp "string" }}
          {{- tpl .Values.injector.annotations . | nindent 8 }}
        {{- else }}
          {{- toYaml .Values.injector.annotations | nindent 8 }}
        {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra injector service annotations
*/}}
{{- define "injector.service.annotations" -}}
  {{- if .Values.injector.service.annotations }}
  annotations:
    {{- $tp := typeOf .Values.injector.service.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.injector.service.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.injector.service.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra ui service annotations
*/}}
{{- define "vault.ui.annotations" -}}
  {{- if .Values.ui.annotations }}
  annotations:
    {{- $tp := typeOf .Values.ui.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.ui.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.ui.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "vault.serviceAccount.name" -}}
{{- if .Values.server.serviceAccount.create -}}
    {{ default (include "vault.fullname" .) .Values.server.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.server.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Sets extra service account annotations
*/}}
{{- define "vault.serviceAccount.annotations" -}}
  {{- if and (ne .mode "dev") .Values.server.serviceAccount.annotations }}
  annotations:
    {{- $tp := typeOf .Values.server.serviceAccount.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.server.serviceAccount.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.server.serviceAccount.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets extra route annotations
*/}}
{{- define "vault.route.annotations" -}}
  {{- if .Values.server.route.annotations }}
  annotations:
    {{- $tp := typeOf .Values.server.route.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.server.route.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.server.route.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}


{{/*
Sets VolumeClaim annotations for data volume
*/}}
{{- define "vault.dataVolumeClaim.annotations" -}}
  {{- if and (ne .mode "dev") (.Values.server.dataStorage.enabled) (.Values.server.dataStorage.annotations) }}
  annotations:
    {{- $tp := typeOf .Values.server.dataStorage.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.server.dataStorage.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.server.dataStorage.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Sets VolumeClaim annotations for audit volume
*/}}
{{- define "vault.auditVolumeClaim.annotations" -}}
  {{- if and (ne .mode "dev") (.Values.server.auditStorage.enabled) (.Values.server.auditStorage.annotations) }}
  annotations:
    {{- $tp := typeOf .Values.server.auditStorage.annotations }}
    {{- if eq $tp "string" }}
      {{- tpl .Values.server.auditStorage.annotations . | nindent 4 }}
    {{- else }}
      {{- toYaml .Values.server.auditStorage.annotations | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Set's the container resources if the user has set any.
*/}}
{{- define "vault.resources" -}}
  {{- if .Values.server.resources -}}
          resources:
{{ toYaml .Values.server.resources | indent 12}}
  {{ end }}
{{- end -}}

{{/*
Sets the container resources if the user has set any.
*/}}
{{- define "injector.resources" -}}
  {{- if .Values.injector.resources -}}
          resources:
{{ toYaml .Values.injector.resources | indent 12}}
  {{ end }}
{{- end -}}



{{/* Scheme for health check and local endpoint */}}
{{- define "vault.scheme" -}}
{{- if .Values.global.tlsDisable -}}
{{ "http" }}
{{- else -}}
{{ "https" }}
{{- end -}}
{{- end -}}
