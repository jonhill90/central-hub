#!/usr/bin/env bash
# The dev inventory copy that rebuild.sh makes (its python block) puts a test admin in the dev realm and keeps the
# owner's name, email and extra users out of it, and still drops the Mac's ssh settings.
#   1. k8s_identity_owner_username is dev-admin, the email is empty and there are no extra users.
#   2. A proxmox group and an ssh proxy setting from the source inventory are gone.
# Usage: .github/hosts-check/tests/test_rebuild_dev_inventory.sh   (needs python3 with pyyaml)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
fail=0
out=$(python3 - "$root/hosts/ansible/roles/agent_box/files/rebuild.sh" <<'PY'
import re, subprocess, sys, tempfile, yaml
s = open(sys.argv[1]).read()
code = re.search(r"<<'PY'\n(.*?)\nPY\n", s, re.S).group(1)
d = tempfile.mkdtemp()
inv = {"all": {"children": {
    "proxmox": {"hosts": {"pve": {"ansible_host": "192.0.2.1"}}},
    "k8s_nodes": {"hosts": {"n1": {"ansible_host": "192.0.2.10", "ansible_ssh_common_args": "-o ProxyJump=x"}},
                  "vars": {"k8s_identity_owner_username": "someone", "k8s_identity_owner_email": "a@b.invalid",
                           "k8s_identity_extra_users": [{"username": "x"}]}}}}}
yaml.safe_dump(inv, open(d + "/src.yml", "w"))
subprocess.run(["python3", "-I", "-c", code, d + "/src.yml", d + "/dst.yml", "/k", "/kh", "/keys"], check=True)
out = yaml.safe_load(open(d + "/dst.yml"))["all"]["children"]
v = out["k8s_nodes"]["vars"]
print(1, v["k8s_identity_owner_username"] == "dev-admin" and v["k8s_identity_owner_email"] == "" and v["k8s_identity_extra_users"] == [])
print(2, "proxmox" not in out and "ansible_ssh_common_args" not in out["k8s_nodes"]["hosts"]["n1"])
PY
)
for n in 1 2; do
  if grep -q "^$n True" <<< "$out"; then echo "ok   $n"; else echo "FAIL $n"; fail=1; fi
done
exit "$fail"
