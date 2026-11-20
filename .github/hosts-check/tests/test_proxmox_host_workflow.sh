#!/usr/bin/env bash
# The workflow lab-proxmox-host.yml must offer exactly the jobs the wrapper proxmox-host has, and must hand the job
# name to the wrapper for both actions. The runner is the only thing that may apply a job (the wrapper's sudo lines
# give sessions check and log only), so a job the workflow can't name can't be applied at all: before the `job`
# input, `sso` and `agent-access` could be checked but never applied. Run from the repository root's checkout.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(cd "$here/../.." && pwd)
wf=$root/.github/workflows/lab-proxmox-host.yml
wrapper=$root/hosts/ansible/roles/agent_box/files/proxmox-host.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "not ok  $1"; fail=1; }

# 1. The workflow's choices equal the wrapper's job names.
# `memory` is read-only and for a session on the box (`proxmox-host check memory`); `ksm` and `ksm-off` are applied by a session
# through `apply-recorded` (a reviewer pass and a go for the commit). None is offered by the workflow, which runs on the
# box and whose file's hash the runner hook pins (D-0042 rule 4), so a change to the workflow is a change to that pin too.
want=$(grep -oE '^declare -A jobs=\(.*\)' "$wrapper" | grep -oE '\[[a-z-]+\]=' | tr -d '[]=' | grep -Evx 'memory|ksm|ksm-off' | sort | tr '\n' ' ')
have=$(python3 -I - "$wf" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get("on") or d.get(True)
job = on["workflow_dispatch"]["inputs"].get("job")
print((" ".join(sorted(job["options"])) + " ") if job else "(no job input) ")
PY
)
[ "$want" = "$have" ] && ok "the workflow offers the wrapper's jobs: $have" || bad "the workflow offers [$have] but the wrapper has [$want]"

# 2. The run step passes the job to the wrapper, for check and for apply, in the order the wrapper reads.
python3 -I - "$wf" > "$t/run.sh" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d["jobs"]["proxmox-host"]["steps"][0]["run"])
PY
mkdir -p "$t/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\n' "$t" > "$t/bin/proxmox-host"; chmod +x "$t/bin/proxmox-host"
sed -i "s|/usr/local/bin/proxmox-host|$t/bin/proxmox-host|g" "$t/run.sh"
for job in $have; do
  : > "$t/calls"
  JOB=$job ACTION=check PASS_ID='' CHECK_HASH='' bash "$t/run.sh"
  JOB=$job ACTION=apply PASS_ID=cmsg_0123456789abc CHECK_HASH=0123456789ab bash "$t/run.sh"
  got=$(tr '\n' '|' < "$t/calls")
  [ "$got" = "check $job|apply $job cmsg_0123456789abc 0123456789ab|" ] && ok "job $job: check and apply reach the wrapper with the job first" || bad "job $job: the wrapper got [$got]"
done
# 3. Job restore-reader runs the reader playbook, and that playbook grants the read-only user only: it sets the reader's keys
#    and never the writer's (a write login on the backup disk is a different right and needs its own job).
pb=$root/hosts/ansible/playbooks/proxmox-restic-reader.yml
grep -Eq '^declare -A jobs=.*\[restore-reader\]=playbooks/proxmox-restic-reader\.yml[ )]' "$wrapper" \
  && ok "job restore-reader runs playbooks/proxmox-restic-reader.yml" || bad "job restore-reader does not run playbooks/proxmox-restic-reader.yml"
if grep -q 'proxmox_restic_sftp_set_reader: true' "$pb" && ! grep -Eq 'set_writer|writer_keys' "$pb"; then
  ok "the reader playbook sets the reader's keys and never the writer's"
else
  bad "the reader playbook must set set_reader true and must not mention set_writer or writer_keys"
fi
exit "$fail"
