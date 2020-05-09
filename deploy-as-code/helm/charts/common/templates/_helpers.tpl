{{- define "common.name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseCommonValues := .Values.common | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseCommonValues .Values $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}

{{- define "common.labels" -}}
{{- $envOverrides := index .Values (include "common.name" .) | deepCopy -}} 
{{- $baseCommonValues := .Values.common | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $envOverrides $baseCommonValues .Values ) -}}
{{- with mustMergeOverwrite . $values }}
app: {{ default .Chart.Name .Values.name }}
{{- if .Values.labels.group }}      
group: {{ .Values.labels.group }}  
{{- end }}  
{{- range $key, $val := .Values.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end }}    
{{- end }}
{{- end }}