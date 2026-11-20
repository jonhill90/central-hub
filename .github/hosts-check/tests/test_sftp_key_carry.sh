#!/bin/bash
# The sftp key carry (rebuild-prod.sh step 1a, roles/k8s_backup/tasks/sftp_key.yml), run for real with ansible-playbook on
# localhost and a temp folder as the node's key folder: a carried key pair is put back as the node's own (0600 and 0644), is never
# put over a key the node already has, a half pair is ignored (a new key is made), and the play's host-key expression reads the
# pinned key out of the carried known_hosts and is empty when none was carried.
set -euo pipefail
cd "$(dirname "$0")/../../.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$t/seed" "$t/roles"
cp -r "$PWD/hosts/ansible/roles/k8s_backup" "$t/roles/k8s_backup"
ssh-keygen -q -t ed25519 -N '' -C carried -f "$t/seed/localhost.key"
mv "$t/seed/localhost.key.pub" "$t/seed/localhost.pub"
echo "c1-backup-target ssh-ed25519 AAAAhostkeyblob" > "$t/seed/localhost.known_hosts"
cat > "$t/play.yml" <<Y
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    k8s_backup_sftp_dir: $t/node
    k8s_backup_sftp_seed_dir: $t/seed
    k8s_backup_azure_identity: false
  tasks:
    - ansible.builtin.include_role: { name: k8s_backup, tasks_from: sftp_key }
Y
play() { ANSIBLE_ROLES_PATH="$t/roles" ANSIBLE_LOCALHOST_WARNING=false ansible-playbook -i localhost, "$t/play.yml" >"$t/out" 2>&1 || true; }
# On a copy: owner and group need root, so a non-root run drops them.
sed -i '/^    owner: root$/d;/^    group: root$/d' "$t/roles/k8s_backup/tasks/sftp_key.yml"

play
if [[ -f $t/node/id_ed25519 && $(stat -c %a "$t/node/id_ed25519") == 600 && $(stat -c %a "$t/node/id_ed25519.pub") == 644 ]] &&
   cmp -s "$t/node/id_ed25519" "$t/seed/localhost.key" && cmp -s "$t/node/id_ed25519.pub" "$t/seed/localhost.pub"; then
  ok "1. a carried key pair is put back as the node's own, 0600 and 0644"
else bad "1. $(tail -5 "$t/out")"; fi

echo "node-made-key" > "$t/node/id_ed25519"
play
if [[ $(cat "$t/node/id_ed25519") == node-made-key ]]; then ok "2. a key the node already has is never overwritten"; else bad "2."; fi

rm -rf "$t/node"; rm -f "$t/seed/localhost.pub"
play
if [[ -f $t/node/id_ed25519 ]] && ! cmp -s "$t/node/id_ed25519" "$t/seed/localhost.key"; then ok "3. a half pair is ignored: the node makes its own key"; else bad "3. $(tail -5 "$t/out")"; fi

# The play's host-key expression, as written in playbooks/k8s-backup.yml and k8s-restore.yml.
expr=$(python3 -I - <<'PY'
import yaml
for f in ("k8s-backup", "k8s-restore"):
    for play in yaml.safe_load(open("hosts/ansible/playbooks/%s.yml" % f)):
        v = (play.get("vars") or {}).get("k8s_backup_sftp_host_key")
        if v: print(f + "\t" + " ".join(v.split()))
PY
)
n=$(printf '%s\n' "$expr" | grep -c .)
if [[ $n -eq 2 ]]; then ok "4. both playbooks carry the host-key expression"; else bad "4. $n"; fi
while IFS=$'\t' read -r f e; do
  cat > "$t/expr.yml" <<Y
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    k8s_backup_sftp_proxmox: ""
    k8s_backup_sftp_seed_dir: $t/seed
    k8s_backup_sftp_host_key: "$(printf '%s' "$e" | sed 's/"/\\"/g')"
  tasks:
    - ansible.builtin.debug: { msg: "KEY=[{{ k8s_backup_sftp_host_key }}]" }
    - ansible.builtin.set_fact: { seed_dir_gone: "{{ k8s_backup_sftp_seed_dir }}/none" }
Y
  ANSIBLE_LOCALHOST_WARNING=false ansible-playbook -i localhost, "$t/expr.yml" >"$t/o2" 2>&1 || true
  if grep -q 'KEY=\[ssh-ed25519 AAAAhostkeyblob\]' "$t/o2"; then ok "5. $f: the pinned host key is read from the carried known_hosts"; else bad "5. $f: $(grep -E 'KEY=|ERROR|error' "$t/o2" | head -3)"; fi
done <<< "$expr"
echo "$fails failed"; [[ $fails -eq 0 ]]
