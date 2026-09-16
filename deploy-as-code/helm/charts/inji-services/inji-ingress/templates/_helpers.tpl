{{/*
Merge the environment file's chart-named block into .Values. See
charts/inji-services/inji-stack-config/templates/_helpers.tpl for why this is
needed: the `common` library chart normally performs this merge in common.name,
and a chart that does not depend on `common` must do it itself or the
environment file is silently ignored.
*/}}
{{- define "inji-ingress.mergedValues" -}}
{{- $envOverrides := default dict (index .Values .Chart.Name) -}}
{{- mustMergeOverwrite (deepCopy .Values) $envOverrides | toYaml -}}
{{- end -}}
