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
Checksum of the payload, so editing credential-config.json produces a new Job
name and the seeding re-runs. A Job's spec.template is immutable, so a fixed
name would never pick up an edit. Same pattern as inji-db-init.
*/}}
{{- define "inji-certify-config.checksum" -}}
{{- .Files.Get "files/credential-config.json" | sha256sum | trunc 8 -}}
{{- end -}}
