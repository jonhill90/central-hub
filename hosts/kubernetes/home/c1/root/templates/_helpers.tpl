{{- /*
Helm parameters for one child Application:
- needsZone: true passes `zone` itself (for charts in this repository that build names from it);
- zoneParameters: value path -> text, with "{zone}" swapped for the zone and "{gatewayAddress}" for
  the Gateway's address, "{gatewayHttps}" for whether it has HTTPS listeners (for charts that need a whole URL, a hostname or the address, such as
  Grafana's root_url). Escape dots inside a key with "\\.".
- switchParameters: value path -> the name of a true/false root value; "true" is passed only when
  that root value is true, so a cluster that leaves it false renders exactly as before.
- switchOffParameters: value path -> the name of a true/false root value; "false" is passed only when
  that root value is false, so a cluster that leaves it true renders exactly as before.
- rootParameters: value path -> the name of a text root value; passed only when that root value is
  not empty, so a cluster that leaves it empty renders exactly as before.
- openbaoParameters: value path -> text; passed only when the root's appSecretsStore is openbao (plan step 8a), so a cluster that
  keeps its apps' secrets in store c1 renders exactly as before.
Both are private (CLAUDE.md rule 4): they live only in the root Application, set by Ansible.
*/ -}}
{{- define "c1.parameters" -}}
{{- $app := .app }}
{{- $switches := list }}
{{- range $path, $key := $app.switchParameters }}
{{- if eq (toString (index $.root.Values $key)) "true" }}
{{- $switches = append $switches $path }}
{{- end }}
{{- end }}
{{- $offs := list }}
{{- range $path, $key := $app.switchOffParameters }}
{{- if eq (toString (index $.root.Values $key)) "false" }}
{{- $offs = append $offs $path }}
{{- end }}
{{- end }}
{{- $fromRoot := dict }}
{{- range $path, $key := $app.rootParameters }}
{{- with index $.root.Values $key }}
{{- $_ := set $fromRoot $path (toString .) }}
{{- end }}
{{- end }}
{{- $fromOpenbao := dict }}
{{- if eq (toString $.root.Values.appSecretsStore) "openbao" }}
{{- range $path, $text := $app.openbaoParameters }}
{{- $_ := set $fromOpenbao $path (toString $text) }}
{{- end }}
{{- end }}
{{- if or $app.needsZone $app.zoneParameters $switches $offs $fromRoot $fromOpenbao }}
parameters:
{{- range $path := $switches }}
  - name: {{ $path | quote }}
    value: "true"
{{- end }}
{{- range $path := $offs }}
  - name: {{ $path | quote }}
    value: "false"
{{- end }}
{{- range $path, $value := $fromRoot }}
  - name: {{ $path | quote }}
    value: {{ $value | quote }}
{{- end }}
{{- range $path, $value := $fromOpenbao }}
  - name: {{ $path | quote }}
    value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- if or $app.needsZone $app.zoneParameters }}
{{- $zone := required "zone: the root Application must set it (k8s_gitops_source_zone)" .root.Values.zone }}
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
