{{/*
Environment-file merge. See
charts/inji-services/inji-stack-config/templates/_helpers.tpl -- this chart
does not depend on the `common` library chart, so it performs the merge that
common.name would otherwise do. Read $v.<key>, never .Values.<key>.
*/}}
{{- define "inji-certify-config.mergedValues" -}}
{{- $envOverrides := default dict (index .Values .Chart.Name) -}}
{{- mustMergeOverwrite (deepCopy .Values) $envOverrides | toYaml -}}
{{- end -}}

{{/*
Checksum over the payload AND the values that shape the Job, so ANY change
that matters produces a new Job name.

A Job's spec.template is immutable: if the name does not change, ArgoCD's apply
is rejected with "field is immutable" and a Failed Job is never replaced. That
is not hypothetical -- the first run failed with DeadlineExceeded because
certify.port was the containerPort instead of the Service port, and fixing the
value alone left the name unchanged, so the broken Job would have persisted
until deleted by hand.

Covering the payload alone is therefore not enough; the resolved endpoint and
key id are included too.
*/}}
{{- define "inji-certify-config.checksum" -}}
{{- $v := include "inji-certify-config.mergedValues" . | fromYaml -}}
{{- $sig := printf "%s|%s|%s|%v|%s"
      (.Files.Get "files/credential-config.json")
      $v.credentialConfigKeyId
      $v.certify.service
      $v.certify.port
      $v.certify.servletPath -}}
{{- $sig | sha256sum | trunc 8 -}}
{{- end -}}
