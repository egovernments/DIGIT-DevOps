{{/*
Chart data generated from upstream: charts/posthog/upstream.yaml
*/}}
{{- define "posthog.upstream" -}}
{{- .Files.Get "upstream.yaml" -}}
{{- end -}}

{{- define "posthog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "posthog.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "posthog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "posthog.labels" -}}
helm.sh/chart: {{ include "posthog.chart" . }}
app.kubernetes.io/name: {{ include "posthog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | trunc 12 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: posthog
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* usage: include "posthog.selectorLabels" (list $ "web") */}}
{{- define "posthog.selectorLabels" -}}
{{- $ := index . 0 -}}{{- $component := index . 1 -}}
app.kubernetes.io/name: {{ include "posthog.name" $ }}
app.kubernetes.io/instance: {{ $.Release.Name }}
app.kubernetes.io/component: {{ $component }}
{{- end -}}

{{/* usage: include "posthog.serviceName" (list $ "web") */}}
{{- define "posthog.serviceName" -}}
{{- $ := index . 0 -}}{{- $component := index . 1 -}}
{{- printf "%s-%s" (include "posthog.fullname" $) $component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Datastore host: the external host when configured, otherwise the bundled service.
usage: include "posthog.host" (list $ "postgresql")
*/}}
{{- define "posthog.host" -}}
{{- $ := index . 0 -}}{{- $key := index . 1 -}}
{{- $bundled := dict "postgresql" "postgresql" "redis" "redis7" "valkey" "valkey" "kafka" "kafka" "clickhouse" "clickhouse" "temporal" "temporal" -}}
{{- $cfg := index $.Values $key | default dict -}}
{{- $ext := $cfg.external | default dict -}}
{{- if $ext.host -}}
{{- $ext.host -}}
{{- else -}}
{{- include "posthog.serviceName" (list $ (index $bundled $key)) -}}
{{- end -}}
{{- end -}}

{{- define "posthog.siteHost" -}}
{{- regexReplaceAll "/.*$" (regexReplaceAll "^https?://" .Values.posthog.siteUrl "") "" -}}
{{- end -}}

{{- define "posthog.publicUrl" -}}
{{- .Values.posthog.publicUrl | default .Values.posthog.siteUrl | trimSuffix "/" -}}
{{- end -}}

{{/* S3 endpoint: external when configured, otherwise the bundled SeaweedFS service. */}}
{{- define "posthog.objectStorageEndpoint" -}}
{{- if .Values.objectStorage.endpoint -}}
{{- .Values.objectStorage.endpoint | trimSuffix "/" -}}
{{- else -}}
{{- printf "http://%s:8333" (include "posthog.serviceName" (list . "seaweedfs")) -}}
{{- end -}}
{{- end -}}

{{- define "posthog.publicHost" -}}
{{- regexReplaceAll "/.*$" (regexReplaceAll "^https?://" (include "posthog.publicUrl" .) "") "" -}}
{{- end -}}

{{/*
Image reference for an upstream image key. Digest pinning is on by default; values.images.overrides
can replace repository, tag or digest per key. usage: include "posthog.image" (list $ "web")
*/}}
{{- define "posthog.image" -}}
{{- $ := index . 0 -}}{{- $key := index . 1 -}}
{{- $up := include "posthog.upstream" $ | fromYaml -}}
{{- $img := index $up.images $key | default dict -}}
{{- $ov := index $.Values.images.overrides $key | default dict -}}
{{- $repo := $ov.repository | default $img.repository -}}
{{- $tag := $ov.tag | default $img.tag -}}
{{- $digest := $ov.digest | default $img.digest -}}
{{- if $.Values.global.imageRegistry -}}
{{- $repo = printf "%s/%s" (trimSuffix "/" $.Values.global.imageRegistry) (regexReplaceAll "^docker.io/" $repo "") -}}
{{- end -}}
{{- if and $digest $.Values.images.pinDigests (not $ov.tag) -}}
{{- printf "%s:%s@%s" $repo $tag $digest -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{/*
Image reference for the chart's own images (router, bundled PostgreSQL and SeaweedFS), written in
values as repository:tag@sha256:... With images.pinDigests off the digest is dropped and the tag
followed. usage: include "posthog.chartImage" (list $ "caddy:2.10-alpine@sha256:...")
*/}}
{{- define "posthog.chartImage" -}}
{{- $ := index . 0 -}}{{- $ref := index . 1 -}}
{{- if $.Values.images.pinDigests -}}
{{- $ref -}}
{{- else -}}
{{- regexReplaceAll "@sha256:[0-9a-f]{64}$" $ref "" -}}
{{- end -}}
{{- end -}}

{{- define "posthog.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range . }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Where a secret key lives. Order: explicit mapping in values.secrets.keys, well-known external
secrets (Postgres URL, object storage), then the chart-managed secret.
usage: include "posthog.secretRef" (list $ "DATABASE_URL") -> "name/key"
*/}}
{{- define "posthog.secretRef" -}}
{{- $ := index . 0 -}}{{- $key := index . 1 -}}
{{- $m := index $.Values.secrets.keys $key | default dict -}}
{{- $pg := $.Values.postgresql.external -}}
{{- $os := $.Values.objectStorage -}}
{{- $sr := $.Values.sessionReplay.storage -}}
{{- if $m.secret -}}
{{- printf "%s/%s" $m.secret ($m.key | default $key) -}}
{{- else if and (eq $key "DATABASE_URL") $pg.existingSecret $pg.urlKey -}}
{{- printf "%s/%s" $pg.existingSecret $pg.urlKey -}}
{{- else if and (eq $key "PGPASSWORD") $pg.existingSecret $pg.passwordKey -}}
{{- printf "%s/%s" $pg.existingSecret $pg.passwordKey -}}
{{- else if and (eq $key "OBJECT_STORAGE_ACCESS_KEY_ID") $os.existingSecret -}}
{{- printf "%s/%s" $os.existingSecret $os.accessKeyIdKey -}}
{{- else if and (eq $key "OBJECT_STORAGE_SECRET_ACCESS_KEY") $os.existingSecret -}}
{{- printf "%s/%s" $os.existingSecret $os.secretAccessKeyKey -}}
{{- else if and (eq $key "SESSION_RECORDING_ACCESS_KEY_ID") $sr.existingSecret -}}
{{- printf "%s/%s" $sr.existingSecret $sr.accessKeyIdKey -}}
{{- else if and (eq $key "SESSION_RECORDING_SECRET_ACCESS_KEY") $sr.existingSecret -}}
{{- printf "%s/%s" $sr.existingSecret $sr.secretAccessKeyKey -}}
{{- else if and (eq $key "SESSION_RECORDING_ACCESS_KEY_ID") (not $sr.accessKeyId) -}}
{{- include "posthog.secretRef" (list $ "OBJECT_STORAGE_ACCESS_KEY_ID") -}}
{{- else if and (eq $key "SESSION_RECORDING_SECRET_ACCESS_KEY") (not $sr.secretAccessKey) -}}
{{- include "posthog.secretRef" (list $ "OBJECT_STORAGE_SECRET_ACCESS_KEY") -}}
{{- else if and (has $key (list "SECRET_KEY" "ENCRYPTION_SALT_KEYS" "BROWSERLESS_TOKEN" "INTERNAL_API_SECRET" "INTERNAL_REQUEST_TOKEN" "RECORDING_API_JWT_SECRET" "AI_GATEWAY_API_KEY")) $.Values.posthog.existingSecret -}}
{{- printf "%s/%s" $.Values.posthog.existingSecret $key -}}
{{- else -}}
{{- printf "%s/%s" (include "posthog.envSecretName" $) $key -}}
{{- end -}}
{{- end -}}

{{- define "posthog.envSecretName" -}}
{{- printf "%s-env" (include "posthog.fullname" .) -}}
{{- end -}}

{{/*
Render a list of env entries from upstream.yaml (value / tpl / secret) plus extras.
usage: include "posthog.env" (list $ $svcName $envList)
*/}}
{{- define "posthog.env" -}}
{{- $ := index . 0 -}}{{- $svc := index . 1 -}}{{- $env := index . 2 -}}
{{- /* values.services.<name>.env overrides upstream entries with the same name */ -}}
{{- $ov := (index $.Values.services $svc | default dict).env | default list -}}
{{- $skip := dict -}}{{- range $ov }}{{- $_ := set $skip .name true -}}{{- end -}}
{{- range $env }}
{{- if not (hasKey $skip .name) }}
- name: {{ .name }}
{{- if .secret }}
{{- $ref := splitn "/" 2 (include "posthog.secretRef" (list $ .secret)) }}
  valueFrom:
    secretKeyRef:
      name: {{ $ref._0 }}
      key: {{ $ref._1 }}
{{- if .optional }}
      optional: true
{{- end }}
{{- else if .tpl }}
  value: {{ tpl (.value | toString) $ | quote }}
{{- else }}
  value: {{ .value | toString | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ConfigMap name for an upstream config directory, e.g. docker/clickhouse -> <fullname>-cfg-clickhouse */}}
{{- define "posthog.configMapName" -}}
{{- $ := index . 0 -}}{{- $dir := index . 1 -}}
{{- $short := regexReplaceAll "^docker/" $dir "" | replace "/" "-" | replace "_" "-" -}}
{{- printf "%s-cfg-%s" (include "posthog.fullname" $) $short | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The set of upstream config directories that become ConfigMaps. */}}
{{- define "posthog.configDirs" -}}
{{- $dirs := dict -}}
{{- range $path, $_ := .Files.Glob "files/upstream/docker/**" -}}
{{- $rel := trimPrefix "files/upstream/" $path -}}
{{- $_ := set $dirs (dir $rel) true -}}
{{- end -}}
{{- range $path, $_ := .Files.Glob "files/chart/**" -}}
{{- $rel := trimPrefix "files/" $path -}}
{{- $_ := set $dirs (dir $rel) true -}}
{{- end -}}
{{- keys $dirs | sortAlpha | toJson -}}
{{- end -}}

{{/*
Pod-level security context and container security context for a service.
usage: include "posthog.podSecurityContext" (list $ $svc)
*/}}
{{- define "posthog.podSecurityContext" -}}
{{- $ := index . 0 -}}{{- $svc := index . 1 -}}
{{- $sc := $svc.securityContext | default dict -}}
{{- $ov := ($svc.overrides).podSecurityContext | default dict -}}
{{- $merged := mergeOverwrite (dict "runAsNonRoot" true "seccompProfile" (dict "type" "RuntimeDefault")) $sc $ov -}}
{{- if hasKey $merged "fsGroup" -}}{{- $_ := set $merged "fsGroupChangePolicy" "OnRootMismatch" -}}{{- end -}}
{{- toYaml $merged -}}
{{- end -}}

{{- define "posthog.containerSecurityContext" -}}
{{- $ := index . 0 -}}{{- $svc := index . 1 -}}
{{- $ov := ($svc.overrides).containerSecurityContext | default dict -}}
{{- $base := dict "allowPrivilegeEscalation" false "capabilities" (dict "drop" (list "ALL")) "readOnlyRootFilesystem" (default false ($svc.overrides).readOnlyRootFilesystem) -}}
{{- toYaml (mergeOverwrite $base $ov) -}}
{{- end -}}

{{/* Standard pod annotations: checksum of config so pods roll on config changes. */}}
{{- define "posthog.podAnnotations" -}}
{{- $ := index . 0 -}}{{- $svc := index . 1 -}}
checksum/upstream: {{ include "posthog.upstream" $ | sha256sum | trunc 16 }}
checksum/values: {{ toYaml $.Values.posthog | sha256sum | trunc 16 }}
{{- with $.Values.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- with ($svc.overrides).podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Init container that copies directories shipped inside the posthog image (IDL, UDF binaries). */}}
{{- define "posthog.imageDirInitContainer" -}}
{{- $ := index . 0 -}}{{- $mounts := index . 1 -}}
- name: copy-upstream
  image: {{ include "posthog.image" (list $ "posthog") | quote }}
  imagePullPolicy: IfNotPresent
  command: ["/bin/sh", "-ec"]
  args:
    - |
{{- range $mounts }}
{{- if .imageDir }}
      cp -r /code/{{ .imageDir }}/. /upstream/{{ .imageDir | replace "/" "-" | replace "_" "-" }}/
{{- end }}
{{- end }}
      ls -la /upstream
  volumeMounts:
{{- range $mounts }}
{{- if .imageDir }}
    - name: upstream-{{ .imageDir | replace "/" "-" | replace "_" "-" }}
      mountPath: /upstream/{{ .imageDir | replace "/" "-" | replace "_" "-" }}
{{- end }}
{{- end }}
  securityContext:
    allowPrivilegeEscalation: false
    capabilities: {drop: [ALL]}
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
  resources:
    requests: {cpu: 10m, memory: 64Mi}
    limits: {memory: 256Mi}
{{- end -}}

{{/*
Init container that blocks until Django migrations are applied (the migrate Job ran). Keeps web
and the workers from crash-looping on a fresh database.
*/}}
{{- define "posthog.waitForMigrationsInitContainer" -}}
{{- $ := index . 0 -}}{{- $svc := index . 1 -}}
- name: wait-for-migrations
  image: {{ include "posthog.image" (list $ "posthog") | quote }}
  imagePullPolicy: IfNotPresent
  command: ["/bin/sh", "-ec"]
  args:
    - |
      i=0
      until python manage.py migrate --check >/dev/null 2>&1; do
        i=$((i+1)); [ $((i % 6)) -eq 0 ] && echo "waiting for database migrations ($((i*10))s)"
        sleep 10
      done
      echo "migrations applied"
  env:
    {{- include "posthog.env" (list $ "wait-for-migrations" $svc.env) | nindent 4 }}
  securityContext:
    allowPrivilegeEscalation: false
    capabilities: {drop: [ALL]}
  resources:
    {{- toYaml $.Values.migrations.waitResources | nindent 4 }}
  volumeMounts:
    - name: tmp
      mountPath: /tmp
{{- end -}}

{{/* Seed volume (schema seed for a fast first start), empty when not configured. */}}
{{- define "posthog.seedVolume" -}}
{{- if .Values.seed.existingClaim }}
- name: seed
  persistentVolumeClaim:
    claimName: {{ .Values.seed.existingClaim }}
    readOnly: true
{{- else if .Values.seed.hostPath }}
- name: seed
  hostPath:
    path: {{ .Values.seed.hostPath }}
    type: Directory
{{- end }}
{{- end -}}

{{- define "posthog.seedMount" -}}
{{- if or .Values.seed.existingClaim .Values.seed.hostPath }}
- name: seed
  mountPath: /seed
  readOnly: true
{{- end }}
{{- end -}}

{{/* Origin of the Gemini gateway; PostHog gets it with /v1 as AI_GATEWAY_URL. */}}
{{- define "posthog.geminiGatewayOrigin" -}}
{{- printf "http://%s:%v" (include "posthog.serviceName" (list . "gemini-gateway")) .Values.geminiGateway.port -}}
{{- end -}}

{{/* AI_GATEWAY_URL / AI_GATEWAY_API_KEY for the services in geminiGateway.clients. */}}
{{- define "posthog.geminiGatewayClientEnv" -}}
{{- $ := index . 0 -}}{{- $svc := index . 1 -}}
{{- if and $.Values.geminiGateway.enabled (has $svc $.Values.geminiGateway.clients) -}}
{{- toYaml (list
  (dict "name" "AI_GATEWAY_URL" "value" (printf "%s/v1" (include "posthog.geminiGatewayOrigin" $)))
  (dict "name" "AI_GATEWAY_API_KEY" "secret" "AI_GATEWAY_API_KEY" "optional" true)) -}}
{{- else -}}
[]
{{- end -}}
{{- end -}}

{{/*
Caddyfile of the Gemini gateway (templates/gemini-gateway.yaml). {$...} are read from the env at start.
args: root, upstream (no trailing slash)
*/}}
{{- define "posthog.geminiGatewayCaddyfile" -}}
{{- $ := index . 0 -}}{{- $upstream := index . 1 -}}
{
	admin off
	persist_config off
	auto_https off
	# Error logs carry the request headers; the token is one of them.
	log {
		format filter {
			request>headers>X-Goog-Api-Key delete
		}
	}
}

:{{ $.Values.geminiGateway.port }} {
	@gemini path /v1beta/* /upload/v1beta/*
	@authorized {
		path /v1beta/* /upload/v1beta/*
		header X-Goog-Api-Key "{$AI_GATEWAY_API_KEY}"
	}

	route {
		respond /_health "ok" 200

		reverse_proxy @authorized {{ $upstream }} {
			header_up Host {upstream_hostport}
			header_up X-Goog-Api-Key "{$GEMINI_API_KEY}"
			# Labels for PostHog's own gateway (product, trace, distinct id, properties): not for Google.
			header_up -X-Posthog-*
			header_up -X-Forwarded-*
			# The client sends the upload chunks to this URL and rejects any origin but the gateway's.
			header_down X-Goog-Upload-Url `^{{ regexQuoteMeta $upstream }}` "{{ include "posthog.geminiGatewayOrigin" $ }}"
			flush_interval -1
		}

		handle @gemini {
			header Content-Type application/json
			respond `{"error":{"code":401,"status":"UNAUTHENTICATED","message":"gemini-gateway: x-goog-api-key is not this release's AI_GATEWAY_API_KEY"}}` 401
		}

		handle {
			header Content-Type application/json
			respond `{"error":{"code":501,"status":"UNIMPLEMENTED","type":"not_supported","message":"gemini-gateway serves the Gemini API (/v1beta) only; PostHog's OpenAI and Anthropic gateway routes are not available"}}` 501
		}
	}
}
{{- end -}}
