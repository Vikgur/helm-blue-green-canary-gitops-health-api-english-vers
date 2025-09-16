{{/*
Common labels for all services
*/}}
{{- define "common.labels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end }}

{{/*
Common resources
*/}}
{{- define "common.resources" -}}
resources:
  limits:
    cpu: {{ .Values.resources.limits.cpu | default "500m" }}
    memory: {{ .Values.resources.limits.memory | default "512Mi" }}
  requests:
    cpu: {{ .Values.resources.requests.cpu | default "100m" }}
    memory: {{ .Values.resources.requests.memory | default "128Mi" }}
{{- end }}

{{/*
Common probes
*/}}
{{- define "common.probes" -}}
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
{{- end }}

{{/*
Name to be used in labels
*/}}
{{- define "common.name" -}}
{{ .Chart.Name }}
{{- end }}
