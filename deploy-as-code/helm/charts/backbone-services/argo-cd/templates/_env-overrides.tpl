{{/*
Fold environment-specific overrides from environments/<env>.yaml into .Values.

WHY THIS EXISTS
  Every application service in this repo is overridden per environment by a
  top-level block in environments/<env>.yaml keyed on the chart name, e.g.

      egov-filestore:
        image:
          tag: security-patch-b62174b

  That is implemented by the `common` library chart, whose "common.name"
  helper does:

      $envOverrides := index .Values (default .Chart.Name .Values.name)
      mustMergeOverwrite $baseCommonValues .Values $envOverrides

  argo-cd is the upstream argoproj chart and deliberately does not depend on
  `common` (it has its own 150-template layout and its own helpers), so the
  same behaviour is reproduced here rather than by pulling `common` in.

USAGE
  environments/unified-dev.yaml
      argo-cd:
        global:
          domain: argocd.unified-dev.digit.org
        configs:
          cm:
            dex.config: |
              connectors:
                - type: github
                  ...
          rbac:
            policy.csv: |
              g, egovernments:unified-dev-admins, role:admin

  The block is merged OVER the chart's own values.yaml, so anything not
  mentioned keeps its default. Nested maps merge key-by-key; lists are
  replaced wholesale (standard mergeOverwrite semantics).

HOW IT TAKES EFFECT
  `mustMergeOverwrite` mutates its first argument in place, so merging into
  .Values makes the overrides visible to every template rendered afterwards.
  This include deliberately emits no output.

  It is invoked from "argo-cd.namespace" (114 templates) and "argo-cd.labels"
  (118 templates). Both are referenced from `metadata:`, which in every
  template precedes `spec:` -- so the merge lands before any value is read for
  real content. The operation is idempotent, so being called ~230 times per
  render is harmless.

  The override key comes from `envOverrideKey` in values.yaml, set to "argo-cd"
  to match the block name used in environments/*.yaml; it falls back to
  .Chart.Name, which is also "argo-cd". Do not confuse it with `nameOverride`
  ("argocd"), which controls resource naming rather than values scoping. A
  mismatch between the key and the env-file block name fails SILENTLY -- the
  block is never read and the chart defaults apply unnoticed.
*/}}
{{- define "argo-cd.envOverrides" -}}
{{- $key := .Values.envOverrideKey | default .Chart.Name -}}
{{- $ov := index .Values $key -}}
{{- if kindIs "map" $ov -}}
{{- /* deepCopy so the override block itself is never mutated by the merge */ -}}
{{- $_ := mustMergeOverwrite .Values (deepCopy $ov) -}}
{{- end -}}
{{- end -}}
