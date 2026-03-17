{{- define "novu.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
{{- end }}
