#!/bin/bash
# /usr/local/libexec/agent-box/tailnet-policy.sh: the pipeline job for the tailnet policy file (D-0041, D-0046
# rule 4), which is OpenTofu on hosts/terraform/home/tailnet-policy: who may reach what, the SSH rules and the
# policy's own tests. Until this wrapper, that stack was applied only from the owner's Mac. Since D-0063 it runs as
# user `guardops` through sudo, with the policy's own OAuth client and tfvars in /etc/agent-keys-guard/, so neither
# the caller nor any keys-user wrapper sees them. Installed by the agent_box role; root owns it.
#   sudo -n -u guardops /usr/local/libexec/agent-box/tailnet-policy.sh plan
#   sudo -n -u guardops /usr/local/libexec/agent-box/tailnet-policy.sh apply <card message ID> <plan hash, 12 hex>   (the runner's)
#   sudo -n -u guardops .../tailnet-policy.sh pass <commit, 40 hex> <plan hash> <pass message ID> <ISO time> reviewer
#   sudo -n -u guardops .../tailnet-policy.sh go <commit, 40 hex> <go message ID> <ISO time> orchestrator
#   sudo -n -u guardops .../tailnet-policy.sh apply-recorded <plan hash, 12 hex>   (the box's own, D-0063 rule 3)
#   sudo -n -u guardops /usr/local/libexec/agent-box/tailnet-policy.sh ledger|log
# plan: `tofu plan -out` on the code at origin/main, and saves the plan with its commit and SHA-256. With no
#   state on the box yet, it first adopts the live policy with `tofu import`, which only reads the tailnet.
# apply: applies that saved plan and nothing else, and only if the hash the owner's card named is the saved
#   plan's, and main has not moved since the plan. The card's message ID is required and goes into both logs.
#   The box cannot check the tap itself (D-0041 rule 6); a reviewing agent does, before the job starts.
# apply-recorded: the same checks on the saved plan, and it also refuses, naming each thing missing, unless this user's
#   ledger holds a reviewer pass for the plan's commit and hash and a go for that commit whose message ID no earlier
#   apply used (the owner's standing go, D-0061 rule 3). pass, go and ledger write and read that ledger; any session
#   can name itself the recorder, so a line proves a recorder's word and its message ID, which a reviewing agent checks.
# log: the newest run's summary lines, and, if that run failed, its scrubbed error lines.
# What is printed (and so what GitHub's public run log holds): the stack, the commit, the plan's hash, the
# counts of changes, the card ID, pass or fail, and on a failed init the last 12 lines of init's output with IP
# addresses replaced. Never the policy's text (it names the Proxmox host's address), a value or a secret. The full output stays on the box in {work}/logs/tailnet-policy/.
set -euo pipefail
umask 077

keys=/etc/agent-keys-guard
work=/var/lib/agent-box-guard/tailnet-policy
logs=$work/logs
ledger=$work/ledger
repo_url=https://github.com/jonhill90/central-hub.git   # public; the reviewed code this job runs
summary=$logs/summary.jsonl

# Output that may leave the box: ANSI colours removed, IPv4 and IPv6 addresses, e-mail addresses and tailnet names (.ts.net) replaced.
scrub() { sed -E 's/\x1b\[[0-9;]*m//g; s/[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?/<ip>/g; s/\[?[0-9a-fA-F]*:[0-9a-fA-F:]*:[0-9a-fA-F]*\]?/<ip>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<email>/g; s/[A-Za-z0-9.-]*\.ts\.net/<tailnet>/g'; }
# Only the Error: summary lines, never the plan's own text (a diff of the policy holds private values).
error_lines() { grep -E -A"${2:-0}" '^(.{0,4})Error: ' | head -n "${1:-4}" | cut -c1-200 | scrub; }

if [[ ${1:-} == log && $# -eq 1 ]]; then
  [[ -s $summary ]] || { echo "tailnet-policy: no run has been logged yet" >&2; exit 1; }
  tail -n 5 -- "$summary"
  # If the newest run failed, also show why: its Error: lines with the 3 lines after each (up to 12 lines), scrubbed, never the rest of its log. A failed init has none, so its last 12 lines.
  if tail -n 1 -- "$summary" | grep -q '"result": "FAIL'; then
    last=$(ls -1 -- "$logs"/run-*.txt 2>/dev/null | tail -n 1 || true)
    if [[ -n $last ]]; then
      echo "tailnet-policy: newest run's errors (scrubbed):"
      found=$(error_lines 12 3 < "$last" || true)
      if [[ -n $found ]]; then printf '%s\n' "$found"; else tail -n 12 -- "$last" | scrub; fi
    fi
  fi
  exit 0
fi

usage() { echo "usage: tailnet-policy plan|apply <card ID> <plan hash>|apply-recorded <plan hash>|pass <commit> <plan hash> <cmsg_...> <ISO time> reviewer|go <commit> <cmsg_...> <ISO time> orchestrator|ledger|log" >&2; exit 2; }
ref_ok() { [[ $1 =~ ^cmsg_[A-Za-z0-9]{10,80}$ ]]; }
iso='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
case ${1:-} in
  plan) [[ $# -eq 1 ]] || usage; action=plan ;;
  apply-recorded) [[ $# -eq 2 && ${2:-} =~ ^[0-9a-f]{12}$ ]] || usage; action=apply-recorded; want=$2 ;;
  pass)
    [[ $# -eq 6 && $2 =~ ^[0-9a-f]{40}$ && $3 =~ ^[0-9a-f]{12}$ && $5 =~ $iso ]] && ref_ok "$4" || usage
    [[ $6 == reviewer ]] || { echo "tailnet-policy: a pass is recorded by the reviewer only" >&2; exit 2; }
    action=pass ;;
  go)
    [[ $# -eq 5 && $2 =~ ^[0-9a-f]{40}$ && $4 =~ $iso ]] && ref_ok "$3" || usage
    [[ $5 == orchestrator ]] || { echo "tailnet-policy: a go is recorded by the orchestrator only, from the owner's own words" >&2; exit 2; }
    action=go ;;
  ledger) [[ $# -eq 1 ]] || usage; action=ledger ;;
  apply)
    [[ $# -eq 3 && ${2:-} =~ ^cmsg_[A-Za-z0-9]{10,80}$ && ${3:-} =~ ^[0-9a-f]{12}$ ]] \
      || { echo "usage: tailnet-policy apply <card message ID, cmsg_...> <plan hash, 12 hex digits>" >&2; exit 2; }
    action=apply; card=$2; want=$3 ;;
  *) usage ;;
esac

# The ledger actions need no key. Each line says who recorded it, with which message ID, and when.
ledger_line() { # kind, then key=value pairs; prints one JSON line
  python3 -I -c 'import json, sys
d = dict(a.split("=", 1) for a in sys.argv[2:])
d["kind"] = sys.argv[1]
print(json.dumps(d, sort_keys=True))' "$@"
}
case $action in
  pass)
    install -d -m 0700 "$ledger"
    ledger_line pass "job=policy" "commit=$2" "hash=$3" "relay_ref=$4" "relay_time=$5" "recorder=$6" "box_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$ledger/pass-policy-$2-$3.jsonl"
    echo "tailnet-policy: reviewer pass recorded for commit ${2:0:12}, plan $3"; exit 0 ;;
  go)
    install -d -m 0700 "$ledger"
    ledger_line go "job=policy" "commit=$2" "relay_ref=$3" "relay_time=$4" "recorder=$5" "box_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$ledger/go-policy-$2.jsonl"
    echo "tailnet-policy: go recorded for commit ${2:0:12}"; exit 0 ;;
  ledger)
    [[ -d $ledger ]] || { echo "tailnet-policy: the ledger is empty"; exit 0; }
    for f in "$ledger"/pass-policy-*.jsonl "$ledger"/go-policy-*.jsonl; do
      [[ -f $f ]] || continue
      cat -- "$f"; [[ ! -s ${f%.jsonl}.used ]] || sed "s/^/(used: /;s/$/)/" "${f%.jsonl}.used"
    done
    exit 0 ;;
esac

repo=$work/checkout   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/tailnet-policy
state=$work/state/home-tailnet-policy.tfstate
plan=$work/state/tailnet-policy.tfplan
meta=$work/state/tailnet-policy.plan.json
tfvars=$keys/tailnet-policy.tfvars
envfile=$keys/tailnet-policy.env
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/tailnet-policy TF_IN_AUTOMATION=1

install -d -m 0700 "$logs" "$work/state"
for f in "$tfvars" "$envfile"; do
  [[ -f $f ]] || { echo "tailnet-policy: $f is missing; the controller's guard_files run has not put it there (D-0063)" >&2; exit 1; }
done
# The state: none until the first plan, which adopts the live policy (tofu import, read only).

# Only the two Tailscale OAuth lines of the controller's .env are read, never the rest of it.
for name in TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_CLIENT_SECRET; do
  v=$(sed -n "s/^${name}=//p" "$envfile" | head -n 1 | tr -d '\r')
  v=${v#\"}; v=${v%\"}
  [[ -n $v ]] || { echo "tailnet-policy: $envfile has no $name" >&2; exit 1; }
  export "$name=$v"
done

# Only reviewed code on main runs with the keys, never a checkout a session can edit. One run at a time.
exec 9>"$work/state/tailnet-policy.lock"
flock -n 9 || { echo "tailnet-policy: another tailnet-policy run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$repo_url" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse HEAD)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
raw=$logs/run-$stamp.txt
: > "$raw"
echo "tailnet-policy: central-hub ${commit:0:12}"

# One JSON line per run for the box's own record; stdout gets the same facts, none of them private.
record() { # result, plan hash, counts
  python3 -I -c 'import json, sys
a = sys.argv
print(json.dumps({"stack": "tailnet-policy", "time": a[1], "action": a[2], "commit": a[3], "plan": a[4], "changes": a[5], "card": a[6], "result": a[7]}))' \
    "$stamp" "$action" "$commit" "$1" "$2" "${card:-}" "$3" >> "$summary"
}

tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
# The VLAN file is read from this checkout; the controller's tfvars names a path on the controller.
vars=(-var-file="$tfvars" -var "vlans_file=$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml")
if ! tofu init -input=false -backend-config="path=$state" >> "$raw" 2>&1; then
  record none none "FAIL: init"; echo "tailnet-policy: FAIL: init (details in the box's log $raw)" >&2
  # Init prints provider names, versions and download errors, no value or secret; the last lines say why it failed.
  # IPv4 and IPv6 addresses are replaced, since a DNS error can name the box's resolver.
  tail -n 12 "$raw" | scrub >&2; exit 1
fi

counts() { # from the saved plan's JSON: only counts of actions
  tofu show -json "$plan" | python3 -I -c 'import json, sys
c = {"create": 0, "update": 0, "delete": 0}
for r in json.load(sys.stdin).get("resource_changes", []):
    a = r["change"]["actions"]
    c["create"] += a == ["create"]; c["delete"] += a == ["delete"]
    c["update"] += a == ["update"] or a == ["delete", "create"] or a == ["create", "delete"]
print("%d to add, %d to change, %d to destroy" % (c["create"], c["update"], c["delete"]))'
}

case $action in
  plan)
    rm -f "$plan" "$meta"
    # First run on the box: adopt the live policy (overwrite_existing_content stays false, so nothing is
    # replaced without a plan that shows it).
    if [[ ! -s $state ]] && ! tofu import -input=false -no-color "${vars[@]}" tailscale_acl.policy acl >> "$raw" 2>&1; then
      record none none "FAIL: import"; echo "tailnet-policy: FAIL: import of the live policy (details in the box's log $raw)" >&2; exit 1
    fi
    if ! tofu plan -input=false -no-color "${vars[@]}" -out="$plan" >> "$raw" 2>&1; then
      record none none "FAIL: plan"; echo "tailnet-policy: FAIL: plan (details in the box's log $raw)" >&2
      error_lines 4 < "$raw" >&2 || true
      exit 1
    fi
    hash=$(sha256sum "$plan" | cut -c1-12)
    n=$(counts)
    python3 -I -c 'import json, sys; json.dump({"commit": sys.argv[1], "hash12": sys.argv[2]}, open(sys.argv[3], "w"))' "$commit" "$hash" "$meta"
    # The policy is one resource, so the counts say only "1 to change". Name the top-level sections that differ,
    # compared as data, and only their names: the contents hold private values (the runbook's card step).
    sections=$(tofu show -json "$plan" | python3 -I "$folder/policy_sections.py") || true
    record "$hash" "$n" ok
    echo "tailnet-policy: plan $hash: $n"
    echo "tailnet-policy: policy sections that differ: ${sections:-unknown}"
    echo "tailnet-policy: the owner's card for an apply names this commit (${commit:0:12}) and this plan hash ($hash)"
    ;;
  apply | apply-recorded)
    [[ -f $plan && -f $meta ]] || { echo "tailnet-policy: no saved plan; run plan first" >&2; exit 1; }
    saved_commit=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["commit"])' "$meta")
    have=$(sha256sum "$plan" | cut -c1-12)
    [[ $have == "$want" ]] || { echo "tailnet-policy: the saved plan's hash is not the one named ($want); nothing applied" >&2; exit 1; }
    [[ $saved_commit == "$commit" ]] || { echo "tailnet-policy: main moved since the plan (plan at ${saved_commit:0:12}); run plan again, nothing applied" >&2; exit 1; }
    if [[ $action == apply-recorded ]]; then
      has_line() { # file kind [key value]... [--unspent used-file]: prints the relay_ref of the first matching line
        [[ -s $1 ]] || return 0
        python3 -I - "$@" <<'PY'
import json, os, sys
path, kind, *kv = sys.argv[1:]
spent = set()
if "--unspent" in kv:
    i = kv.index("--unspent"); used = kv[i + 1]; kv = kv[:i]
    if os.path.exists(used):
        spent = {l.split()[2] for l in open(used) if len(l.split()) >= 3}
want = {"kind": kind, "job": "policy", **dict(zip(kv[::2], kv[1::2]))}
want["recorder"] = "reviewer" if kind == "pass" else "orchestrator"
for line in open(path):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if all(d.get(k) == v for k, v in want.items()) and d.get("relay_ref", "") not in spent:
        print(d.get("relay_ref", "")); break
PY
      }
      missing=()
      pf=$ledger/pass-policy-$commit-$have.jsonl gf=$ledger/go-policy-$commit.jsonl
      card=$(has_line "$pf" pass commit "$commit" hash "$have")
      go_any=$(has_line "$gf" go commit "$commit")
      go_ref=$(has_line "$gf" go commit "$commit" --unspent "${gf%.jsonl}.used")
      [[ -n $card ]] || missing+=("no reviewer pass for commit ${commit:0:12}, plan $have")
      if [[ -z $go_any ]]; then missing+=("no go for commit ${commit:0:12}")
      elif [[ -z $go_ref ]]; then missing+=("every go for commit ${commit:0:12} was used already; a new go is needed"); fi
      if [[ ${#missing[@]} -gt 0 ]]; then
        record "$have" "none" "refused: ledger"
        echo "tailnet-policy: refused, nothing applied: $(IFS=';'; echo "${missing[*]}")" >&2; exit 1
      fi
      printf '%s %s %s\n' "$stamp" "$have" "$go_ref" >> "${gf%.jsonl}.used"
    fi
    n=$(counts)
    if tofu apply -input=false -no-color "$plan" >> "$raw" 2>&1; then
      rm -f "$plan" "$meta"
      record "$have" "$n" ok
      echo "tailnet-policy: applied plan $have ($n), card $card"
    else
      record "$have" "$n" "FAIL: apply"
      echo "tailnet-policy: FAIL: apply of plan $have (details in the box's log $raw)" >&2; exit 1
    fi
    ;;
esac
