#!/bin/bash
# /usr/local/libexec/agent-box/opnsense-backup.sh: keep a fresh copy of OPNsense's configuration on the
# box, so a rebuilt firewall can be restored from it (pick 220, docs/runbooks/set-up-the-box-lifeline.md).
# Runs as user `keys` from the box's daily timer; no session runs it, so it has no sudo line. It reads
# the API key from the keys folder, fetches the configuration over HTTPS and keeps the newest copies in
# {work}/opnsense-backup (folder 0700, files 0600). The key goes to curl on stdin, never in an argument.
# A copy is kept only if it is an OPNsense configuration (root element <opnsense>); a failed fetch keeps
# the older copies and fails the run.
set -euo pipefail
umask 077

work=/var/lib/agent-box
settings=$work/opnsense-backup.json   # host and keep: written by the agent_box role
apikey=/etc/agent-keys/prod/opnsense-api.txt   # key=... and secret=... lines, as OPNsense's download gives them
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

[[ -f $settings ]] || { echo "opnsense-backup: $settings is missing; set agent_box_opnsense_backup in the inventory and run the agent_box role" >&2; exit 1; }
[[ -f $apikey ]] || { echo "opnsense-backup: $apikey is missing; copy the controller's files (docs/runbooks/set-up-the-agent-box.md)" >&2; exit 1; }

host=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["host"])' "$settings")
keep=$(python3 -I -c 'import json,sys; print(int(json.load(open(sys.argv[1]))["keep"]))' "$settings")
[[ $host =~ ^[A-Za-z0-9.-]+$ ]] || { echo "opnsense-backup: the host setting is not a name or an address" >&2; exit 1; }
[[ $keep =~ ^[0-9]+$ ]] && (( keep >= 3 && keep <= 60 )) || { echo "opnsense-backup: keep must be from 3 to 60" >&2; exit 1; }

dest=$work/opnsense-backup
install -d -m 0700 "$dest"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
tmp=$(mktemp "$dest/.fetch.XXXXXX")
trap 'rm -f "$tmp"' EXIT

key=$(sed -n 's/^key=//p' "$apikey" | head -n1)
secret=$(sed -n 's/^secret=//p' "$apikey" | head -n1)
[[ -n $key && -n $secret ]] || { echo "opnsense-backup: $apikey has no key= and secret= lines" >&2; exit 1; }
printf 'user = "%s:%s"\n' "$key" "$secret" | curl -sS --fail --max-time 60 -K - -o "$tmp" "https://$host/api/core/backup/download/this"

head -c 4096 "$tmp" | grep -q '<opnsense>' || { echo "opnsense-backup: what came back is not an OPNsense configuration; kept the older copies" >&2; exit 1; }
mv "$tmp" "$dest/config-$stamp.xml"
trap - EXIT
# Keep the newest $keep copies.
find "$dest" -maxdepth 1 -name 'config-*.xml' -printf '%f\n' | sort -r | tail -n +"$((keep + 1))" | while read -r old; do rm -f "$dest/$old"; done
echo "opnsense-backup: kept config-$stamp.xml ($(find "$dest" -maxdepth 1 -name 'config-*.xml' | wc -l) copies)"
