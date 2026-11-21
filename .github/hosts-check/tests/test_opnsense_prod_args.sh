#!/usr/bin/env bash
# The firewall's pipeline job (hosts/ansible/roles/agent_box/files/opnsense-prod.sh; D-0063), with a stand-in
# ansible-playbook that prints set JSON and a local repository as main:
#   1. Any other argument is refused, before anything runs; `apply` (the runner's form) does not exist here.
#   2. With no inventory, key file or lab root, it refuses.
#   3. check prints a 12-hex hash, and the same firewall gives the same hash twice; it also prints one line per changed task
#      (name and host only, 3b).
#   4. apply-recorded refuses, naming each thing missing, with no pass and no go; the wrong recorder is refused.
#   5. With a reviewer pass for the commit and hash and a go for the commit, it applies; the go is then spent, and a
#      second apply-recorded on the same go is refused.
#   6. The key and secret reach the playbook only in a vars file (-e @file), never on its command line, and the vars
#      file is gone after the run; nothing printed holds them.
#   9. Every run (check, apply, the check after it) skips the tag dns_proof, which needs dig and the mgmt DNS on the controller.
#   8. Every run gets the checkout's VLAN file before the vars file; a failed check names the failed tasks, not their messages.
#   7. The way back (D-0063 rule 4): the apply arms the host's guard before the playbook runs and confirms it after a check
#      that works; a failed apply is rolled back at once; a guard that can't be armed stops the run before the playbook; a confirm
#      the host refuses (its timer fired during a slow run) makes the apply a failure.
# Usage: .github/hosts-check/tests/test_opnsense_prod_args.sh   (needs git and python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/dir/inventory" "$t/work" "$t/collections"
touch "$t/dir/inventory/hosts.yml"
echo "- {}" > "$t/dir/inventory/hosts.yml"
printf 'TESTKEY0123\nTESTSECRET4567\n' > "$t/dir/opnsense-api.txt"
echo "-----BEGIN CERTIFICATE-----" > "$t/dir/lab-root.crt"
git init -q -b main "$t/src" && mkdir -p "$t/src/hosts/ansible/playbooks" && echo "- hosts: opnsense" > "$t/src/hosts/ansible/playbooks/opnsense.yml"
git -C "$t/src" add -A && git -C "$t/src" -c user.name=t -c user.email=t@t commit -q -m one
git clone -q --bare "$t/src" "$t/main.git"

# The stand-in: records its arguments and a copy of the vars file it was given, prints set JSON.
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
echo "\$*" >> "$t/calls"
for a in "\$@"; do case "\$a" in @*) cat "\${a#@}" > "$t/vars-seen.json"; echo "\${a#@}" >> "$t/vars-paths" ;; esac; done
cat "$t/out.json"
EOF
chmod +x "$t/bin/ansible-playbook"
python3 - > "$t/out.json" <<'PY'
import json
def task(name, **r):
    return {"task": {"name": name}, "hosts": {"opnsense_fw": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [
    task("read", changed=False),
    task("rule", changed=True, diff=[{"before": "old", "after": "new"}]),
    task("dns", skipped=True, changed=False)]}], "stats": {}}))
PY

# The host guard's stand-in: records each call; exits with the code in $t/guard-rc-<action>, if there is one.
cat > "$t/bin/host-guard" <<EOF
#!/bin/sh
echo "\$*" >> "$t/guard-calls"
[ -f "$t/guard-rc-\$2" ] && exit "\$(cat "$t/guard-rc-\$2")"
exit 0
EOF
chmod +x "$t/bin/host-guard"
# The handoff helper, the real script pointed into the test's folders: a file in $t/handoff is what the wrappers read.
mkdir -p "$t/libexec" "$t/handoff"
sed -e "s|^handoff=.*|handoff=$t/handoff|" "$root/hosts/ansible/roles/agent_box/files/dev-worker-address.sh" > "$t/libexec/dev-worker-address.sh"
chmod +x "$t/libexec/dev-worker-address.sh"
sed -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^guard_cmd=.*|guard_cmd=($t/bin/host-guard guard)|" -e "s|^dir=.*|dir=$t/dir|" -e "s|^work=.*|work=$t/work|" -e "s|^ansible_bin=.*|ansible_bin=$t/bin|" \
    -e "s|^collections=.*|collections=$t/collections|" -e "s|^repo_url=.*|repo_url=$t/main.git|" \
    "$root/hosts/ansible/roles/agent_box/files/opnsense-prod.sh" > "$t/job.sh"
grep -q "^guard_cmd=($t/bin/host-guard" "$t/job.sh" && grep -q "^repo_url=$t/main.git" "$t/job.sh" && grep -q "^ansible_bin=$t/bin" "$t/job.sh" ||
  { echo "FAIL: the test could not point the wrapper at its folders"; exit 1; }
mkdir -p "$t/ga"; sed -i -e "s|applied_dir=/var/lib/agent-box-guard-applied|applied_dir=$t/ga|" -e "s|applied_group=devaddr|applied_group=$(id -gn)|" "$t/job.sh"
job() { bash "$t/job.sh" "$@"; }

# 1
for a in "" "plan" "check extra" "apply cmsg_0123456789ab 0123456789ab" "apply-recorded" "apply-recorded 0123456789AB" \
         "ledger x" "log x" "go abc cmsg_0123456789ab 2026-11-20T00:00:00Z orchestrator"; do
  # shellcheck disable=SC2086
  job $a >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || bad "1 '$a' gave $rc, not 2"
done
[ ! -e "$t/calls" ] && ok "1 other arguments are refused before anything runs" || bad "1 the playbook ran on a refused call"

# 2
for f in inventory/hosts.yml opnsense-api.txt lab-root.crt; do
  mv "$t/dir/$f" "$t/hold"
  job check > "$t/2.out" 2>&1 && bad "2 check ran with no $f" || grep -q "no inventory, API key or lab root" "$t/2.out" || bad "2 wrong message for $f: $(cat "$t/2.out")"
  mv "$t/hold" "$t/dir/$f"
done
[ ! -e "$t/calls" ] && ok "2 refuses with any guard file missing" || bad "2 the playbook ran with a file missing"

# 3
h1=$(job check 2>&1 | sed -n 's/^opnsense-prod: check \([0-9a-f]\{12\}\):.*/\1/p')
h2=$(job check 2>&1 | sed -n 's/^opnsense-prod: check \([0-9a-f]\{12\}\):.*/\1/p')
[ -n "$h1" ] && [ "$h1" = "$h2" ] && ok "3 check gives the same 12-hex hash twice ($h1)" || bad "3 hashes '$h1' '$h2'"
# 3b: check names each changed task and its host, and nothing else (no unchanged or skipped task, no diff text)
job check > "$t/3b.out" 2>&1
n=$(grep -c '^opnsense-prod: changed: ' "$t/3b.out")
if grep -qxF 'opnsense-prod: changed: rule (opnsense_fw)' "$t/3b.out" && [ "$n" = 1 ] && ! grep -qE 'changed: (read|dns)|old|new' "$t/3b.out"; then
  ok "3b check prints one line per changed task, its name and host, and no diff text"
else bad "3b changed-task lines: $(cat "$t/3b.out")"; fi
c=$(git -C "$t/main.git" rev-parse main)
tm=2026-11-20T00:00:00Z

# 4
job apply-recorded "$h1" > "$t/4.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "no reviewer pass for job firewall" "$t/4.out" && grep -q "no go for job firewall" "$t/4.out" \
  && ok "4 no pass and no go: refused, naming both" || bad "4 rc=$rc $(cat "$t/4.out")"
job pass "$c" "$h1" cmsg_0123456789ab "$tm" builder > /dev/null 2>&1; r1=$?
job go "$c" cmsg_0123456789cd "$tm" reviewer > /dev/null 2>&1; r2=$?
[ $r1 = 2 ] && [ $r2 = 2 ] && [ ! -d "$t/work/ledger" ] && ok "4 the wrong recorders are refused, nothing written" || bad "4 recorders $r1 $r2"

# 5
job pass "$c" "$h1" cmsg_0123456789ab "$tm" reviewer > /dev/null
job go "$c" cmsg_0123456789cd "$tm" orchestrator > /dev/null
n0=$(grep -vc -- '--check' "$t/calls")
job apply-recorded "$h1" > "$t/5.out" 2>&1; rc=$?
n1=$(grep -vc -- '--check' "$t/calls")
[ $rc = 0 ] && [ "$n1" = $((n0 + 1)) ] && grep -q "applied check $h1" "$t/5.out" && ok "5 with a pass and a go it applies once" || bad "5 rc=$rc runs $n0->$n1 $(cat "$t/5.out")"
job apply-recorded "$h1" > "$t/5b.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "was used already" "$t/5b.out" && ok "5 the go is spent: a second apply is refused" || bad "5b rc=$rc $(cat "$t/5b.out")"

[ "$(cat "$t/guard-calls" 2>/dev/null | tr '\n' ' ')" = "guard arm guard confirm " ] && ok "7 the apply armed the guard, then confirmed it" \
  || bad "7 guard calls: $(cat "$t/guard-calls" 2>/dev/null)"

# 6
if grep -q 'TESTKEY0123\|TESTSECRET4567' "$t/calls"; then bad "6 the key reached a command line"; else ok "6 the key is never on the playbook's command line"; fi
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["opnsense_api_key"]=="TESTKEY0123" and d["opnsense_api_secret"]=="TESTSECRET4567" else 1)' "$t/vars-seen.json" \
  && ok "6 the playbook got the key and secret in its vars file" || bad "6 vars file: $(cat "$t/vars-seen.json")"
left=0; while read -r p; do [ -e "$p" ] && left=1; done < "$t/vars-paths"
[ $left = 0 ] && ok "6 every vars file is gone after its run" || bad "6 a vars file was left behind"
if cat "$t"/*.out | grep -q 'TESTKEY0123\|TESTSECRET4567'; then bad "6 the key was printed"; else ok "6 nothing printed holds the key"; fi

# 7 (more): a failed apply is rolled back; an arm that fails stops the run before the playbook.
rm -f "$t/guard-calls"
job go "$c" cmsg_0123456789ef "$tm" orchestrator > /dev/null
cp "$t/bin/ansible-playbook" "$t/ap.ok"
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
case "\$*" in *--check*) cat "$t/out.json" ;; *) echo "\$*" >> "$t/calls"; exit 2 ;; esac
EOF
job apply-recorded "$h1" > "$t/7.out" 2>&1; rc=$?
[ $rc = 1 ] && [ "$(tr '\n' ' ' < "$t/guard-calls")" = "guard arm guard rollback " ] && grep -q "rolled back" "$t/7.out" \
  && ok "7 a failed apply is rolled back at once" || bad "7 failed apply: rc=$rc guard=$(cat "$t/guard-calls") $(cat "$t/7.out")"
cp "$t/ap.ok" "$t/bin/ansible-playbook"
rm -f "$t/guard-calls"; echo 1 > "$t/guard-rc-arm"
job go "$c" cmsg_0123456789gh "$tm" orchestrator > /dev/null
n0=$(grep -vc -- '--check' "$t/calls")
job apply-recorded "$h1" > "$t/7b.out" 2>&1; rc=$?
n1=$(grep -vc -- '--check' "$t/calls")
[ $rc = 1 ] && [ "$n0" = "$n1" ] && grep -q "nothing applied" "$t/7b.out" && ok "7 no guard, no apply" || bad "7 arm failed: rc=$rc runs $n0->$n1 $(cat "$t/7b.out")"
rm -f "$t/guard-rc-arm"
rm -f "$t/guard-calls"; echo 1 > "$t/guard-rc-confirm"
job go "$c" cmsg_0123456789ij "$tm" orchestrator > /dev/null
job apply-recorded "$h1" > "$t/7c.out" 2>&1; rc=$?
[ $rc = 1 ] && [ "$(tr '\n' ' ' < "$t/guard-calls")" = "guard arm guard confirm " ] && grep -q "not confirmed on the host" "$t/7c.out" \
  && ! grep -q "applied check" "$t/7c.out" && tail -n 1 "$t/work/logs/summary.jsonl" | grep -q '"result": "FAIL: guard confirm' \
  && ok "7 a confirm the host refuses (timer fired) is a failed apply, not an applied one" || bad "7 confirm refused: rc=$rc $(cat "$t/7c.out")"
rm -f "$t/guard-rc-confirm"

# 8
grep -v -- '--check' "$t/calls" | head -1 | grep -q -- "-e @$t/work/checkout/hosts/ansible/inventories/home/group_vars/all/vlans.yml -e @" \
  && ok "8 the VLAN file goes to every run" || bad "8 calls: $(head -1 "$t/calls")"
cp "$t/out.json" "$t/out.ok"
python3 - > "$t/out.json" <<'PY'
import json
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [
    {"task": {"name": "Check that the VLAN values are not empty"}, "hosts": {"opnsense_fw": {"failed": True, "msg": "TESTSECRET4567 private"}}}]}]}))
PY
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
cat "$t/out.json"; exit 2
EOF
job check > "$t/8.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "failed task(s): Check that the VLAN values are not empty" "$t/8.out" && ! grep -q "TESTSECRET4567" "$t/8.out" \
  && ok "8 a failed check names the failed task and not its message" || bad "8 rc=$rc $(cat "$t/8.out")"
cp "$t/out.ok" "$t/out.json"; cp "$t/ap.ok" "$t/bin/ansible-playbook"

# 9
n_all=$(grep -c . "$t/calls"); n_skip=$(grep -c -- "--skip-tags dns_proof" "$t/calls")
[ "$n_all" -gt 0 ] && [ "$n_all" = "$n_skip" ] && grep -v -- '--check' "$t/calls" | grep -q -- "--skip-tags dns_proof" \
  && ok "9 every run skips dns_proof, the apply too ($n_skip of $n_all)" || bad "9 $n_skip of $n_all runs skip dns_proof"

# 10 the dev worker's address from the handoff file joins the playbook's vars as the one extra backup source: in the vars file only,
#    never on the command line or in the output; no file adds nothing; a file that is not exactly one dev node address stops the run
rm -f "$t/handoff/dev-worker-address"; : > "$t/calls"
job check > "$t/10a.out" 2>&1; rc=$?
if [ $rc = 0 ] && ! grep -q "opnsense_lab_backup_target_extra_sources" "$t/vars-seen.json"; then ok "10a no handoff file: no extra source"; else bad "10a rc=$rc $(cat "$t/10a.out")"; fi
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"; : > "$t/calls"
job check > "$t/10b.out" 2>&1; rc=$?
if [ $rc = 0 ] && python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["opnsense_lab_backup_target_extra_sources"]==[{"name":"dev worker","address":"10.1.30.12","vlan":30}], v' "$t/vars-seen.json" \
   && ! grep -q "10.1.30.12" "$t/calls" "$t/10b.out"; then ok "10b the address is one extra source named dev worker on VLAN 30, in the vars file only"
else bad "10b rc=$rc $(cat "$t/10b.out")"; fi
for v in '10.1.30.230' '10.1.30.0' '10.1.20.5' '10.1.30.5/32' '10.1.30.5 10.1.30.6' 'abc' '010.1.30.5' ''; do
  printf '%s\n' "$v" > "$t/handoff/dev-worker-address"; : > "$t/calls"
  job check > "$t/10c.out" 2>&1; rc=$?
  if [ $rc = 1 ] && [ ! -s "$t/calls" ] && { [ -z "$v" ] || ! grep -qF -- "$v" "$t/10c.out"; }; then :; else bad "10c shape '$v' rc=$rc [$(cat "$t/calls")] $(cat "$t/10c.out")"; fi
done
ok "10c 8 bad shapes stop the check before the playbook, naming no value"
rm -f "$t/handoff/dev-worker-address"
# 10d the box's own address (box-backup-address) is a second extra source, named agent box, on VLAN 30, in the vars file only; alone or after the dev
#     worker; a bad shape stops the run before the playbook, naming no value
printf '10.1.30.31\n' > "$t/handoff/box-backup-address"; : > "$t/calls"
job check > "$t/10d.out" 2>&1; rc=$?
if [ $rc = 0 ] && python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["opnsense_lab_backup_target_extra_sources"]==[{"name":"agent box","address":"10.1.30.31","vlan":30}], v' "$t/vars-seen.json" \
   && ! grep -q "10.1.30.31" "$t/calls" "$t/10d.out"; then ok "10d the box's address alone is one extra source named agent box on VLAN 30, in the vars file only"
else bad "10d rc=$rc $(cat "$t/10d.out")"; fi
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"; : > "$t/calls"
job check > "$t/10e.out" 2>&1; rc=$?
if [ $rc = 0 ] && python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); assert [x["name"] for x in v["opnsense_lab_backup_target_extra_sources"]]==["dev worker","agent box"], v' "$t/vars-seen.json"; then
  ok "10e with both addresses the sources are dev worker, then agent box"
else bad "10e rc=$rc $(cat "$t/10e.out")"; fi
for v in '10.1.30.230' '10.1.20.5' '10.1.30.5 10.1.30.6' 'abc' ''; do
  printf '%s\n' "$v" > "$t/handoff/box-backup-address"; : > "$t/calls"
  job check > "$t/10f.out" 2>&1; rc=$?
  if [ $rc = 1 ] && [ ! -s "$t/calls" ] && { [ -z "$v" ] || ! grep -qF -- "$v" "$t/10f.out"; }; then :; else bad "10f shape '$v' rc=$rc [$(cat "$t/calls")] $(cat "$t/10f.out")"; fi
done
ok "10f 5 bad box address shapes stop the check before the playbook, naming no value"
rm -f "$t/handoff/dev-worker-address" "$t/handoff/box-backup-address"

# 11 a confirmed apply leaves a marker: the sha256 of the dev address it opened (nothing else), so the box's rebuild wrapper switches dev to the
#    Proxmox target only when the firewall has the rule; an apply with no dev address removes it; a check never writes it
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"
want=$(printf '10.1.30.12\n' | sha256sum | cut -c1-64)
rm -f "$t/ga/dev-rule-applied"; job check > "$t/11a.out" 2>&1
c11=$(git -C "$t/main.git" rev-parse main); h11=$(sed -n 's/^opnsense-prod: check \([0-9a-f]\{12\}\):.*/\1/p' "$t/11a.out")
job pass "$c11" "$h11" cmsg_0123456789aa "$tm" reviewer > /dev/null
[ ! -e "$t/ga/dev-rule-applied" ] && ok "11a a check writes no marker" || bad "11a a check wrote the marker"
job go "$c11" cmsg_0123456789e1 "$tm" orchestrator > /dev/null
job apply-recorded "$h11" > "$t/11b.out" 2>&1; rc=$?
if [ $rc = 0 ] && [ "$(cat "$t/ga/dev-rule-applied" 2>/dev/null)" = "$want" ] && [ "$(stat -c %a "$t/ga/dev-rule-applied")" = 640 ] && ! grep -q "10.1.30.12" "$t/11b.out"; then
  ok "11b a confirmed apply with the dev address leaves the marker (the address's sha256, 0640) and prints no address"
else bad "11b rc=$rc marker=[$(cat "$t/ga/dev-rule-applied" 2>/dev/null)] $(cat "$t/11b.out")"; fi
rm -f "$t/handoff/dev-worker-address"
job go "$c11" cmsg_0123456789e2 "$tm" orchestrator > /dev/null
job apply-recorded "$h11" > "$t/11c.out" 2>&1; rc=$?
[ $rc = 0 ] && [ ! -e "$t/ga/dev-rule-applied" ] && ok "11c an apply with no dev address removes the marker" || bad "11c rc=$rc $(ls "$t/ga")"

grep -q 'applied_group=devaddr' "$root/hosts/ansible/roles/agent_box/files/opnsense-prod.sh" && grep -q 'mode: "2750"' "$root/hosts/ansible/roles/agent_box/tasks/guard_job.yml" \
  && ok "11d the marker's real group is devaddr and the role makes its folder setgid (2750)" || bad "11d the marker's group or its folder's mode is not as expected"

exit $fail
