#!/usr/bin/env bash
# The handoff of dev's worker address (hosts/ansible/roles/agent_box/files/dev-worker-address.sh), with the script's folders
# pointed into a temp folder and a stand-in ansible-inventory:
#   1. write puts exactly one line, the worker's address, in the file (mode 0640), and prints no address; it does not look at the VMs.
#   2. write with no worker or two workers leaves no file (and removes an older one).
#   3. write refuses an address that is not one dev node address, and leaves no file.
#   4. read prints the address, prints nothing and passes for a missing file, and refuses (naming no value) a file that is empty, holds
#      two lines, no final newline, spaces, a prefix length, a leading zero, another VLAN, .0, or .224 and up.
#   5. remove deletes the file and passes when there is none. The file survives a teardown: the teardown hook does not touch it, and
#      rebuild.sh writes it each time it has parsed the inventory (and so also on `teardown`).
#   6. A write leaves no temp file behind (the move is the only step that makes the file appear).
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
role=$src/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/work/state" "$t/handoff" "$t/libexec/ansible-venv/bin"
mkdir -p "$t/keys" "$t/hostkey"
sed -e "s|^work=.*|work=$t/work|" -e "s|^handoff=.*|handoff=$t/handoff|" -e "s|^keys=.*|keys=$t/keys|" -e "s|^hostkey_file=.*|hostkey_file=$t/hostkey/proxmox-host.pub|" -e "s|^group=.*|group=$(id -gn)|" -e "s|^libexec=.*|libexec=$t/libexec|" \
  "$role/files/dev-worker-address.sh" > "$t/h.sh"
chmod +x "$t/h.sh"
file=$t/handoff/dev-worker-address
state=$t/work/state/dev-vms.tfstate
mkdir -p "$t/work/rebuild-dev/inventory"

# The stand-in prints $t/inv.json, the shape of `ansible-inventory --list`.
printf '#!/bin/sh\ncat "%s/inv.json"\n' "$t" > "$t/libexec/ansible-venv/bin/ansible-inventory"
chmod +x "$t/libexec/ansible-venv/bin/ansible-inventory"
inv() { printf '{"k8s_workers":{"hosts":[%s]},"_meta":{"hostvars":{"w1":{"ansible_host":"%s"},"w2":{"ansible_host":"10.1.30.14"}}}}\n' "$1" "$2" > "$t/inv.json"; }
vm='{"mode":"managed","type":"proxmox_virtual_environment_vm","instances":[{}]}'
up() { echo "{\"resources\":[$vm]}" > "$state"; }
down() { echo '{"resources":[]}' > "$state"; }

# 1
up; inv '"w1"' 10.1.30.12; rm -f "$file"
out=$("$t/h.sh" write 2>&1) || bad "1 write failed: $out"
[[ $(cat "$file") == 10.1.30.12 && $(wc -l < "$file") == 1 && $(stat -c %a "$file") == 640 ]] && ! grep -q "10.1.30.12" <<<"$out" \
  && ok "1 write puts one line, the address, in the file at 0640, and prints no address" || bad "1 file=[$(cat "$file" 2>/dev/null)] out=$out"
# 6
[[ ! -e $file.part ]] && ok "6 a write leaves no temp file" || bad "6 temp file left"

# 2
down; inv '"w1"' 10.1.30.12; rm -f "$file"; "$t/h.sh" write >/dev/null
[[ $(cat "$file" 2>/dev/null) == 10.1.30.12 ]] && ok "1 with 0 dev VMs in the state (after a teardown) the file is still written: it follows the inventory" || bad "1 no file with 0 VMs"
echo 'not json' > "$state"; echo 10.1.30.77 > "$file"; "$t/h.sh" write >/dev/null
[[ $(cat "$file") == 10.1.30.12 ]] && ok "1 an unreadable state changes nothing" || bad "1 unreadable state"
up; inv '' 10.1.30.12; "$t/h.sh" write >/dev/null 2>&1 && bad "2 no worker: write passed"; [[ ! -e $file ]] && ok "2 no worker: no file" || bad "2 no worker: file"
up; inv '"w1","w2"' 10.1.30.12; "$t/h.sh" write >/dev/null 2>&1 && bad "2 two workers: write passed"; [[ ! -e $file ]] && ok "2 two workers: no file" || bad "2 two workers: file"

# 3
up
for v in 10.1.30.230 10.1.30.0 10.1.20.5 192.0.2.5 abc; do
  inv '"w1"' "$v"; echo 10.1.30.12 > "$file"
  out=$("$t/h.sh" write 2>&1) && bad "3 '$v': write passed" || { [[ ! -e $file ]] && ! grep -qF -- "$v" <<<"$out" && true || bad "3 '$v': file kept or value printed: $out"; }
done
ok "3 five addresses that are not dev node addresses: refused, no file, no value printed"

# 4
echo 10.1.30.12 > "$file"; [[ $("$t/h.sh" read) == 10.1.30.12 ]] && ok "4 read prints the address" || bad "4 read"
rm -f "$file"; out=$("$t/h.sh" read) && [[ -z $out ]] && ok "4 a missing file: nothing, and it passes" || bad "4 missing"
n=0
for v in '' '10.1.30.5\n10.1.30.6' '10.1.30.5' ' 10.1.30.5' '10.1.30.5 ' '10.1.30.5/32' '010.1.30.5' '10.1.20.5' '10.1.30.0' '10.1.30.224' '10.1.30.255' '10.1.30.256' 'abc'; do
  printf "$v" > "$file"   # the cases without \n have no final newline
  out=$("$t/h.sh" read 2>&1) && { bad "4 '$v' was accepted"; continue; }
  [[ -z $v ]] || ! grep -qF -- "$(printf "$v" | head -1)" <<<"$out" || bad "4 '$v' was printed"
  n=$((n+1))
done
printf '10.1.30.223\n' > "$file"; [[ $("$t/h.sh" read) == 10.1.30.223 ]] && ok "4 .223 is the highest accepted" || bad "4 .223"
printf '10.1.30.1\n' > "$file"; [[ $("$t/h.sh" read) == 10.1.30.1 ]] && ok "4 .1 is accepted" || bad "4 .1"
[[ $n == 13 ]] && ok "4 13 bad shapes refused, none printed" || bad "4 only $n refused"

# 5
echo 10.1.30.12 > "$file"; "$t/h.sh" remove; [[ ! -e $file ]] && "$t/h.sh" remove && ok "5 remove deletes the file and passes with none" || bad "5 remove"
tear=$(grep -c "^TEARDOWN_HOOK='\$libexec/dev-secrets.sh remove'$" "$role/files/rebuild.sh")
# the call sits after the inventory's checks and before the env file, in the same wrapper that runs every action
call=$(grep -n 'dev-worker-address.sh" write || true' "$role/files/rebuild.sh" | cut -d: -f1)
chk=$(grep -n 'every inventory host must be one of those addresses' "$role/files/rebuild.sh" | cut -d: -f1)
env=$(grep -n '^cat > "\$envdir/rebuild.env"' "$role/files/rebuild.sh" | cut -d: -f1)
[[ $tear == 1 && -n $call && -n $chk && -n $env && $chk -lt $call && $call -lt $env ]] && ok "5 the teardown hook leaves the file, and the wrapper writes it after the inventory checks, before every run" || bad "5 the wrapper's calls are not as expected (tear=$tear chk=$chk call=$call env=$env)"
grep -q 'dest: "{{ agent_box_libexec_dir }}/dev-worker-address.sh"' "$role/tasks/main.yml" && ok "5 the role installs the script" || bad "5 not installed"
# 7 key: the worker's own pair, made once; its public half handed over; the host's pinned key beside the pair
down; inv '"w1"' 10.1.30.12; rm -f "$t/handoff/dev-worker-backup.pub"
"$t/h.sh" key >/dev/null 2>&1 || bad "7 key failed"
kd=$t/keys/dev/backup-sftp
pub=$(cut -d' ' -f1,2 "$kd/w1.pub")
[[ -s $kd/w1.key && $(stat -c %a "$kd/w1.key") == 600 && $(cat "$t/handoff/dev-worker-backup.pub") == "$pub" && $(stat -c %a "$t/handoff/dev-worker-backup.pub") == 640 \
   && $("$t/h.sh" read-key) == "$pub" ]] && ok "7 key makes the pair once and hands over the public half only, at 0640, with no comment" || bad "7 key"
before=$(sha256sum "$kd/w1.key" "$kd/w1.pub" | cut -d' ' -f1 | tr -d '\n'); "$t/h.sh" key >/dev/null
after=$(sha256sum "$kd/w1.key" "$kd/w1.pub" | cut -d' ' -f1 | tr -d '\n')
[[ $before == "$after" ]] && ok "7 a second key run leaves the pair as it was" || bad "7 the pair changed"
[[ ! -e $kd/w1.known_hosts ]] && ok "7 no published host key: no known_hosts" || bad "7 known_hosts without a host key"
hk=$(ssh-keygen -q -t ed25519 -N '' -f "$t/hk" && cut -d' ' -f1,2 "$t/hk.pub")
printf '%s\n' "$hk" > "$t/hostkey/proxmox-host.pub"; "$t/h.sh" key >/dev/null
[[ $(cat "$kd/w1.known_hosts") == "c1-backup-target $hk" && $(stat -c %a "$kd/w1.known_hosts") == 600 ]] && ok "7 the published host key becomes <worker>.known_hosts" || bad "7 known_hosts"
printf 'ssh-rsa AAAAB3\n' > "$t/hostkey/proxmox-host.pub"; rm -f "$kd/w1.known_hosts"; "$t/h.sh" key >/dev/null
[[ ! -e $kd/w1.known_hosts ]] && ok "7 a host key that is not ssh-ed25519 is not pinned" || bad "7 bad host key pinned"
inv '"w1","w2"' 10.1.30.12; if "$t/h.sh" key >/dev/null 2>&1; then bad "7 two workers: key passed"; else [[ ! -e $t/handoff/dev-worker-backup.pub ]] && ok "7 two workers: no key handed over" || bad "7 file kept"; fi
inv '"w1"' 10.1.30.12; "$t/h.sh" key >/dev/null
for v in '' 'ssh-rsa AAAAB3' "ssh-ed25519 AAAA" "$pub extra" "$pub\n$pub"; do
  printf "$v\n" > "$t/handoff/dev-worker-backup.pub"
  out=$("$t/h.sh" read-key 2>&1) && bad "7 read-key accepted '$v'" || { grep -qF "AAAA" <<<"$out" && bad "7 read-key printed a value" || true; }
done
ok "7 read-key refuses five bad shapes and prints no value"
rm -f "$t/handoff/dev-worker-backup.pub"; out=$("$t/h.sh" read-key) && [[ -z $out ]] && ok "7 read-key: no file, nothing, and it passes" || bad "7 read-key missing"
exit "$fail"
