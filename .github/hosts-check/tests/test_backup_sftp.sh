#!/usr/bin/env bash
# The Proxmox host as c1's restic target (agent pick 262), end to end with real sshd and restic. Two containers from
# the stand-in Proxmox image (proxy/Dockerfile: Debian trixie, systemd, OpenSSH): "host" plays the Proxmox host with
# a mount at /mnt/hdd-backup, "node" plays a c1 node. Ansible runs from here, as the controller does. Test values only.
#   1. Role proxmox_restic_sftp refuses a host where nothing is mounted at the repository's mount.
#   2. The node's key and ssh alias (k8s_backup tasks/sftp_key.yml and sftp.yml), then the host role with that key as
#      the writer and the node's address as the only source; the alias probe sees /c1. A second run changes nothing.
#   3. restic 0.19.1 (the role's pin, checked against its SHA-256) through the alias: `cat config` exits 10 on the
#      empty repository, init, backup, a full restore equal to the source, and `forget --prune` (the nodes prune).
#   4. The writer gets nothing but sftp in its chroot: no shell command runs, `ls /` lists only c1, /etc can't be
#      read; root can't sign in from the node's address even with a key root accepts; the writer's key is refused
#      from any other address; sshd's effective settings for the writer forbid every kind of forwarding and a tty.
#   5. The reader, from a second container ("dev", its own address, k8s_backup_reader): after the host's group-read
#      pass it lists and restores the snapshot with --no-lock, and every write (backup, forget, a lock) is refused.
#      Root stays refused from both addresses after the reader run and after the next writer run, since each run
#      writes one user's keys and the root refusal must cover both.
#   6. The real k8s-backup.yml's first --check run on a node with no key gets through every play and changes nothing.
#   7. With the Azure sign-in off, the role turns off a c1-backup-azure-cert.timer a past run left on.
# Usage: .github/hosts-check/tests/test_backup_sftp.sh   (needs docker that can run a privileged systemd container,
# ansible-playbook, ssh-keygen, curl, bunzip2). RESTIC_BIN=<path> uses that restic instead of downloading the pin.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
here=$root/.github/hosts-check
t=$(mktemp -d)
image=localhost/central-hub-sftp-test:$$
cleanup() {
  docker ps -aq --filter "label=central-hub-sftp-test=$$" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker rmi -f "$image" >/dev/null 2>&1 || true
  rm -rf "$t"
}
trap cleanup EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

docker build -q -t "$image" "$here/proxy" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$t/key"

if [ -n "${RESTIC_BIN:-}" ]; then
  cp "$RESTIC_BIN" "$t/restic"
else
  read -r restic_v restic_sum < <(python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d["k8s_backup_restic_version"], d["k8s_backup_restic_sha256"])
' "$root/hosts/ansible/roles/k8s_backup/defaults/main.yml")
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 15 -o "$t/restic.bz2" \
    "https://github.com/restic/restic/releases/download/v$restic_v/restic_${restic_v}_linux_amd64.bz2"
  echo "$restic_sum  $t/restic.bz2" | sha256sum --check --quiet
  bunzip2 -c "$t/restic.bz2" > "$t/restic"
fi
chmod 0755 "$t/restic"

start() { # name [docker args...]: a fresh systemd container with sshd up and our key for root; prints its address
  local name=central-hub-sftp-$1-$$; shift
  docker run -d --name "$name" --label "central-hub-sftp-test=$$" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock "$@" "$image" >/dev/null
  docker exec -i "$name" sh -c 'umask 077; cat > /root/.ssh/authorized_keys' < "$t/key.pub"
  for _ in $(seq 1 60); do docker exec "$name" systemctl is-active -q ssh.service 2>/dev/null && break; sleep 1; done
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name"
}
host_ip=$(start host --tmpfs /mnt/hdd-backup:mode=0755)
bare_ip=$(start bare)
node_ip=$(start node)
dev_ip=$(start dev)
H=central-hub-sftp-host-$$ N=central-hub-sftp-node-$$ D=central-hub-sftp-dev-$$
docker cp "$t/restic" "$N:/usr/local/bin/restic"
docker cp "$t/restic" "$D:/usr/local/bin/restic"

common="ansible_user: root, ansible_ssh_private_key_file: $t/key, ansible_python_interpreter: /usr/bin/python3, ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
cat > "$t/inv.yml" <<INV
all:
  hosts:
    host: { ansible_host: $host_ip, $common }
    bare: { ansible_host: $bare_ip, $common }
    node: { ansible_host: $node_ip, $common }
    dev: { ansible_host: $dev_ip, $common }
INV
# The plays of k8s-backup.yml and k8s-restore.yml that touch the target, with the role's own task files.
cat > "$t/play.yml" <<'YML'
- hosts: "{{ node_host | default('node') }}"
  gather_facts: false
  tasks:
    - ansible.builtin.include_role: {name: k8s_backup, tasks_from: sftp_key}
- hosts: "{{ target | default('host') }}"
  gather_facts: false
  tasks:
    - ansible.builtin.include_role: {name: proxmox_restic_sftp}
      vars:
        proxmox_restic_sftp_set_writer: "{{ not (k8s_backup_reader | default(false) | bool) }}"
        proxmox_restic_sftp_set_reader: "{{ k8s_backup_reader | default(false) | bool }}"
        n: "{{ node_host | default('node') }}"
        proxmox_restic_sftp_writer_keys: "{{ [{'key': hostvars[n].k8s_backup_sftp_pubkey, 'from': hostvars[n].ansible_host}] }}"
        proxmox_restic_sftp_reader_keys: "{{ proxmox_restic_sftp_writer_keys }}"
        proxmox_restic_sftp_no_root_from: ["{{ hostvars[n].ansible_host }}"]
- hosts: "{{ node_host | default('node') }}"
  gather_facts: false
  vars:
    k8s_backup_sftp_address: "{{ hostvars['host'].ansible_host }}"
    k8s_backup_sftp_host_key: "{{ hostvars['host'].proxmox_restic_sftp_host_key }}"
  tasks:
    - ansible.builtin.include_role: {name: k8s_backup, tasks_from: sftp}
- hosts: host
  gather_facts: false
  tasks:
    - ansible.builtin.include_role: {name: proxmox_restic_sftp, tasks_from: group_read}
YML
play() { (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i "$t/inv.yml" "$t/play.yml" "$@"); }
on_node() { docker exec -i "$N" bash -c "$1"; }

# 1
if play -e target=bare > "$t/1.log" 2>&1; then bad "1 a host with nothing mounted was not refused"
elif grep -q "The backup HDD is mounted" "$t/1.log"; then ok "1 a host with nothing mounted at /mnt/hdd-backup is refused"
else bad "1 the run failed some other way"; tail -20 "$t/1.log"; fi

# 2
if play > "$t/2.log" 2>&1; then ok "2 node key, host role and alias probe pass"; else bad "2 the run failed"; tail -40 "$t/2.log"; fi
if play > "$t/2b.log" 2>&1 && grep -Eq 'changed=0 +unreachable=0 +failed=0' <(grep '^host ' "$t/2b.log") \
   && grep -Eq 'changed=0 +unreachable=0 +failed=0' <(grep '^node ' "$t/2b.log"); then
  ok "2 a second run changes nothing"
else bad "2 a second run changed something or failed"; grep -E '^(host|node) ' "$t/2b.log" || tail -30 "$t/2b.log"; fi
# The node env file as the role writes it (the task's own content line), from a controller file that still names Azure.
printf 'RESTIC_REPOSITORY=azure:c1-backup:/c1\nRESTIC_PASSWORD=x\n' > "$t/ctl.env"
python3 -c '
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
c = next(x for x in tasks if x.get("name") == "timers | The env file on the node")["ansible.builtin.copy"]["content"]
play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
         "vars_files": [sys.argv[2], sys.argv[3]],
         "tasks": [{"ansible.builtin.copy": {"content": c, "dest": sys.argv[4], "mode": "0600"}}]}]
yaml.safe_dump(play, open(sys.argv[5], "w"))
' "$root/hosts/ansible/roles/k8s_backup/tasks/main.yml" "$root/hosts/ansible/roles/k8s_backup/defaults/main.yml" \
  "$root/hosts/ansible/roles/k8s_backup/vars/main.yml" "$t/node.env" "$t/env.yml"
(cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i localhost, "$t/env.yml" \
  -e ansible_python_interpreter=auto_silent -e k8s_backup_sftp=true -e k8s_backup_is_control_plane=false -e "k8s_backup_env_file=$t/ctl.env" >"$t/env.log" 2>&1) \
  || { bad "2 the env file task did not render"; tail -20 "$t/env.log"; }
[ "$(bash -c 'set -a; . "$1"; echo "$RESTIC_REPOSITORY"' _ "$t/node.env")" = "sftp:c1-backup-target:/c1" ] \
  && ok "2 the node env file's last RESTIC_REPOSITORY is the alias, over the controller's Azure line" \
  || { bad "2 the node env file names another repository"; cat -A "$t/node.env"; }

# 3
on_node 'mkdir -p /srv/src/a && head -c 300000 /dev/urandom > /srv/src/a/blob && echo canary-1 > /srv/src/canary'
export_env='export RESTIC_PASSWORD=test-only-password RESTIC_REPOSITORY=sftp:c1-backup-target:/c1 RESTIC_CACHE_DIR=/var/cache/restic-test'
rc=0; on_node "$export_env; restic cat config >/dev/null 2>&1" || rc=$?
[ "$rc" = 10 ] && ok "3 cat config on the empty repository exits 10" || bad "3 cat config exited $rc, not 10"
on_node "$export_env; restic init -q && restic backup -q --host node /srv/src && restic snapshots --json" > "$t/snaps.json" \
  && ok "3 init and backup through the alias" || bad "3 init or backup failed"
on_node "$export_env; rm -rf /srv/back && restic restore -q latest --target /srv/back >/dev/null && diff -r /srv/src /srv/back/srv/src" \
  && ok "3 a full restore equals the source" || bad "3 the restore differs from the source"
on_node "$export_env; restic forget -q --keep-last 1 --prune" >/dev/null && ok "3 forget --prune works for the writer" || bad "3 forget --prune failed"

# 4
out=$(on_node 'ssh c1-backup-target id 2>&1' || true)
[[ $out != *uid=* ]] && ok "4 no shell command runs as the writer" || bad "4 a shell command ran: $out"
out=$(on_node 'printf "ls /\n" | sftp -q -b - c1-backup-target 2>&1' || true)
[ "$(printf '%s\n' "$out" | grep -v '^sftp>' | tr -s ' \n' ' ' | sed 's/ $//')" = "/c1" ] && ok "4 the chroot holds only c1" || bad "4 ls / showed: $out"
on_node 'printf "get /etc/passwd /tmp/p\n" | sftp -q -b - c1-backup-target >/dev/null 2>&1' && bad "4 the writer read /etc/passwd" || ok "4 /etc/passwd can't be read"
docker exec "$H" sh -c "cat >> /root/.ssh/authorized_keys" < <(docker exec "$N" cat /etc/central-hub/backup-ssh/id_ed25519.pub)
on_node "ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /etc/central-hub/backup-ssh/id_ed25519 root@$host_ip true 2>/dev/null" \
  && bad "4 root signed in from the node's address" || ok "4 root can't sign in from the node's address, even with a key root accepts"
docker exec "$H" true && (cd "$t" && ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$t/key" root@"$host_ip" true 2>/dev/null) \
  && ok "4 root still signs in from the controller" || bad "4 root can't sign in from the controller any more"
docker cp "$N:/etc/central-hub/backup-ssh/id_ed25519" "$t/nodekey" >/dev/null && chmod 600 "$t/nodekey"
on_node "ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /etc/central-hub/backup-ssh/id_ed25519 -s c1backup@$host_ip sftp </dev/null >/dev/null 2>&1" \
  && ok "4 the same command signs the writer in from the node (control for the next check)" || bad "4 the writer can't sign in from the node by plain ssh"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$t/nodekey" -s c1backup@"$host_ip" sftp </dev/null >/dev/null 2>&1 \
  && bad "4 the writer's key worked from another address" || ok "4 the writer's key is refused from any other address"
eff=$(docker exec "$H" sshd -T -C "user=c1backup,host=node,addr=$node_ip")
for want in "allowtcpforwarding no" "allowagentforwarding no" "allowstreamlocalforwarding no" "permittunnel no" "permittty no" \
            "x11forwarding no" "chrootdirectory /mnt/hdd-backup/restic" "forcecommand internal-sftp -u 0027 -d /c1" "authenticationmethods publickey"; do
  grep -qx "$want" <<<"$eff" && ok "4 writer: $want" || bad "4 writer lacks: $want"
done
grep -qx "permitrootlogin no" < <(docker exec "$H" sshd -T -C "user=root,host=node,addr=$node_ip") && ok "4 root: permitrootlogin no from the node" || bad "4 root may sign in from the node"

# 5
on_dev() { docker exec -i "$D" bash -c "$1"; }
root_refused() { # address: sshd's effective PermitRootLogin for root from that address is no
  grep -qx "permitrootlogin no" < <(docker exec "$H" sshd -T -C "user=root,host=x,addr=$1")
}
if play -e node_host=dev -e k8s_backup_reader=true -e k8s_backup_sftp_alias=c1-backup-read > "$t/5.log" 2>&1; then
  ok "5 the reader's key, host role and read-only alias pass"
else bad "5 the reader run failed"; tail -40 "$t/5.log"; fi
on_node "$export_env; restic backup -q --host node /srv/src" >/dev/null && ok "5 the writer backs up after the reader run" || bad "5 the writer lost access"
docker exec "$H" bash -c 'cd /mnt/hdd-backup/restic && runuser -u c1restore -- find c1 -type f ! -readable | head -3' > "$t/unreadable" 2>/dev/null || true
root_refused "$node_ip" && root_refused "$dev_ip" && ok "5 after the reader run, root is refused from the node and from dev" \
  || bad "5 after the reader run, root is not refused from both addresses"
read_env='export RESTIC_PASSWORD=test-only-password RESTIC_REPOSITORY=sftp:c1-backup-read:/c1 RESTIC_CACHE_DIR=/var/cache/restic-read'
on_dev "$read_env; restic --no-lock snapshots --json" > "$t/rsnaps.json" 2>"$t/r.err" \
  && [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$t/rsnaps.json")" -ge 1 ] \
  && ok "5 the reader lists the snapshots" || { bad "5 the reader can't list: $(head -3 "$t/r.err")"; cat "$t/unreadable"; }
on_dev "$read_env; rm -rf /srv/rback && restic --no-lock restore -q latest --target /srv/rback >/dev/null" && docker exec "$N" tar -C /srv -c src | on_dev "rm -rf /srv/src && tar -C /srv -x && diff -r /srv/src /srv/rback/srv/src" \
  && ok "5 the reader restores the snapshot whole" || bad "5 the reader's restore failed or differs"
on_dev "$read_env; restic backup -q --host dev /srv/src" >/dev/null 2>&1 && bad "5 the reader wrote a backup" || ok "5 the reader can't back up"
on_dev "$read_env; restic forget -q --keep-last 1" >/dev/null 2>&1 && bad "5 the reader ran forget" || ok "5 the reader can't forget"
on_dev "$read_env; restic snapshots -q" >/dev/null 2>&1 && bad "5 the reader made a lock" || ok "5 the reader can't take a lock"

if play > "$t/6.log" 2>&1; then ok "5 a writer run after the reader run passes"; else bad "5 the writer run after the reader run failed"; tail -30 "$t/6.log"; fi
root_refused "$node_ip" && root_refused "$dev_ip" && ok "5 after the next writer run, root is still refused from both" \
  || bad "5 after the next writer run, root is not refused from both addresses"
on_dev "$read_env; restic --no-lock snapshots -q" >/dev/null && ok "5 the reader still reads after the writer run" || bad "5 the writer run cut the reader off"

# 6
# The real playbook's first --check run, on a node that never had a key: play 1 makes none in check mode, so play 2
# skips the host role. It must still read the host's key, or play 3 stops at sftp.yml's assert and plays 2 to 4 go
# unchecked (the first check run of the change on the Mac, 2026-11-18). Nothing may change on the node.
fresh_ip=$(start fresh)
F=central-hub-sftp-fresh-$$
printf 'RESTIC_REPOSITORY=azure:c1-backup:/c1\nRESTIC_PASSWORD=x\n' > "$t/ctl6.env" && chmod 600 "$t/ctl6.env"
cat > "$t/inv6.yml" <<INV
all:
  vars: { k8s_backup_enabled: true, k8s_backup_sftp: true, k8s_backup_env_file: $t/ctl6.env }
  children:
    k8s_nodes: { hosts: { fresh: { ansible_host: $fresh_ip, $common } } }
    k8s_control_plane: { hosts: {} }
    proxmox: { hosts: { host: { ansible_host: $host_ip, proxmox_host_mgmt_address: $host_ip, $common } } }
INV
if (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i "$t/inv6.yml" playbooks/k8s-backup.yml \
      --check --diff --tags drill) > "$t/7.log" 2>&1; then
  ok "6 a first --check run of k8s-backup.yml gets through every play on a node with no key"
else bad "6 the first --check run of k8s-backup.yml failed"; grep -E 'fatal|FAILED|msg' "$t/7.log" | head -10; fi
grep -q "TASK \[proxmox_restic_sftp : Remember the host key\]" "$t/7.log" && ok "6 the host play read the host's key in check mode" \
  || bad "6 the host play did not read the host's key"
docker exec "$F" test -e /etc/central-hub/backup-ssh/id_ed25519 && bad "6 the check run made a key on the node" \
  || ok "6 the check run left the node without a key"

# 7
# The Azure certificate timer goes off when the Azure sign-in does: a node that ran the Azure path keeps the unit files,
# and the timer's daily renew would fail on every node once the env file has no AZURE_* lines. The role's own two tasks.
docker exec -i "$F" bash -c 'cat > /etc/systemd/system/c1-backup-azure-cert.service; printf "[Timer]\nOnCalendar=daily\n[Install]\nWantedBy=timers.target\n" > /etc/systemd/system/c1-backup-azure-cert.timer; systemctl daemon-reload && systemctl enable -q --now c1-backup-azure-cert.timer' \
  <<<$'[Service]\nType=oneshot\nExecStart=/bin/false'
python3 -c '
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
names = ["timers | The Azure certificate timer, if a past run made it",
         "timers | The Azure certificate timer off while the Azure sign-in is off"]
picked = [x for x in tasks if x.get("name") in names]
if len(picked) != 2: sys.exit("the role has no tasks named " + repr(names))
yaml.safe_dump([{"hosts": "fresh:node", "gather_facts": False, "vars": {"k8s_backup_azure_identity": False},
                 "tasks": picked}], open(sys.argv[2], "w"))
' "$root/hosts/ansible/roles/k8s_backup/tasks/main.yml" "$t/azoff.yml" > "$t/8.log" 2>&1 || { bad "7 the role's Azure timer tasks are missing"; cat "$t/8.log"; }
printf 'all:\n  hosts:\n    fresh: { ansible_host: %s, %s }\n    node: { ansible_host: %s, %s }\n' "$fresh_ip" "$common" "$node_ip" "$common" > "$t/inv7.yml"
azoff() { (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i "$t/inv7.yml" "$t/azoff.yml"); }
if [ -s "$t/azoff.yml" ] && azoff > "$t/9.log" 2>&1; then
  st=$(docker exec "$F" bash -c 'echo "$(systemctl is-enabled c1-backup-azure-cert.timer) $(systemctl is-active c1-backup-azure-cert.timer)"' || true)
  [ "$st" = "disabled inactive" ] && ok "7 the Azure certificate timer is off once the sign-in is off" || bad "7 the timer is still: $st"
else bad "7 the Azure timer tasks failed"; tail -20 "$t/9.log"; fi
if [ -s "$t/azoff.yml" ] && azoff > "$t/10.log" 2>&1 && grep -Eq '^fresh .*changed=0 .*failed=0' "$t/10.log" \
   && grep -Eq '^node .*changed=0 .*failed=0' "$t/10.log"; then
  ok "7 a second run changes nothing, and a node that never had the timer passes"
else bad "7 the second run changed something or failed"; grep -E '^(fresh|node) ' "$t/10.log" || tail -20 "$t/10.log"; fi

[[ $fail -eq 0 ]] && echo "backup sftp: all checks passed" || { echo "backup sftp: a check failed"; exit 1; }
