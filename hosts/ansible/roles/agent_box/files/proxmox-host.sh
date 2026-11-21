#!/bin/bash
# /usr/local/libexec/agent-box/proxmox-host.sh: the pipeline job for the Proxmox host's web UI proxy (D-0041; Library
# plans/r1-host-job/DESIGN.md v3.1). It runs one of the named playbooks from main, and nothing else, on the Proxmox
# host as root, with the key in /etc/agent-keys-host/. It runs as user `hostops` through sudo, so no session and no
# other wrapper can read that key. Installed by the agent_box role; root owns it.
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh check [<job>]
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh apply [<job>] <pass message ID> <check hash, 12 hex>
# <job> names which one playbook runs: `proxy` (the default, playbooks/proxmox-proxy.yml), `opnsense-sso` (playbooks/opnsense-sso.yml: the firewall's web sign-in, installed through VM 100's guest agent; its secret is the one line in $dir/opnsense-sso.env), `sso` (playbooks/proxmox-sso.yml:
#   the web UI's sign-in through Keycloak; its client secret is the one line in $dir/proxmox-sso.env, read on the box by this
#   user only) or `agent-access` (playbooks/
#   proxmox-agent-access.yml: it copies hosts/terraform/home/bootstrap/agent-access.sh from the same commit to the host and
#   runs it as root, so the agents' Proxmox rights change by a reviewed PR and no longer need the Mac) or `firewall`
#   (playbooks/proxmox-firewall.yml, proxmox-safety.yml's firewall role alone: the host firewall, with the role's dead-man timer and its
#   checks before and after, D-0063 rule 4; its private values come from this job's inventory, written by the controller),
#   `memory` (playbooks/proxmox-memory.yml: read-only; `check memory` prints, per guest and per host counter, numbers and fixed words only,
#     the lines its REPORT task writes that match this wrapper's allowlist, so a session can see who holds the host's memory)
#   `ksm` and `ksm-off` (playbooks/proxmox-ksm.yml, proxmox-ksm-off.yml: kernel same-page merging on the host, on with a pinned pace and off again;
#     what it does: playbooks/tasks/proxmox-ksm.yml. A setting, so a session applies it only through `apply-recorded` with a reviewer pass and a go)
#   `connector` (playbooks/proxmox-connector.yml: read-only; `check connector` prints which of nine facts about container 900 are true: running, online, advertises and has approved a lab range,
#     forwards, has a lab route, reaches the management, prod and dev gateways; fixed words from the reviewed playbook, no name or address)
#   `connector-route` (playbooks/proxmox-connector-route.yml: puts the lab route unit back in container 900, the tailnet connector, and proves the route to the prod and dev gateways
#     leaves by the management interface. A change inside CT 900, so a session applies it only through `apply-recorded` with a reviewer pass and a go)
#   `guests` (playbooks/proxmox-guests.yml: read-only; `check guests` prints which of container 259 and VM 258 exist, so a session on the box can tell)
#   `ct259-destroy` (playbooks/proxmox-ct259-destroy.yml: deletes the rehearsal's container CT 259 after tag, privilege and mount-point guards.
#     A delete, so a session applies it only through `apply-recorded` with a reviewer pass and a go)
#   `box-writer` (playbooks/proxmox-restic-box.yml: the user `boxbackup` for the agent box's own backups, replacing Azure for them: one key, only from
#     the address this job runs from, only the folder /box on the backup disk, internal-sftp, no shell, no root. The public half of the box's key comes
#     from the handoff (dev-worker-address.sh read-box-key), in a vars file of this user's own and never on a command line. An access right, so a
#     session applies it only through `apply-recorded` with a reviewer pass and a go)
#   or `restore-reader` (playbooks/proxmox-restic-reader.yml: the proxmox_restic_sftp role's read-only user `c1restore` and the keys
#   that sign in as it, one per dev worker, each only from its own address; the list is in this job's inventory, written by the
#   controller. An access right, and the only one this job can grant: no write, no shell, no root).
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh log
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh guard arm|confirm|rollback|clear|status
# guard: the firewall VM's way back (playbooks/opnsense-guard.yml, D-0063 rule 4): a snapshot of the firewall's VM and a timer on
#   the host that rolls it back unless the apply is confirmed. Not a change of the host's settings, so no check, pass or go: the
#   firewall's wrapper (opnsense-prod.sh, as guardops) calls arm before its apply and confirm or rollback after it. A session may
#   read the status, and clear a snapshot left by a rollback or a failed confirm (refused while the timer is armed).
# check: `--check --diff` on the code at origin/main. It saves a result file: the commit, the playbook, the
#   SHA-256 of every diff's before and after text, and for each task its name, whether it changed and whether it
#   was skipped. It prints the first 12 hex digits of that file's SHA-256: the hash the agents pass (D-0041 rule 6).
# apply: checks again and refuses unless the new hash is the one named, so a new commit on main or a host that
#   changed since stops it. Then it runs the playbook, and fails the run if a task changed that the check showed
#   neither changed nor skipped (D-0041 rule 4). An Ansible run can't be held back part-way, so that comparison
#   comes after the run; the role's own proofs and roll-back guard the host during it. The pass's message ID is
#   required and goes into both logs. The box can't check the pass itself; a reviewing agent does, before the job.
# log: the newest runs' summary lines.
# The box's own apply (D-0042 rule 2's shape, for a host job): no workflow dispatch and so no new token. A session on the box runs
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh apply-recorded [<job>] <check hash, 12 hex>
# which re-checks main's head and refuses, naming each thing missing, unless (1) that check gives the hash named, (2) the job's
# ledger holds a reviewer pass for this job, this commit and this hash, and (3) it holds a go, recorded by the orchestrator from
# the owner's own words, for this job and this commit, whose line (its message ID) no earlier apply used. Every job needs the go: sso and agent-access
# change access rights, and the proxy changes what the host listens on; the wrapper can't tell from a diff which of its changes
# touch the firewall, so it asks for the go on all three. The ledger is this user's own folder, written only by these actions:
#   sudo -n -u hostops .../proxmox-host.sh pass [<job>] <commit, 40 hex> <check hash> <pass message ID> <ISO time> reviewer
#   sudo -n -u hostops .../proxmox-host.sh go [<job>] <commit, 40 hex> <go message ID> <ISO time> orchestrator
#   sudo -n -u hostops .../proxmox-host.sh ledger [<job>]
# Any session can name itself the reviewer or the orchestrator, so a ledger line proves a recorder's word and the message ID it
# gave, not the owner's; the pass-record ledger has the same limit (its header says so). The runner's three-argument `apply` below
# is unchanged and is not gated by the ledger.
# What is printed (and so what GitHub's public run log holds): the commit, the hash, counts of tasks, the pass ID,
# pass or fail. Never a task's diff, a host name or an address. The full output stays in {work}/logs/.
set -euo pipefail
umask 077

dir=/etc/agent-keys-host
work=/var/lib/agent-box-host
libexec=/usr/local/libexec/agent-box
ansible_bin=$libexec/ansible-venv/bin
collections=$libexec/collections
repo_url=https://github.com/jonhill90/central-hub.git   # public; the reviewed code this job runs
declare -A jobs=([proxy]=playbooks/proxmox-proxy.yml [agent-access]=playbooks/proxmox-agent-access.yml [sso]=playbooks/proxmox-sso.yml [opnsense-sso]=playbooks/opnsense-sso.yml [firewall]=playbooks/proxmox-firewall.yml [guests]=playbooks/proxmox-guests.yml [connector]=playbooks/proxmox-connector.yml [connector-route]=playbooks/proxmox-connector-route.yml [ct259-destroy]=playbooks/proxmox-ct259-destroy.yml [restore-reader]=playbooks/proxmox-restic-reader.yml [memory]=playbooks/proxmox-memory.yml [ksm]=playbooks/proxmox-ksm.yml [ksm-off]=playbooks/proxmox-ksm-off.yml [box-writer]=playbooks/proxmox-restic-box.yml)
inventory=$dir/inventory/hosts.yml
logs=$work/logs
summary=$logs/summary.jsonl
result=$work/state/check.json

ledger=$work/ledger
usage() {
  echo "       proxmox-host guard arm|confirm|rollback|clear|status" >&2
  echo "usage: proxmox-host check [proxy|agent-access|sso|opnsense-sso|firewall|guests|connector|ct259-destroy|restore-reader|memory|ksm|ksm-off|box-writer]|apply [proxy|agent-access|sso|opnsense-sso|firewall|guests|connector|ct259-destroy|restore-reader|memory|ksm|ksm-off|box-writer] <pass message ID, cmsg_...> <check hash, 12 hex digits>|log" >&2
  echo "       proxmox-host apply-recorded [job] <check hash>|pass [job] <commit> <check hash> <cmsg_...> <ISO time> reviewer|go [job] <commit> <cmsg_...> <ISO time> orchestrator|ledger [job]" >&2
  exit 2
}

if [[ ${1:-} == log ]]; then
  [[ $# -eq 1 ]] || usage
  [[ -s $summary ]] || { echo "proxmox-host: no run has been logged yet" >&2; exit 1; }
  tail -n 5 -- "$summary"
  exit 0
fi
# An optional job name comes right after the action; with none, the job is the proxy.
action=${1:-} job=proxy
case $action in check | apply | apply-recorded | pass | go | ledger)
  if [[ -n ${2:-} && -n ${jobs[${2:-x}]:-} ]]; then job=$2; set -- "$action" "${@:3}"; fi ;;
esac
playbook=${jobs[$job]}
ref_ok() { [[ $1 =~ ^cmsg_[A-Za-z0-9]{10,80}$ ]]; }
case $action in
  check) [[ $# -eq 1 ]] || usage ;;
  apply)
    [[ $# -eq 3 && ${2:-} =~ ^cmsg_[A-Za-z0-9]{10,80}$ && ${3:-} =~ ^[0-9a-f]{12}$ ]] || usage
    pass_ref=$2; want=$3 ;;
  apply-recorded)
    [[ $# -eq 2 && ${2:-} =~ ^[0-9a-f]{12}$ ]] || usage
    want=$2 ;;
  pass)
    [[ $# -eq 6 && $2 =~ ^[0-9a-f]{40}$ && $3 =~ ^[0-9a-f]{12}$ && $5 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ref_ok "$4" || usage
    [[ $6 == reviewer ]] || { echo "proxmox-host: a pass is recorded by the reviewer only" >&2; exit 2; } ;;
  go)
    [[ $# -eq 5 && $2 =~ ^[0-9a-f]{40}$ && $4 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ref_ok "$3" || usage
    [[ $5 == orchestrator ]] || { echo "proxmox-host: a go is recorded by the orchestrator only, from the owner's own words" >&2; exit 2; } ;;
  ledger) [[ $# -eq 1 ]] || usage ;;
  guard) [[ $# -eq 2 && $2 =~ ^(arm|confirm|rollback|clear|status)$ ]] || usage
    guard_action=$2 playbook=playbooks/opnsense-guard.yml ;;
  *) usage ;;
esac

# The ledger actions need no key and no inventory. Each line says who recorded it, with which message ID, and when.
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
ledger_line() { # kind, then key=value pairs; prints one JSON line
  python3 -I -c 'import json, sys
d = dict(a.split("=", 1) for a in sys.argv[2:])
d["kind"] = sys.argv[1]
print(json.dumps(d, sort_keys=True))' "$@"
}
case $action in
  pass)
    install -d -m 0700 "$ledger"
    ledger_line pass "job=$job" "commit=$2" "hash=$3" "relay_ref=$4" "relay_time=$5" "recorder=$6" "box_time=$(now)" >> "$ledger/pass-$job-$2-$3.jsonl"
    echo "proxmox-host: reviewer pass recorded for job $job, commit ${2:0:12}, check $3"
    exit 0 ;;
  go)
    install -d -m 0700 "$ledger"
    ledger_line go "job=$job" "commit=$2" "relay_ref=$3" "relay_time=$4" "recorder=$5" "box_time=$(now)" >> "$ledger/go-$job-$2.jsonl"
    echo "proxmox-host: go recorded for job $job, commit ${2:0:12}"
    exit 0 ;;
  ledger)
    [[ -d $ledger ]] || { echo "proxmox-host: the ledger is empty"; exit 0; }
    for f in "$ledger"/pass-"$job"-*.jsonl "$ledger"/go-"$job"-*.jsonl; do
      [[ -f $f ]] || continue
      cat -- "$f"; [[ ! -s ${f%.jsonl}.used ]] || sed "s/^/(used: /;s/$/)/" "${f%.jsonl}.used"
    done
    exit 0 ;;
esac

[[ -f $inventory && -f $dir/id_ed25519 && -f $dir/known_hosts ]] \
  || { echo "proxmox-host: no inventory or key in $dir; the install from the controller has not run (docs/runbooks/serve-proxmox-on-443.md)" >&2; exit 1; }
# Publish the host's public host key (two fields: type and key, public data) for the keys user's rebuild wrapper, which pins it for dev's
# worker (dev-worker-address.sh key). Written from this job's own known_hosts, by this user, into a folder it owns and the devaddr group reads;
# best effort, never a stop. It is the key the host job itself already trusts.
# Files this user makes carry its own group, so the file is given the handoff group (the keys user is in it) before it is moved into place.
hostkey_dir=/var/lib/agent-box-hostkey
handoff_group=devaddr
publish() { # <file in the hostkey folder> <text>: atomically, mode 0640, group devaddr; best effort
  local f=$hostkey_dir/$1 tmp=$hostkey_dir/$1.part
  [[ -d $hostkey_dir ]] || return 0
  printf '%s\n' "$2" > "$tmp" && chmod 0640 "$tmp" && chgrp "$handoff_group" "$tmp" && mv -f -- "$tmp" "$f" || rm -f -- "$tmp"
}
if [[ -d $hostkey_dir ]]; then
  hk=$(python3 -I -c '
import sys
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) == 3 and f[1] == "ssh-ed25519":
        print(f[1] + " " + f[2])
        break' "$dir/known_hosts" 2>/dev/null || true)
  [[ -z $hk ]] || publish proxmox-host.pub "$hk"
fi

# The sso job reads the proxmox client's secret from one file of this user's own, made by the controller's run (tag
# proxmox_host_inventory); the playbook is told its path, so it never looks in the controller's home or the keys user's folder.
sso_args=()
if [[ $job == sso ]]; then
  [[ -s $dir/proxmox-sso.env ]] \
    || { echo "proxmox-host: $dir/proxmox-sso.env is missing; the controller's proxmox_host_inventory run makes it (docs/runbooks/sign-in-to-proxmox-through-keycloak.md)" >&2; exit 1; }
  sso_args=(-e "proxmox_sso_values_file=$dir/proxmox-sso.env")
fi

# The opnsense-sso job (role opnsense_sso) reads the opnsense client's secret from one file of this user's own, $dir/opnsense-sso.env.
# The box's prod identity.env holds the secret (c1-ansible's identity-values makes it, the one Keycloak's realm reads), and only the keys
# user can read that file, so this user asks the keys user's opnsense-sso-secret.sh for the one line, on a pipe, and keeps it 0600.
# It is never printed here. A check and an apply both refresh it, so the job always uses what Keycloak holds.
if [[ $job == opnsense-sso ]]; then
  os_line=$(sudo -n -u keys "$libexec/opnsense-sso-secret.sh" read) \
    || { echo "proxmox-host: the keys user has no OPNSENSE_CLIENT_SECRET to hand over (run c1-ansible identity-values; docs/runbooks/sign-in-to-opnsense-through-keycloak.md)" >&2; exit 1; }
  [[ $os_line =~ ^OPNSENSE_CLIENT_SECRET=[0-9a-f]{64}$ ]] || { echo "proxmox-host: the handed-over secret line is malformed" >&2; exit 1; }
  ( umask 077; printf '%s\n' "$os_line" > "$dir/opnsense-sso.env.new" ) && mv -f -- "$dir/opnsense-sso.env.new" "$dir/opnsense-sso.env"
  unset os_line
  sso_args=(-e "opnsense_sso_values_file=$dir/opnsense-sso.env")
fi

# The restore-reader job lets in the dev worker's address, read from the handoff the keys user's rebuild wrapper writes while dev is up
# (dev-worker-address.sh; it prints the address only to this capture). No file, no worker: the job stops, since a reader key with no
# address to work from would be a key that works from nowhere. The address goes to the playbook in a vars file of this user's own,
# mode 0600, deleted when the run ends; never on a command line.
rr_args=()
if [[ $job == restore-reader ]]; then
  rr_addr=$("$libexec/dev-worker-address.sh" read) || exit 1
  [[ -n $rr_addr ]] || { echo "proxmox-host: no dev worker address (the handoff file is missing: dev has no worker up); restore-reader stops" >&2; exit 1; }
  install -d -m 0700 "$work/state"
  rr_vars=$(mktemp "$work/state/rr-vars.XXXXXX")
  trap 'rm -f "$rr_vars"' EXIT
  # The worker's public key, from the same handoff (one ed25519 line, or nothing: the inventory's own list is used then).
  rr_key=$("$libexec/dev-worker-address.sh" read-key) || exit 1
  RR_ADDR=$rr_addr RR_KEY=$rr_key python3 -I -c 'import json, os, sys
v = {"proxmox_restic_reader_from": os.environ["RR_ADDR"]}
if os.environ.get("RR_KEY"): v["proxmox_restic_reader_key"] = os.environ["RR_KEY"]
json.dump(v, open(sys.argv[1], "w"))' "$rr_vars"
  rr_args=(-e "@$rr_vars")
fi

# The box-writer job lets in the box's own backup key and the one address it works from, read from the handoff (dev-worker-address.sh box-key makes
# the pair and hands over the public half and the address). No key or no address, no job. It goes to the playbook in a vars file of this user's own, mode 0600, deleted when the run ends; never on a command line.
bw_args=()
if [[ $job == box-writer ]]; then
  bw_key=$("$libexec/dev-worker-address.sh" read-box-key) || exit 1
  bw_addr=$("$libexec/dev-worker-address.sh" read-box-address) || exit 1
  [[ -n $bw_key && -n $bw_addr ]] || { echo "proxmox-host: no box backup key or address (the handoff files are missing: run dev-worker-address.sh box-key as the keys user); box-writer stops" >&2; exit 1; }
  install -d -m 0700 "$work/state"
  bw_vars=$(mktemp "$work/state/bw-vars.XXXXXX")
  trap 'rm -f "$bw_vars"' EXIT
  BW_KEY=$bw_key BW_ADDR=$bw_addr python3 -I -c 'import json, os, sys; json.dump({"proxmox_restic_box_key": os.environ["BW_KEY"], "proxmox_restic_box_from": os.environ["BW_ADDR"]}, open(sys.argv[1], "w"))' "$bw_vars"
  bw_args=(-e "@$bw_vars")
fi

repo=$work/checkout   # this wrapper's own checkout of central-hub
# The firewall job runs with the shared VLAN file from the same checkout (the job's
# inventory is one file, so the inventory folder's group_vars are not next to it).
fw_args=()
if [[ $job == firewall ]]; then
  fw_args=(-e "@$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml")
  # The host's own firewall drops ssh from any source outside its management set, so the box's backup address (the one address its
  # restic sftp works from, handed over by dev-worker-address.sh box-key) gets one more IN rule, tcp 22 from that address alone. No address
  # in the handoff: no rule, and the job runs as before. It reaches the playbook in a vars file of this user's own, never on a command line.
  fw_addr=$("$libexec/dev-worker-address.sh" read-box-address) || exit 1
  # The same holds for dev's worker, whose read-only restore user (job restore-reader) the host's sshd lets in from that worker's address
  # alone: its address, from the same handoff as restore-reader's, gets one more IN rule, tcp 22 from that address alone (prod run 6 and dev
  # run 2, 2026-11-21: with the host firewall on, dev's restore over sftp got "Connection closed" after 20 s). No file: no rule.
  dw_addr=$("$libexec/dev-worker-address.sh" read) || exit 1
  if [[ -n $fw_addr || -n $dw_addr ]]; then
    install -d -m 0700 "$work/state"
    fw_vars=$(mktemp "$work/state/fw-vars.XXXXXX")
    trap 'rm -f "$fw_vars"' EXIT
    FW_ADDR=$fw_addr DW_ADDR=$dw_addr python3 -I -c 'import json, os, sys
v = {}
if os.environ["FW_ADDR"]: v["proxmox_firewall_box_ssh_source"] = os.environ["FW_ADDR"]
if os.environ["DW_ADDR"]: v["proxmox_firewall_reader_ssh_source"] = os.environ["DW_ADDR"]
json.dump(v, open(sys.argv[1], "w"))' "$fw_vars"
    fw_args+=(-e "@$fw_vars")
  fi
fi
export HOME=$work PATH=$ansible_bin:/usr/local/bin:/usr/bin:/bin
export ANSIBLE_CONFIG=$repo/hosts/ansible/ansible.cfg ANSIBLE_COLLECTIONS_PATH=$collections ANSIBLE_HOME=$work/ansible-home
export ANSIBLE_STDOUT_CALLBACK=ansible.posix.json ANSIBLE_NOCOLOR=1 ANSIBLE_RETRY_FILES_ENABLED=0

install -d -m 0700 "$logs" "$work/state"
# Only reviewed code on main runs with the key, never a checkout a session can edit. One run at a time.
exec 9>"$work/state/proxmox-host.lock"
flock -n 9 || { echo "proxmox-host: another proxmox-host run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$repo_url" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse HEAD)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
if [[ $action == guard ]]; then
  # The guard runs on its own: no check, hash or ledger. It prints one line: what it did, or why it failed.
  out=$logs/guard-$guard_action-$stamp.json
  rc=0
  (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory" "$playbook" -e "opnsense_guard_action=$guard_action") > "$out" 2>> "$logs/run-$stamp.err" || rc=$?
  msg=$(python3 -I - "$out" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("no result"); sys.exit()
said, changed, failed = "", 0, ""
for play in data.get("plays", []):
    for t in play.get("tasks", []):
        for r in t.get("hosts", {}).values():
            if t["task"]["name"] == "Status" and not r.get("skipped"):
                said = r.get("msg", said)
            changed += bool(r.get("changed"))
            if r.get("failed") and not failed:
                failed = t["task"]["name"]
print(f"failed at: {failed}" if failed else said or f"{changed} step(s) changed")
PY
)
  python3 -I -c 'import json, sys
a = sys.argv
print(json.dumps({"job": "proxmox-host", "time": a[1], "action": "guard " + a[2], "commit": a[3], "result": a[4]}))' \
    "$stamp" "$guard_action" "$commit" "$([[ $rc == 0 ]] && echo ok || echo FAIL): $msg" >> "$summary"
  if [[ $rc != 0 ]]; then echo "proxmox-host: FAIL: guard $guard_action, $msg (details in the box's log $out)" >&2; exit 1; fi
  echo "proxmox-host: guard $guard_action, central-hub ${commit:0:12}: $msg"
  exit 0
fi
echo "proxmox-host: central-hub ${commit:0:12}, job $job"

# One JSON line per run for the box's own record; stdout gets the same facts, none of them private.
record() { # hash, counts, result
  python3 -I -c 'import json, sys
a = sys.argv
print(json.dumps({"job": "proxmox-host", "time": a[1], "action": a[2], "commit": a[3], "hash": a[4], "tasks": a[5], "pass": a[6], "result": a[7]}))' \
    "$stamp" "$action" "$commit" "$1" "$2" "${pass_ref:-}" "$3" >> "$summary"
}

play() { # out-file, extra ansible-playbook arguments...
  local out=$1; shift
  (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory" "$playbook" ${sso_args[@]+"${sso_args[@]}"} ${fw_args[@]+"${fw_args[@]}"} ${rr_args[@]+"${rr_args[@]}"} ${bw_args[@]+"${bw_args[@]}"} "$@") > "$out" 2>> "$logs/run-$stamp.err"
}

# summarize <json output> <result file>: writes the result file and prints "<hash> <changed> <skipped> <tasks>".
# Only the before and after text of each diff is hashed, not its headers, which can name temporary files.
summarize() {
  python3 -I - "$1" "$2" "$commit" "$playbook" <<'PY'
import hashlib, json, sys
out, dest, commit, playbook = sys.argv[1:5]
data = json.load(open(out))
tasks, diffs = [], []
def diff_parts(r):
    d = r.get("diff")
    for x in (d if isinstance(d, list) else [d] if d else []):
        if isinstance(x, dict):
            diffs.append([x.get("before"), x.get("after"), x.get("prepared")])
for play in data.get("plays", []):
    for t in play.get("tasks", []):
        name = t["task"]["name"]
        for host, r in sorted(t.get("hosts", {}).items()):
            diff_parts(r)
            for item in r.get("results", []) if isinstance(r.get("results"), list) else []:
                if isinstance(item, dict):
                    diff_parts(item)
            tasks.append({"name": name, "host": host, "changed": bool(r.get("changed")), "skipped": bool(r.get("skipped"))})
blob = json.dumps(diffs, sort_keys=True, separators=(",", ":"), default=str).encode()
res = {"commit": commit, "playbook": playbook, "diff_sha256": hashlib.sha256(blob).hexdigest(), "tasks": tasks}
text = json.dumps(res, sort_keys=True, separators=(",", ":"))
open(dest, "w").write(text + "\n")
print(hashlib.sha256(text.encode()).hexdigest()[:12], sum(t["changed"] for t in tasks), sum(t["skipped"] for t in tasks), len(tasks))
PY
}

# has_line <file> <recorder> <kind> <job> [<key> <value>]... [--unspent <used file>]: prints the relay_ref of the first line that
# has all of them and, with --unspent, whose relay_ref is not the third word of a line of the used file.
has_line() {
  [[ -s $1 ]] || return 0
  python3 -I - "$@" <<'PY'
import json, os, sys
path, recorder, kind, job, *kv = sys.argv[1:]
spent = set()
if "--unspent" in kv:
    i = kv.index("--unspent")
    used = kv[i + 1]
    kv = kv[:i]
    if os.path.exists(used):
        spent = {l.split()[2] for l in open(used) if len(l.split()) >= 3}
want = {"recorder": recorder, "kind": kind, "job": job, **dict(zip(kv[::2], kv[1::2]))}
for line in open(path):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if all(d.get(k) == v for k, v in want.items()) and d.get("relay_ref", "") not in spent:
        print(d.get("relay_ref", ""))
        break
PY
}

# failed_tasks <json output>: the names of the tasks that failed or could not reach the host, for a session to read. Names
# come from the reviewed code; a task's message can hold private values, so it stays in the box's log (same as opnsense-prod.sh).
failed_tasks() {
  python3 -I - "$1" <<'PY' 2>/dev/null || echo "no readable result"
import json, sys
data = json.load(open(sys.argv[1]))
names = []
for play in data.get("plays", []):
    for t in play.get("tasks", []):
        for r in t.get("hosts", {}).values():
            if (r.get("failed") or r.get("unreachable")) and t["task"]["name"] not in names:
                names.append(t["task"]["name"])
print("; ".join(names) or "none (the run stopped before a task: see the box's log)")
PY
}

do_check() { # prints the hash line; returns non-zero if the check run failed
  local out=$logs/check-$stamp.json
  if ! play "$out" --check --diff; then
    return 1
  fi
  summarize "$out" "$result"
}

case $action in
  check)
    rm -f "$result"
    if ! line=$(do_check); then
      record none none "FAIL: check"; echo "proxmox-host: FAIL: check; failed task(s): $(failed_tasks "$logs/check-$stamp.json") (details in the box's log $logs/check-$stamp.json)" >&2; exit 1
    fi
    read -r hash changed skipped total <<< "$line"
    record "$hash" "$changed changed, $skipped skipped, $total tasks" ok
    echo "proxmox-host: check $hash: $changed changed, $skipped skipped, $total tasks"
    echo "proxmox-host: the agents' pass for an apply names this commit (${commit:0:12}) and this hash ($hash)"
    if [[ $job == memory ]]; then
      # The read-only memory job's answer: the lines of its REPORT task that match the allowlist, and nothing else (no name or address
      # can pass: every line is fixed words and digits).
      python3 -I - "$logs/check-$stamp.json" <<'PY'
import json, re, sys
ok = [re.compile(p) for p in (
    r"guest [0-9]{1,9} (qemu|lxc) [a-z]{1,12} maxmem [0-9]{1,9} mem [0-9]{1,9}",
    r"kvm id [0-9]{1,9} rss [0-9]{1,9}",
    r"kvm id [0-9]{1,9} merge (on|off)",
    r"host (memtotal|memavailable|swaptotal|swapfree|shmem) [0-9]{1,9}",
    r"host ksm (run|pages_shared|pages_sharing|sleep_millisecs|pages_to_scan|full_scans) [0-9]{1,12}",
    r"host ksmd (utime|stime) [0-9]{1,15}",
    r"host clk_tck [0-9]{1,6}")]
n = 0
for play in json.load(open(sys.argv[1])).get("plays", []):
    for t in play.get("tasks", []):
        if t["task"]["name"] != "memory | REPORT":
            continue
        for r in t.get("hosts", {}).values():
            msg = r.get("msg", "")
            for line in (msg if isinstance(msg, list) else str(msg).split("\n")):
                line = str(line).strip()
                if any(p.fullmatch(line) for p in ok):
                    print("proxmox-host: memory: " + line)
                    n += 1
print("proxmox-host: memory: %d line(s)" % n)
PY
    fi
    if [[ $job == connector ]]; then
      # The read-only job's answer: the FACT tasks that show as changed are the facts that are true (names come from the reviewed playbook).
      python3 -I - "$result" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))["tasks"]
print("proxmox-host: connector facts true: " + ("; ".join(x["name"].split("FACT ", 1)[1] for x in t if x["changed"] and "FACT " in x["name"]) or "none"))
PY
    fi
    if [[ $job == guests ]]; then
      # The read-only job's answer: its tasks that show as changed name a guest that exists (names come from the reviewed playbook).
      python3 -I - "$result" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))["tasks"]
print("proxmox-host: guests found: " + ("; ".join(x["name"].split("EXISTS ", 1)[1] for x in t if x["changed"] and "EXISTS " in x["name"]) or "none of the two named"))
PY
    fi
    ;;
  apply | apply-recorded)
    if ! line=$(do_check); then
      record none none "FAIL: re-check"; echo "proxmox-host: FAIL: the re-check before the apply failed; nothing applied; failed task(s): $(failed_tasks "$logs/check-$stamp.json")" >&2; exit 1
    fi
    read -r hash changed skipped total <<< "$line"
    if [[ $hash != "$want" ]]; then
      record "$hash" "$changed changed, $skipped skipped, $total tasks" "refused: hash"
      echo "proxmox-host: the check now gives $hash, not the hash named ($want): main or the host changed since; nothing applied" >&2
      exit 1
    fi
    if [[ $action == apply-recorded ]]; then
      # (2) a reviewer pass for this job, commit and hash; (3) an unused go for this job and commit. Every gap is named, then nothing runs.
      missing=()
      pf=$ledger/pass-$job-$commit-$hash.jsonl gf=$ledger/go-$job-$commit.jsonl
      pass_ref=$(has_line "$pf" reviewer pass "$job" commit "$commit" hash "$hash")
      go_any=$(has_line "$gf" orchestrator go "$job" commit "$commit")
      go_ref=$(has_line "$gf" orchestrator go "$job" commit "$commit" --unspent "${gf%.jsonl}.used")
      [[ -n $pass_ref ]] || missing+=("no reviewer pass for job $job, commit ${commit:0:12}, check $hash")
      if [[ -z $go_any ]]; then missing+=("no go for job $job, commit ${commit:0:12}")
      elif [[ -z $go_ref ]]; then missing+=("every go for job $job, commit ${commit:0:12} was used already; a new go is needed"); fi
      if [[ ${#missing[@]} -gt 0 ]]; then
        record "$hash" "$changed changed, $skipped skipped, $total tasks" "refused: ledger"
        echo "proxmox-host: refused, nothing applied: $(IFS=';'; echo "${missing[*]}")" >&2
        exit 1
      fi
      # That one go line, by its message ID, is spent before the playbook runs, so a run that fails part-way needs a new go line
      # (a new message ID, same commit); the other lines of the file stay as they were.
      printf '%s %s %s\n' "$stamp" "$hash" "$go_ref" >> "${gf%.jsonl}.used"
    fi
    out=$logs/apply-$stamp.json
    if ! play "$out" --diff; then
      record "$hash" "$changed changed" "FAIL: apply"
      echo "proxmox-host: FAIL: apply of check $hash (details in the box's log $out)" >&2; exit 1
    fi
    # Every task the apply changed must be one the check showed as changed or skipped.
    extra=$(python3 -I - "$out" "$result" "$out.extra" <<'PY'
import json, sys
done = json.load(open(sys.argv[1]))
shown = {(t["name"], t["host"]) for t in json.load(open(sys.argv[2]))["tasks"] if t["changed"] or t["skipped"]}
extra = set()
for play in done.get("plays", []):
    for t in play.get("tasks", []):
        for host, r in t.get("hosts", {}).items():
            if r.get("changed") and (t["task"]["name"], host) not in shown:
                extra.add(t["task"]["name"])
open(sys.argv[3], "w").write("".join(n + "\n" for n in sorted(extra)))   # the box's log only: task names
print(len(extra))
PY
)
    if [[ $extra != 0 ]]; then
      record "$hash" "$changed changed" "FAIL: $extra task(s) changed that the check did not show"
      echo "proxmox-host: FAIL: the apply changed $extra task(s) that check $hash did not show (D-0041 rule 4; details in $out)" >&2
      # The names are the repository's own task titles (never a diff, host name or address), so they may be printed.
      sed 's/^/proxmox-host:   unlisted task: /' "$out.extra" >&2
      exit 1
    fi
    record "$hash" "$changed changed, $skipped skipped, $total tasks" ok
    # restore-reader: say what it put on the host, so the box's rebuild wrapper switches dev to this target only when the key and its address
    # are really there (sha256 of the key line and the address; the key and the address themselves are not published here).
    if [[ $job == restore-reader ]]; then
      if [[ -n ${rr_key:-} ]]; then publish reader-applied "$(printf '%s\n%s\n' "$rr_key" "$rr_addr" | sha256sum | cut -c1-64)"; else rm -f -- "$hostkey_dir/reader-applied"; fi
    fi
    echo "proxmox-host: applied check $hash ($changed changed, $skipped skipped, $total tasks), pass $pass_ref"
    ;;
esac
