{{/* vim: set filetype=mustache: */}}
{{- define "name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}

{{- define "elasticsearch.roles" -}}
{{- range $.Values.roles -}}
{{ . }},
{{- end -}}
{{- end -}}

{{/*
Generate certificates when the secret doesn't exist
*/}}
{{- define "elasticsearch.gen-certs" -}}
{{- $certs := lookup "v1" "Secret" .Release.Namespace ( printf "%s-certs" (include "name" . ) ) -}}
{{- if $certs -}}
tls.crt: {{ index $certs.data "tls.crt" }}
tls.key: {{ index $certs.data "tls.key" }}
ca.crt: {{ index $certs.data "ca.crt" }}
{{- else -}}
{{- $altNames := list ( include "elasticsearch.masterService" . ) ( printf "%s.%s" (include "elasticsearch.masterService" .) .Release.Namespace ) ( printf "%s.%s.svc" (include "elasticsearch.masterService" .) .Release.Namespace ) -}}
{{- $ca := genCA "elasticsearch-ca" 365 -}}
{{- $cert := genSignedCert ( include "elasticsearch.masterService" . ) nil $altNames 365 $ca -}}
tls.crt: {{ $cert.Cert | toString | b64enc }}
tls.key: {{ $cert.Key | toString | b64enc }}
ca.crt: {{ $ca.Cert | toString | b64enc }}
{{- end -}}
{{- end -}}


{{- define "elasticsearch.masterService" -}}
{{- if empty .Values.masterService -}}
{{- if empty .Values.fullnameOverride -}}
{{- if empty .Values.nameOverride -}}
{{ .Values.clusterName }}-master
{{- else -}}
{{ .Values.nameOverride }}-master
{{- end -}}
{{- else -}}
{{ .Values.fullnameOverride }}
{{- end -}}
{{- else -}}
{{ .Values.masterService }}
{{- end -}}
{{- end -}}

{{- define "elasticsearch.endpoints" -}}
{{- $replicas := int (toString (.Values.replicas)) }}
{{- $uname := printf "%s-%s" .Values.clusterName .Values.nodeGroup }}
  {{- range $i, $e := untilStep 0 $replicas 1 -}}
{{ $uname }}-{{ $i }},
  {{- end -}}
{{- end -}}

{{- define "elasticsearch.esMajorVersion" -}}
{{- if .Values.esMajorVersion -}}
{{ .Values.esMajorVersion }}
{{- else -}}
{{- $version := int (index (.Values.image.tag | splitList ".") 0) -}}
  {{- if and (contains "docker.elastic.co/elasticsearch/elasticsearch" .Values.image.repository) (not (eq $version 0)) -}}
{{ $version }}
  {{- else -}}
8
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for statefulset.
*/}}
{{- define "elasticsearch.statefulset.apiVersion" -}}
{{- if semverCompare "<1.9-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "apps/v1beta2" -}}
{{- else -}}
{{- print "apps/v1" -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for ingress.
*/}}
{{- define "elasticsearch.ingress.apiVersion" -}}
{{- if semverCompare "<1.14-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "extensions/v1beta1" -}}
{{- else -}}
{{- print "networking.k8s.io/v1beta1" -}}
{{- end -}}
{{- end -}}

{{- define "common.image" -}}
{{- if contains "/" .repository -}}      
{{- printf "%s:%s" .repository  ( required "Tag is mandatory" .tag ) -}}
{{- else -}}
{{- printf "%s/%s:%s" $.Values.global.containerRegistry .repository ( required "Tag is mandatory" .tag ) -}}
{{- end -}}
{{- end -}}