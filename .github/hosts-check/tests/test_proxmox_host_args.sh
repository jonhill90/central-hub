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
git init -q -b main "$t/src" && mkdir -p "$t/src/hosts/ansible/playbooks" && echo "- hosts: proxmox" > "$t/src/hosts/ansible/playbooks/proxmox-proxy.yml"
git -C "$t/src" add -A && git -C "$t/src" -c user.name=t -c user.email=t@t commit -q -m one
git clone -q --bare "$t/src" "$t/main.git"

# The stand-in: records its arguments, prints out-check.json with --check, out-apply.json without.
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/sh
echo "\$*" >> "$t/calls"
case " \$* " in *" --check "*) cat "$t/out-check.json" ;; *) cat "$t/out-apply.json" ;; esac
EOF
chmod +x "$t/bin/ansible-playbook"
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

sed -e "s|^dir=.*|dir=$t/dir|" -e "s|^work=.*|work=$t/work|" -e "s|^ansible_bin=.*|ansible_bin=$t/bin|" \
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

exit "$fail"
