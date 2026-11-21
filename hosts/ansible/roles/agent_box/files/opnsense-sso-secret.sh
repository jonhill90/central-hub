#!/bin/bash
# /usr/local/libexec/agent-box/opnsense-sso-secret.sh: hands the opnsense client's secret from the box's prod identity.env (readable
# by the keys user only) to the host job's user, on a pipe. Only proxmox-host.sh (as hostops) may call it, so a session can't (sudoers
# gives it no argument here). Installed by the agent_box role; root owns it.
#   opnsense-sso-secret.sh read   prints the one line OPNSENSE_CLIENT_SECRET=<64 hex> to stdout, nothing else; exit 1 and no output if the file
#                                 or the line is missing or does not have that shape. No other argument is accepted.
# The caller keeps the line in its own 0600 file and never prints it. Nothing here writes a file or reads another key.
set -euo pipefail
umask 077
values=/etc/agent-keys/prod/identity.env
[[ ${1:-} == read && $# -eq 1 ]] || { echo "usage: opnsense-sso-secret read" >&2; exit 2; }
[[ -f $values && ! -L $values ]] || { echo "opnsense-sso-secret: no identity.env" >&2; exit 1; }
line=$(grep -E '^OPNSENSE_CLIENT_SECRET=[0-9a-f]{64}$' -- "$values" | head -n 1 || true)
[[ -n $line ]] || { echo "opnsense-sso-secret: identity.env has no OPNSENSE_CLIENT_SECRET line of 64 hex digits" >&2; exit 1; }
printf '%s\n' "$line"
