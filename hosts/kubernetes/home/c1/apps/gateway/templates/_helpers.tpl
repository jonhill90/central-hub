{{- define "gateway.domain" -}}
{{ .Values.appsDomain }}.{{ required "zone: set by the root Application (k8s_gitops_source_zone)" .Values.zone }}
{{- end -}}
