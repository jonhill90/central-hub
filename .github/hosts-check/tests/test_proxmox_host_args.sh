#!/usr/bin/env bash
# The Proxmox host job's wrapper (hosts/ansible/roles/agent_box/files/proxmox-host.sh; Library plans/r1-host-job/
# DESIGN.md v3.1), with a stand-in ansible-playbook that prints set JSON and a local repository as main:
#   1. Any other argument is refused, before anything runs.
#   2. With no inventory or key, it refuses.
#   3. check prints a 12-hex hash, the commit and counts, and the same host gives the same hash twice.
#   4. The hash covers each diff's text but not its headers (which can name temporary files).
#   5. apply with a hash that is not the check's refuses, and never runs the playbook without --check.
#   6. apply after main moved refuses, because the commit is in the hash.
#   7. apply with the check's hash runs the playbook and passes; the log line holds the pass ID.
#   8. apply fails when a task changes that the check showed neither changed nor skipped (D-0041 rule 4).
#  10. A job name picks the playbook: `check agent-access` runs proxmox-agent-access.yml, no name runs the proxy playbook,
#      an unknown name is refused, and `apply agent-access <pass> <hash>` takes the same pass and hash as the proxy job.
#  11. `check sso` runs proxmox-sso.yml with the secret file's path as proxmox_sso_values_file, and refuses with no such file;
#      the proxy and agent-access jobs are never given that variable.
#  12. `apply-recorded <hash>`, the box's own apply (no pass ID argument): it re-checks, and refuses naming each thing missing unless
#      the check gives the hash, the ledger holds a reviewer pass for the job, commit and hash, and an unused go for the job and
#      commit. A pass or go for another hash, commit or job does not count; the wrong recorder is refused; a go line (by its message ID) is spent by one apply, and a new go line at the same commit works once.
#  13. `check firewall` runs proxmox-firewall.yml with the checkout's VLAN file; the other jobs don't get it.
#  22. (at the end) the proxy, firewall, connector and sso jobs take the settable host values from `inventory view proxmox` in a 0600 vars file deleted after the run; a failing view stops the job; read-only jobs never ask.
#  14. `guard arm|confirm|rollback|clear|status` runs opnsense-guard.yml with that action and needs no ledger; any other guard
#      action is refused before anything runs.
#   9. Nothing printed holds a diff's text or the host's address; log prints the summary lines.
# Usage: .github/hosts-check/tests/test_proxmox_host_args.sh   (needs git and python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/dir/inventory" "$t/work" "$t/collections"
touch "$t/dir/inventory/hosts.yml" "$t/dir/id_ed25519" "$t/dir/known_hosts"
# main: a local repository holding the playbook path the wrapper runs.
git init -q -b main "$t/src" && mkdir -p "$t/src/hosts/ansible/playbooks" && echo "- hosts: proxmox" > "$t/src/hosts/ansible/playbooks/proxmox-proxy.yml" && echo "- hosts: proxmox" > "$t/src/hosts/ansible/playbooks/proxmox-restic-reader.yml"
mkdir -p "$t/src/hosts/ansible/inventories/home" && cp "$root/hosts/ansible/inventories/home/editable-values.yml" "$t/src/hosts/ansible/inventories/home/"
git -C "$t/src" add -A && git -C "$t/src" -c user.name=t -c user.email=t@t commit -q -m one
git clone -q --bare "$t/src" "$t/main.git"

# The stand-in: records its arguments, prints out-check.json with --check, out-apply.json without.
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
echo "\$*" >> "$t/calls"
case " \$* " in *" --check "*) cat "$t/out-check.json" ;; *) cat "$t/out-apply.json" ;; esac
exit \$(cat "$t/rc" 2>/dev/null || echo 0)
EOF
chmod +x "$t/bin/ansible-playbook"
# The inventory wrapper's `view proxmox`, through a stand-in sudo: it prints $t/view.yml (exit $t/view-rc) and records its arguments.
# The wrapper reads the view with the venv's python, so the stand-in folder gets this machine's python3 (with yaml) under that name.
ln -s "$(command -v python3)" "$t/bin/python3"
cat > "$t/bin/sudo" <<EOF
#!/bin/sh
echo "\$*" >> "$t/sudo-calls"
case "\$*" in "-n -u invops "*" view proxmox") cat "$t/view.yml"; exit \$(cat "$t/view-rc" 2>/dev/null || echo 0) ;; esac
exit 99
EOF
chmod +x "$t/bin/sudo"
cat > "$t/view.yml" <<'EOF'
all:
  vars:
    k8s_gateway_address: 192.0.2.1
  children:
    proxmox:
      hosts:
        proxmox_host:
          proxmox_cert_names: [test-one.example]
          proxmox_firewall_enable: true
          proxmox_firewall_home_lan_cidr: 192.0.2.0/24
          proxmox_not_listed: must-not-pass
EOF
# json <after text> <header> <changed task> <skipped task> <extra changed task, or none>
json() {
  python3 - "$@" <<'PY'
import json, sys
after, header, changed, skipped, extra = sys.argv[1:6]
def task(name, **r):
    return {"task": {"name": name}, "hosts": {"proxmox_host": r}}
tasks = [task("read state", changed=False),
         task(changed, changed=True, diff=[{"before": "old 192.0.2.10 secret-name.example", "after": after,
                                            "before_header": header, "after_header": header}]),
         task(skipped, skipped=True, changed=False)]
if extra != "none":
    tasks.append(task(extra, changed=True))
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": tasks}], "stats": {}}))
PY
}

# The handoff helper, the real script pointed into the test's folders: a file in $t/handoff is what the wrappers read.
mkdir -p "$t/libexec" "$t/handoff"
sed -e "s|^handoff=.*|handoff=$t/handoff|" -e "s|^keys=.*|keys=$t/keys|" "$root/hosts/ansible/roles/agent_box/files/dev-worker-address.sh" > "$t/libexec/dev-worker-address.sh"
chmod +x "$t/libexec/dev-worker-address.sh"
sed -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^hostkey_dir=.*|hostkey_dir=$t/hostkey|" -e "s|^dir=.*|dir=$t/dir|" -e "s|^work=.*|work=$t/work|" -e "s|^ansible_bin=.*|ansible_bin=$t/bin|" \
    -e "s|^collections=.*|collections=$t/collections|" -e "s|^repo_url=.*|repo_url=$t/main.git|" \
    "$root/hosts/ansible/roles/agent_box/files/proxmox-host.sh" > "$t/job.sh"
grep -q "^repo_url=$t/main.git" "$t/job.sh" && grep -q "^ansible_bin=$t/bin" "$t/job.sh" ||
  { echo "FAIL: the test could not point the wrapper at its folders"; exit 1; }
job() { bash "$t/job.sh" "$@"; }

# 1
for a in "" "plan" "check extra" "apply" "apply cmsg_0123456789ab" "apply notanid 0123456789ab" \
         "apply cmsg_0123456789ab 0123456789AB" "apply cmsg_0123456789ab 0123456789ab x" "log x"; do
  # shellcheck disable=SC2086
  job $a >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || bad "1 '$a' gave $rc, not 2"
done
[ ! -e "$t/calls" ] && ok "1 other arguments are refused before anything runs" || bad "1 the playbook ran on a refused call"

# 2
mv "$t/dir/known_hosts" "$t/kh"
job check > "$t/2.out" 2>&1 && bad "2 check ran with no known_hosts" || { grep -q 'no inventory or key' "$t/2.out" && ok "2 refuses with no inventory or key" || bad "2 wrong message: $(cat "$t/2.out")"; }
mv "$t/kh" "$t/dir/known_hosts"

# 3
json "new" "/tmp/a" "write config" "move" none > "$t/out-check.json"
job check > "$t/3a.out" 2>&1 || bad "3 check failed: $(cat "$t/3a.out")"
h1=$(sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p' "$t/3a.out")
job check > "$t/3b.out" 2>&1
h2=$(sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p' "$t/3b.out")
grep -q "1 changed, 1 skipped, 3 tasks" "$t/3a.out" && [ -n "$h1" ] && [ "$h1" = "$h2" ] \
  && ok "3 check prints a hash and counts, the same twice ($h1)" || bad "3 hash '$h1' vs '$h2': $(cat "$t/3a.out")"
grep -q "$(git -C "$t/main.git" rev-parse main | cut -c1-12)" "$t/3a.out" && ok "3 check prints main's commit" || bad "3 no commit printed"

# 4
json "new" "/tmp/other-temp-name" "write config" "move" none > "$t/out-check.json"
h3=$(job check 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p')
json "newer" "/tmp/a" "write config" "move" none > "$t/out-check.json"
h4=$(job check 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p')
[ "$h3" = "$h1" ] && [ -n "$h4" ] && [ "$h4" != "$h1" ] && ok "4 a header change keeps the hash, a text change moves it" || bad "4 h1=$h1 h3=$h3 h4=$h4"

# 5
json "new" "/tmp/a" "write config" "move" none > "$t/out-check.json"
json "new" "/tmp/a" "write config" "move" none > "$t/out-apply.json"
: > "$t/calls"
job apply cmsg_0123456789ab 0123456789ab > "$t/5.out" 2>&1 && bad "5 apply passed with a wrong hash"
grep -q "not the hash named" "$t/5.out" && ! grep -qv -- '--check' "$t/calls" && ok "5 a wrong hash refuses, and only the check ran" || bad "5 $(cat "$t/5.out"); calls: $(cat "$t/calls")"

# 6
job check > /dev/null 2>&1
git -C "$t/src" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two && git -C "$t/src" push -q "$t/main.git" main
: > "$t/calls"
job apply cmsg_0123456789ab "$h1" > "$t/6.out" 2>&1 && bad "6 apply passed after main moved"
grep -q "main or the host changed" "$t/6.out" && ! grep -qv -- '--check' "$t/calls" && ok "6 main moved: refused, nothing applied" || bad "6 $(cat "$t/6.out")"

# 7
h7=$(job check 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p')
: > "$t/calls"
job apply cmsg_0123456789ab "$h7" > "$t/7.out" 2>&1 || bad "7 apply failed: $(cat "$t/7.out")"
grep -q "applied check $h7" "$t/7.out" && grep -c . "$t/calls" | grep -q '^2$' && grep -qv -- '--check' "$t/calls" \
  && ok "7 the right hash: re-check, then the playbook runs and passes" || bad "7 $(cat "$t/7.out"); calls: $(cat "$t/calls")"
tail -n 1 "$t/work/logs/summary.jsonl" | grep -q '"pass": "cmsg_0123456789ab"' && ok "7 the log line holds the pass ID" || bad "7 log: $(tail -n 1 "$t/work/logs/summary.jsonl")"

# 8
json "new" "/tmp/a" "write config" "move" "restart something" > "$t/out-apply.json"
job apply cmsg_0123456789ab "$h7" > "$t/8.out" 2>&1 && bad "8 apply passed with an undeclared change"
grep -q "changed 1 task(s) that check $h7 did not show" "$t/8.out" && ok "8 an undeclared change fails the run" || bad "8 $(cat "$t/8.out")"
grep -q "unlisted task: restart something" "$t/8.out" && ok "8 the run names the unlisted task" || bad "8 no name: $(cat "$t/8.out")"
json "new" "/tmp/a" "write config" "move" none > "$t/out-apply.json"
python3 - "$t/out-apply.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["plays"][0]["tasks"][2]["hosts"]["proxmox_host"] = {"changed": True}
json.dump(d, open(sys.argv[1], "w"))
PY
job apply cmsg_0123456789ab "$h7" > "$t/8b.out" 2>&1 && ok "8 a task skipped in the check may change in the apply" || bad "8 skipped-then-changed failed: $(cat "$t/8b.out")"

# 9
cat "$t"/[3-8]*.out > "$t/all.out"
if grep -q -e '192.0.2.10' -e 'secret-name' -e 'old ' "$t/all.out"; then bad "9 a diff's text or the address was printed"; else ok "9 no diff text or address printed"; fi
job log > "$t/9.out" 2>&1 && [ "$(grep -c '"job": "proxmox-host"' "$t/9.out")" -ge 1 ] && ok "9 log prints the summary lines" || bad "9 log: $(cat "$t/9.out")"
grep -q -e '192.0.2.10' -e 'secret-name' "$t/work/logs/summary.jsonl" && bad "9 the summary holds private text" || ok "9 the summary holds no private text"

# 10
: > "$t/calls"
job check agent-access > "$t/10a.out" 2>&1; rc10a=$?
c10a=$(cat "$t/calls"); : > "$t/calls"
job check > "$t/10b.out" 2>&1; c10b=$(cat "$t/calls"); : > "$t/calls"
job check bogus > /dev/null 2>&1; rc10c=$?
job apply bogus cmsg_0123456789ab 0123456789ab > /dev/null 2>&1; rc10d=$?
h10=$(sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p' "$t/10a.out")
job apply agent-access cmsg_0123456789ab "$h10" > "$t/10e.out" 2>&1; rc10e=$?
if [ $rc10a = 0 ] && [[ $c10a == *playbooks/proxmox-agent-access.yml* && $c10b == *playbooks/proxmox-proxy.yml* && $c10b != *agent-access* ]] &&
   [ "$rc10c" = 2 ] && [ "$rc10d" = 2 ] && [ $rc10e = 0 ] && grep -q "job agent-access" "$t/10a.out"; then
  ok "10 a job name picks the playbook; none means the proxy; an unknown name is refused"
else bad "10 rc=$rc10a/$rc10c/$rc10d/$rc10e [$c10a] [$c10b] $(cat "$t/10a.out")"; fi

# 11
: > "$t/calls"
job check sso > "$t/11a.out" 2>&1; rc11a=$?
c11a=$(cat "$t/calls"); : > "$t/calls"
echo "PROXMOX_CLIENT_SECRET=stand-in-not-a-secret-0123456789abcdef" > "$t/dir/proxmox-sso.env"
job check sso > "$t/11b.out" 2>&1; rc11b=$?
c11b=$(cat "$t/calls"); : > "$t/calls"
job check agent-access > /dev/null 2>&1; c11c=$(cat "$t/calls"); : > "$t/calls"
job check > /dev/null 2>&1; c11d=$(cat "$t/calls")
if [ "$rc11a" = 1 ] && [ -z "$c11a" ] && grep -q 'proxmox-sso.env is missing' "$t/11a.out" &&
   [ "$rc11b" = 0 ] && [[ $c11b == *playbooks/proxmox-sso.yml* && $c11b == *"-e proxmox_sso_values_file=$t/dir/proxmox-sso.env"* ]] &&
   [[ $c11c != *proxmox_sso_values_file* && $c11d != *proxmox_sso_values_file* ]] && ! grep -q 'stand-in-not-a-secret' "$t"/11?.out; then
  ok "11 the sso job needs its secret file, runs proxmox-sso.yml with that path, and the other jobs get no such variable"
else bad "11 rc=$rc11a/$rc11b [$c11a] [$c11b] [$c11c] [$c11d] $(cat "$t/11a.out")"; fi

# 12
json "new" "/tmp/a" "write config" "move" none > "$t/out-check.json"
json "new" "/tmp/a" "write config" "move" none > "$t/out-apply.json"
c12=$(git -C "$t/main.git" rev-parse main)
h12=$(job check 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p')
ref1=cmsg_aaaaaaaaaaaa; ref2=cmsg_bbbbbbbbbbbb; tm=2026-11-18T23:00:00Z
only_check() { ! grep -qv -- '--check' "$t/calls"; }
: > "$t/calls"
job apply-recorded "$h12" > "$t/12a.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q "no reviewer pass for job proxy" "$t/12a.out" && grep -q "no go for job proxy" "$t/12a.out" && only_check; then
  ok "12 no pass and no go: refused naming both, only the check ran"; else bad "12a rc=$rc $(cat "$t/12a.out")"; fi
job apply-recorded 0123456789ab > "$t/12b.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q "not the hash named" "$t/12b.out"; then ok "12 a hash that is not the check's refuses first"; else bad "12b rc=$rc $(cat "$t/12b.out")"; fi
# wrong recorders and shapes are refused before anything is written
job pass "$c12" "$h12" "$ref1" "$tm" builder > /dev/null 2>&1; r1=$?
job go "$c12" "$ref2" "$tm" reviewer > /dev/null 2>&1; r2=$?
job pass "$c12" "$h12" "notanid" "$tm" reviewer > /dev/null 2>&1; r3=$?
job go "${c12:0:12}" "$ref2" "$tm" orchestrator > /dev/null 2>&1; r4=$?
if [ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 2 ] && [ "$r4" = 2 ] && [ ! -e "$t/work/ledger" ]; then
  ok "12 pass by a builder, go by a reviewer, a bad ID, a short commit: all refused, nothing written"; else bad "12 recorders $r1 $r2 $r3 $r4"; fi
# a pass for another hash, another commit or another job does not count
job pass "$c12" 0123456789ab "$ref1" "$tm" reviewer > /dev/null 2>&1
job pass "0123456789012345678901234567890123456789" "$h12" "$ref1" "$tm" reviewer > /dev/null 2>&1
job pass agent-access "$c12" "$h12" "$ref1" "$tm" reviewer > /dev/null 2>&1
job go "$c12" "$ref2" "$tm" orchestrator > /dev/null 2>&1
: > "$t/calls"
job apply-recorded "$h12" > "$t/12c.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q "no reviewer pass for job proxy" "$t/12c.out" && ! grep -q "no go for" "$t/12c.out" && only_check; then
  ok "12 a pass for another hash, commit or job does not count; the go alone is named as present"; else bad "12c rc=$rc $(cat "$t/12c.out")"; fi
# a pass without a go
rm -rf "$t/work/ledger"
job pass "$c12" "$h12" "$ref1" "$tm" reviewer > /dev/null 2>&1
: > "$t/calls"
job apply-recorded "$h12" > "$t/12d.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q "no go for job proxy" "$t/12d.out" && ! grep -q "no reviewer pass" "$t/12d.out" && only_check; then
  ok "12 a pass without a go: refused, naming the go"; else bad "12d rc=$rc $(cat "$t/12d.out")"; fi
# a go for the same commit but another job does not count
job go agent-access "$c12" "$ref2" "$tm" orchestrator > /dev/null 2>&1
job apply-recorded "$h12" > "$t/12e.out" 2>&1 && bad "12 a go for another job let the proxy apply"
grep -q "no go for job proxy" "$t/12e.out" && ok "12 a go for another job does not count" || bad "12e $(cat "$t/12e.out")"
# both: it applies, the log line holds the pass ID, and the go is spent
job go "$c12" "$ref2" "$tm" orchestrator > /dev/null 2>&1
: > "$t/calls"
job apply-recorded "$h12" > "$t/12f.out" 2>&1; rc=$?
if [ $rc = 0 ] && grep -q "applied check $h12" "$t/12f.out" && grep -qv -- '--check' "$t/calls" && grep -c . "$t/calls" | grep -q '^2$'; then
  ok "12 pass and go present: re-check, then the playbook runs and passes"; else bad "12f rc=$rc $(cat "$t/12f.out")"; fi
tail -n 1 "$t/work/logs/summary.jsonl" | grep -q "\"pass\": \"$ref1\"" && tail -n 1 "$t/work/logs/summary.jsonl" | grep -q '"action": "apply-recorded"' \
  && ok "12 the log line names the reviewer pass's ID and the action" || bad "12 log: $(tail -n 1 "$t/work/logs/summary.jsonl")"
: > "$t/calls"
job apply-recorded "$h12" > "$t/12g.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q "was used already" "$t/12g.out" && only_check; then ok "12 the go is spent: a second apply is refused"; else bad "12g rc=$rc $(cat "$t/12g.out")"; fi
# a new go line (a new message ID) at the same commit works once; the spent line stays spent
job go "$c12" cmsg_cccccccccccc "$tm" orchestrator > /dev/null 2>&1
: > "$t/calls"
job apply-recorded "$h12" > "$t/12i.out" 2>&1; rc=$?
if [ $rc = 0 ] && grep -q "applied check $h12" "$t/12i.out" && grep -qv -- '--check' "$t/calls"; then ok "12 a new go at the same commit applies"; else bad "12i rc=$rc $(cat "$t/12i.out")"; fi
job apply-recorded "$h12" > "$t/12j.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q "was used already" "$t/12j.out"; then ok "12 and is spent in its turn: a third apply is refused"; else bad "12j rc=$rc $(cat "$t/12j.out")"; fi
# the same message ID recorded twice is one go, not two
job go "$c12" cmsg_cccccccccccc "$tm" orchestrator > /dev/null 2>&1
job apply-recorded "$h12" > "$t/12k.out" 2>&1 && bad "12 a repeated go message ID applied again"
grep -q "was used already" "$t/12k.out" && ok "12 a go line repeated under a spent message ID stays spent" || bad "12k $(cat "$t/12k.out")"
job ledger > "$t/12h.out" 2>&1
if grep -q "\"relay_ref\": \"$ref1\"" "$t/12h.out" && grep -q "\"relay_ref\": \"$ref2\"" "$t/12h.out" && grep -q '^(used: ' "$t/12h.out"; then
  ok "12 ledger prints the lines, marks the spent go"; else bad "12h $(cat "$t/12h.out")"; fi
if grep -q -e '192.0.2.10' -e 'secret-name' "$t"/12?.out "$t/work/ledger"/* 2>/dev/null; then bad "12 private text printed or stored"; else ok "12 no private text in the output or the ledger"; fi

# 13
: > "$t/calls"
job check firewall > "$t/13a.out" 2>&1; rc13=$?
c13=$(cat "$t/calls"); : > "$t/calls"
job check > /dev/null 2>&1; c13b=$(cat "$t/calls")
if [ $rc13 = 0 ] && [[ $c13 == *playbooks/proxmox-firewall.yml* && $c13 != *"--tags"* && $c13 == *"-e @$t/work/checkout/hosts/ansible/inventories/home/group_vars/all/vlans.yml"* ]] &&
   [[ $c13b != *vlans.yml* ]]; then
  ok "13 the firewall job runs proxmox-firewall.yml with the VLAN file; the proxy job doesn't get it"
else bad "13 rc=$rc13 [$c13] [$c13b] $(cat "$t/13a.out")"; fi

# 14
for a in "guard" "guard apply" "guard arm x" "guard firewall arm"; do
  : > "$t/calls"
  # shellcheck disable=SC2086
  job $a > /dev/null 2>&1; rc=$?
  { [ "$rc" = 2 ] && [ ! -s "$t/calls" ]; } || bad "14 '$a' gave $rc, not 2, or ran the playbook"
done
ok14=1
for g in arm confirm rollback clear status; do
  : > "$t/calls"
  job guard "$g" > "$t/14-$g.out" 2>&1 || { ok14=0; echo "  guard $g failed: $(cat "$t/14-$g.out")"; }
  c=$(cat "$t/calls")
  [[ $c == *playbooks/opnsense-guard.yml* && $c == *"opnsense_guard_action=$g"* && $c != *--check* && $(wc -l < "$t/calls") -eq 1 ]] || { ok14=0; echo "  guard $g ran [$c]"; }
done
[ $ok14 = 1 ] && ok "14 guard runs opnsense-guard.yml once with its action, no ledger; other guard actions are refused" || bad "14 guard"

# 15 a failed check names the failed task and prints no private text from its message
python3 - > "$t/out-check.json" <<'PY'
import json
t = lambda n, **r: {"task": {"name": n}, "hosts": {"proxmox_host": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [t("read state", changed=False),
      t("Check the host firewall values", failed=True, msg="no 192.0.2.10 secret-name.example")]}], "stats": {}}))
PY
echo 2 > "$t/rc"
job check > "$t/15.out" 2>&1; rc15=$?
rm -f "$t/rc"
if [ $rc15 != 0 ] && grep -q 'failed task(s): Check the host firewall values' "$t/15.out" && ! grep -q '192.0.2.10\|secret-name' "$t/15.out"; then
  ok "15 a failed check names the failed task and no private text"
else bad "15 rc=$rc15 $(cat "$t/15.out")"; fi

# 16 the guests job runs proxmox-guests.yml and prints which guests the changed tasks name, nothing else
python3 - > "$t/out-check.json" <<'PY'
import json
t = lambda n, **r: {"task": {"name": n}, "hosts": {"proxmox_host": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [t("guests | Look for the container 259 config", changed=False),
      t("guests | EXISTS container 259", changed=True), t("guests | EXISTS VM 258", changed=False)]}], "stats": {}}))
PY
: > "$t/calls"
job check guests > "$t/16.out" 2>&1; rc16=$?
c16=$(cat "$t/calls")
if [ $rc16 = 0 ] && [[ $c16 == *playbooks/proxmox-guests.yml* ]] && grep -qx 'proxmox-host: guests found: container 259' "$t/16.out"; then
  ok "16 the guests job runs proxmox-guests.yml and prints the guest that exists"
else bad "16 rc=$rc16 [$c16] $(cat "$t/16.out")"; fi

# 16a the connector job runs proxmox-connector.yml and prints only the facts its changed tasks name
python3 - > "$t/out-check.json" <<'PY'
import json
t = lambda n, **r: {"task": {"name": n}, "hosts": {"proxmox_host": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [t("connector | Read the container's state", changed=False),
      t("connector | FACT container 900 is running", changed=True), t("connector | FACT it advertises at least one lab range", changed=False)]}], "stats": {}}))
PY
: > "$t/calls"
job check connector > "$t/16a.out" 2>&1; rc16a=$?
c16a=$(cat "$t/calls")
if [ $rc16a = 0 ] && [[ $c16a == *playbooks/proxmox-connector.yml* ]] && grep -qx 'proxmox-host: connector facts true: container 900 is running' "$t/16a.out"; then
  ok "16a the connector job runs proxmox-connector.yml and prints the facts that are true"
else bad "16a rc=$rc16a [$c16a] $(cat "$t/16a.out")"; fi

# 16b the memory job runs proxmox-memory.yml and prints only the report lines that match its allowlist: a line with a name, an address
#     or any extra word is dropped, so nothing private can pass
python3 - > "$t/out-check.json" <<'PY'
import json
msg = "\n".join(["guest 301 qemu running maxmem 4096 mem 3072", "kvm id 301 rss 4096", "host memavailable 8407", "host ksm run 0",
                 "guest 302 qemu running maxmem 4096 mem 3072 name secret-host-name", "host 192.0.2.10 5", "pve-secret.example 1",
                 "kvm id 258 rss 1024 -name other",
                 "kvm id 258 merge off", "kvm id 100 merge on", "kvm id 100 merge maybe secret", "host ksmd utime 123", "host ksmd stime 45",
                 "host clk_tck 100", "host ksm full_scans 7", "host ksm pages_to_scan 1000", "host ksmd comm ksmd"])
t = lambda n, **r: {"task": {"name": n}, "hosts": {"proxmox_host": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [t("memory | Read the guests' resources", changed=False),
      t("memory | REPORT", changed=False, msg=msg)]}], "stats": {}}))
PY
: > "$t/calls"
job check memory > "$t/16b.out" 2>&1; rc16b=$?
c16b=$(cat "$t/calls")
if [ $rc16b = 0 ] && [[ $c16b == *playbooks/proxmox-memory.yml* ]] && grep -qx 'proxmox-host: memory: guest 301 qemu running maxmem 4096 mem 3072' "$t/16b.out" \
   && grep -qx 'proxmox-host: memory: kvm id 301 rss 4096' "$t/16b.out" && grep -qx 'proxmox-host: memory: host memavailable 8407' "$t/16b.out" \
   && grep -qx 'proxmox-host: memory: host ksm run 0' "$t/16b.out" && grep -qx 'proxmox-host: memory: 11 line(s)' "$t/16b.out" \
   && grep -qx 'proxmox-host: memory: kvm id 258 merge off' "$t/16b.out" && grep -qx 'proxmox-host: memory: kvm id 100 merge on' "$t/16b.out" \
   && grep -qx 'proxmox-host: memory: host ksmd utime 123' "$t/16b.out" && grep -qx 'proxmox-host: memory: host ksmd stime 45' "$t/16b.out" \
   && grep -qx 'proxmox-host: memory: host clk_tck 100' "$t/16b.out" && grep -qx 'proxmox-host: memory: host ksm full_scans 7' "$t/16b.out" \
   && ! grep -q 'maybe\|ksmd comm' "$t/16b.out" \
   && ! grep -q 'secret\|192.0.2.10\|pve-secret\|-name' "$t/16b.out"; then
  ok "16b the memory job prints the allowlisted report lines and drops any other text"
else bad "16b rc=$rc16b [$c16b] $(cat "$t/16b.out")"; fi

# 17 restore-reader takes the dev worker's address from the handoff file, in a vars file and never on the command line;
#    no file, or a file that is not exactly one dev node address, stops it before the playbook runs, and no output shows the value
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
echo "\$*" >> "$t/calls"
for a in "\$@"; do case "\$a" in @*) cat "\${a#@}" > "$t/vars-seen.json"; echo "\${a#@}" >> "$t/vars-paths" ;; esac; done
case " \$* " in *" --check "*) cat "$t/out-check.json" ;; *) cat "$t/out-apply.json" ;; esac
EOF
python3 - > "$t/out-check.json" <<'PY'
import json
t = lambda n, **r: {"task": {"name": n}, "hosts": {"proxmox_host": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [t("keys", changed=True)]}], "stats": {}}))
PY
rm -f "$t/handoff/dev-worker-address"; : > "$t/calls"
job check restore-reader > "$t/17a.out" 2>&1; rc=$?
if [ $rc = 1 ] && [ ! -s "$t/calls" ] && grep -q "no dev worker address" "$t/17a.out"; then ok "17a restore-reader with no handoff file stops before the playbook"
else bad "17a rc=$rc $(cat "$t/17a.out")"; fi
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"; : > "$t/calls"; rm -f "$t/vars-paths" "$t/vars-seen.json"
job check restore-reader > "$t/17b.out" 2>&1; rc=$?
if [ $rc = 0 ] && grep -q "playbooks/proxmox-restic-reader.yml" "$t/calls" && grep -q '"proxmox_restic_reader_from": "10.1.30.12"' "$t/vars-seen.json" \
   && ! grep -q "10.1.30.12" "$t/calls" "$t/17b.out" && [ ! -e "$(head -1 "$t/vars-paths")" ]; then
  ok "17b the address reaches the playbook in a vars file, not on the command line or in the output, and the file is gone after"
else bad "17b rc=$rc [$(cat "$t/calls")] $(cat "$t/17b.out")"; fi
for v in '10.1.30.230' '10.1.30.0' '10.1.20.5' '10.1.30.5/32' '10.1.30.5 10.1.30.6' 'abc' '010.1.30.5' ''; do
  printf '%s\n' "$v" > "$t/handoff/dev-worker-address"; : > "$t/calls"
  job check restore-reader > "$t/17c.out" 2>&1; rc=$?
  if [ $rc = 1 ] && [ ! -s "$t/calls" ] && { [ -z "$v" ] || ! grep -qF -- "$v" "$t/17c.out"; }; then :; else bad "17c shape '$v' rc=$rc [$(cat "$t/calls")] $(cat "$t/17c.out")"; fi
done
printf '10.1.30.5\n10.1.30.6\n' > "$t/handoff/dev-worker-address"; : > "$t/calls"
job check restore-reader > "$t/17c.out" 2>&1; [ $? = 1 ] && [ ! -s "$t/calls" ] && ok "17c a bad shape stops it before the playbook, naming no value (8 shapes and two lines)" || bad "17c two lines"
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"; : > "$t/calls"
job check proxy > "$t/17d.out" 2>&1
! grep -q "proxmox_restic_reader_from\|rr-vars\|bw-vars" "$t/calls" && ok "17d the other jobs are not given the address" || bad "17d $(cat "$t/calls")"

# 18 restore-reader also takes the worker's public key from the handoff (proxmox_restic_reader_key, in the vars file only); a bad key line
#    stops it before the playbook; no key file leaves the inventory's own list in use
mkdir -p "$t/hostkey"
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"
k18=$(ssh-keygen -q -t ed25519 -N '' -f "$t/k18" && cut -d' ' -f1,2 "$t/k18.pub")
rm -f "$t/handoff/dev-worker-backup.pub"; : > "$t/calls"; rm -f "$t/vars-seen.json"
job check restore-reader > "$t/18a.out" 2>&1; rc=$?
[ $rc = 0 ] && ! grep -q proxmox_restic_reader_key "$t/vars-seen.json" && ok "18a no key file: the vars hold no key (the inventory's list is used)" || bad "18a rc=$rc $(cat "$t/18a.out")"
printf '%s\n' "$k18" > "$t/handoff/dev-worker-backup.pub"; : > "$t/calls"
job check restore-reader > "$t/18b.out" 2>&1; rc=$?
if [ $rc = 0 ] && python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v["proxmox_restic_reader_key"]==sys.argv[2], v' "$t/vars-seen.json" "$k18" \
   && ! grep -qF "$k18" "$t/calls" "$t/18b.out"; then ok "18b the worker's key reaches the playbook in the vars file, not on the command line or in the output"
else bad "18b rc=$rc $(cat "$t/18b.out")"; fi
printf 'ssh-rsa AAAAB3\n' > "$t/handoff/dev-worker-backup.pub"; : > "$t/calls"
job check restore-reader > "$t/18c.out" 2>&1; rc=$?
[ $rc = 1 ] && [ ! -s "$t/calls" ] && ok "18c a key line that is not ssh-ed25519 stops it before the playbook" || bad "18c rc=$rc $(cat "$t/calls")"
rm -f "$t/handoff/dev-worker-backup.pub" "$t/handoff/dev-worker-address"

# 19 the host's public host key is published for the keys user's rebuild wrapper: two fields, mode 0640, from this job's own known_hosts
hk19=$(ssh-keygen -q -t ed25519 -N '' -f "$t/k19" && cut -d' ' -f1,2 "$t/k19.pub")
printf '192.0.2.1 %s\n' "$hk19" > "$t/dir/known_hosts"; rm -f "$t/hostkey/proxmox-host.pub"
job check > "$t/19.out" 2>&1
# These tests run as one user, so the file's group would be right by luck: a stand-in chgrp records the group and the file it is asked to set, and the
# file must be given group devaddr before it is moved into place (the job's user is not in the group as a primary one: files it makes get its own).
printf '#!/bin/sh\necho "$*" >> "%s/chgrp-calls"\nexec /usr/bin/chgrp "$@"\n' "$t" > "$t/bin/chgrp"; chmod +x "$t/bin/chgrp"
sed -i "s|^handoff_group=.*|handoff_group=$(id -gn)|" "$t/job.sh"; : > "$t/chgrp-calls"
PATH=$t/bin:$PATH job check > "$t/19.out" 2>&1
if [[ $(cat "$t/hostkey/proxmox-host.pub" 2>/dev/null) == "$hk19" && $(stat -c %a "$t/hostkey/proxmox-host.pub") == 640 ]] && ! grep -qF "${hk19#* }" "$t/19.out" "$t/calls"; then
  ok "19 the host's public host key is published (two fields, 0640) and not printed"
else bad "19 published=[$(cat "$t/hostkey/proxmox-host.pub" 2>/dev/null)] $(cat "$t/19.out")"; fi
grep -q "^$(id -gn) $t/hostkey/proxmox-host.pub.part$" "$t/chgrp-calls" && ok "19 the file is given the handoff group before it is moved into place" || bad "19 no chgrp of the published file: $(cat "$t/chgrp-calls")"
grep -q 'handoff_group=devaddr' "$root/hosts/ansible/roles/agent_box/files/proxmox-host.sh" && grep -q 'mode: "2750"' "$root/hosts/ansible/roles/agent_box/tasks/proxmox_host.yml" \
  && ok "19 the real group is devaddr and the role makes the folder setgid (2750)" || bad "19 the group or the folder mode is not as expected"

# 20 an apply of restore-reader leaves the marker the box's rebuild wrapper needs: the sha256 of the key line and the address it put on the host
#    (neither itself); a check does not write it; an apply with no key from the handoff removes it; another job's apply never touches it
printf '10.1.30.12\n' > "$t/handoff/dev-worker-address"; printf '%s\n' "$k18" > "$t/handoff/dev-worker-backup.pub"
cp "$t/out-check.json" "$t/out-apply.json"
want20=$(printf '%s\n%s\n' "$k18" 10.1.30.12 | sha256sum | cut -c1-64)
rm -f "$t/hostkey/reader-applied"
h20=$(job check restore-reader 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\):.*/\1/p')
[ -n "$h20" ] && [ ! -e "$t/hostkey/reader-applied" ] && ok "20a a check writes no marker" || bad "20a h=$h20 marker=$(ls "$t/hostkey")"
job apply restore-reader cmsg_0123456789abc "$h20" > "$t/20b.out" 2>&1; rc=$?
if [ $rc = 0 ] && [ "$(cat "$t/hostkey/reader-applied" 2>/dev/null)" = "$want20" ] && [ "$(stat -c %a "$t/hostkey/reader-applied")" = 640 ] && ! grep -qF "$k18" "$t/20b.out" && ! grep -q 10.1.30.12 "$t/20b.out"; then
  ok "20b a restore-reader apply leaves the marker (sha256 of the key line and the address, 0640), printing neither"
else bad "20b rc=$rc marker=[$(cat "$t/hostkey/reader-applied" 2>/dev/null)] $(cat "$t/20b.out")"; fi
rm -f "$t/handoff/dev-worker-backup.pub"
h20=$(job check restore-reader 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\):.*/\1/p')
job apply restore-reader cmsg_0123456789abc "$h20" > "$t/20c.out" 2>&1
[ ! -e "$t/hostkey/reader-applied" ] && ok "20c an apply with no key from the handoff removes the marker" || bad "20c the marker stayed"
echo stale > "$t/hostkey/reader-applied"; h20=$(job check proxy 2>&1 | sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\):.*/\1/p')
job apply proxy cmsg_0123456789abc "$h20" > "$t/20d.out" 2>&1
[ "$(cat "$t/hostkey/reader-applied")" = stale ] && ok "20d another job's apply leaves the marker alone" || bad "20d the marker changed"
rm -f "$t/handoff/dev-worker-address"

# 21 box-writer takes the box's public backup key and address from the handoff (proxmox_restic_box_key and proxmox_restic_box_from, in the vars file
#    only); no key or no address, or a bad key line, stops it before the playbook; the other jobs are not given them
k21=$(ssh-keygen -q -t ed25519 -N '' -f "$t/k21" && cut -d' ' -f1,2 "$t/k21.pub")
rm -f "$t/handoff/box-backup.pub" "$t/handoff/box-backup-address"; : > "$t/calls"
job check box-writer > "$t/21a.out" 2>&1; rc=$?
[ $rc = 1 ] && [ ! -s "$t/calls" ] && grep -q "no box backup key or address" "$t/21a.out" && ok "21a box-writer with no key and no address stops before the playbook" || bad "21a rc=$rc $(cat "$t/21a.out")"
printf '%s\n' "$k21" > "$t/handoff/box-backup.pub"; : > "$t/calls"
job check box-writer > "$t/21a.out" 2>&1; rc=$?
[ $rc = 1 ] && [ ! -s "$t/calls" ] && ok "21a a key with no address stops it too" || bad "21a key only: rc=$rc"
printf '10.1.30.31\n' > "$t/handoff/box-backup-address"; : > "$t/calls"; rm -f "$t/vars-paths" "$t/vars-seen.json"
job check box-writer > "$t/21b.out" 2>&1; rc=$?
if [ $rc = 0 ] && grep -q "playbooks/proxmox-restic-box.yml" "$t/calls" && python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v=={"proxmox_restic_box_key":sys.argv[2],"proxmox_restic_box_from":"10.1.30.31"}, v' "$t/vars-seen.json" "$k21" \
   && ! grep -qF "$k21" "$t/calls" "$t/21b.out" && ! grep -q "10.1.30.31" "$t/calls" "$t/21b.out" && [ ! -e "$(head -1 "$t/vars-paths")" ]; then
  ok "21b the key and the address reach the playbook in a vars file, not on the command line or in the output, and the file is gone after"
else bad "21b rc=$rc [$(cat "$t/calls")] $(cat "$t/21b.out")"; fi
for v in 'ssh-rsa AAAAB3' 'ssh-ed25519 AAAA' "$k21 comment" ''; do
  printf '%s\n' "$v" > "$t/handoff/box-backup.pub"; : > "$t/calls"
  job check box-writer > "$t/21c.out" 2>&1; rc=$?
  if [ $rc = 1 ] && [ ! -s "$t/calls" ] && ! grep -qF "$k21" "$t/21c.out"; then :; else bad "21c shape '$v' rc=$rc [$(cat "$t/calls")]"; fi
done
ok "21c four bad key shapes stop it before the playbook"
printf '%s\n' "$k21" > "$t/handoff/box-backup.pub"; printf '10.1.20.5\n' > "$t/handoff/box-backup-address"; : > "$t/calls"
job check box-writer > "$t/21c.out" 2>&1; rc=$?
[ $rc = 1 ] && [ ! -s "$t/calls" ] && ! grep -q "10.1.20.5" "$t/21c.out" && ok "21c an address outside the dev range stops it before the playbook, naming no value" || bad "21c address rc=$rc"
printf '%s\n' "$k21" > "$t/handoff/box-backup.pub"; printf '10.1.30.31\n' > "$t/handoff/box-backup-address"; : > "$t/calls"
job check proxy > "$t/21d.out" 2>&1
! grep -q "proxmox_restic_box_key\|rr-vars\|bw-vars" "$t/calls" && ok "21d the other jobs are not given the key" || bad "21d $(cat "$t/calls")"
rm -f "$t/handoff/box-backup.pub" "$t/handoff/box-backup-address"

# 19 ct259-destroy runs its own playbook on a check, and an apply without a pass is refused with nothing run
python3 - > "$t/out-check.json" <<'PY'
import json
t = lambda n, **r: {"task": {"name": n}, "hosts": {"proxmox_host": r}}
print(json.dumps({"plays": [{"play": {"name": "p"}, "tasks": [t("ct259 | A check run shows the delete as a change", changed=True)]}], "stats": {}}))
PY
: > "$t/calls"
job check ct259-destroy > "$t/18a.out" 2>&1; rc18a=$?
c18=$(cat "$t/calls"); : > "$t/calls"
job apply-recorded ct259-destroy 0123456789ab > "$t/18b.out" 2>&1; rc18b=$?
if [ $rc18a = 0 ] && [[ $c18 == *playbooks/proxmox-ct259-destroy.yml* && $c18 == *--check* ]] && [ $rc18b != 0 ] &&
   ! grep -qv -e '--check' "$t/calls"; then
  ok "19 ct259-destroy: the check runs its playbook; apply-recorded with no pass or go only re-checks"
else bad "19 rc=$rc18a/$rc18b [$c18] [$(cat "$t/calls")] $(cat "$t/18b.out")"; fi

# 22 the proxy, firewall, connector and sso jobs take the settable host values from `view proxmox`, as a 0600 vars file that is gone after the run
iv_file() { sed -n 's/.* -e @\([^ ]*iv-vars[^ ]*\).*/\1/p' "$t/calls" | head -1; }
json "new" "/tmp/a" "write config" "move" none > "$t/out-check.json"
: > "$t/calls"; : > "$t/sudo-calls"
job check firewall > "$t/22a.out" 2>&1; rc22=$?
ivf=$(iv_file)
if [ $rc22 = 0 ] && [ -n "$ivf" ] && [ ! -e "$ivf" ] && grep -q -- "-u invops $t/libexec/inventory.sh view proxmox" "$t/sudo-calls"; then
  ok "22 firewall: asks the inventory wrapper for view proxmox as invops, passes a vars file, deletes it after"
else bad "22 rc=$rc22 file=[$ivf] sudo=[$(cat "$t/sudo-calls")] $(cat "$t/22a.out")"; fi
# the file's content and mode, caught while the playbook runs
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
echo "\$*" >> "$t/calls"
for a in "\$@"; do case \$a in @*iv-vars*) f=\${a#@}; stat -c %a "\$f" > "$t/iv-mode"; cp "\$f" "$t/iv-copy" ;; esac; done
case " \$* " in *" --check "*) cat "$t/out-check.json" ;; *) cat "$t/out-apply.json" ;; esac
EOF
job check proxy > "$t/22b.out" 2>&1
if python3 - "$t/iv-copy" "$(cat "$t/iv-mode" 2>/dev/null)" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert sys.argv[2] == "600", sys.argv[2]
assert d == {"proxmox_cert_names": ["test-one.example"], "proxmox_firewall_enable": True, "proxmox_firewall_home_lan_cidr": "192.0.2.0/24"}, d
PY
then ok "22 the vars file is 0600 and holds the listed names only (no unlisted name, no all.vars)"
else bad "22 vars file wrong: $(cat "$t/iv-copy" 2>/dev/null) mode=$(cat "$t/iv-mode" 2>/dev/null)"; fi
# no view, no job; the read-only jobs never ask
: > "$t/calls"; echo 1 > "$t/view-rc"
job check proxy > "$t/22c.out" 2>&1; rc22c=$?
rm -f "$t/view-rc"
if [ $rc22c = 1 ] && [ ! -s "$t/calls" ] && grep -q "view proxmox gave no usable values" "$t/22c.out"; then
  ok "22 a failing view stops the job before the playbook, with no silent fallback"
else bad "22 rc=$rc22c calls=[$(cat "$t/calls")] $(cat "$t/22c.out")"; fi
: > "$t/sudo-calls"
job check memory > "$t/22d.out" 2>&1
[ ! -s "$t/sudo-calls" ] && ok "22 the memory job never asks for the view" || bad "22 memory asked: $(cat "$t/sudo-calls")"

exit "$fail"
