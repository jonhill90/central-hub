#!/usr/bin/env bash
# The same-page merging job (playbooks/proxmox-ksm.yml and proxmox-ksm-off.yml, both importing playbooks/tasks/proxmox-ksm.yml).
# The real tasks run on localhost with the host's reads replaced by made-up values and its writes (tee, qm, systemd, the boot file)
# replaced by one log line each, in the order they would run:
#   1. Both playbooks are valid, `ksm` is on and `ksm-off` off, and the wrapper maps both jobs.
#   2. On, on a fresh host: the prior state (three kernel values, ksmtuned enabled and active) is saved to a file; allow-ksm 0 is set for
#      each protected VM that exists and lacks it (not for one with no config, not for one that has it); ksmtuned is stopped and
#      disabled; the pace is written before the switch.
#   3. On again: the saved file keeps the state from before the first run (it is not overwritten with the state ksm left).
#   4. Off: run 2 first (unmerge), then the saved pace, then the saved run; ksmtuned as it was; the saved file and the boot file go.
#      With ksmtuned saved as stopped and disabled it stays stopped and disabled; with KSM saved as already on there is no run 2.
#   5. Off refuses with no saved state, and refuses an unmerge that would leave less than 1 GiB of free memory. The memory an
#      unmerge needs is pages_sharing in full (the saving, ksm.rst), not pages_sharing minus pages_shared.
#   6. On refuses while VM 400 is running with merging on, and goes on when its process has mem-merge=off or it is not running.
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
t = open(sys.argv[1] + "/tasks/proxmox-ksm.yml").read()
print("vms-ok" if all("/etc/pve/qemu-server/%d.conf" % n in t for n in (100, 258, 400)) else "vms-wrong")
PY
)
jobs_ok=0
grep -q '\[ksm\]=playbooks/proxmox-ksm.yml' "$wrapper" && grep -q '\[ksm-off\]=playbooks/proxmox-ksm-off.yml' "$wrapper" && jobs_ok=1
if [[ $r == *pace-same* && $r == *flags-ok* && $r == *vms-ok* && $jobs_ok == 1 ]]; then ok "1. both playbooks are valid, on and off differ only in the switch, the protected VMs are 100, 258 and 400, and the wrapper maps both jobs"; else bad "1. $r jobs_ok=$jobs_ok"; fi

# The harness: the real tasks, with reads and writes replaced.
cat > "$t/make.py" <<'PY'
import json, sys, yaml
tasks_file, out, case = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
t = case["dir"]
tasks = yaml.safe_load(open(tasks_file))
log = t + "/writes.log"
def logline(line, **kw):
    d = {"ansible.builtin.lineinfile": {"path": log, "line": line, "create": True}}
    d.update(kw)
    return d
play_tasks = []
for task in tasks:
    n = task["name"]
    keep = {k: v for k, v in task.items() if k in ("name", "when", "loop", "loop_control")}
    if n == "ksm | Read the services":
        continue
    if n == "ksm | Read the kernel's current values":
        play_tasks.append({"name": n, "ansible.builtin.set_fact": {"ksm_now": {"stdout_lines": case["ksm"]}}})
    elif n == "ksm | Read the free memory":
        play_tasks.append({"name": n, "ansible.builtin.set_fact": {"ksm_mem": {"stdout": "MemAvailable: %d kB" % (case["free_mib"] * 1024)}}})
    elif n == "ksm | Read the VM processes' command lines":
        play_tasks.append({"name": n, "ansible.builtin.set_fact": {"ksm_procs": {"stdout_lines": case.get("procs", [])}}})
    elif n.startswith("ksm | Read which protected VMs"):
        play_tasks.append({"name": n, "ansible.builtin.set_fact": {"ksm_allow": {"stdout_lines": case["allow"]}}})
    elif n == "ksm | Protected VMs kept out of merging (applies at each one's next start)":
        play_tasks.append(dict(keep, **logline("qm set {{ item }} --allow-ksm 0")))
    elif n.startswith("ksm | ksmtuned stopped and disabled"):
        play_tasks.append(dict(keep, **logline("systemd ksmtuned stopped disabled")))
    elif n == "ksm | ksmtuned as it was":
        play_tasks.append(dict(keep, **logline("systemd ksmtuned {{ 'started' if ksm_prior['ksmtuned_active'] | default('no') == 'yes' else 'stopped' }} enabled={{ ksm_prior['ksmtuned_enabled'] | default('no') == 'yes' }}")))
    elif n == "ksm | The three values, kept across a reboot":
        play_tasks.append(dict(keep, **logline("boot file written")))
    elif n.startswith("ksm | The kernel's pace, then its switch"):
        play_tasks.append(dict(keep, **logline("tee {{ item }}={{ ksm_want[item] }}")))
    elif n == "ksm | The kernel put back as it was":
        play_tasks.append(dict(keep, **logline("tee {{ item.k }}={{ item.v }}")))
    elif n == "ksm | The boot file and the saved state removed":
        play_tasks.append(dict(keep, **{"ansible.builtin.file": {"path": "{{ item }}", "state": "absent"}}))
        play_tasks[-1]["loop"] = ["{{ proxmox_ksm_prior_file }}"]
        play_tasks.append(logline("boot file removed", when=task["when"]))
    elif "ansible.builtin.copy" in task and task["ansible.builtin.copy"]["dest"] == "{{ proxmox_ksm_prior_file }}":
        c = dict(task["ansible.builtin.copy"]); c.pop("owner"); c.pop("group")
        play_tasks.append(dict(keep, **{"ansible.builtin.copy": c}))
    else:
        play_tasks.append(task)
play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
         "vars": {"proxmox_ksm_enabled": case["enabled"], "proxmox_ksm_sleep_millisecs": 200, "proxmox_ksm_pages_to_scan": 1000,
                  "proxmox_ksm_prior_file": t + "/prior",
                  "ansible_facts": {"services": case["services"]}},
         "tasks": play_tasks}]
yaml.safe_dump(play, open(out, "w"))
PY
run_case() { # <name> <json: enabled ksm free_mib allow services> [prior file text]
  local name=$1 json=$2 prior=${3:-}
  mkdir -p "$t/$name"; : > "$t/$name/writes.log"
  [[ -z $prior ]] || printf '%s\n' "$prior" > "$t/$name/prior"
  python3 -I "$t/make.py" "$root/hosts/ansible/playbooks/tasks/proxmox-ksm.yml" "$t/$name.yml" "$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); d["dir"]=sys.argv[2]; print(json.dumps(d))' "$json" "$t/$name")"
  ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, "$t/$name.yml" > "$t/$name/out" 2>&1 && echo 0 > "$t/$name/rc" || echo 1 > "$t/$name/rc"
}
log() { tr '\n' '|' < "$t/$1/writes.log"; }
RUNNING='{"ksmtuned.service": {"state": "running", "status": "enabled"}}'
STOPPED='{"ksmtuned.service": {"state": "stopped", "status": "disabled"}}'
KSM_OFF='["/sys/kernel/mm/ksm/run:0", "/sys/kernel/mm/ksm/sleep_millisecs:20", "/sys/kernel/mm/ksm/pages_to_scan:100", "/sys/kernel/mm/ksm/pages_shared:0", "/sys/kernel/mm/ksm/pages_sharing:0"]'
KSM_ON='["/sys/kernel/mm/ksm/run:1", "/sys/kernel/mm/ksm/sleep_millisecs:200", "/sys/kernel/mm/ksm/pages_to_scan:1000", "/sys/kernel/mm/ksm/pages_shared:1000", "/sys/kernel/mm/ksm/pages_sharing:5000"]'
ALLOW='["/etc/pve/qemu-server/100.conf:0", "/etc/pve/qemu-server/258.conf:0"]'

# 2. On, on a fresh host: VM 400 has no config (skipped), 100 and 258 lack allow-ksm 0.
run_case on_fresh "{\"enabled\": true, \"ksm\": $KSM_OFF, \"free_mib\": 8000, \"allow\": $ALLOW, \"services\": $RUNNING}"
want_prior=$'run=0\nsleep_millisecs=20\npages_to_scan=100\nksmtuned_enabled=yes\nksmtuned_active=yes'
if [[ $(cat "$t/on_fresh/prior" 2>/dev/null) == "$want_prior" ]]; then ok "2a. on saves the prior values and ksmtuned's state to the file"; else bad "2a. prior: $(cat "$t/on_fresh/prior" 2>&1) / $(tail -5 "$t/on_fresh/out")"; fi
if [[ $(log on_fresh) == "qm set 100 --allow-ksm 0|qm set 258 --allow-ksm 0|systemd ksmtuned stopped disabled|boot file written|tee sleep_millisecs=200|tee pages_to_scan=1000|tee run=1|" ]]; then
  ok "2b. on sets allow-ksm 0 for the protected VMs that exist (not 400), stops ksmtuned, then writes the pace before the switch"
else bad "2b. $(log on_fresh)"; fi
# A VM that already has it is not set again.
run_case on_has "{\"enabled\": true, \"ksm\": $KSM_OFF, \"free_mib\": 8000, \"allow\": [\"/etc/pve/qemu-server/100.conf:1\", \"/etc/pve/qemu-server/258.conf:0\"], \"services\": $RUNNING}"
if [[ $(log on_has) == "qm set 258 --allow-ksm 0|"* && $(log on_has) != *"qm set 100"* ]]; then ok "2c. a VM that already has allow-ksm 0 is not set again"; else bad "2c. $(log on_has)"; fi

# 3. On again, with the state ksm left: the saved file keeps the state from before the first run.
run_case on_again "{\"enabled\": true, \"ksm\": $KSM_ON, \"free_mib\": 8000, \"allow\": [\"/etc/pve/qemu-server/100.conf:1\", \"/etc/pve/qemu-server/258.conf:1\"], \"services\": $STOPPED}" "$want_prior"
if [[ $(cat "$t/on_again/prior") == "$want_prior" && -z $(log on_again | tr -d '|' | sed 's/boot file written//;s/systemd ksmtuned stopped disabled//') ]]; then
  ok "3. a second on keeps the first run's saved state and writes nothing it does not need to"
else bad "3. $(cat "$t/on_again/prior") / $(log on_again)"; fi

# 4. Off.
run_case off_back "{\"enabled\": false, \"ksm\": $KSM_ON, \"free_mib\": 8000, \"allow\": [], \"services\": $STOPPED}" "$want_prior"
if [[ $(log off_back) == "tee run=2|tee sleep_millisecs=20|tee pages_to_scan=100|tee run=0|systemd ksmtuned started enabled=True|boot file removed|" && ! -e $t/off_back/prior ]]; then
  ok "4a. off unmerges (run 2), restores the saved pace and run, starts and enables ksmtuned as it was, and removes the saved file"
else bad "4a. $(log off_back) prior-exists=$([[ -e $t/off_back/prior ]] && echo y || echo n) $(tail -8 "$t/off_back/out")"; fi
tuned_off=$'run=0\nsleep_millisecs=20\npages_to_scan=100\nksmtuned_enabled=no\nksmtuned_active=no'
run_case off_tuned "{\"enabled\": false, \"ksm\": $KSM_ON, \"free_mib\": 8000, \"allow\": [], \"services\": $STOPPED}" "$tuned_off"
if [[ $(log off_tuned) == *"systemd ksmtuned stopped enabled=False"* ]]; then ok "4b. ksmtuned saved as stopped and disabled stays so"; else bad "4b. $(log off_tuned)"; fi
was_on=$'run=1\nsleep_millisecs=100\npages_to_scan=500\nksmtuned_enabled=yes\nksmtuned_active=yes'
run_case off_wason "{\"enabled\": false, \"ksm\": $KSM_ON, \"free_mib\": 8000, \"allow\": [], \"services\": $STOPPED}" "$was_on"
if [[ $(log off_wason) == "tee sleep_millisecs=100|tee pages_to_scan=500|systemd ksmtuned started enabled=True|boot file removed|" ]]; then ok "4c. with KSM saved as already on there is no run 2 and no change to run"; else bad "4c. $(log off_wason)"; fi

# 5. Refusals.
run_case off_none "{\"enabled\": false, \"ksm\": $KSM_ON, \"free_mib\": 8000, \"allow\": [], \"services\": $STOPPED}"
if [[ $(cat "$t/off_none/rc") == 1 && $(cat "$t/off_none/out") == *"no saved state"* && -z $(log off_none) ]]; then ok "5a. off with no saved state refuses and writes nothing"; else bad "5a. $(tail -6 "$t/off_none/out") / $(log off_none)"; fi
BIG='["/sys/kernel/mm/ksm/run:1", "/sys/kernel/mm/ksm/sleep_millisecs:200", "/sys/kernel/mm/ksm/pages_to_scan:1000", "/sys/kernel/mm/ksm/pages_shared:1000", "/sys/kernel/mm/ksm/pages_sharing:3001000"]'
run_case off_big "{\"enabled\": false, \"ksm\": $BIG, \"free_mib\": 4000, \"allow\": [], \"services\": $STOPPED}" "$want_prior"
if [[ $(cat "$t/off_big/rc") == 1 && $(cat "$t/off_big/out") == *"would leave less than 1024 MiB"* && -z $(log off_big) ]]; then ok "5b. off refuses an unmerge of 11.7 GiB into 4000 MiB free, and writes nothing"; else bad "5b. $(tail -6 "$t/off_big/out") / $(log off_big)"; fi
# The reviewer's case: 1,000,000 sharing and 900,000 shared is 3906 MiB that comes back; with 4500 MiB free that leaves 594 (under 1024).
# Counting only the difference (390 MiB) would pass it.
OVER='["/sys/kernel/mm/ksm/run:1", "/sys/kernel/mm/ksm/sleep_millisecs:200", "/sys/kernel/mm/ksm/pages_to_scan:1000", "/sys/kernel/mm/ksm/pages_shared:900000", "/sys/kernel/mm/ksm/pages_sharing:1000000"]'
run_case off_over "{\"enabled\": false, \"ksm\": $OVER, \"free_mib\": 4500, \"allow\": [], \"services\": $STOPPED}" "$want_prior"
if [[ $(cat "$t/off_over/rc") == 1 && $(cat "$t/off_over/out") == *"unmerging 3906 MiB"* && -z $(log off_over) ]]; then ok "5c. the unmerge counts pages_sharing in full: 3906 MiB into 4500 free is refused"; else bad "5c. $(tail -6 "$t/off_over/out") / $(log off_over)"; fi

# 6. The desktop.
run_case on_desk "{\"enabled\": true, \"ksm\": $KSM_OFF, \"free_mib\": 8000, \"allow\": $ALLOW, \"services\": $RUNNING, \"procs\": [\"/usr/bin/kvm -id 400 -name x -cpu host\", \"/usr/bin/kvm -id 258 -name y -machine type=q35,mem-merge=off\"]}"
if [[ $(cat "$t/on_desk/rc") == 1 && $(cat "$t/on_desk/out") == *"VM 400 (the desktop"* && -z $(log on_desk) && ! -e $t/on_desk/prior ]]; then ok "6a. on refuses while VM 400 runs with merging on, and changes nothing"; else bad "6a. $(tail -6 "$t/on_desk/out") / $(log on_desk)"; fi
run_case on_desk_off "{\"enabled\": true, \"ksm\": $KSM_OFF, \"free_mib\": 8000, \"allow\": $ALLOW, \"services\": $RUNNING, \"procs\": [\"/usr/bin/kvm -id 400 -name x -machine type=q35,mem-merge=off\", \"/usr/bin/kvm -id 4000 -name z\"]}"
if [[ $(cat "$t/on_desk_off/rc") == 0 && $(log on_desk_off) == *"tee run=1"* ]]; then ok "6b. on goes ahead when VM 400 has mem-merge=off (and VM 4000 is not VM 400)"; else bad "6b. $(tail -6 "$t/on_desk_off/out") / $(log on_desk_off)"; fi
exit $fail
