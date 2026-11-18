#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-prod.sh: the secrets-store wrapper for the store inside prod's c1 (D-0058).
# The same actions and guards as secrets-store.sh, which this runs with --prod first: the prod keys folder
# (/etc/agent-keys/prod), the prod settings (secrets-store-prod.json), and the prod inventory's store name, so a call
# never reaches dev's store with prod's keys or the other way round. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store-prod.sh recovery|status|snapshot|restore|...
set -euo pipefail
exec "$(dirname "$0")/secrets-store.sh" --prod "$@"
