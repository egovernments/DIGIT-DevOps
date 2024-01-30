{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "name" -}}
{{- $envOverrides := index .Values (tpl (default .Chart.Name .Values.name) .) -}} 
{{- $baseValues := .Values | deepCopy -}}
{{- $values := dict "Values" (mustMergeOverwrite $baseValues $envOverrides) -}}
{{- with mustMergeOverwrite . $values -}}
{{- default .Chart.Name .Values.name -}}    
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for statefulset.
*/}}
{{- define "statefulset.apiVersion" -}}
{{- if semverCompare "<1.9-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "apps/v1beta2" -}}
{{- else -}}
{{- print "apps/v1" -}}
{{- end -}}
{{- end -}}

{{- define "common.image" -}}
{{- if contains "/" .repository -}}      
{{- printf "%s:%s" .repository  ( required "Tag is mandatory" .tag ) -}}
{{- else -}}
{{- printf "%s/%s:%s" $.Values.global.containerRegistry .repository ( required "Tag is mandatory" .tag ) -}}
{{- end -}}
{{- end -}}

{{/*
Return the proper Storage Class
*/}}
{{- define "kafka.storageClass" -}}
{{/*
Helm 2.11 supports the assignment of a value to a variable defined in a different scope,
but Helm 2.9 and 2.10 does not support it, so we need to implement this if-else logic.
*/}}
{{- if .Values.global -}}
    {{- if .Values.global.storageClass -}}
        {{- if (eq "-" .Values.global.storageClass) -}}
            {{- printf "storageClassName: \"\"" -}}
        {{- else }}
            {{- printf "storageClassName: %s" .Values.global.storageClass -}}
        {{- end -}}
    {{- else -}}
        {{- if .Values.persistence.storageClass -}}
              {{- if (eq "-" .Values.persistence.storageClass) -}}
                  {{- printf "storageClassName: \"\"" -}}
              {{- else }}
                  {{- printf "storageClassName: %s" .Values.persistence.storageClass -}}
              {{- end -}}
        {{- end -}}
    {{- end -}}
{{- else -}}
    {{- if .Values.persistence.storageClass -}}
        {{- if (eq "-" .Values.persistence.storageClass) -}}
            {{- printf "storageClassName: \"\"" -}}
        {{- else }}
            {{- printf "storageClassName: %s" .Values.persistence.storageClass -}}
        {{- end -}}
    {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return true if authentication via SASL should be configured for client communications
*/}}
{{- define "kafka.client.saslAuthentication" -}}
{{- $saslProtocols := list "sasl" "sasl_tls" -}}
{{- if has .Values.auth.clientProtocol $saslProtocols -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if authentication via SASL should be configured for inter-broker communications
*/}}
{{- define "kafka.interBroker.saslAuthentication" -}}
{{- $saslProtocols := list "sasl" "sasl_tls" -}}
{{- if has .Values.auth.interBrokerProtocol $saslProtocols -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if encryption via TLS for client connections should be configured
*/}}
{{- define "kafka.client.tlsEncryption" -}}
{{- $tlsProtocols := list "tls" "mtls" "sasl_tls" -}}
{{- if (has .Values.auth.clientProtocol $tlsProtocols) -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if encryption via TLS for inter broker communication connections should be configured
*/}}
{{- define "kafka.interBroker.tlsEncryption" -}}
{{- $tlsProtocols := list "tls" "mtls" "sasl_tls" -}}
{{- if (has .Values.auth.interBrokerProtocol $tlsProtocols) -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if encryption via TLS should be configured
*/}}
{{- define "kafka.tlsEncryption" -}}
{{- if or (include "kafka.client.tlsEncryption" .) (include "kafka.interBroker.tlsEncryption" .) -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return the type of listener
Usage:
{{ include "kafka.listenerType" ( dict "protocol" .Values.path.to.the.Value ) }}
*/}}
{{- define "kafka.listenerType" -}}
{{- if eq .protocol "plaintext" -}}
PLAINTEXT
{{- else if or (eq .protocol "tls") (eq .protocol "mtls") -}}
SSL
{{- else if eq .protocol "sasl_tls" -}}
SASL_SSL
{{- else if eq .protocol "sasl" -}}
SASL_PLAINTEXT
{{- end -}}
{{- end -}}


