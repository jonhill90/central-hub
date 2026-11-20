#!/bin/bash
# /usr/local/libexec/agent-box/dev-secrets.sh: the one place that decides when dev's secrets leave the box's disk
# (TASK-0362; the owner's "Delete at teardown" tap, 2026-11-20 03:12:59 UTC; docs/runbooks/make-the-box-secrets-bundle.md).
# Runs as user `keys`; no session runs it and it has no sudo line. Two callers, one rule:
#   dev-secrets.sh down     exit 0 only when the dev state file (dev-vms.tfstate) holds no VM, or does not exist (dev was
#                           never built, or a destroy of an empty state wrote none: rebuild.sh counts it as 0 VMs too); 1 when
#                           dev has a VM or the file can't be read (a number nobody saw is not a pass). secrets-bundle.sh asks it, and
#                           leaves the dev folder out of the daily bundle while dev is down.
#   dev-secrets.sh remove   if dev is down, delete the dev SOPS file of the apps' secrets (openbao-kv.sops.json) and say so.
#                           rebuild-k8s.sh's teardown stage runs it as TEARDOWN_HOOK, after the destroy, so every teardown
#                           path reaches it: `rebuild teardown`, `rebuild rebuild`, and the end of every full run under
#                           ephemeral-dev. Never anything else: the seal key's SOPS copy, the AppRole IDs, the CA and the
#                           Raft snapshots stay, because restore-rebuilt needs them.
# Each dev run's put-apps writes every one of the apps' values again, so the next run makes the file anew.
set -euo pipefail
umask 077
work=/var/lib/agent-box
keys=/etc/agent-keys
state=$work/state/dev-vms.tfstate
kvfile=$keys/dev/openbao-kv.sops.json
export PATH=/usr/local/bin:/usr/bin:/bin

# Prints the number of dev VMs in the state (0 when there is no state file), or nothing when it is unreadable.
vms() {
  [[ -e $state ]] || { echo 0; return; }
  python3 -I -c '
import json, sys
try:
    s = json.load(open(sys.argv[1]))
    print(sum(len(r.get("instances", [])) for r in s.get("resources", [])
              if r.get("type") == "proxmox_virtual_environment_vm" and r.get("mode") == "managed"))
except (OSError, ValueError, AttributeError, TypeError):
    pass' "$state" 2>/dev/null || true
}

is_down() { [[ $(vms) == 0 ]]; }

case ${1:-} in
  down) [[ $# -eq 1 ]] || { echo "usage: dev-secrets.sh down|remove" >&2; exit 2; }; is_down ;;
  remove)
    [[ $# -eq 1 ]] || { echo "usage: dev-secrets.sh down|remove" >&2; exit 2; }
    if ! is_down; then
      echo "dev-secrets: the dev state does not read as 0 VMs; ${kvfile##*/} kept" >&2
      exit 1
    fi
    if [[ -e $kvfile ]]; then
      rm -f -- "$kvfile" "$kvfile.part"
      echo "dev-secrets: dev state holds 0 VMs; deleted ${kvfile##*/} (the seal key's copy and the snapshots stay)"
    else
      echo "dev-secrets: dev state holds 0 VMs; no ${kvfile##*/} to delete"
    fi ;;
  *) echo "usage: dev-secrets.sh down|remove" >&2; exit 2 ;;
esac
