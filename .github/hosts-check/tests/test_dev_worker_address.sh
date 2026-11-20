#!/usr/bin/env bash
# The handoff of dev's worker address (hosts/ansible/roles/agent_box/files/dev-worker-address.sh), with the script's folders
# pointed into a temp folder and a stand-in ansible-inventory:
#   1. write, with a dev VM in the state, puts exactly one line, the worker's address, in the file (mode 0640), and prints no address.
#   2. write with no dev VM, an unreadable state, no worker or two workers leaves no file (and removes an older one).
#   3. write refuses an address that is not one dev node address, and leaves no file.
#   4. read prints the address, prints nothing and passes for a missing file, and refuses (naming no value) a file that is empty, holds
#      two lines, no final newline, spaces, a prefix length, a leading zero, another VLAN, .0, or .224 and up.
#   5. remove deletes the file and passes when there is none; the teardown hook and the restore hook call it.
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
sed -e "s|^work=.*|work=$t/work|" -e "s|^handoff=.*|handoff=$t/handoff|" -e "s|^group=.*|group=$(id -gn)|" -e "s|^libexec=.*|libexec=$t/libexec|" \
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

# 1
up; inv '"w1"' 10.1.30.12; rm -f "$file"
out=$("$t/h.sh" write 2>&1) || bad "1 write failed: $out"
[[ $(cat "$file") == 10.1.30.12 && $(wc -l < "$file") == 1 && $(stat -c %a "$file") == 640 ]] && ! grep -q "10.1.30.12" <<<"$out" \
  && ok "1 write puts one line, the address, in the file at 0640, and prints no address" || bad "1 file=[$(cat "$file" 2>/dev/null)] out=$out"
# 6
[[ ! -e $file.part ]] && ok "6 a write leaves no temp file" || bad "6 temp file left"

# 2
for case in "no VM|echo '{\"resources\":[]}' > $state" "unreadable state|echo 'not json' > $state" ; do
  up; "$t/h.sh" write >/dev/null; eval "${case#*|}"
  "$t/h.sh" write >/dev/null 2>&1 || true
  [[ ! -e $file ]] && ok "2 ${case%%|*}: no file" || bad "2 ${case%%|*}: the old file stayed"
done
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
grep -q "dev-worker-address.sh remove'" "$role/files/rebuild.sh" && grep -q "dev-worker-address.sh write || true; cd" "$role/files/rebuild.sh" \
  && ok "5 the wrapper's teardown hook removes it and the restore hook writes it" || bad "5 the hooks are not wired"
grep -q 'dest: "{{ agent_box_libexec_dir }}/dev-worker-address.sh"' "$role/tasks/main.yml" && ok "5 the role installs the script" || bad "5 not installed"
exit "$fail"
