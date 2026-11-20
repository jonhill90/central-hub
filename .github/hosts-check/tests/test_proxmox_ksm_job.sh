#!/usr/bin/env bash
# The same-page merging job (playbooks/proxmox-ksm.yml and proxmox-ksm-off.yml, both importing playbooks/tasks/proxmox-ksm.yml):
#   1. Both playbooks are valid, `ksm` sets enabled true and `ksm-off` false with the same pace, and the wrapper maps both jobs.
#   2. On fake reads, the tasks that parse the kernel's values and say whether they differ: on with run 0 is a change; on with the
#      wanted values is no change; off with run 1 is a change; off with run 0 is no change (the pace is not compared when off).
#   3. The shipped tasks pin the pace, write it to a boot file, stop ksmtuned when on, and start it again when off.
# Usage: .github/hosts-check/tests/test_proxmox_ksm_job.sh   (needs ansible-playbook and python3 with PyYAML)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
pb=$root/hosts/ansible/playbooks
wrapper=$root/hosts/ansible/roles/agent_box/files/proxmox-host.sh
for f in proxmox-ksm proxmox-ksm-off; do
  (cd "$root/hosts/ansible" && ansible-playbook --syntax-check -i localhost, "playbooks/$f.yml" >/dev/null 2>&1) || bad "1. $f.yml fails its syntax check"
done
r=$(python3 -I - "$pb" <<'PY'
import sys, yaml
on = yaml.safe_load(open(sys.argv[1] + "/proxmox-ksm.yml"))[0]["vars"]
off = yaml.safe_load(open(sys.argv[1] + "/proxmox-ksm-off.yml"))[0]["vars"]
print("pace-same" if on["proxmox_ksm_sleep_millisecs"] == off["proxmox_ksm_sleep_millisecs"] and on["proxmox_ksm_pages_to_scan"] == off["proxmox_ksm_pages_to_scan"] else "pace-differs")
print("flags-ok" if on["proxmox_ksm_enabled"] is True and off["proxmox_ksm_enabled"] is False else "flags-wrong")
PY
)
jobs_ok=0
grep -q '\[ksm\]=playbooks/proxmox-ksm.yml' "$wrapper" && grep -q '\[ksm-off\]=playbooks/proxmox-ksm-off.yml' "$wrapper" && jobs_ok=1
if [[ $r == *pace-same* && $r == *flags-ok* && $jobs_ok == 1 ]]; then ok "1. both playbooks are valid, on and off differ only in the switch, and the wrapper maps both jobs"; else bad "1. $r jobs_ok=$jobs_ok"; fi

# 2. Run the tasks that parse and compare, on fake reads.
python3 -I - "$pb/tasks/proxmox-ksm.yml" "$t" <<'PY'
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
parse = next(x for x in tasks if x["name"] == "ksm | The values this play sets")
diff = next(x for x in tasks if x["name"].startswith("ksm | The kernel's values differ"))
cases = {"on-from-0": (True, 0), "on-same": (True, 1), "off-from-1": (False, 1), "off-same": (False, 0)}
for name, (enabled, run) in cases.items():
    lines = ["/sys/kernel/mm/ksm/run:%d" % run, "/sys/kernel/mm/ksm/sleep_millisecs:%d" % (200 if run else 20),
             "/sys/kernel/mm/ksm/pages_to_scan:%d" % (1000 if run else 100)]
    play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
             "vars": {"proxmox_ksm_enabled": enabled, "proxmox_ksm_sleep_millisecs": 200, "proxmox_ksm_pages_to_scan": 1000},
             "tasks": [{"name": "fake", "ansible.builtin.set_fact": {"ksm_now": {"stdout_lines": lines}, "ksm_unit": {"stat": {"exists": True}}}},
                       parse, diff]}]
    yaml.safe_dump(play, open("%s/%s.yml" % (sys.argv[2], name), "w"))
PY
want() { # <case> <changed|ok>
  local out; out=$(ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, "$t/$1.yml" 2>&1 || true)
  if grep -qE "^$2: \[localhost\]" <(grep -A0 -E "^(changed|ok): \[localhost\]" <<<"$out" | tail -1); then ok "2. $1: $2"; else bad "2. $1 wanted $2: $out"; fi
}
want on-from-0 changed; want on-same ok; want off-from-1 changed; want off-same ok

# 3. What the shipped tasks do.
tf=$pb/tasks/proxmox-ksm.yml
if grep -q 'central-hub-ksm.conf' "$tf" && grep -q 'name: ksmtuned' "$tf" && grep -q 'state: stopped' "$tf" && grep -q 'state: started' "$tf" \
   && grep -q "'sleep_millisecs', 'pages_to_scan', 'run'" "$tf"; then ok "3. the tasks pin the pace first, keep it across a reboot, stop ksmtuned when on and start it when off"; else bad "3. a pinned step is missing from $tf"; fi
exit $fail
