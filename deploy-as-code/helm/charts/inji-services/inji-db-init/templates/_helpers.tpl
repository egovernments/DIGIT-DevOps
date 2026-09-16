{{/*
=============================================================================
Environment-file value merge.
=============================================================================

Every chart in this repo is rendered with the shared environment file as a
second -f, so the env file's keys land at the TOP level of .Values. A chart's
own overrides therefore have to live under a key named after the chart
("inji-db-init:"), or they would collide with every other chart's keys.

The DIGIT convention is to let the `common` library chart perform that merge,
in common.name:

    $envOverrides := index .Values (default .Chart.Name .Values.name)
    mustMergeOverwrite $baseCommonValues .Values $envOverrides

This chart deliberately does not depend on `common` -- common exists to render
deployments/services/ingresses, and pulling it in would require a set of
global.* values a bootstrap Job has no use for. So the merge is done here
instead.

It cannot be a helper that "returns" the merged values: Helm templates can only
return strings, not dicts. Each template therefore starts with

    {{- $v := include "inji-db-init.mergedValues" . | fromYaml -}}

and reads $v.<key> instead of .Values.<key>. Reading .Values directly in a
template is a bug -- it silently ignores the environment file, which is exactly
how `enabled: false` in this chart's values.yaml can override an
`enabled: true` in test-lts.yaml and leave the whole chart rendering nothing.
*/}}
{{- define "inji-db-init.mergedValues" -}}
{{- $envOverrides := default dict (index .Values .Chart.Name) -}}
{{- mustMergeOverwrite (deepCopy .Values) $envOverrides | toYaml -}}
{{- end -}}

{{/*
Short checksum of the provisioning SQL.

Both the ConfigMap and the Job are named with this suffix, which solves two
problems at once:

  1. A Job's spec.template is immutable. With a fixed name, editing
     provision.sql would leave the Job spec byte-identical (it only mounts a
     ConfigMap), so ArgoCD would see it as in sync and the new SQL would never
     run. Adding a checksum annotation to the pod template to force a change
     fails outright with "field is immutable".
  2. It keeps the Job stable across syncs when the SQL has NOT changed: the
     named Job already exists and matches, so repeated syncs are a no-op
     rather than re-running provisioning every time.

Consequence: editing the SQL leaves the previous Job and ConfigMap behind,
because every appset in this repo runs prune:false. That is a few KB of
completed Job history. Deliberately NOT using ttlSecondsAfterFinished to clean
them up -- the TTL controller would delete a Job ArgoCD is tracking, the
Application would flip to Missing, and selfHeal would recreate it in a loop.

Called with the root context, since it needs .Files.
*/}}
{{- define "inji-db-init.sqlChecksum" -}}
{{- .Files.Get "files/provision.sql" | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
Labels. Called with the labels map itself, e.g.

    {{- include "inji-db-init.labels" $v.labels | nindent 4 }}

rather than with a context, so it works against the merged values without
needing a synthetic .Values wrapper.
*/}}
{{- define "inji-db-init.labels" -}}
{{- range $k, $val := . }}
{{ $k }}: {{ $val | quote }}
{{- end }}
{{- end -}}
