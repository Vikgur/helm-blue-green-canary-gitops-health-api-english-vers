{{- define "swagger.name" -}}
swagger
{{- end }}

{{- define "swagger.fullname" -}}
{{ include "swagger.name" . }}-{{ .Release.Name }}
{{- end }}
