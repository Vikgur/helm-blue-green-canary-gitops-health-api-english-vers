{{- define "nginx.name" -}}
nginx
{{- end }}

{{- define "nginx.fullname" -}}
{{ include "nginx.name" . }}-{{ .Release.Name }}
{{- end }}
