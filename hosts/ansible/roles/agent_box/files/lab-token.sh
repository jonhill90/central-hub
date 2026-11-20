#!/bin/bash
# /usr/local/libexec/agent-box/lab-token.sh: makes the agents' lab token (agentlab@pve!lab) on the Proxmox host and stores it on the
# box for rebuild-prod, so prod's check no longer fails on a missing /etc/agent-keys/proxmox-lab.env. It runs as `hostops`, which
# holds the host key, and hands the secret to lab-token-put.sh (as the keys user) on a pipe. Installed by the agent_box role.
#   sudo -n -u hostops /usr/local/libexec/agent-box/lab-token.sh status   whether the host has the token and the box has the file
#   sudo -n -u hostops /usr/local/libexec/agent-box/lab-token.sh mint <go id>   makes the token (privsep, expiring in 30 days) and
#     stores it. <go id> is the message id of the owner's standing go (D-0061, cmsg_...); it is checked for shape and written to the
#     box's log line, so the trail names the go. The wrapper can't check the go itself.
# mint refuses when the box already has the file or the host already has the token: a renewal is a delete (`pveum user token remove`)
# and waits on its own go. If storing fails after the host made the token, mint removes that token again, so no secret is left
# that nothing holds. It prints no secret, no address and no key: only what it did.
# After a mint, run the agent-access job (proxmox-host.sh apply-recorded agent-access ...) once: a privilege-separated token has
# only its own ACLs, and agent-access.sh adds them once the token exists (runbook step 4).
set -euo pipefail
umask 077
dir=/etc/agent-keys-host
libexec=/usr/local/libexec/agent-box
inventory=$dir/inventory/hosts.yml
action=${1:-} go=''
case $action in
  status) [[ $# -eq 1 ]] || { echo "usage: lab-token status|mint <go id>" >&2; exit 2; } ;;
  mint)
    [[ $# -eq 2 && $2 =~ ^cmsg_[A-Za-z0-9]{20,60}$ ]] || { echo "usage: lab-token mint <go id: cmsg_...>" >&2; exit 2; }
    go=$2 ;;
  *) echo "usage: lab-token status|mint <go id>" >&2; exit 2 ;;
esac
[[ -f $inventory && -f $dir/id_ed25519 && -f $dir/known_hosts ]] || { echo "lab-token: no inventory or key in $dir; the controller's install has not run" >&2; exit 1; }
address=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["proxmox"]["hosts"]["proxmox_host"]["ansible_host"])' "$inventory")
[[ $address =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "lab-token: the inventory's host address is not an IPv4 address" >&2; exit 1; }
host() { ssh -n -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$dir/known_hosts" -i "$dir/id_ed25519" "root@$address" "$@"; }
put() { sudo -n -u keys "$libexec/lab-token-put.sh" "$@"; }
# A failed read (ssh timeout, a refusal) stops here: it must never look like "no token", or a later add that fails because the token
# exists would be rolled back by removing a token this run did not make.
list=$(host "pveum user token list agentlab@pve --output-format json") ||
  { echo "lab-token: could not read the host's token list; nothing was changed" >&2; exit 1; }
on_host=no
if grep -q '"tokenid":"lab"' <<< "$list"; then on_host=yes; fi
on_box=$(put exists </dev/null || true)
echo "lab-token: token on the host: $on_host; file on the box: ${on_box:-absent}"
[[ $action == status ]] && exit 0
[[ $on_host == no ]] || { echo "lab-token: the host already has agentlab@pve!lab; a renewal is a delete and waits on its own go" >&2; exit 1; }
[[ $on_box != present ]] || { echo "lab-token: the box already has proxmox-lab.env; nothing was made" >&2; exit 1; }
expire=$(( $(date +%s) + 30 * 24 * 3600 ))
echo "lab-token: mint under the standing go $go"
made=no
json=$(host "pveum user token add agentlab@pve lab --privsep 1 --expire $expire --output-format json") && made=yes
if [[ $made == yes ]] && printf '%s' "$json" | put put; then
  echo "lab-token: PASS: token made on the host (expires in 30 days) and stored on the box; run the agent-access job next"
else
  # Remove the host's token only when this run's own add made it.
  if [[ $made == yes ]]; then
    host "pveum user token remove agentlab@pve lab" >/dev/null 2>&1 || true
    echo "lab-token: FAIL: storing the token failed; the host's token was removed again" >&2
  else
    echo "lab-token: FAIL: the host did not make the token; nothing was removed" >&2
  fi
  exit 1
fi
