{{- define "name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}

{{- define "common.image" -}}
{{- if contains "/" .repository -}}      
{{- printf "%s:%s" .repository  ( required "Tag is mandatory" .tag ) -}}
{{- else -}}
{{- printf "%s/%s:%s" $.Values.global.containerRegistry .repository ( required "Tag is mandatory" .tag ) -}}
{{- end -}}
{{- end -}}

{{- define "helm-toolkit.utils.joinListWithComma" -}}
{{- $local := dict "first" true -}}
{{- range $k, $v := . -}}{{- if not $local.first -}},{{- end -}}{{- $v -}}{{- $_ := set $local "first" false -}}{{- end -}}
{{- end -}}

{{/*
Cassandra related command line options
*/}}
{{- define "cassandra.cmdArgs" -}}
{{- range $key, $value := .Values.storage.cassandra.cmdlineParams -}}
{{- if $value -}}
- --{{ $key }}={{ $value }}
{{- else }}
- --{{ $key }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Elasticsearch related command line options
*/}}
{{- define "elasticsearch.cmdArgs" -}}
{{- range $key, $value := .Values.storage.elasticsearch.cmdlineParams -}}
{{- if $value -}}
- --{{ $key }}={{ $value }}
{{- else }}
- --{{ $key }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Cassandra or Elasticsearch related command line options depending on which is used
*/}}
{{- define "storage.cmdArgs" -}}
{{- if eq .Values.storage.type "cassandra" -}}
{{- include "cassandra.cmdArgs" . -}}
{{- else if eq .Values.storage.type "elasticsearch" -}}
{{- include "elasticsearch.cmdArgs" . -}}
{{- end -}}
{{- end -}}
