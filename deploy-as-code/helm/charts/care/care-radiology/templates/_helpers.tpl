{{- define "care-radiology.init" -}}
{{- $envOverrides := index .Values (default .Chart.Name .Values.name) -}}
{{- if $envOverrides -}}
{{- $_ := mustMergeOverwrite .Values $envOverrides -}}
{{- end -}}
{{- end -}}
