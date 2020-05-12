{{- define "kafka.serverlist" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- $namespace := .Values.namespace }}
{{- $name := .Values.name -}}
{{- $serverPort := .Values.serverPort -}}
{{- $leaderElectionPort := .Values.leaderElectionPort -}}
{{- $zk := dict "servers" (list) -}}
{{- range $idx, $v := until (int .Values.replicas) }}
{{- $noop := printf "%s-%d.%s-headless.%s:%d:%d" $name $idx $name $namespace (int $serverPort) (int $leaderElectionPort) | append $zk.servers | set $zk "servers" -}}
{{- end }}
{{- printf "%s" (join ";" $zk.servers) | quote -}}
{{- end }}
{{- end }}

{{- define "name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}