{{/*
Merge the environment file's chart-named block into .Values.

The shared environment file is passed as a second -f, so its keys land at the
TOP level of .Values; a chart's overrides therefore live under a key named
after the chart. The DIGIT convention is for the `common` library chart to do
this merge inside common.name. This chart does not depend on `common`, so it
does it here.

Read $v.<key>, never .Values.<key>, in the templates -- reading .Values
directly silently ignores the environment file and lets this chart's own
values.yaml win, with no error to notice.
*/}}
{{- define "inji-stack-config.mergedValues" -}}
{{- $envOverrides := default dict (index .Values .Chart.Name) -}}
{{- mustMergeOverwrite (deepCopy .Values) $envOverrides | toYaml -}}
{{- end -}}
