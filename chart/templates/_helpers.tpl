{{/* Service name; also the Service and workload name so hosts stay <svc>.<ns>. */}}
{{- define "svc.name" -}}
{{- required "service.name is required" .Values.service.name -}}
{{- end -}}

{{- define "svc.sandbox" -}}
{{- if .Values.service.sandbox.name -}}true{{- end -}}
{{- end -}}

{{- define "svc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "svc.name" . }}
app.kubernetes.io/instance: {{ include "svc.name" . }}{{ with .Values.service.sandbox.name }}-sbx-{{ . }}{{ end }}
{{- end -}}

{{- define "svc.labels" -}}
{{ include "svc.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
platform.mcafeelabs.io/env: {{ .Values.service.environment | quote }}
platform.mcafeelabs.io/owner: {{ .Values.service.owner | default "unknown" | quote }}
platform.mcafeelabs.io/profile: {{ .Values.service.profile | quote }}
{{- with .Values.service.sandbox.name }}
platform.mcafeelabs.io/sandbox: {{ . | quote }}
{{- end }}
{{- end -}}

{{/* Rollouts in long-lived environments only; sandboxes start fast with a Deployment. */}}
{{- define "svc.useRollout" -}}
{{- if and .Values.platform.rollouts.enabled (not (include "svc.sandbox" .)) -}}true{{- end -}}
{{- end -}}

{{- define "svc.configSecret" -}}
{{ include "svc.name" . }}-config
{{- end -}}
