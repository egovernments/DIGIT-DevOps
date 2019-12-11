{{- define "common.labels" -}}
{{- $common := dict "Values" .Values.common -}} 
{{- $noCommon := omit .Values "common" -}} 
{{- $module := dict "Values" (index .Values (tpl .Chart.Name .)) -}} 
{{- $noModule := omit (index .Values (tpl .Chart.Name .)) -}} 
{{- $overrides := dict "Values" (merge $noModule $noCommon ) -}} 
{{- $noValues := omit . "Values" -}} 
{{- with merge $noValues $overrides $common -}}
app: {{ .Chart.Name }}
{{- if .Values.labels.group }}      
group: {{ .Values.labels.group }}  
{{- end }}  
{{- range $key, $val := .Values.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end}}    
{{- end }}
{{- end }}