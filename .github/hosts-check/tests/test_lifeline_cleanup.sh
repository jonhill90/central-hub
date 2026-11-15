#!/usr/bin/env bash
# The lifeline role's cleanup of duplicate `lifeline` profiles (hosts/ansible/roles/agent_box/tasks/lifeline_cleanup.yml),
# run with ansible-playbook on localhost against a stand-in nmcli that keeps its profiles in a file:
#   1. Six profiles, one active on the NIC: the five inactive ones are deleted, the active one stays.
#   2. A second run deletes nothing and reports no change.
#   3. One profile, or none, changes nothing and does not fail.
#   4. Duplicates with no active profile, two active profiles, or one active on another device: it fails, nothing deleted.
#   5. A check run deletes nothing and reports the deletion as a change.
#   6. Other names (the primary NIC's profile) are never touched.
#   7. The mutation (the assert dropped) is caught: the no-active case then deletes.
# Usage: .github/hosts-check/tests/test_lifeline_cleanup.sh   (needs ansible-playbook)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin"
cat > "$t/bin/nmcli" <<'SH'
#!/usr/bin/env bash
# stand-in: profiles in $NM_FILE as UUID:NAME:DEVICE:ACTIVE; deletes are logged in $NM_FILE.deleted
if [ "$1" = -t ] && [ "$2" = -f ] && [ "$4" = connection ] && [ "$5" = show ]; then cat "$NM_FILE"; exit 0; fi
if [ "$1" = connection ] && [ "$2" = delete ] && [ "$3" = uuid ]; then
  grep -q "^$4:" "$NM_FILE" || { echo "no such profile $4" >&2; exit 10; }
  grep -v "^$4:" "$NM_FILE" > "$NM_FILE.new" || true; mv "$NM_FILE.new" "$NM_FILE"; echo "$4" >> "$NM_FILE.deleted"; exit 0
fi
echo "stand-in nmcli: unexpected arguments: $*" >&2; exit 2
SH
chmod +x "$t/bin/nmcli"

play() {  # play <tasks dir> [extra ansible args]: runs the cleanup tasks on localhost
  local dir=$1; shift
  cat > "$t/play.yml" <<YML
- hosts: localhost
  gather_facts: false
  connection: local
  vars: {agent_box_lifeline_interface: eth1}
  tasks:
    - ansible.builtin.import_tasks: $root/$dir/lifeline_cleanup.yml
YML
  PATH="$t/bin:$PATH" NM_FILE="$t/nm" ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ansible-playbook -i localhost, "$t/play.yml" "$@" 2>&1
}
ROLE=hosts/ansible/roles/agent_box/tasks
A=aaaaaaaa-0000-4000-8000-000000000001   # the active lifeline profile
D1=bbbbbbbb-0000-4000-8000-000000000001; D2=bbbbbbbb-0000-4000-8000-000000000002; D3=bbbbbbbb-0000-4000-8000-000000000003
D4=bbbbbbbb-0000-4000-8000-000000000004; D5=bbbbbbbb-0000-4000-8000-000000000005
P=cccccccc-0000-4000-8000-000000000001   # the primary NIC's profile
six() { printf '%s\n' "$A:lifeline:eth1:yes" "$D1:lifeline::no" "$D2:lifeline::no" "$D3:lifeline::no" "$D4:lifeline::no" "$D5:lifeline::no" "$P:cloud-init eth0:eth0:yes" > "$t/nm"; : > "$t/nm.deleted"; }
deleted() { sort "$t/nm.deleted" | tr '\n' ' '; }

six
out=$(play "$ROLE")
[ "$(deleted)" = "$D1 $D2 $D3 $D4 $D5 " ] && ok "six profiles: the five inactive ones are deleted" || bad "six profiles: deleted '$(deleted)'"
grep -q "^$A:lifeline:eth1:yes" "$t/nm" && grep -q "^$P:" "$t/nm" && ok "the active profile and the primary NIC's profile stay" || bad "a profile that should stay was deleted"
echo "$out" | grep -q "changed=1" && ok "the first run reports a change" || bad "the first run did not report a change: $out"
: > "$t/nm.deleted"
out=$(play "$ROLE")
[ -z "$(deleted)" ] && echo "$out" | grep -q "changed=0" && ok "a second run deletes nothing and reports no change" || bad "second run: deleted '$(deleted)'"

printf '%s\n' "$A:lifeline:eth1:yes" "$P:cloud-init eth0:eth0:yes" > "$t/nm"; : > "$t/nm.deleted"
out=$(play "$ROLE") && [ -z "$(deleted)" ] && ok "one profile changes nothing and does not fail" || bad "one profile: $out"
printf '%s\n' "$D1:lifeline::no" > "$t/nm"; : > "$t/nm.deleted"
out=$(play "$ROLE") && [ -z "$(deleted)" ] && ok "one inactive profile (a fresh box before its NIC is up) is left alone" || bad "one inactive profile: $out"
printf '%s\n' "$P:cloud-init eth0:eth0:yes" > "$t/nm"; : > "$t/nm.deleted"
out=$(play "$ROLE") && [ -z "$(deleted)" ] && ok "no lifeline profile changes nothing and does not fail" || bad "no lifeline profile: $out"

refuse() {  # refuse <name> <script dir>
  if out=$(play "$2"); then bad "$1: the run did not fail"; else
    [ -z "$(deleted)" ] && echo "$out" | grep -q "nothing was deleted" && ok "$1: fails, nothing deleted" || bad "$1: deleted '$(deleted)'"
  fi
}
printf '%s\n' "$D1:lifeline::no" "$D2:lifeline::no" "$D3:lifeline::no" "$P:cloud-init eth0:eth0:yes" > "$t/nm"; : > "$t/nm.deleted"
refuse "three duplicates and none active" "$ROLE"
printf '%s\n' "$A:lifeline:eth1:yes" "$D1:lifeline:eth1:yes" "$D2:lifeline::no" > "$t/nm"; : > "$t/nm.deleted"
refuse "two active on the NIC" "$ROLE"
printf '%s\n' "$A:lifeline:eth0:yes" "$D1:lifeline::no" "$D2:lifeline::no" > "$t/nm"; : > "$t/nm.deleted"
refuse "the only active one is on another device" "$ROLE"

six
out=$(play "$ROLE" --check)
[ -z "$(deleted)" ] && echo "$out" | grep -q "changed=1" && echo "$out" | grep -q "$D1" && echo "$out" | grep -q "$D5" && ok "a check run deletes nothing, reports a change and names the five" || bad "check run: deleted '$(deleted)': $out"

# The mutation: the "exactly one active" condition always passes. With no active profile the cleanup then deletes every duplicate.
mut=.mut-lifeline-cleanup
mkdir -p "$root/$mut"
trap 'rm -rf "$t" "$root/$mut"' EXIT
python3 - "$root/$ROLE/lifeline_cleanup.yml" "$root/$mut/lifeline_cleanup.yml" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = "      - agent_box_lifeline_rows | length < 2\n        or ("
assert a in s
open(sys.argv[2], "w").write(s.replace(a, "      - true\n        or (", 1))
PY
printf '%s\n' "$D1:lifeline::no" "$D2:lifeline::no" "$D3:lifeline::no" "$P:cloud-init eth0:eth0:yes" > "$t/nm"; : > "$t/nm.deleted"
play "$mut" >/dev/null || true
[ -n "$(deleted)" ] && ok "mutation: with that condition dropped, the no-active case deletes ($(deleted | wc -w) profiles)" || bad "mutation: the condition dropped still deleted nothing"
exit $fail
