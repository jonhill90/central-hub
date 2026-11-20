#!/usr/bin/env bash
# The Proxmox host's backup store for the agent box's own copies (playbooks/proxmox-restic-box.yml), end to end with real sshd and restic.
# Containers from the stand-in Proxmox image (proxy/Dockerfile: Debian trixie, systemd, OpenSSH): "host" plays the Proxmox host with a
# mount at /mnt/hdd-backup, "bare" a host with nothing mounted, "other" a machine at another address. Ansible and restic run from here, as
# the box does (the play is given this machine's address, as the host job is given the box's, so the key works from here). Test values only.
#   1. A host with nothing mounted is refused; a bad key line is refused with nothing changed.
#   2. The play passes on a host whose chroot and keys folder c1's role made; a second run changes nothing.
#   3. restic (the k8s_backup role's pin, checked against its SHA-256) through the box's key: cat config exits 10 on the empty folder, init,
#      backup, a full restore equal to the source, dump of one file, and forget --prune.
#   4. The user gets nothing but sftp in its chroot: no shell command runs, /etc/passwd can't be read, c1's repository folder can't be
#      read (a canary file is there), a write outside /box is refused; the key is refused from another address; sshd's effective
#      settings forbid every kind of forwarding and a tty.
#   5. Root still signs in from this machine's address, the very address the key works from (the host jobs reach the host as root from
#      the box): sshd's answer for root from it is not a refusal, and this play's second run, which signs in as root, passed.
# Usage: .github/hosts-check/tests/test_restic_box.sh   (needs docker that can run a privileged systemd container, ansible-playbook,
# ssh-keygen, curl, bunzip2). RESTIC_BIN=<path> uses that restic instead of downloading the pin.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
here=$root/.github/hosts-check
t=$(mktemp -d)
image=localhost/central-hub-box-test:$$
cleanup() {
  docker ps -aq --filter "label=central-hub-box-test=$$" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker rmi -f "$image" >/dev/null 2>&1 || true
  rm -rf "$t"
}
trap cleanup EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

docker build -q -t "$image" "$here/proxy" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$t/key"        # root's key, the controller's
ssh-keygen -q -t ed25519 -N '' -f "$t/boxkey"     # the box's backup key
boxpub=$(cut -d' ' -f1,2 "$t/boxkey.pub")

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
  local name=central-hub-box-$1-$$; shift
  docker run -d --name "$name" --label "central-hub-box-test=$$" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock "$@" "$image" >/dev/null
  docker exec -i "$name" sh -c 'umask 077; cat > /root/.ssh/authorized_keys' < "$t/key.pub"
  for _ in $(seq 1 60); do docker exec "$name" systemctl is-active -q ssh.service 2>/dev/null && break; sleep 1; done
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name"
}
host_ip=$(start host --tmpfs /mnt/hdd-backup:mode=0755)
bare_ip=$(start bare)
start other >/dev/null
H=central-hub-box-host-$$ O=central-hub-box-other-$$

# What c1's play leaves on the host before this one runs: the chroot (root's, 0755), the keys folder, and c1's repository with a canary.
docker exec "$H" bash -c 'install -d -m 0755 /mnt/hdd-backup/restic /etc/ssh/central-hub-restic
  useradd --system --shell /usr/sbin/nologin c1backup
  install -d -m 0750 -o c1backup -g c1backup /mnt/hdd-backup/restic/c1
  echo c1-canary > /mnt/hdd-backup/restic/c1/config; chown c1backup:c1backup /mnt/hdd-backup/restic/c1/config; chmod 0640 /mnt/hdd-backup/restic/c1/config'

common="ansible_user: root, ansible_ssh_private_key_file: $t/key, ansible_python_interpreter: /usr/bin/python3, ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
cat > "$t/inv.yml" <<INV
all:
  hosts:
    proxmox_host: { ansible_host: $host_ip, $common }
    bare: { ansible_host: $bare_ip, $common }
  children:
    proxmox: { hosts: { proxmox_host: {}, bare: {} } }
INV
play() { (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i "$t/inv.yml" playbooks/proxmox-restic-box.yml "$@"); }

src=$(ip -4 route get "$host_ip" | sed -n 's/.* src \([0-9.]*\).*/\1/p')   # the address the host sees this machine at
# 1
if play -l bare -e "proxmox_restic_box_key=$boxpub" -e "proxmox_restic_box_from=$src" > "$t/1.log" 2>&1; then bad "1 a host with nothing mounted was not refused"
elif grep -q "The backup disk is mounted" "$t/1.log"; then ok "1 a host with nothing mounted at /mnt/hdd-backup is refused"
else bad "1 the run failed some other way"; tail -20 "$t/1.log"; fi
for v in '' 'ssh-rsa AAAAB3NzaC1yc2E' "$boxpub comment"; do
  if play -l proxmox_host -e "proxmox_restic_box_key=$v" -e "proxmox_restic_box_from=$src" > "$t/1b.log" 2>&1; then bad "1 key '$v' was accepted"; fi
done
docker exec "$H" bash -c '! id boxbackup 2>/dev/null && [ ! -e /etc/ssh/sshd_config.d/41-central-hub-restic-box.conf ]' \
  && ok "1 three bad key lines are refused and nothing was changed" || bad "1 a bad key line changed the host"

# 2
if play -l proxmox_host -e "proxmox_restic_box_key=$boxpub" -e "proxmox_restic_box_from=$src" > "$t/2.log" 2>&1; then ok "2 the play passes"; else bad "2 the run failed"; tail -40 "$t/2.log"; fi
if play -l proxmox_host -e "proxmox_restic_box_key=$boxpub" -e "proxmox_restic_box_from=$src" > "$t/2b.log" 2>&1 && grep -Eq 'changed=0 +unreachable=0 +failed=0' <(grep '^proxmox_host ' "$t/2b.log"); then
  ok "2 a second run changes nothing (and signed in as root)"
else bad "2 a second run changed something or failed"; grep '^proxmox_host ' "$t/2b.log" || tail -30 "$t/2b.log"; fi
[ "$(docker exec "$H" stat -c '%U:%a' /mnt/hdd-backup/restic/box)" = "boxbackup:700" ] && ok "2 /box is the user's alone (0700)" || bad "2 /box is not boxbackup 0700"
[ "$(docker exec "$H" stat -c '%U:%a' /mnt/hdd-backup/restic)" = "root:755" ] && ok "2 the chroot is still root's (0755)" || bad "2 the chroot changed"
grep -qF "from=\"$src\"" <(docker exec "$H" cat /etc/ssh/central-hub-restic/boxbackup) \
  && ok "2 the key works only from the address the play was reached from" || bad "2 the key line has another from= address: $(docker exec "$H" cut -c1-60 /etc/ssh/central-hub-restic/boxbackup)"

# 3
sshopt=(-i "$t/boxkey" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
sftpcmd="ssh ${sshopt[*]} boxbackup@$host_ip -s sftp"
rx() { RESTIC_PASSWORD=test-only-password RESTIC_CACHE_DIR="$t/cache" "$t/restic" -r "sftp:boxbackup@$host_ip:/box" -o "sftp.command=$sftpcmd" "$@"; }
mkdir -p "$t/src/a" && head -c 300000 /dev/urandom > "$t/src/a/blob" && echo canary-1 > "$t/src/canary"
rc=0; rx cat config >/dev/null 2>&1 || rc=$?
[ "$rc" = 10 ] && ok "3 cat config on the empty folder exits 10" || bad "3 cat config exited $rc, not 10"
rx init -q && rx backup -q --host agent-box --tag opnsense "$t/src" && ok "3 init and backup through the box's key" || bad "3 init or backup failed"
rm -rf "$t/back" && rx restore -q latest --target "$t/back" >/dev/null && diff -r "$t/src" "$t/back$t/src" && ok "3 a full restore equals the source" || bad "3 the restore differs"
rx dump --host agent-box --tag opnsense latest "$t/src/canary" | cmp -s - "$t/src/canary" && ok "3 dump of one file reads back the same" || bad "3 dump differs"
rx forget -q --host agent-box --tag opnsense --keep-last 1 --prune >/dev/null && ok "3 forget --prune works" || bad "3 forget --prune failed"

# 4
out=$(ssh "${sshopt[@]}" boxbackup@"$host_ip" id 2>&1 || true)
[[ $out != *uid=* ]] && ok "4 no shell command runs as the user" || bad "4 a shell command ran: $out"
sftp_run() { printf '%s\n' "$1" | sftp -q "${sshopt[@]}" -b - boxbackup@"$host_ip" 2>&1; }
out=$(sftp_run 'ls /' | grep -v '^sftp>' | tr -s ' \n' ' ' | sed 's/ $//' | tr ' ' '\n' | sort | tr '\n' ' ')
[ "$out" = "/box /c1 " ] && ok "4 the chroot lists only box and c1 (names only)" || bad "4 ls / showed: $out"
sftp_run 'get /etc/passwd /tmp/p' | grep -qi "not found\|No such file" && ok "4 /etc/passwd can't be read" || bad "4 /etc/passwd read"
sftp_run "get /c1/config $t/c1config" >/dev/null 2>&1; [ ! -s "$t/c1config" ] && ok "4 c1's repository file can't be read" || bad "4 c1's canary was read"
sftp_run 'ls /c1' | grep -qi "denied\|permission" && ok "4 c1's folder can't be listed" || bad "4 c1's folder was listed"
sftp_run "put $t/src/canary /c1/x" | grep -qi "denied\|permission\|failure" ; docker exec "$H" test -e /mnt/hdd-backup/restic/c1/x && bad "4 a write into c1 worked" || ok "4 a write into c1 is refused"
sftp_run "put $t/src/canary /outside" | grep -qi "denied\|permission\|failure" ; docker exec "$H" test -e /mnt/hdd-backup/restic/outside && bad "4 a write beside /box worked" || ok "4 a write outside /box is refused"
[ "$(docker exec "$H" stat -c %a /mnt/hdd-backup/restic/box/config)" = 600 ] && ok "4 files the user makes are 0600" || bad "4 file mode: $(docker exec "$H" stat -c %a /mnt/hdd-backup/restic/box/config)"
docker cp "$t/boxkey" "$O:/tmp/boxkey" >/dev/null && docker exec "$O" chmod 600 /tmp/boxkey
docker exec "$O" bash -c "ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/boxkey -s boxbackup@$host_ip sftp </dev/null >/dev/null 2>&1" \
  && bad "4 the key worked from another address" || ok "4 the key is refused from any other address"
eff=$(docker exec "$H" sshd -T -C "user=boxbackup,host=box,addr=$src")
for want in "allowtcpforwarding no" "allowagentforwarding no" "allowstreamlocalforwarding no" "permittunnel no" "permittty no" \
            "x11forwarding no" "chrootdirectory /mnt/hdd-backup/restic" "forcecommand internal-sftp -u 0077 -d /box" "authenticationmethods publickey"; do
  grep -qx "$want" <<<"$eff" && ok "4 user: $want" || bad "4 user lacks: $want"
done

# 5
grep -qx "permitrootlogin no" < <(docker exec "$H" sshd -T -C "user=root,host=box,addr=$src") && bad "5 root is refused from the box's address" \
  || ok "5 sshd's answer for root from the box's address is not a refusal"
(cd "$t" && ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$t/key" root@"$host_ip" true 2>/dev/null) \
  && ok "5 root still signs in from the box's address" || bad "5 root can't sign in from the box's address"

[[ $fail -eq 0 ]] && echo "box store: all checks passed" || { echo "box store: a check failed"; exit 1; }
