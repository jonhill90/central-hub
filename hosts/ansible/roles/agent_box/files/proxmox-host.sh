#!/bin/bash
# /usr/local/libexec/agent-box/proxmox-host.sh: the pipeline job for the Proxmox host's web UI proxy (D-0041; Library
# plans/r1-host-job/DESIGN.md v3.1). It runs one of three named playbooks from main, and nothing else, on the Proxmox
# host as root, with the key in /etc/agent-keys-host/. It runs as user `hostops` through sudo, so no session and no
# other wrapper can read that key. Installed by the agent_box role; root owns it.
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh check [<job>]
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh apply [<job>] <pass message ID> <check hash, 12 hex>
# <job> names which one playbook runs: `proxy` (the default, playbooks/proxmox-proxy.yml), `sso` (playbooks/proxmox-sso.yml:
#   the web UI's sign-in through Keycloak; its client secret is the one line in $dir/proxmox-sso.env, read on the box by this
#   user only) or `agent-access` (playbooks/
#   proxmox-agent-access.yml: it copies hosts/terraform/home/bootstrap/agent-access.sh from the same commit to the host and
#   runs it as root, so the agents' Proxmox rights change by a reviewed PR and no longer need the Mac) or `firewall`
#   (playbooks/proxmox-safety.yml with --tags firewall only: the host firewall, with the role's dead-man timer and its
#   checks before and after, D-0063 rule 4; its private values come from this job's inventory, written by the controller).
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh log
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
declare -A jobs=([proxy]=playbooks/proxmox-proxy.yml [agent-access]=playbooks/proxmox-agent-access.yml [sso]=playbooks/proxmox-sso.yml [firewall]=playbooks/proxmox-safety.yml)
inventory=$dir/inventory/hosts.yml
logs=$work/logs
summary=$logs/summary.jsonl
result=$work/state/check.json

ledger=$work/ledger
usage() {
  echo "usage: proxmox-host check [proxy|agent-access|sso|firewall]|apply [proxy|agent-access|sso|firewall] <pass message ID, cmsg_...> <check hash, 12 hex digits>|log" >&2
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
# The sso job reads the proxmox client's secret from one file of this user's own, made by the controller's run (tag
# proxmox_host_inventory); the playbook is told its path, so it never looks in the controller's home or the keys user's folder.
sso_args=()
if [[ $job == sso ]]; then
  [[ -s $dir/proxmox-sso.env ]] \
    || { echo "proxmox-host: $dir/proxmox-sso.env is missing; the controller's proxmox_host_inventory run makes it (docs/runbooks/sign-in-to-proxmox-through-keycloak.md)" >&2; exit 1; }
  sso_args=(-e "proxmox_sso_values_file=$dir/proxmox-sso.env")
fi

repo=$work/checkout   # this wrapper's own checkout of central-hub
# The firewall job runs only the playbook's firewall role, with the shared VLAN file from the same checkout (the job's
# inventory is one file, so the inventory folder's group_vars are not next to it).
fw_args=()
if [[ $job == firewall ]]; then
  fw_args=(--tags firewall -e "@$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml")
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
  (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory" "$playbook" ${sso_args[@]+"${sso_args[@]}"} ${fw_args[@]+"${fw_args[@]}"} "$@") > "$out" 2>> "$logs/run-$stamp.err"
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
      record none none "FAIL: check"; echo "proxmox-host: FAIL: check (details in the box's log $logs/check-$stamp.json)" >&2; exit 1
    fi
    read -r hash changed skipped total <<< "$line"
    record "$hash" "$changed changed, $skipped skipped, $total tasks" ok
    echo "proxmox-host: check $hash: $changed changed, $skipped skipped, $total tasks"
    echo "proxmox-host: the agents' pass for an apply names this commit (${commit:0:12}) and this hash ($hash)"
    ;;
  apply | apply-recorded)
    if ! line=$(do_check); then
      record none none "FAIL: re-check"; echo "proxmox-host: FAIL: the re-check before the apply failed; nothing applied" >&2; exit 1
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
      exit 1
    fi
    record "$hash" "$changed changed, $skipped skipped, $total tasks" ok
    echo "proxmox-host: applied check $hash ($changed changed, $skipped skipped, $total tasks), pass $pass_ref"
    ;;
esac
