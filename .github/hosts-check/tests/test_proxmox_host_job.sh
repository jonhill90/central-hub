#!/usr/bin/env bash
# The Proxmox host job end to end (Library plans/r1-host-job/DESIGN.md v3.1, section 7), against the stand-in Proxmox
# host of test_proxy.sh (proxy/): systemd, sshd, nginx on 443 and 80, a stand-in pveproxy. Root's authorized_keys is a
# link to /etc/pve/priv/authorized_keys, as on Proxmox VE. Test values only.
#   1. playbooks/proxmox-host-key.yml puts the job's key line in, narrowed by from= to this runner's address, and the
#      job's key logs in; with from= another address, the same key is refused. It writes the file in place (same inode:
#      no rename and no chmod, which pmxcfs refuses), keeps the other lines, and with state absent takes the line out.
#      A write that fails part-way (a full tmpfs) is put back from the copy off pmxcfs, and the run fails.
#   2. The wrapper's check prints a hash and changes nothing on the host (nginx still holds 443), and gives the
#      same hash twice.
#   3. apply with a hash that is not the check's refuses, and nginx still holds 443.
#   4. apply with the check's hash moves 443 to Apache httpd and passes.
#   5. A check after the apply gives a new hash (the host changed), so the old hash no longer applies.
# Usage: .github/hosts-check/tests/test_proxmox_host_job.sh   (needs docker that can run a privileged systemd
# container, git, ansible-playbook with the collections in hosts/ansible/collections, ssh-keygen, ssh)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
here=$root/.github/hosts-check
t=$(mktemp -d)
image=localhost/central-hub-proxmox-host-test:$$
name=central-hub-proxmox-host-$$
cleanup() {
  docker ps -aq --filter "label=central-hub-proxmox-host-test=$$" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker rmi -f "$image" >/dev/null 2>&1 || true
  rm -rf "$t"
}
trap cleanup EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

docker build -q -t "$image" "$here/proxy" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$t/admin"                       # the controller's key
ssh-keygen -q -t ed25519 -N '' -C central-hub-r1 -f "$t/jobkey"    # the box's job key
docker run -d --name "$name" --label "central-hub-proxmox-host-test=$$" --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock "$image" >/dev/null
docker exec -i "$name" sh -c 'umask 077; mkdir -p /etc/pve/priv && cat > /etc/pve/priv/authorized_keys && ln -sf /etc/pve/priv/authorized_keys /root/.ssh/authorized_keys' < "$t/admin.pub"
for _ in $(seq 1 60); do
  docker exec "$name" systemctl is-active -q ssh.service nginx.service standin-pveproxy.service 2>/dev/null && break
  sleep 1
done
# Ansible's apt module needs python3-apt for a check run (it installs it itself only on a real run). The stand-in's
# image leaves it out so test_proxy.sh covers a host without it; this test adds it, as the job's first check needs it.
docker exec "$name" sh -c 'apt-get -qq update && apt-get -qq install -y --no-install-recommends python3-apt' >/dev/null 2>&1 \
  || { echo "FAIL: could not install python3-apt in the stand-in"; exit 1; }
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
gw=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' "$name")   # this runner, as the host sees it
ssh-keyscan -t ed25519 "$ip" 2>/dev/null > "$t/known_hosts"
on443() { docker exec "$name" ss -Hltnp 'sport = :443' | grep -o '"[a-z0-9]*"' | head -1 | tr -d '"'; }

# The controller's inventory: the stand-in host, and an agent box whose lifeline address is this runner's.
admin_inv() { # admin_inv <box address>
  cat > "$t/admin.yml" <<INV
all:
  children:
    proxmox:
      hosts:
        standin:
          ansible_host: $ip
          ansible_user: root
          ansible_ssh_private_key_file: $t/admin
          ansible_ssh_common_args: -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$t/known_hosts
          ansible_python_interpreter: /usr/bin/python3
    agent_box:
      hosts:
        box:
          agent_box_lifeline_address: $1/24
INV
}
keyplay() { (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i "$t/admin.yml" playbooks/proxmox-host-key.yml -e "proxmox_host_key_file=$t/jobkey.pub" "$@"); }
jobssh() { ssh -n -i "$t/jobkey" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$t/known_hosts" "root@$ip" true 2>/dev/null; }

# 1
ino() { docker exec "$name" stat -c %i /etc/pve/priv/authorized_keys; }
ino0=$(ino)
admin_inv "$gw"
keyplay > "$t/1.log" 2>&1 || { bad "1 the key playbook failed"; tail -20 "$t/1.log"; }
docker exec "$name" grep -q "^restrict,from=\"$gw\" ssh-ed25519 .* central-hub-r1\$" /etc/pve/priv/authorized_keys \
  && ok "1 the key line is in, narrowed to this runner's address" || bad "1 line: $(docker exec "$name" cat /etc/pve/priv/authorized_keys)"
jobssh && ok "1 the job's key logs in from the lifeline address" || bad "1 the job's key was refused from its own address"
admin_inv 192.0.2.99
keyplay > "$t/1b.log" 2>&1 || bad "1 the key playbook failed for another address"
jobssh && bad "1 the job's key logged in from an address not in from=" || ok "1 from another address the key is refused"
[ "$(docker exec "$name" grep -c central-hub-r1 /etc/pve/priv/authorized_keys)" = 1 ] && ok "1 one line, replaced in place" || bad "1 more than one job line"
keyplay -e proxmox_host_key_state=absent > "$t/1c.log" 2>&1 || bad "1 the key playbook failed with state absent"
docker exec "$name" grep -q central-hub-r1 /etc/pve/priv/authorized_keys && bad "1 state absent left the job's line" || ok "1 state absent takes the line out"
docker exec "$name" cat /etc/pve/priv/authorized_keys | cmp -s - "$t/admin.pub" && ok "1 the other lines are kept as they were" || bad "1 the other lines changed"
admin_inv "$gw"; keyplay > "$t/1d.log" 2>&1 || bad "1 the key playbook failed putting the line back"
keyplay > "$t/1e.log" 2>&1 && grep -q 'changed=0' "$t/1e.log" && ok "1 a second run changes nothing" || bad "1 second run: $(grep -h 'changed=' "$t/1e.log")"
[ "$(ino)" = "$ino0" ] && ok "1 the file was written in place (same inode)" || bad "1 the file was replaced, not written in place"
# A write that fails part-way is put back. Here the folder is a full 4 KiB tmpfs: the file is just under 4 KiB with no
# job line, so adding the line runs out of space after the file was cut short.
{ cat "$t/admin.pub"; printf '# %s\n' "$(head -c 3900 /dev/zero | tr '\0' x)"; } > "$t/padded"
docker exec "$name" sh -c 'cp /etc/pve/priv/authorized_keys /root/ak.keep && mount -t tmpfs -o size=4k tmpfs /etc/pve/priv'
docker exec -i "$name" sh -c 'cat > /etc/pve/priv/authorized_keys' < "$t/padded"
keyplay > "$t/1f.log" 2>&1 && bad "1 the key playbook passed although its write failed"
grep -q 'is as it was before this run' "$t/1f.log" && docker exec "$name" cat /etc/pve/priv/authorized_keys | cmp -s - "$t/padded" \
  && ok "1 a write that fails part-way is put back, and the run fails" || bad "1 failed write: $(grep -h -o 'msg.\{0,200\}' "$t/1f.log" | head -3)"
docker exec "$name" cat /root/authorized_keys.pre-central-hub-r1 | cmp -s - "$t/padded" && ok "1 the copy off pmxcfs holds the file as it was" || bad "1 no copy off pmxcfs"
docker exec "$name" sh -c 'umount /etc/pve/priv && cmp -s /root/ak.keep /etc/pve/priv/authorized_keys' || { echo "FAIL: the stand-in's key file did not come back"; exit 1; }

# The wrapper, pointed at a test folder, at this commit as main, with the job's inventory.
mkdir -p "$t/dir/inventory" "$t/work"
cp "$t/jobkey" "$t/dir/id_ed25519"; cp "$t/known_hosts" "$t/dir/known_hosts"
cat > "$t/dir/inventory/hosts.yml" <<INV
proxmox:
  hosts:
    proxmox_host:
      ansible_host: $ip
      ansible_user: root
      ansible_ssh_private_key_file: $t/dir/id_ed25519
      ansible_ssh_common_args: -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$t/dir/known_hosts
      ansible_python_interpreter: /usr/bin/python3
      proxmox_cert_names: [pve.example.test]
INV
git clone -q --bare "$root" "$t/main.git"
git -C "$t/main.git" update-ref refs/heads/main "$(git -C "$root" rev-parse HEAD)"
bin=$(dirname "$(command -v ansible-playbook)")
sed -e "s|^dir=.*|dir=$t/dir|" -e "s|^work=.*|work=$t/work|" -e "s|^ansible_bin=.*|ansible_bin=$bin|" \
    -e "s|^collections=.*|collections=$root/hosts/ansible/collections|" -e "s|^repo_url=.*|repo_url=$t/main.git|" \
    "$root/hosts/ansible/roles/agent_box/files/proxmox-host.sh" > "$t/job.sh"
grep -q "^repo_url=$t/main.git" "$t/job.sh" || { echo "FAIL: the test could not point the wrapper at its folders"; exit 1; }
hashof() { sed -n 's/^proxmox-host: check \([0-9a-f]\{12\}\): .*/\1/p' "$1"; }

# 2
why() { # the failed tasks and the error log of the newest run, for a failed case
  tail -20 "$t/work/logs/"run-*.err 2>/dev/null || true
  cat "$t/work/logs/"*.extra 2>/dev/null | sed 's/^/not shown by the check: /' || true
  python3 - "$t/work/logs" <<'PY2' || true
import glob, json, os, sys
f = max(glob.glob(os.path.join(sys.argv[1], "*.json")), key=os.path.getmtime)
try:
    d = json.load(open(f))
except ValueError:
    print(open(f).read()[-2000:]); sys.exit()
for p in d.get("plays", []):
    for t in p.get("tasks", []):
        for h, r in t.get("hosts", {}).items():
            if r.get("failed") or r.get("unreachable"):
                print("failed:", t["task"]["name"], str(r.get("msg", ""))[:400], str(r.get("stderr", ""))[:400])
PY2
}
bash "$t/job.sh" check > "$t/2a.out" 2>&1 || { bad "2 check failed"; cat "$t/2a.out"; why; }
h=$(hashof "$t/2a.out")
[ -n "$h" ] && [ "$(on443)" = nginx ] && ok "2 check prints a hash ($h) and nginx still holds 443" || bad "2 hash '$h', 443 held by '$(on443)'"
bash "$t/job.sh" check > "$t/2b.out" 2>&1 || true
[ "$(hashof "$t/2b.out")" = "$h" ] && ok "2 the same host gives the same hash" || bad "2 hashes differ: $h vs $(hashof "$t/2b.out")"

# 3
bash "$t/job.sh" apply cmsg_0123456789ab 000000000000 > "$t/3.out" 2>&1 && bad "3 a wrong hash applied"
grep -q 'not the hash named' "$t/3.out" && [ "$(on443)" = nginx ] && ok "3 a wrong hash refuses, nginx still holds 443" || bad "3 $(cat "$t/3.out"); 443: $(on443)"

# 4
if bash "$t/job.sh" apply cmsg_0123456789ab "$h" > "$t/4.out" 2>&1; then ok "4 apply with the check's hash passes"; else bad "4 apply failed"; cat "$t/4.out"; why; fi
[ "$(on443)" = apache2 ] && ok "4 Apache httpd holds 443" || bad "4 443 held by '$(on443)'"

# 5
bash "$t/job.sh" check > "$t/5.out" 2>&1 || bad "5 check after the apply failed"
[ -n "$(hashof "$t/5.out")" ] && [ "$(hashof "$t/5.out")" != "$h" ] && ok "5 the host changed, so the hash changed" || bad "5 hash after apply: $(hashof "$t/5.out")"
bash "$t/job.sh" apply cmsg_0123456789ab "$h" > "$t/5b.out" 2>&1 && bad "5 the old hash applied again" || ok "5 the old hash no longer applies"

grep -h -e "$ip" -e 'pve.example.test' "$t"/[2-5]*.out && bad "6 the address or a name was printed" || ok "6 nothing printed names the host"
exit "$fail"
