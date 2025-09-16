{{- define "backend.name" -}}
{{ .Chart.Name }}
{{- end }}

{{- define "backend.fullname" -}}
{{ include "backend.name" . }}-{{ .Release.Name }}
{{- end }}
