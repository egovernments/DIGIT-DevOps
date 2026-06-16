{{- define "binfmt.name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}}
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
