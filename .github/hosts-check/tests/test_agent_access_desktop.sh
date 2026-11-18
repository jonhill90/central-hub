#!/usr/bin/env bash
# agent-access.sh, the dev token's line on the desktop VM, against a stand-in for pveum that keeps an ACL table and computes a
# token's rights the way Proxmox does for one path: NoAccess at the path beats every role there. Nothing reaches a host.
#   1. A fresh host: VM 400 gets AgentDesktopPower (VM.Audit, VM.PowerMgmt) for the group and the token, and the check passes.
#   2. A host with an old NoAccess on /vms/400: the run removes it, and the check passes.
#   3. Mutation, the delete removed: the old NoAccess stays and the check stops the run.
#   4. A power role that also allows VM.Config.CPU is refused.
#   5. DESKTOP_ACCESS on: the power line is removed, so the pool's AgentDev applies during the apply.
# It tests the script's own text, not a real Proxmox host; the real proof is the run printing "agent-access: done".
# Usage: .github/hosts-check/tests/test_agent_access_desktop.sh   (needs python3)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
src=$root/hosts/terraform/home/bootstrap/agent-access.sh
# The constants, the role loop and acl(), then the desktop block, from the script's own text.
{
  sed -n '/^CLONE_PRIVS=/,/^DESKTOP_POWER_PRIVS=/p' "$src"
  printf 'for r in "AgentDesktopPower:$DESKTOP_POWER_PRIVS"; do role=${r%%%%:*}; privs=${r#*:}; pveum role add "$role" --privs "$privs"; done\n'
  sed -n '/^acl() {/,/^}/p' "$src"
  sed -n '/^power_acl_delete() {/,/^# ===== Part 2/p' "$src" | sed '$d'
} > "$work/part.sh"
grep -q 'acl "/vms/$DESKTOP_POWER_VMID" AgentDesktopPower 0' "$work/part.sh" || { echo "FAIL: the desktop block was not found in the script"; exit 1; }

cat > "$work/bin/pveum" <<'PY'
#!/usr/bin/env python3
import json, os, sys
st = os.environ["STATE"]
a = sys.argv[1:]
d = json.load(open(st)) if os.path.exists(st) else {"acl": [], "roles": {}}
def save(): json.dump(d, open(st, "w"))
def opt(name):
    return a[a.index(name) + 1] if name in a else None
who = "token" if "--tokens" in a else "group"
if a[:3] == ["user", "token", "list"]:
    print(json.dumps([{"tokenid": "dev"}], separators=(",", ":")))
elif a[:2] in (["role", "add"], ["role", "modify"]):
    d["roles"][a[2]] = opt("--privs").split(","); save()
elif a[:2] == ["acl", "modify"]:
    d["acl"].append([a[2], who, opt("--roles")]); save()
elif a[:2] == ["acl", "delete"]:
    d["acl"] = [e for e in d["acl"] if not (e[0] == a[2] and e[1] == who and e[2] == opt("--roles"))]; save()
elif a[:3] == ["user", "token", "permissions"]:
    p = opt("--path")
    here = [e[2] for e in d["acl"] if e[0] == p and e[1] == "token"]
    if "NoAccess" in here: print("{}"); sys.exit(0)
    privs = sorted({x for r in here for x in d["roles"].get(r, [])})
    print(json.dumps({p: {x: 1 for x in privs}}))
else:
    sys.exit(0)
PY
chmod +x "$work/bin/pveum"
fail=0
run() { # mode -> prints rc and the last output line
  ( cd "$work" && PATH="$work/bin:$PATH" STATE="$STATE_FILE" sh -c 'set -eu; DESKTOP_ACCESS=$1; . "$2"' _ "$1" "$work/part.sh" ) > "$work/out" 2>&1 && echo "rc=0" || echo "rc=$?"; tail -n 1 "$work/out"
}
ok() { if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
lines() { python3 -I - "$STATE_FILE" "$1" "$2" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); p = sys.argv[2]; w = sys.argv[3]
print(",".join(sorted(e[2] for e in d["acl"] if e[0] == p and e[1] == w)))
PY2
}
old='{"acl": [["/vms/400","group","NoAccess"],["/vms/400","token","NoAccess"]], "roles": {}}'

STATE_FILE=$work/s1.json; export STATE_FILE
out=$(run off); ok "a fresh host: the desktop block passes" "$out" "rc=0"
ok "the token holds only the power role on VM 400" "$(lines /vms/400 token)" "AgentDesktopPower"
ok "the group holds the power role on VM 400" "$(lines /vms/400 group)" "AgentDesktopPower"

STATE_FILE=$work/s2.json; export STATE_FILE
printf '%s' "$old" > "$STATE_FILE"
out=$(run off); ok "an old NoAccess on VM 400 is removed and the check passes" "$out" "rc=0"
[[ $(lines /vms/400 token) == "AgentDesktopPower" ]] && echo "ok   only the power role is left for the token" || { echo "FAIL: the token holds $(lines /vms/400 token)"; fail=1; }

cp "$work/part.sh" "$work/part.keep"
sed 's/^  power_acl_delete NoAccess$/  :/' "$work/part.keep" > "$work/part.sh"
STATE_FILE=$work/s3.json; export STATE_FILE
printf '%s' "$old" > "$STATE_FILE"
out=$(run off); ok "mutation: with the old NoAccess kept, the check stops the run" "$out" "lacks VM.PowerMgmt"

sed 's/^DESKTOP_POWER_PRIVS="VM.Audit,VM.PowerMgmt"$/DESKTOP_POWER_PRIVS="VM.Audit,VM.PowerMgmt,VM.Config.CPU"/' "$work/part.keep" > "$work/part.sh"
STATE_FILE=$work/s4.json; export STATE_FILE
out=$(run off); ok "a power role that also allows VM.Config.CPU is refused" "$out" "allows more than"
cp "$work/part.keep" "$work/part.sh"

STATE_FILE=$work/s5.json; export STATE_FILE
printf '{"acl": [["/vms/400","token","AgentDesktopPower"],["/vms/400","group","AgentDesktopPower"]], "roles": {}}' > "$STATE_FILE"
out=$(run on); ok "access on: the run passes" "$out" "rc=0"
[[ -z $(lines /vms/400 token) ]] && echo "ok   access on: the power line is removed" || { echo "FAIL: access on left $(lines /vms/400 token)"; fail=1; }
ok "access on: the pool line is set" "$(lines /pool/desktop token)" "AgentDev"
exit $fail
