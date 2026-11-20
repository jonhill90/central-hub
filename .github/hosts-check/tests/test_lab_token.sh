#!/bin/bash
# Wrappers lab-token (as hostops) and lab-token-put (as keys), run for real with stand-ins for ssh and sudo and temp folders:
# put writes the two-line file once (0600, the dev file's URL line, the secret never printed) and refuses a wrong token id, a
# non-UUID secret, a missing URL line and an existing file; mint makes the token, stores it, prints no secret, and removes the
# host's token again when storing fails; it refuses when the host already has the token or the box already has the file.
set -euo pipefail
cd "$(dirname "$0")/../../.."
f=hosts/ansible/roles/agent_box/files
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$t/keys" "$t/host/inventory" "$t/bin" "$t/lib"
sed -e "s#^keys=/etc/agent-keys\$#keys=$t/keys#" "$f/lab-token-put.sh" > "$t/lib/lab-token-put.sh"
sed -e "s#^dir=/etc/agent-keys-host\$#dir=$t/host#" -e "s#^libexec=.*#libexec=$t/lib#" "$f/lab-token.sh" > "$t/lib/lab-token.sh"
chmod +x "$t"/lib/*.sh
SECRET=11111111-2222-3333-4444-555555555555
printf 'PROXMOX_VE_ENDPOINT=https://pve.example.invalid:8006/\nPROXMOX_VE_API_TOKEN=agent@pve!dev=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n' > "$t/keys/proxmox-dev.env"
printf 'proxmox:\n  hosts:\n    proxmox_host:\n      ansible_host: "192.0.2.10"\n' > "$t/host/inventory/hosts.yml"
: > "$t/host/id_ed25519"; : > "$t/host/known_hosts"
good="{\"full-tokenid\":\"agentlab@pve!lab\",\"value\":\"$SECRET\",\"info\":{\"privsep\":\"1\"}}"

out=$(printf '%s' "$good" | "$t/lib/lab-token-put.sh" put 2>&1) || true
if [[ -f $t/keys/proxmox-lab.env && $(stat -c %a "$t/keys/proxmox-lab.env") == 600 && $(wc -l < "$t/keys/proxmox-lab.env") -eq 2 &&
      $(sed -n 1p "$t/keys/proxmox-lab.env") == "PROXMOX_VE_ENDPOINT=https://pve.example.invalid:8006/" &&
      $(sed -n 2p "$t/keys/proxmox-lab.env") == "PROXMOX_VE_API_TOKEN=agentlab@pve!lab=$SECRET" && $out != *"$SECRET"* ]]; then
  ok "1. put writes the two-line file, 0600, the dev file's URL line, and prints no secret"
else bad "1. $out"; fi
out=$(printf '%s' "$good" | "$t/lib/lab-token-put.sh" put 2>&1) && rc=0 || rc=$?
if [[ $rc -ne 0 && $out == *"already exists"* ]]; then ok "2. put never replaces an existing file"; else bad "2. $rc $out"; fi
[[ $("$t/lib/lab-token-put.sh" exists) == present ]] && ok "3. exists says present" || bad "3."
rm -f "$t/keys/proxmox-lab.env"
rc=0; "$t/lib/lab-token-put.sh" exists >/dev/null || rc=$?
[[ $rc -eq 1 ]] && ok "4. exists says absent (exit 1)" || bad "4. $rc"
for case in 'wrong id:{"full-tokenid":"agent@pve!dev","value":"'$SECRET'"}' 'not a uuid:{"full-tokenid":"agentlab@pve!lab","value":"abc"}' 'not json:nope'; do
  rc=0; printf '%s' "${case#*:}" | "$t/lib/lab-token-put.sh" put >/dev/null 2>&1 || rc=$?
  [[ $rc -ne 0 && ! -e $t/keys/proxmox-lab.env ]] && ok "5. put refuses: ${case%%:*}" || bad "5. ${case%%:*} rc=$rc"
done
mv "$t/keys/proxmox-dev.env" "$t/keys/dev.bak"
rc=0; printf '%s' "$good" | "$t/lib/lab-token-put.sh" put >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 && ! -e $t/keys/proxmox-lab.env ]] && ok "6. put refuses with no dev file to copy the URL from" || bad "6. $rc"
mv "$t/keys/dev.bak" "$t/keys/proxmox-dev.env"

# Stand-ins: ssh answers by the command it was given; sudo runs the wrapper in the lib folder (the user switch is not under test).
cat > "$t/bin/ssh" <<'S'
#!/bin/bash
cmd="${*: -1}"
echo "$cmd" >> "$LOG"
case $cmd in
  *"token list"*) [[ ${HOST_HAS:-no} == yes ]] && echo '[{"tokenid":"lab"}]' || echo '[]' ;;
  *"token add"*) printf '%s' "$GOOD" ;;
  *"token remove"*) : ;;
esac
S
cat > "$t/bin/sudo" <<'S'
#!/bin/bash
[[ $1 == -n && $2 == -u ]] && shift 3
exec "$@"
S
chmod +x "$t/bin/ssh" "$t/bin/sudo"
export PATH="$t/bin:$PATH" LOG="$t/log" GOOD="$good"
: > "$t/log"; out=$("$t/lib/lab-token.sh" mint 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && $out == *"PASS: token made"* && $out != *"$SECRET"* && -f $t/keys/proxmox-lab.env &&
      $(grep -c 'token add agentlab@pve lab --privsep 1 --expire [0-9]* --output-format json' "$t/log") -eq 1 ]]; then
  ok "7. mint makes the token privsep with an expiry, stores it, and prints no secret"
else bad "7. $rc $out"; fi
rc=0; out=$("$t/lib/lab-token.sh" mint 2>&1) || rc=$?
[[ $rc -ne 0 && $out == *"already has proxmox-lab.env"* ]] && ok "8. mint refuses when the box has the file" || bad "8. $rc $out"
rm -f "$t/keys/proxmox-lab.env"
rc=0; out=$(HOST_HAS=yes "$t/lib/lab-token.sh" mint 2>&1) || rc=$?
[[ $rc -ne 0 && $out == *"host already has agentlab@pve!lab"* && ! -e $t/keys/proxmox-lab.env ]] && ok "9. mint refuses when the host has the token" || bad "9. $rc $out"
: > "$t/log"; rc=0; out=$(GOOD='{"full-tokenid":"agentlab@pve!lab","value":"bad"}' "$t/lib/lab-token.sh" mint 2>&1) || rc=$?
if [[ $rc -ne 0 && $out == *"the host's token was removed again"* && $(grep -c 'token remove agentlab@pve lab' "$t/log") -eq 1 && ! -e $t/keys/proxmox-lab.env ]]; then
  ok "10. a failed store removes the host's token again"
else bad "10. $rc $out"; fi
rc=0; out=$("$t/lib/lab-token.sh" status 2>&1) || rc=$?
[[ $rc -eq 0 && $out == "lab-token: token on the host: no; file on the box: absent" ]] && ok "11. status only reads" || bad "11. $rc $out"
echo "$fails failed"; [[ $fails -eq 0 ]]
