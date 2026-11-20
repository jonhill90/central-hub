#!/usr/bin/env bash
# playbooks/proxmox-memory.yml's REPORT task, run with ansible-playbook on fake values that stand in for what the four read tasks
# register (a made-up guest list with a name, ps lines with a name, meminfo and KSM lines):
#   1. It prints one line per guest (qemu and lxc only), per kvm process with its VM ID, per meminfo counter and per KSM counter,
#      with sizes in MiB.
#   2. No guest name, process argument or address in the made-up data reaches the output.
# Usage: .github/hosts-check/tests/test_proxmox_memory_report.sh   (needs ansible-playbook and python3 with PyYAML)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
python3 -I - "$root/hosts/ansible/playbooks/proxmox-memory.yml" "$t/p.yml" <<'PY'
import json, sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))[0]["tasks"]
report = next(x for x in tasks if x["name"] == "memory | REPORT")
guests = [{"vmid": 301, "type": "qemu", "status": "running", "maxmem": 4294967296, "mem": 3221225472, "name": "secret-host-name"},
          {"vmid": 900, "type": "lxc", "status": "stopped", "maxmem": 536870912, "mem": 0, "name": "x"},
          {"type": "storage", "id": "storage/x/local", "status": "available"}]
facts = {"memory_guests": {"stdout": json.dumps(guests)},
         "memory_host": {"stdout_lines": ["MemTotal:       32786344 kB", "MemAvailable:    8609340 kB", "Shmem:  2048 kB"]},
         "memory_kvm": {"stdout_lines": ["4194304 /usr/bin/kvm -id 301 -name secret-host-name,debug-threads=on -cpu host 192.0.2.10",
                                         "1048576 /usr/bin/kvm -id 258 -name other"]},
         "memory_ksm": {"stdout_lines": ["/sys/kernel/mm/ksm/run:0", "/sys/kernel/mm/ksm/pages_shared:7", "/sys/kernel/mm/ksm/pages_sharing:9"]}}
play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
         "tasks": [{"name": "fake", "ansible.builtin.set_fact": facts}, report]}]
yaml.safe_dump(play, open(sys.argv[2], "w"))
PY
out=$(ANSIBLE_NOCOLOR=1 ANSIBLE_CALLBACK_RESULT_FORMAT=yaml ansible-playbook -i localhost, "$t/p.yml" 2>&1 || true)
want='guest 301 qemu running maxmem 4096 mem 3072
guest 900 lxc stopped maxmem 512 mem 0
kvm id 301 rss 4096
kvm id 258 rss 1024
host memtotal 32017
host memavailable 8407
host shmem 2
host ksm run 0
host ksm pages_shared 7
host ksm pages_sharing 9'
got=$(grep -E '^ +(guest|kvm|host) ' <<<"$out" | sed -E 's/^ +//')
if [[ $got == "$want" ]]; then ok "1. the report has one line per guest, process and counter, in MiB"; else bad "1. got: $got"; fi
if ! grep -q 'secret-host-name\|192.0.2.10\|debug-threads\|storage/x' <<<"$got"; then ok "2. no name, argument or address reaches the report"; else bad "2. $got"; fi
exit $fail
