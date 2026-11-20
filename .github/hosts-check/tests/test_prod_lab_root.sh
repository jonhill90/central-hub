#!/bin/bash
# The agent_box role's prod_lab_root tasks, run for real (ansible-playbook on localhost, temp folders as the guard and keys
# folders): the box's guard copy of the lab root is installed at <keys>/prod/lab-ca/root.crt, byte for byte, mode 0600; a file
# that is not exactly one CA certificate, or holds a private key, stops the run and installs nothing; a box with no guard copy
# installs nothing and does not fail; a second run changes nothing.
set -euo pipefail
cd "$(dirname "$0")/../../.."
tasks=hosts/ansible/roles/agent_box/tasks/prod_lab_root.yml
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

# The role's tasks, with owner and group dropped (they need root), run against temp folders.
python3 -I - "$tasks" "$t/play.yml" "$t" <<'PY'
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
for task in tasks:
    for mod in ("ansible.builtin.file", "ansible.builtin.copy"):
        if mod in task:
            task[mod].pop("owner", None)
            task[mod].pop("group", None)
t = sys.argv[3]
yaml.safe_dump([{"hosts": "localhost", "gather_facts": False, "connection": "local",
                 "vars": {"agent_box_guard_dir": t + "/guard", "agent_box_keys_dir": t + "/keys", "agent_box_keys_user": "x"},
                 "tasks": tasks}], open(sys.argv[2], "w"))
PY
ok "the role's prod_lab_root tasks load"

run() { ansible-playbook -i localhost, "$t/play.yml" > "$t/out" 2>&1; }
dest="$t/keys/prod/lab-ca/root.crt"

# 1. No guard copy: nothing installed, no failure.
mkdir -p "$t/guard"
if run && [ ! -e "$dest" ] && grep -q 'nothing is installed' "$t/out"; then ok "no guard copy: nothing installed, no failure"; else bad "no guard copy"; cat "$t/out"; fi

# A CA certificate, and files that must be refused.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$t/ca.key" -out "$t/ca.crt" -days 2 -subj "/CN=Test Root" \
  -addext "basicConstraints=critical,CA:TRUE" > /dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$t/leaf.key" -out "$t/leaf.crt" -days 2 -subj "/CN=Leaf" \
  -addext "basicConstraints=CA:FALSE" > /dev/null 2>&1

# An intermediate CA: signed by the root, so subject differs from issuer.
openssl req -newkey rsa:2048 -nodes -keyout "$t/int.key" -out "$t/int.csr" -subj "/CN=Test Intermediate" > /dev/null 2>&1
printf 'basicConstraints=critical,CA:TRUE\n' > "$t/int.ext"
openssl x509 -req -in "$t/int.csr" -CA "$t/ca.crt" -CAkey "$t/ca.key" -CAcreateserial -out "$t/int.crt" -days 2 -extfile "$t/int.ext" > /dev/null 2>&1

# 2. Refused files install nothing.
for case in leaf two key intermediate; do
  rm -rf "$t/keys"
  case $case in
    leaf) cp "$t/leaf.crt" "$t/guard/lab-root.crt" ;;
    two) cat "$t/ca.crt" "$t/leaf.crt" > "$t/guard/lab-root.crt" ;;
    key) cat "$t/ca.crt" "$t/ca.key" > "$t/guard/lab-root.crt" ;;
    intermediate) cp "$t/int.crt" "$t/guard/lab-root.crt" ;;
  esac
  if run; then bad "a $case file was accepted"; elif [ -e "$dest" ]; then bad "a $case file was installed"; else ok "a $case file is refused and nothing is installed"; fi
done

# 3. A CA certificate is installed, byte for byte, mode 0600, and a second run changes nothing.
rm -rf "$t/keys"; cp "$t/ca.crt" "$t/guard/lab-root.crt"
if run && cmp -s "$t/ca.crt" "$dest"; then ok "the CA certificate is installed byte for byte"; else bad "install"; cat "$t/out"; fi
m=$(stat -c %a "$dest"); if [ "$m" = 600 ]; then ok "mode 600"; else bad "mode $m"; fi
if run && grep -q "changed=0" "$t/out"; then ok "a second run changes nothing"; else bad "a second run changed something"; fi

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
