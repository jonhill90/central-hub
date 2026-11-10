{{- /*
Helm parameters for one child Application:
- needsZone: true passes `zone` itself (for charts in this repository that build names from it);
- zoneParameters: value path -> text, with "{zone}" swapped for the zone and "{gatewayAddress}" for
  the Gateway's address, "{gatewayHttps}" for whether it has HTTPS listeners (for charts that need a whole URL, a hostname or the address, such as
  Grafana's root_url). Escape dots inside a key with "\\.".
Both are private (CLAUDE.md rule 4): they live only in the root Application, set by Ansible.
*/ -}}
{{- define "c1.parameters" -}}
{{- $app := .app }}
{{- if or $app.needsZone $app.zoneParameters }}
{{- $zone := required "zone: the root Application must set it (k8s_gitops_source_zone)" .root.Values.zone }}
parameters:
{{- if $app.needsZone }}
  - name: zone
    value: {{ $zone | quote }}
{{- end }}
{{- $root := .root }}
{{- range $path, $text := $app.zoneParameters }}
{{- /* No address yet: leave the parameter out, so only that child fails, not the root. */}}
{{- /* HTTPS on, the chart's own default: leave the parameter out, so c1's render is unchanged. */}}
{{- if not (or (and (contains "{gatewayAddress}" $text) (not $root.Values.gatewayAddress)) (and (contains "{gatewayHttps}" $text) $root.Values.gatewayHttps)) }}
  - name: {{ $path | quote }}
    value: {{ replace "{gatewayAddress}" ($root.Values.gatewayAddress | default "") $text | replace "{gatewayHttps}" (toString $root.Values.gatewayHttps) | replace "{zone}" $zone | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
