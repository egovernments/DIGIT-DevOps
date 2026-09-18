{{/*
Environment-file merge -- this chart does not depend on the `common` library
chart. Read $v.<key>, never .Values.<key>.
*/}}
{{- define "inji-mimoto-keygen.mergedValues" -}}
{{- $envOverrides := default dict (index .Values .Chart.Name) -}}
{{- mustMergeOverwrite (deepCopy .Values) $envOverrides | toYaml -}}
{{- end -}}

{{/*
Checksum over files/* plus the values that shape the Job, so any change
produces a new Job name. A Job's spec.template is immutable, so a fixed name
would leave an edited Job unappliable.
*/}}
{{- define "inji-mimoto-keygen.checksum" -}}
{{- $v := include "inji-mimoto-keygen.mergedValues" . | fromYaml -}}
{{- $acc := "" -}}
{{- range $path, $_ := .Files.Glob "files/*" -}}
{{- $acc = printf "%s%s%s" $acc $path ($.Files.Get $path) -}}
{{- end -}}
{{- $sig := printf "%s|%s|%s|%s|%v" $acc $v.pvc.name $v.keystore.fileName $v.keystore.subject $v.keystore.days -}}
{{- $sig | sha256sum | trunc 8 -}}
{{- end -}}
