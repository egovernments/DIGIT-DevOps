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
