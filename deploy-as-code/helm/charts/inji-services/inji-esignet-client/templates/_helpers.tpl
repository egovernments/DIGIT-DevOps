{{/*
Environment-file merge -- this chart does not depend on the `common` library
chart. Read $v.<key>, never .Values.<key>.
*/}}
{{- define "inji-esignet-client.mergedValues" -}}
{{- $envOverrides := default dict (index .Values .Chart.Name) -}}
{{- mustMergeOverwrite (deepCopy .Values) $envOverrides | toYaml -}}
{{- end -}}

{{/*
Checksum over the payload AND the values that shape the Job, so any meaningful
change produces a new Job name. A Job's spec.template is immutable: with a
fixed name, ArgoCD's apply is rejected with "field is immutable" and a Failed
Job is never replaced.
*/}}
{{- define "inji-esignet-client.checksum" -}}
{{- $v := include "inji-esignet-client.mergedValues" . | fromYaml -}}
{{- $sig := printf "%s|%s|%s|%v|%s"
      (.Files.Get "files/client.json")
      $v.clientId $v.esignet.service $v.esignet.port $v.esignet.servletPath -}}
{{- $sig | sha256sum | trunc 8 -}}
{{- end -}}
