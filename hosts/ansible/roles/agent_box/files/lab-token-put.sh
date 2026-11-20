#!/bin/bash
# /usr/local/libexec/agent-box/lab-token-put.sh: puts the agents' lab token on the box, as the keys user. Only lab-token.sh (run as
# hostops, which holds the host key) may call it; a session can't (sudoers gives it no argument here). Installed by the agent_box
# role; root owns it.
#   lab-token-put.sh exists       exit 0 and print "present" if /etc/agent-keys/proxmox-lab.env is there, else exit 1 and print "absent"
#   lab-token-put.sh put          reads the host's `pveum user token add ... --output-format json` on stdin and writes
#                                 /etc/agent-keys/proxmox-lab.env (0600, keys): the API URL line copied from proxmox-dev.env, and
#                                 PROXMOX_VE_API_TOKEN=agentlab@pve!lab=<secret>. Refuses to replace a file already there.
# The secret is never printed, and the JSON is never kept: it is read into a variable and the file is written once.
# Why a second wrapper: hostops may not read the keys folder, and the keys user may not read hostops's key, so the secret crosses
# once, on a pipe, between two users that each hold half (docs/runbooks/give-agents-proxmox-rights-for-the-whole-lab.md step 4).
set -euo pipefail
umask 077
keys=/etc/agent-keys
dest=$keys/proxmox-lab.env
dev=$keys/proxmox-dev.env
case ${1:-} in
  exists)
    [[ $# -eq 1 ]] || exit 2
    if [[ -e $dest ]]; then echo present; exit 0; fi
    echo absent; exit 1 ;;
  put)
    [[ $# -eq 1 ]] || exit 2
    [[ ! -e $dest ]] || { echo "lab-token-put: $dest already exists; remove it on purpose before a new token is stored" >&2; exit 1; }
    [[ -s $dev ]] || { echo "lab-token-put: $dev is missing, so there is no API URL to copy" >&2; exit 1; }
    endpoint=$(grep -E '^PROXMOX_VE_ENDPOINT=https://[A-Za-z0-9._:/-]+$' -- "$dev" | head -n 1 || true)
    [[ -n $endpoint ]] || { echo "lab-token-put: $dev has no PROXMOX_VE_ENDPOINT=https://... line" >&2; exit 1; }
    json=$(head -c 4096)
    secret=$(printf '%s' "$json" | python3 -I -c '
import json, re, sys
d = json.load(sys.stdin)
v = d.get("value", "")
fid = d.get("full-tokenid", "")
if fid != "agentlab@pve!lab" or not re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", v):
    sys.exit(1)
print(v)') || { echo "lab-token-put: the input is not the token agentlab@pve!lab with a UUID secret" >&2; exit 1; }
    tmp=$(mktemp -p "$keys" .proxmox-lab.XXXXXX)
    trap 'rm -f -- "$tmp"' EXIT
    printf '%s\nPROXMOX_VE_API_TOKEN=agentlab@pve!lab=%s\n' "$endpoint" "$secret" > "$tmp"
    chmod 600 -- "$tmp"
    ln -- "$tmp" "$dest"   # fails if a file appeared meanwhile, so it never replaces one
    echo "lab-token-put: wrote $dest (two lines, 0600); the secret was not printed" ;;
  *) echo "usage: lab-token-put exists|put" >&2; exit 2 ;;
esac
