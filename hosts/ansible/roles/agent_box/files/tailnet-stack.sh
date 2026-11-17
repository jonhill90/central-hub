#!/bin/bash
# /usr/local/libexec/agent-box/tailnet-stack.sh: the pipeline job for the tailnet stack (D-0041), which
# is OpenTofu on hosts/terraform/home/tailnet: the connector's subnet routes and split DNS. It runs as
# user `keys` through sudo, so the caller never sees the Tailscale OAuth client. Installed by the
# agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/tailnet-stack.sh plan
#   sudo -n -u keys /usr/local/libexec/agent-box/tailnet-stack.sh apply <card message ID> <plan hash, 12 hex>
#   sudo -n -u keys /usr/local/libexec/agent-box/tailnet-stack.sh log
# plan: `tofu plan -out` on the code at origin/main, and saves the plan with its commit and SHA-256.
# apply: applies that saved plan and nothing else, and only if the hash the owner's card named is the saved
#   plan's, and main has not moved since the plan. The card's message ID is required and goes into both logs.
#   The box cannot check the tap itself (D-0041 rule 6); a reviewing agent does, before the job starts.
# log: the newest run's summary lines.
# What is printed (and so what GitHub's public run log holds): the stack, the commit, the plan's hash, the
# counts of changes, the card ID, pass or fail. Never a resource address (split DNS names are private), a
# value or a secret. The full output stays on the box in {work}/logs/tailnet-stack/.
set -euo pipefail
umask 077

keys=/etc/agent-keys
work=/var/lib/agent-box
logs=$work/logs/tailnet-stack
summary=$logs/summary.jsonl

if [[ ${1:-} == log && $# -eq 1 ]]; then
  [[ -s $summary ]] || { echo "tailnet-stack: no run has been logged yet" >&2; exit 1; }
  tail -n 5 -- "$summary"
  exit 0
fi

case ${1:-} in
  plan) [[ $# -eq 1 ]] || { echo "usage: tailnet-stack plan|apply <card ID> <plan hash>|log" >&2; exit 2; }; action=plan ;;
  apply)
    [[ $# -eq 3 && ${2:-} =~ ^cmsg_[A-Za-z0-9]{10,80}$ && ${3:-} =~ ^[0-9a-f]{12}$ ]] \
      || { echo "usage: tailnet-stack apply <card message ID, cmsg_...> <plan hash, 12 hex digits>" >&2; exit 2; }
    action=apply; card=$2; want=$3 ;;
  *) echo "usage: tailnet-stack plan|apply <card ID> <plan hash>|log" >&2; exit 2 ;;
esac

repo=$work/checkouts/tailnet-stack   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/tailnet
state=$work/state/home-tailnet.tfstate
plan=$work/state/tailnet-stack.tfplan
meta=$work/state/tailnet-stack.plan.json
tfvars=$keys/prod/tfvars/tailnet.tfvars
envfile=$keys/prod/hosts.env
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/tailnet-stack TF_IN_AUTOMATION=1

install -d -m 0700 "$logs" "$work/state"
for f in "$tfvars" "$envfile"; do
  [[ -f $f ]] || { echo "tailnet-stack: $f is missing; copy the controller's files (docs/runbooks/set-up-the-agent-box.md)" >&2; exit 1; }
done
# The state the controller made is copied once, as the starting point; after that the box's copy is the state.
if [[ ! -f $state ]]; then
  [[ -f $keys/prod/state/home-tailnet.tfstate ]] \
    || { echo "tailnet-stack: no tailnet state on the box ($keys/prod/state/home-tailnet.tfstate); copy the controller's files" >&2; exit 1; }
  install -m 0600 "$keys/prod/state/home-tailnet.tfstate" "$state"
fi

# Only the two Tailscale OAuth lines of the controller's .env are read, never the rest of it.
for name in TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_CLIENT_SECRET; do
  v=$(sed -n "s/^${name}=//p" "$envfile" | head -n 1 | tr -d '\r')
  v=${v#\"}; v=${v%\"}
  [[ -n $v ]] || { echo "tailnet-stack: $envfile has no $name" >&2; exit 1; }
  export "$name=$v"
done

# Only reviewed code on main runs with the keys, never a checkout a session can edit. One run at a time.
exec 9>"$work/state/tailnet-stack.lock"
flock -n 9 || { echo "tailnet-stack: another tailnet-stack run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse HEAD)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
raw=$logs/run-$stamp.txt
: > "$raw"
echo "tailnet-stack: central-hub ${commit:0:12}"

# One JSON line per run for the box's own record; stdout gets the same facts, none of them private.
record() { # result, plan hash, counts
  python3 -I -c 'import json, sys
a = sys.argv
print(json.dumps({"stack": "tailnet", "time": a[1], "action": a[2], "commit": a[3], "plan": a[4], "changes": a[5], "card": a[6], "result": a[7]}))' \
    "$stamp" "$action" "$commit" "$1" "$2" "${card:-}" "$3" >> "$summary"
}

tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
if ! tofu init -input=false -backend-config="path=$state" >> "$raw" 2>&1; then
  record none none "FAIL: init"; echo "tailnet-stack: FAIL: init (details in the box's log $raw)" >&2; exit 1
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
    if ! tofu plan -input=false -no-color -var-file="$tfvars" -out="$plan" >> "$raw" 2>&1; then
      record none none "FAIL: plan"; echo "tailnet-stack: FAIL: plan (details in the box's log $raw)" >&2; exit 1
    fi
    hash=$(sha256sum "$plan" | cut -c1-12)
    n=$(counts)
    python3 -I -c 'import json, sys; json.dump({"commit": sys.argv[1], "hash12": sys.argv[2]}, open(sys.argv[3], "w"))' "$commit" "$hash" "$meta"
    record "$hash" "$n" ok
    echo "tailnet-stack: plan $hash: $n"
    echo "tailnet-stack: the owner's card for an apply names this commit (${commit:0:12}) and this plan hash ($hash)"
    ;;
  apply)
    [[ -f $plan && -f $meta ]] || { echo "tailnet-stack: no saved plan; run plan first" >&2; exit 1; }
    saved_commit=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["commit"])' "$meta")
    have=$(sha256sum "$plan" | cut -c1-12)
    [[ $have == "$want" ]] || { echo "tailnet-stack: the saved plan's hash is not the one named ($want); nothing applied" >&2; exit 1; }
    [[ $saved_commit == "$commit" ]] || { echo "tailnet-stack: main moved since the plan (plan at ${saved_commit:0:12}); run plan again, nothing applied" >&2; exit 1; }
    n=$(counts)
    if tofu apply -input=false -no-color "$plan" >> "$raw" 2>&1; then
      rm -f "$plan" "$meta"
      record "$have" "$n" ok
      echo "tailnet-stack: applied plan $have ($n), card $card"
    else
      record "$have" "$n" "FAIL: apply"
      echo "tailnet-stack: FAIL: apply of plan $have (details in the box's log $raw)" >&2; exit 1
    fi
    ;;
esac
