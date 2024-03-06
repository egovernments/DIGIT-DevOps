{{- define "common.name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseCommonValues := .Values.common | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseCommonValues .Values $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}

{{- define "common.labels" -}}
app: {{ template "common.name" . }}
{{- if .Values.labels.group }}      
group: {{ .Values.labels.group }}  
{{- end }}  
{{- range $key, $val := .Values.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end }}    
{{- end }}

{{- define "common.image" -}}
{{- if contains "/" .repository -}}      
{{- printf "%s:%s" .repository  ( required "Tag is mandatory" .tag ) -}}
{{- else -}}
{{- printf "%s/%s:%s" $.Values.global.containerRegistry .repository ( required "Tag is mandatory" .tag ) -}}
{{- end -}}
{{- end -}}