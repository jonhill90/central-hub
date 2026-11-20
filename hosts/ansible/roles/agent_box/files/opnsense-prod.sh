#!/bin/bash
# /usr/local/libexec/agent-box/opnsense-prod.sh: the firewall's (OPNsense) pipeline job (D-0063). It runs
# playbooks/opnsense.yml from main, and nothing else, against the prod firewall's API, with the API key in
# /etc/agent-keys-guard/. It runs as user `guardops` through sudo, so no session and no keys-user wrapper can read that
# key. Installed by the agent_box role; root owns it. The same shape as proxmox-host.sh (D-0041 rules 4 and 6):
#   sudo -n -u guardops /usr/local/libexec/agent-box/opnsense-prod.sh check
#   sudo -n -u guardops .../opnsense-prod.sh pass <commit, 40 hex> <check hash> <pass message ID> <ISO time> reviewer
#   sudo -n -u guardops .../opnsense-prod.sh go <commit, 40 hex> <go message ID> <ISO time> orchestrator
#   sudo -n -u guardops .../opnsense-prod.sh apply-recorded <check hash, 12 hex>
#   sudo -n -u guardops .../opnsense-prod.sh ledger|log
# check: `--check --diff` on the code at origin/main; saves a result file (the commit, the SHA-256 of every diff's before
#   and after text, and for each task its name and whether it changed or was skipped) and prints the first 12 hex digits of
#   that file's SHA-256, the hash the reviewer passes.
# apply-recorded: re-checks main's head and refuses, naming each thing missing, unless (1) the check gives the hash named,
#   (2) the ledger holds a reviewer pass for this commit and hash, and (3) it holds a go for this commit whose message ID no
#   earlier apply used. The go is the owner's standing go (D-0061 rule 3) or his own words where D-0061 rule 2 applies. Then
#   it runs the playbook and fails the run if a task changed that the check showed neither changed nor skipped.
# The ledger is this user's own folder. Any session can name itself the reviewer or the orchestrator, so a ledger line proves
#   a recorder's word and the message ID it gave, not the owner's; a reviewing agent checks the IDs (D-0063, Confirmation).
# What is printed: the commit, the hash, counts of tasks, the pass ID, pass or fail. Never a task's diff, a name or an
#   address. The full output stays in {work}/logs/. The API key and secret go to the playbook in a vars file of this
#   user's own, mode 0600, deleted when the run ends; never on a command line.
# The way back (D-0063 rule 4): OPNsense 26.7's API has no savepoint, so the undo is on the Proxmox host. Before the playbook
#   runs, the host job (proxmox-host.sh guard arm, as hostops, through its own sudo line) snapshots the firewall's VM and starts
#   a timer on the host that rolls the VM back. After the run, the apply is confirmed (guard confirm: timer stopped, snapshot
#   deleted) only if a fresh check through the firewall's API works and the box still reaches GitHub through the firewall.
#   If the run fails, changes a task the check did not show, or the confirm fails, the wrapper rolls back at once (guard
#   rollback); if the box can't reach the host to do that, the host's timer does it.
set -euo pipefail
umask 077

dir=/etc/agent-keys-guard
work=/var/lib/agent-box-guard/opnsense
libexec=/usr/local/libexec/agent-box
ansible_bin=$libexec/ansible-venv/bin
collections=$libexec/collections
repo_url=https://github.com/jonhill90/central-hub.git   # public; the reviewed code this job runs
guard_cmd=(sudo -n -u hostops /usr/local/libexec/agent-box/proxmox-host.sh guard)   # the firewall VM's way back (D-0063 rule 4)
job=firewall
playbook=playbooks/opnsense.yml
inventory=$dir/inventory/hosts.yml
logs=$work/logs
summary=$logs/summary.jsonl
result=$work/state/check.json
ledger=$work/ledger
usage() {
  echo "usage: opnsense-prod check|apply-recorded <check hash, 12 hex>|pass <commit> <check hash> <cmsg_...> <ISO time> reviewer|go <commit> <cmsg_...> <ISO time> orchestrator|ledger|log" >&2
  exit 2
}

if [[ ${1:-} == log ]]; then
  [[ $# -eq 1 ]] || usage
  [[ -s $summary ]] || { echo "opnsense-prod: no run has been logged yet" >&2; exit 1; }
  tail -n 5 -- "$summary"
  exit 0
fi
action=${1:-}
ref_ok() { [[ $1 =~ ^cmsg_[A-Za-z0-9]{10,80}$ ]]; }
case $action in
  check) [[ $# -eq 1 ]] || usage ;;
  apply-recorded)
    [[ $# -eq 2 && ${2:-} =~ ^[0-9a-f]{12}$ ]] || usage
    want=$2 ;;
  pass)
    [[ $# -eq 6 && $2 =~ ^[0-9a-f]{40}$ && $3 =~ ^[0-9a-f]{12}$ && $5 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ref_ok "$4" || usage
    [[ $6 == reviewer ]] || { echo "opnsense-prod: a pass is recorded by the reviewer only" >&2; exit 2; } ;;
  go)
    [[ $# -eq 5 && $2 =~ ^[0-9a-f]{40}$ && $4 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ref_ok "$3" || usage
    [[ $5 == orchestrator ]] || { echo "opnsense-prod: a go is recorded by the orchestrator only, from the owner's own words" >&2; exit 2; } ;;
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
    echo "opnsense-prod: reviewer pass recorded for job $job, commit ${2:0:12}, check $3"
    exit 0 ;;
  go)
    install -d -m 0700 "$ledger"
    ledger_line go "job=$job" "commit=$2" "relay_ref=$3" "relay_time=$4" "recorder=$5" "box_time=$(now)" >> "$ledger/go-$job-$2.jsonl"
    echo "opnsense-prod: go recorded for job $job, commit ${2:0:12}"
    exit 0 ;;
  ledger)
    [[ -d $ledger ]] || { echo "opnsense-prod: the ledger is empty"; exit 0; }
    for f in "$ledger"/pass-"$job"-*.jsonl "$ledger"/go-"$job"-*.jsonl; do
      [[ -f $f ]] || continue
      cat -- "$f"; [[ ! -s ${f%.jsonl}.used ]] || sed "s/^/(used: /;s/$/)/" "${f%.jsonl}.used"
    done
    exit 0 ;;
esac

[[ -s $inventory && -s $dir/opnsense-api.txt && -s $dir/lab-root.crt ]] \
  || { echo "opnsense-prod: no inventory, API key or lab root in $dir; the controller's guard_files run has not run (D-0063)" >&2; exit 1; }

repo=$work/checkout   # this wrapper's own checkout of central-hub
export HOME=$work PATH=$ansible_bin:/usr/local/bin:/usr/bin:/bin
export ANSIBLE_CONFIG=$repo/hosts/ansible/ansible.cfg ANSIBLE_COLLECTIONS_PATH=$collections ANSIBLE_HOME=$work/ansible-home
export ANSIBLE_STDOUT_CALLBACK=ansible.posix.json ANSIBLE_NOCOLOR=1 ANSIBLE_RETRY_FILES_ENABLED=0

install -d -m 0700 "$logs" "$work/state"
# The key and secret, lines 1 and 2 of the key file, into a vars file of this user's own for this run only.
vars_file=$(mktemp "$work/state/vars.XXXXXX")
trap 'rm -f "$vars_file"' EXIT
python3 -I - "$dir/opnsense-api.txt" "$dir/lab-root.crt" "$ansible_bin/python3" "$vars_file" <<'PY'
import json, sys
lines = [l.strip() for l in open(sys.argv[1]).read().splitlines() if l.strip()]
if len(lines) < 2:
    sys.exit("opnsense-prod: the key file needs the key on line 1 and the secret on line 2")
json.dump({"opnsense_api_key": lines[0], "opnsense_api_secret": lines[1], "opnsense_lab_ssl_ca_file": sys.argv[2],
           "ansible_python_interpreter": sys.argv[3]}, open(sys.argv[4], "w"))
PY
# Only reviewed code on main runs with the key, never a checkout a session can edit. One run at a time.
exec 9>"$work/state/opnsense-prod.lock"
flock -n 9 || { echo "opnsense-prod: another opnsense-prod run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$repo_url" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse HEAD)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
echo "opnsense-prod: central-hub ${commit:0:12}, job $job"

# One JSON line per run for the box's own record; stdout gets the same facts, none of them private.
record() { # hash, counts, result
  python3 -I -c 'import json, sys
a = sys.argv
print(json.dumps({"job": "opnsense-prod", "time": a[1], "action": a[2], "commit": a[3], "hash": a[4], "tasks": a[5], "pass": a[6], "result": a[7]}))' \
    "$stamp" "$action" "$commit" "$1" "$2" "${pass_ref:-}" "$3" >> "$summary"
}

play() { # out-file, extra ansible-playbook arguments...
  local out=$1; shift
  (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory" -e "@$vars_file" "$playbook" "$@") > "$out" 2>> "$logs/run-$stamp.err"
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
      record none none "FAIL: check"; echo "opnsense-prod: FAIL: check (details in the box's log $logs/check-$stamp.json)" >&2; exit 1
    fi
    read -r hash changed skipped total <<< "$line"
    record "$hash" "$changed changed, $skipped skipped, $total tasks" ok
    echo "opnsense-prod: check $hash: $changed changed, $skipped skipped, $total tasks"
    echo "opnsense-prod: the agents' pass for an apply names this commit (${commit:0:12}) and this hash ($hash)"
    ;;
  apply-recorded)
    if ! line=$(do_check); then
      record none none "FAIL: re-check"; echo "opnsense-prod: FAIL: the re-check before the apply failed; nothing applied" >&2; exit 1
    fi
    read -r hash changed skipped total <<< "$line"
    if [[ $hash != "$want" ]]; then
      record "$hash" "$changed changed, $skipped skipped, $total tasks" "refused: hash"
      echo "opnsense-prod: the check now gives $hash, not the hash named ($want): main or the firewall changed since; nothing applied" >&2
      exit 1
    fi
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
      echo "opnsense-prod: refused, nothing applied: $(IFS=';'; echo "${missing[*]}")" >&2
      exit 1
    fi
    # That one go line, by its message ID, is spent before the playbook runs, so a run that fails part-way needs a new go line
    # (a new message ID, same commit); the other lines of the file stay as they were.
    printf '%s %s %s\n' "$stamp" "$hash" "$go_ref" >> "${gf%.jsonl}.used"
    if ! "${guard_cmd[@]}" arm; then
      record "$hash" "$changed changed" "FAIL: guard arm"
      echo "opnsense-prod: FAIL: the firewall VM's snapshot and timer could not be set up; nothing applied" >&2; exit 1
    fi
    # roll_back <reason>: undo now through the host; if that fails, the host's timer does it.
    roll_back() {
      local how="rolled back"
      "${guard_cmd[@]}" rollback || how="roll-back could not be started from the box; the host's timer rolls the firewall back"
      record "$hash" "$changed changed" "FAIL: $1; $how"
      echo "opnsense-prod: FAIL: $1 of check $hash; $how (details in the box's log $logs)" >&2
      exit 1
    }
    out=$logs/apply-$stamp.json
    play "$out" --diff || roll_back "apply"
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
    [[ $extra == 0 ]] || roll_back "the apply changed $extra task(s) that the check did not show (D-0063 rule 3)"
    # The confirm: a fresh check through the firewall's API, and the box still reaches GitHub through the firewall.
    play "$logs/confirm-$stamp.json" --check || roll_back "the check after the apply failed"
    git ls-remote --exit-code --quiet "$repo_url" main > /dev/null || roll_back "the box no longer reaches GitHub after the apply"
    if ! "${guard_cmd[@]}" confirm; then
      record "$hash" "$changed changed" "FAIL: guard confirm; the host's timer rolls the firewall back"
      echo "opnsense-prod: FAIL: the apply worked but could not be confirmed on the host; its timer rolls the firewall back" >&2
      exit 1
    fi
    record "$hash" "$changed changed, $skipped skipped, $total tasks" ok
    echo "opnsense-prod: applied check $hash ($changed changed, $skipped skipped, $total tasks), pass $pass_ref"
    ;;
esac
