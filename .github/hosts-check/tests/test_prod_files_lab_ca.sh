#!/usr/bin/env bash
# The agent box role's prod_files tasks, with the role's own agent_box_prod_files list, copy the three lab CA files that
# rebuild-prod.sh points the prod inventory at (k8s_certs_lab_ca_cert_file, k8s_certs_lab_ca_key_file,
# k8s_gitops_sso_root_ca_file) and never the root's key or passphrase. Runs the task file on localhost, with a stand-in
# controller home and keys folder:
#   1. The list names lab-ca/c1-intermediate-chain.crt, lab-ca/c1-intermediate.key and lab-ca/root.crt, each to the
#      dest rebuild-prod.sh reads, and neither lab-ca/root.key nor lab-ca/lab-ca.env.
#   2. A run copies the three into <keys>/prod/lab-ca/, each mode 0600 and owned by the keys user, byte for byte.
#   3. The intermediate key's content never reaches the output, and the root key on the controller is not copied.
# Usage: .github/hosts-check/tests/test_prod_files_lab_ca.sh   (needs ansible-core, python3 with pyyaml)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
defaults=$root/hosts/ansible/roles/agent_box/defaults/main.yml
prod=$root/hosts/ansible/roles/agent_box/files/rebuild-prod.sh

# 1
r1=$(python3 - "$defaults" "$prod" <<'PY'
import re, sys, yaml
files = yaml.safe_load(open(sys.argv[1]))["agent_box_prod_files"]
src = open(sys.argv[2]).read()
pairs = {(f["from"], f["path"], f["dest"]) for f in files}
want = ["c1-intermediate-chain.crt", "c1-intermediate.key", "root.crt"]
listed = all(("config", "lab-ca/" + n, "lab-ca/" + n) in pairs for n in want)
read = all(re.search(r'pkeys \+ "/lab-ca/' + re.escape(n) + '"', src) for n in want)
never = not any(f["path"] in ("lab-ca/root.key", "lab-ca/lab-ca.env") for f in files)
print(listed, read, never)
PY
)
if [[ $r1 == "True True True" ]]; then
  ok "1. the list names the three lab CA files rebuild-prod.sh reads, to the same paths, and not the root's key or passphrase"
else bad "1. listed, read by rebuild-prod.sh, root key left out: $r1"; fi

# 2 and 3
mkdir -p "$t/home/.config/central-hub/lab-ca" "$t/home/.local/state/central-hub" "$t/clone" "$t/box"
printf -- '-----BEGIN CERTIFICATE-----\nchain-int\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nchain-root\n-----END CERTIFICATE-----\n' > "$t/home/.config/central-hub/lab-ca/c1-intermediate-chain.crt"
printf -- '-----BEGIN EC PRIVATE KEY-----\nINTERMEDIATEKEYSECRET\n-----END EC PRIVATE KEY-----\n' > "$t/home/.config/central-hub/lab-ca/c1-intermediate.key"
printf -- '-----BEGIN CERTIFICATE-----\nroot-public\n-----END CERTIFICATE-----\n' > "$t/home/.config/central-hub/lab-ca/root.crt"
printf -- '-----BEGIN EC PRIVATE KEY-----\nROOTKEYSECRET\n-----END EC PRIVATE KEY-----\n' > "$t/home/.config/central-hub/lab-ca/root.key"
echo 'LAB_ROOT_CA_KEY_PASSPHRASE=ROOTPASSSECRET' > "$t/home/.config/central-hub/lab-ca/lab-ca.env"
chmod 0600 "$t/home/.config/central-hub/lab-ca/"*.key "$t/home/.config/central-hub/lab-ca/lab-ca.env"
cat > "$t/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars_files: [$defaults]
  tasks:
    - ansible.builtin.include_tasks: $root/hosts/ansible/roles/agent_box/tasks/prod_files.yml
PLAY
HOME=$t/home ANSIBLE_LOCALHOST_WARNING=false ANSIBLE_INVENTORY_UNPARSED_WARNING=false \
  ansible-playbook -i localhost, -c local "$t/play.yml" \
  -e "agent_box_keys_dir=$t/box" -e "agent_box_keys_user=$(id -un)" -e "agent_box_prod_files_clone=$t/clone" \
  -e "agent_box_prod_theme_src=" -e "ansible_python_interpreter=$(command -v python3)" > "$t/out" 2>&1
rc=$?
r2=""
for n in c1-intermediate-chain.crt c1-intermediate.key root.crt; do
  f=$t/box/prod/lab-ca/$n
  if cmp -s "$t/home/.config/central-hub/lab-ca/$n" "$f" && [[ $(stat -c '%a %U' "$f") == "600 $(id -un)" ]]; then r2+="ok "; else r2+="$n:$(stat -c '%a %U' "$f" 2>&1) "; fi
done
if [[ $rc -eq 0 && $r2 == "ok ok ok " ]]; then
  ok "2. a run copies the chain, the intermediate key and the root certificate into prod/lab-ca, 0600, the keys user's"
else bad "2. rc=$rc [$r2] $(tail -n 20 "$t/out")"; fi
if ! grep -q 'SECRET' "$t/out" && [[ ! -e $t/box/prod/lab-ca/root.key && ! -e $t/box/prod/lab-ca/lab-ca.env ]] &&
   grep -q 'lab-ca/c1-intermediate.key' "$t/out"; then
  ok "3. the key's content never reaches the output (its name does), and the root's key and passphrase stay on the controller"
else bad "3. $(grep -c SECRET "$t/out") secret lines in the output; root.key on the box: $([[ -e $t/box/prod/lab-ca/root.key ]] && echo yes || echo no)"; fi

exit $fail
