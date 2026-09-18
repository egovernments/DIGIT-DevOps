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
{{/* every file under files/ -- payload AND script -- so a change to either
     produces a new Job name. Keeping the script inline in job.yaml left it out
     of the hash: an edit then collided with the immutable spec.template of the
     existing Job and ArgoCD could never apply it. */}}
{{- $acc := "" -}}
{{- range $path, $_ := .Files.Glob "files/*" -}}
{{- $acc = printf "%s%s%s" $acc $path ($.Files.Get $path) -}}
{{- end -}}
{{- $sig := printf "%s|%s|%s|%v|%s"
      $acc $v.clientId $v.esignet.service $v.esignet.port $v.esignet.servletPath -}}
{{- $sig | sha256sum | trunc 8 -}}
{{- end -}}
