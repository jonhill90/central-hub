{{- /*
The notebook sync script: clone agent-notebook (depth 1) with the read-only token, or fetch it again. The token is read from
its file each time (it is replaced every 30 minutes) and goes to git in the environment, never in an argument or a log line.
once: clone if there is a token, then stop; otherwise loop every syncSeconds.
*/ -}}
{{- define "hub.notebookSync" -}}
set -u
export HOME=/tmp GIT_TERMINAL_PROMPT=0
dest=/notebook/repo
sync() {
  tok=$(cat /var/run/hub/feed-token/notebook-token 2>/dev/null || true)
  if [ -z "$tok" ]; then echo "notebook-sync: no token yet"; return 0; fi
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$tok" | base64 | tr -d '\n')"
  export GIT_CONFIG_VALUE_0
  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --quiet --depth 1 origin main && git -C "$dest" reset --quiet --hard FETCH_HEAD && echo "notebook-sync: at $(git -C "$dest" rev-parse --short HEAD)" || echo "notebook-sync: fetch failed"
  else
    rm -rf "$dest.tmp"
    git clone --quiet --depth 1 --branch main {{ .v.feed.notebookRepo | quote }} "$dest.tmp" && mv "$dest.tmp" "$dest" && echo "notebook-sync: cloned $(git -C "$dest" rev-parse --short HEAD)" || echo "notebook-sync: clone failed"
  fi
  return 0
}
{{- if .once }}
sync
exit 0
{{- else }}
while true; do sync; sleep {{ .v.feed.syncSeconds }}; done
{{- end }}
{{- end -}}
