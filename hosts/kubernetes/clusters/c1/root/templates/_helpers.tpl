{{- /*
Helm parameters for one child Application:
- needsZone: true passes `zone` itself (for charts in this repository that build names from it);
- zoneParameters: value path -> text, with "{zone}" swapped for the zone (for upstream charts that
  need a whole URL or hostname, such as Grafana's root_url). Escape dots inside a key with "\\.".
The zone is private (CLAUDE.md rule 4): it lives only in the root Application, set by Ansible.
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
{{- range $path, $text := $app.zoneParameters }}
  - name: {{ $path | quote }}
    value: {{ replace "{zone}" $zone $text | quote }}
{{- end }}
{{- end }}
{{- end -}}
