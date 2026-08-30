{{- define "minio.fullname" -}}
{{- default "minio" .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "minio.headless" -}}
{{- printf "%s-svc" (include "minio.fullname" .) -}}
{{- end -}}

{{- define "minio.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end -}}

{{- define "minio.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
{{- include "minio.fullname" . -}}
{{- end -}}
{{- end -}}

{{- define "minio.labels" -}}
app: {{ include "minio.fullname" . }}
release: {{ .Release.Name }}
{{- end -}}

{{/*
Selector labels: intentionally exclude the release name. The StatefulSet was
originally created under a different Helm release name, and its selector is
immutable — Services selecting on the release label end up with no endpoints
(which breaks per-pod DNS via the headless service and MinIO quorum).
Selecting on the stable app label alone matches the pods regardless of the
release name used to render the chart.
*/}}
{{- define "minio.selectorLabels" -}}
app: {{ include "minio.fullname" . }}
{{- end -}}
