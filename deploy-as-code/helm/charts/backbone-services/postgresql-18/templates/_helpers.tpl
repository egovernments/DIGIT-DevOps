{{/*
Environment overrides.

Mirrors the contract used by the `common` library chart that every other
backbone service follows: values under a key matching the chart name in
environments/<env>.yaml are merged over the chart's own values.yaml, with the
environment winning.

  environments/unified-dev.yaml:
    postgresql-18:
      instances: 3
      storage:
        storageClass: managed-csi

mustMergeOverwrite is used rather than merge because argument order decides
precedence: the LAST argument wins, so the environment block overrides the
chart defaults rather than the other way round.

Usage in a template:
  {{- $v := include "pg18.values" . | fromYaml }}
  ... {{ $v.instances }} ...
*/}}
{{- define "pg18.values" -}}
{{- $envOverrides := (index .Values .Chart.Name) | default dict -}}
{{- toYaml (mustMergeOverwrite (deepCopy .Values) $envOverrides) -}}
{{- end -}}

{{/*
Resource name. Everything the operator derives (Services, Secrets, PVCs) is
prefixed with this, so it is deliberately the plain chart name and not
release-qualified -- consumers reference postgresql-18-rw by hostname.
*/}}
{{- define "pg18.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "pg18.labels" -}}
app: {{ include "pg18.name" . }}
{{- $v := include "pg18.values" . | fromYaml }}
{{- range $k, $val := ($v.labels | default dict) }}
{{ $k }}: {{ $val | quote }}
{{- end }}
{{- end -}}
