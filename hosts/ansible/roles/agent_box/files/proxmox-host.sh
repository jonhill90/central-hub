#!/bin/bash
# /usr/local/libexec/agent-box/proxmox-host.sh: the pipeline job for the Proxmox host's web UI proxy (D-0041; Library
# plans/r1-host-job/DESIGN.md v3.1). It runs one of two named playbooks from main, and nothing else, on the Proxmox
# host as root, with the key in /etc/agent-keys-host/. It runs as user `hostops` through sudo, so no session and no
# other wrapper can read that key. Installed by the agent_box role; root owns it.
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh check [<job>]
#   sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh apply [<job>] <pass message ID> <check hash, 12 hex>
# <job> names which one playbook runs: `proxy` (the default, playbooks/proxmox-proxy.yml) or `agent-access` (playbooks/
#   proxmox-agent-access.yml: it copies hosts/terraform/home/bootstrap/agent-access.sh from the same commit to the host and
#   runs it as root, so the agents' Proxmox rights change by a reviewed PR and no longer need the Mac).
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
declare -A jobs=([proxy]=playbooks/proxmox-proxy.yml [agent-access]=playbooks/proxmox-agent-access.yml)
inventory=$dir/inventory/hosts.yml
logs=$work/logs
summary=$logs/summary.jsonl
result=$work/state/check.json

usage() { echo "usage: proxmox-host check [proxy|agent-access]|apply [proxy|agent-access] <pass message ID, cmsg_...> <check hash, 12 hex digits>|log" >&2; exit 2; }

if [[ ${1:-} == log ]]; then
  [[ $# -eq 1 ]] || usage
  [[ -s $summary ]] || { echo "proxmox-host: no run has been logged yet" >&2; exit 1; }
  tail -n 5 -- "$summary"
  exit 0
fi
# An optional job name comes right after the action; with none, the job is the proxy.
action=${1:-} job=proxy
if [[ $action == check || $action == apply ]] && [[ -n ${2:-} && -n ${jobs[${2:-x}]:-} ]]; then job=$2; set -- "$action" "${@:3}"; fi
playbook=${jobs[$job]}
case $action in
  check) [[ $# -eq 1 ]] || usage ;;
  apply)
    [[ $# -eq 3 && ${2:-} =~ ^cmsg_[A-Za-z0-9]{10,80}$ && ${3:-} =~ ^[0-9a-f]{12}$ ]] || usage
    pass_ref=$2; want=$3 ;;
  *) usage ;;
esac

[[ -f $inventory && -f $dir/id_ed25519 && -f $dir/known_hosts ]] \
  || { echo "proxmox-host: no inventory or key in $dir; the install from the controller has not run (docs/runbooks/serve-proxmox-on-443.md)" >&2; exit 1; }

repo=$work/checkout   # this wrapper's own checkout of central-hub
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
  (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory" "$playbook" "$@") > "$out" 2>> "$logs/run-$stamp.err"
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
  apply)
    if ! line=$(do_check); then
      record none none "FAIL: re-check"; echo "proxmox-host: FAIL: the re-check before the apply failed; nothing applied" >&2; exit 1
    fi
    read -r hash changed skipped total <<< "$line"
    if [[ $hash != "$want" ]]; then
      record "$hash" "$changed changed, $skipped skipped, $total tasks" "refused: hash"
      echo "proxmox-host: the check now gives $hash, not the hash named ($want): main or the host changed since; nothing applied" >&2
      exit 1
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
