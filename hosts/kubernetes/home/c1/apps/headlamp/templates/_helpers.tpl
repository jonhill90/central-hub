{{- define "headlamp.host" -}}
{{ .Values.name }}.{{ .Values.gateway.hostSuffix }}.{{ required "zone: set by the root Application (k8s_gitops_source_zone)" .Values.zone }}
{{- end -}}
{{- define "headlamp.shortHost" -}}
{{ .Values.name }}.{{ required "zone: set by the root Application (k8s_gitops_source_zone)" .Values.zone }}
{{- end -}}
{{- define "headlamp.ssoHost" -}}
{{- if .Values.sso.shortNames -}}
{{ .Values.sso.issuerHost }}.{{ .Values.zone }}
{{- else -}}
{{ .Values.sso.issuerHost }}.{{ .Values.gateway.hostSuffix }}.{{ .Values.zone }}
{{- end -}}
{{- end -}}
