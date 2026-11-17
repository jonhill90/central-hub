#!/bin/bash
# /usr/local/libexec/agent-box/vps-host.sh: the pipeline job for the VPS apps host (D-0046). It runs as user
# `keys` through sudo; the box signs in to the VPS by Tailscale SSH, so no SSH key is involved. Installed by
# the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/vps-host.sh bootstrap        (S3, once, as root, before the narrowing)
#   sudo -n -u keys /usr/local/libexec/agent-box/vps-host.sh apply            (as deploy: vps-apply host <main's commit>)
#   sudo -n -u keys /usr/local/libexec/agent-box/vps-host.sh secrets [rotate] (as deploy: vps-apply secrets, S5)
#   sudo -n -u keys /usr/local/libexec/agent-box/vps-host.sh status|log
# bootstrap: runs hosts/ansible/playbooks/vps-app-host.yml from origin/main over SSH as root. It works only
#   while the tailnet lets the box sign in as root (S1 to S4); after S4 it is refused by the tailnet itself.
# apply, secrets, status: sign in as deploy, whose sudo on the VPS allows vps-apply only.
# What is printed (and so what GitHub's public run log holds): the action, the commit, pass or fail. Never
# the VPS's name or any value. Full output stays on the box in {work}/logs/vps-host/.
set -euo pipefail
umask 077

work=/var/lib/agent-box
logs=$work/logs/vps-host
summary=$logs/summary.jsonl
settings=$work/vps-host.json
repo=$work/checkouts/vps-host   # this wrapper's own checkout of central-hub
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export ANSIBLE_COLLECTIONS_PATH=/usr/local/libexec/agent-box/collections ANSIBLE_HOME=$work/ansible-home

usage() { echo "usage: vps-host bootstrap|apply|secrets [rotate]|status|log" >&2; exit 2; }
case "${1:-}:${2:-}:$#" in
  bootstrap::1 | apply::1 | secrets::1 | status::1 | log::1) action=$1 ;;
  secrets:rotate:2) action="secrets rotate" ;;
  *) usage ;;
esac

if [[ $action == log ]]; then
  [[ -s $summary ]] || { echo "vps-host: no run has been logged yet" >&2; exit 1; }
  tail -n 5 -- "$summary"
  exit 0
fi

[[ -f $settings ]] || { echo "vps-host: $settings is missing; set agent_box_vps_host in the inventory and run the agent_box role" >&2; exit 1; }
name=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["name"])' "$settings")
[[ $name =~ ^[a-z0-9][a-z0-9.-]{0,252}$ ]] || { echo "vps-host: the name in $settings is not a host name; refused" >&2; exit 1; }

install -d -m 0700 "$logs" "$work/state" "$work/.ssh"
exec 9>"$work/state/vps-host.lock"
flock -n 9 || { echo "vps-host: another vps-host run is going; try again when it ends" >&2; exit 1; }

# Only reviewed code on main, never a checkout a session can edit.
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse HEAD)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
raw=$logs/run-$stamp.txt
: > "$raw"
echo "vps-host: $action, central-hub ${commit:0:12}"

record() { # result
  python3 -I -c 'import json, sys
a = sys.argv
print(json.dumps({"time": a[1], "action": a[2], "commit": a[3], "result": a[4]}))' \
    "$stamp" "$action" "$commit" "$1" >> "$summary"
}
ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$work/.ssh/known_hosts_vps")
as_deploy() { ssh "${ssh_opts[@]}" "deploy@$name" sudo -n /usr/local/sbin/vps-apply "$@"; }

case $action in
  bootstrap)
    inventory=$(mktemp --suffix=.json "$work/state/vps-host-inventory.XXXXXX")
    # shellcheck disable=SC2064
    trap "rm -f '$inventory'" EXIT
    python3 -I -c 'import json, sys
json.dump({"vps_app_host": {"hosts": {"vps": {"ansible_host": sys.argv[1], "ansible_user": "root"}}}}, open(sys.argv[2], "w"))' \
      "$name" "$inventory"
    if (cd "$repo/hosts/ansible" && ANSIBLE_SSH_ARGS="${ssh_opts[*]}" ansible-playbook -i "$inventory" playbooks/vps-app-host.yml) >> "$raw" 2>&1; then
      record ok; echo "vps-host: bootstrap ok"
    else
      record "FAIL: bootstrap"; echo "vps-host: FAIL: bootstrap (details in the box's log $raw)" >&2; exit 1
    fi
    ;;
  apply)
    if as_deploy host "$commit" >> "$raw" 2>&1; then
      record ok; echo "vps-host: apply of ${commit:0:12} ok"
    else
      record "FAIL: apply"; echo "vps-host: FAIL: apply (details in the box's log $raw)" >&2; exit 1
    fi
    ;;
  secrets | "secrets rotate")
    # vps-apply prints names and counts only, never a value.
    # shellcheck disable=SC2086
    if as_deploy $action 2>&1 | tee -a "$raw"; then
      record ok
    else
      record "FAIL: $action"; echo "vps-host: FAIL: $action" >&2; exit 1
    fi
    ;;
  status)
    as_deploy status 2>&1 | tee -a "$raw"
    ;;
esac
