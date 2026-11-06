{{- define "sdipredis.values" -}}
{{- $overrides := get .Values .Chart.Name | default dict -}}
{{- toYaml (mergeOverwrite (deepCopy .Values) $overrides) -}}
{{- end -}}

{{- define "sdipredis.authPing" -}}
exec:
  command:
    - /bin/sh
    - -ec
    - |
      REDISCLI_AUTH="$(cat /etc/redis/password)"
      export REDISCLI_AUTH
      test "$(redis-cli -h 127.0.0.1 -p 6379 ping)" = "PONG"
{{- end -}}
