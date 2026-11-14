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
apikey=/etc/agent-keys/prod/opnsense-api.txt   # key=/secret= lines (OPNsense's download) or two bare lines, key then secret
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

# The key file is either OPNsense's own download format (lines key=... and secret=...) or the controller's
# file from set-up-lab-network-and-firewall.md step 6: two bare lines, the key first, then the secret.
# CR, spaces around "=" and quotes are tolerated; any other shape is refused without printing a value.
parsed=$(python3 -I -c '
import re, sys
lines = [l.strip() for l in open(sys.argv[1], encoding="ascii", errors="replace").read().replace("\r", "").split("\n")]
lines = [l for l in lines if l]
kv = {}
for l in lines:
    m = re.fullmatch(r"(key|secret)\s*=\s*(.*)", l)
    if m:
        kv.setdefault(m.group(1), m.group(2).strip().strip("\"\x27"))
if "key" in kv and "secret" in kv:
    key, secret = kv["key"], kv["secret"]
elif len(lines) == 2 and not kv:
    key, secret = lines
else:
    sys.exit(1)
if not re.fullmatch(r"[A-Za-z0-9+/=_-]+", key) or not re.fullmatch(r"[A-Za-z0-9+/=_-]+", secret):
    sys.exit(1)
print(key); print(secret)
' "$apikey") || { echo "opnsense-backup: $apikey is neither key=/secret= lines nor two lines (key, then secret)" >&2; exit 1; }
key=$(printf '%s\n' "$parsed" | sed -n 1p)
secret=$(printf '%s\n' "$parsed" | sed -n 2p)
[[ -n $key && -n $secret ]] || { echo "opnsense-backup: $apikey has an empty key or secret" >&2; exit 1; }
printf 'user = "%s:%s"\n' "$key" "$secret" | curl -sS --fail --max-time 60 -K - -o "$tmp" "https://$host/api/core/backup/download/this"

head -c 4096 "$tmp" | grep -q '<opnsense>' || { echo "opnsense-backup: what came back is not an OPNsense configuration; kept the older copies" >&2; exit 1; }
mv "$tmp" "$dest/config-$stamp.xml"
trap - EXIT
# Keep the newest $keep copies.
find "$dest" -maxdepth 1 -name 'config-*.xml' -printf '%f\n' | sort -r | tail -n +"$((keep + 1))" | while read -r old; do rm -f "$dest/$old"; done
echo "opnsense-backup: kept config-$stamp.xml ($(find "$dest" -maxdepth 1 -name 'config-*.xml' | wc -l) copies)"
