{{- define "common.name" -}}
{{- default "audit-service" .Values.name -}}
{{- end -}}

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
{{- default "audit-service:v1.0.0-24873ba-4" .Values.image -}}
{{- end -}}
// {{- define "common.name" -}}
// {{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}}
// {{- printf "envOverrides: %s" $envOverrides | quote -}}
// {{- $baseCommonValues := .Values.common | deepCopy -}}
// {{- printf "baseCommonValues: %s" $baseCommonValues | quote -}}
// {{- $values := dict "Values" (mustMergeOverwrite $baseCommonValues .Values $envOverrides) -}}
// {{- printf "mergedValues: %s" $values | quote -}}
// {{- with mustMergeOverwrite . $values -}}
// {{- default .Chart.Name .Values.name -}}    
// {{- end }}
// {{- end }}

// {{- define "common.labels" -}}
// app: {{ template "common.name" . }}
// {{- if .Values.labels.group }}      
// group: {{ .Values.labels.group }}  
// {{- end }}  
// {{- range $key, $val := .Values.additionalLabels }}
// {{ $key }}: {{ $val | quote }}
// {{- end }}    
// {{- end }}

// {{- define "common.image" -}}
// {{- if contains "/" .repository -}}      
// {{- printf "%s:%s" .repository  ( required "Tag is mandatory" .tag ) -}}
// {{- else -}}
// {{- printf "%s/%s:%s" $.Values.global.containerRegistry .repository ( required "Tag is mandatory" .tag ) -}}
// {{- end -}}
// {{- end -}}
