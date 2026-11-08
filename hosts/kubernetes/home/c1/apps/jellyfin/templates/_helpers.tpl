{{- define "jellyfin.host" -}}
{{ .Values.name }}.{{ .Values.gateway.hostSuffix }}.{{ required "zone: set by the root Application (k8s_gitops_source_zone)" .Values.zone }}
{{- end -}}
