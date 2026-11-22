#!/usr/bin/env bash
# The box trust role (hosts/ansible/roles/ssh_ca_trust, D-0064), run for real with ansible-playbook on this machine against a
# temporary folder, with stand-ins for sshd and systemctl that record what the real ones would see:
#   systemctl reload copies the drop-in (or notes there is none) into live.conf, which is what the live daemon would run, and
#   logs whether every file the drop-in names exists at that moment. sshd -t refuses any drop-in while the file `refuse` exists; sshd -T
#   prints the settings from the drop-in. Cases:
#   1. apply writes the drop-in, the CA key, a KRL and a principals file, and reloads sshd once (the live config then trusts the CA)
#   2. a second apply changes nothing and reloads nothing
#   3. a drop-in that sshd refuses: apply fails, nothing is reloaded, and the earlier drop-in is back as it was
#   4. a first apply whose drop-in sshd refuses leaves no drop-in
#   5. a box that takes no local key logins: apply stops and writes nothing
#   6. undo reloads sshd while the files the drop-in named still exist, after removing the drop-in and before removing them,
#      so the live config never names a missing file (a missing KRL makes OpenSSH revoke every key)
# (-e ansible_managed=managed lets an older copy of the role, which used that variable, run without the repo's ansible.cfg.)
# ROLES_DIR=<dir holding ssh_ca_trust> runs the same cases against another copy of the role (to show them fail on old code).
# Usage: .github/hosts-check/tests/test_ssh_ca_trust.sh   (needs ansible-playbook, ssh-keygen, python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
roles=${ROLES_DIR:-$root/hosts/ansible/roles}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/etc"
ssh-keygen -q -t ed25519 -N '' -f "$t/ca" -C test-ca
cat > "$t/bin/sshd" <<'STUB'
#!/usr/bin/env bash
d=$STUB_ETC/dropin.conf
case $1 in
  -t) [[ -f $STUB_ETC/refuse && -f $d ]] && { echo "sshd: bad configuration" >&2; exit 255; }; exit 0 ;;
  -T) if [[ -n ${STUB_NO_KEYS:-} ]]; then echo "pubkeyauthentication yes"; echo "authorizedkeysfile none"
      else echo "pubkeyauthentication yes"; echo "authorizedkeysfile .ssh/authorized_keys"; fi
      [[ -f $d ]] && awk '/^TrustedUserCAKeys/{print "trustedusercakeys " $2} /^RevokedKeys/{print "revokedkeys " $2}' "$d"; exit 0 ;;
esac
STUB
cat > "$t/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
[[ $1 == reload ]] || exit 0
d=$STUB_ETC/dropin.conf
missing=0
if [[ -f $d ]]; then
  cp "$d" "$STUB_ETC/live.conf"
  for f in $(awk '/^(TrustedUserCAKeys|RevokedKeys|HostCertificate)/{print $2}' "$d"); do [[ -e $f ]] || missing=1; done
else rm -f "$STUB_ETC/live.conf"; fi
echo "reload dropin=$([[ -f $d ]] && echo yes || echo no) ca=$([[ -e $STUB_ETC/ca.pub ]] && echo yes || echo no) krl=$([[ -e $STUB_ETC/lab.krl ]] && echo yes || echo no) missing=$missing" >> "$STUB_ETC/reloads"
STUB
chmod +x "$t/bin/sshd" "$t/bin/systemctl"
export PATH="$t/bin:$PATH" STUB_ETC="$t/etc" ANSIBLE_ROLES_PATH="$roles" ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False

cat > "$t/play.yml" <<E2
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    ssh_ca_trust_user_ca_file: $t/ca.pub
    ssh_ca_trust_accounts: [alice]
    ssh_ca_trust_dropin: $t/etc/dropin.conf
    ssh_ca_trust_user_ca_dest: $t/etc/ca.pub
    ssh_ca_trust_krl_dest: $t/etc/lab.krl
    ssh_ca_trust_principals_dir: $t/etc/principals
    ssh_ca_trust_host_cert_dest: $t/etc/host-cert.pub
    ssh_ca_trust_file_owner: $(id -un)
    ssh_ca_trust_file_group: $(id -gn)
  roles: [ssh_ca_trust]
E2
run() { out=$(ansible-playbook -i localhost, "$t/play.yml" -e ansible_managed=managed "$@" 2>&1); rc=$?; [[ -z ${SHOW:-} ]] || echo "$out"; }
reloads() { [[ -f $t/etc/reloads ]] && wc -l < "$t/etc/reloads" || echo 0; }

run
if [[ $rc -eq 0 && -f $t/etc/dropin.conf && -f $t/etc/ca.pub && -f $t/etc/lab.krl && $(cat "$t/etc/principals/alice" 2>/dev/null) == lab-admin ]] &&
   grep -q '^TrustedUserCAKeys' "$t/etc/dropin.conf" && grep -q '^AuthorizedPrincipalsFile' "$t/etc/dropin.conf"; then
  ok "1a. apply writes the drop-in, the CA key, the KRL and the principals file"
else bad "1a. rc=$rc $(echo "$out" | grep -v -i 'deprec\|^Origin\|^$' | tail -6)"; fi
if [[ $(reloads) -eq 1 ]] && grep -q '^TrustedUserCAKeys' "$t/etc/live.conf" 2>/dev/null; then
  ok "1b. apply reloads sshd once, and the live config then trusts the CA"
else bad "1b. reloads=$(reloads), live.conf $([[ -f $t/etc/live.conf ]] && echo present || echo missing)"; fi

run
if [[ $rc -eq 0 && $(reloads) -eq 1 ]]; then ok "2. a second apply reloads nothing"; else bad "2. rc=$rc reloads=$(reloads)"; fi

# 3. a changed drop-in that sshd refuses: the earlier one is restored, nothing is reloaded
cp "$t/etc/dropin.conf" "$t/good.conf"; n0=$(reloads); touch "$t/etc/refuse"
run -e ssh_ca_trust_principals_dir="$t/etc/principals2"
if [[ $rc -ne 0 && $(reloads) -eq $n0 ]] && cmp -s "$t/etc/dropin.conf" "$t/good.conf"; then
  ok "3. a drop-in sshd refuses: apply fails, nothing is reloaded, the earlier drop-in is back as it was"
else bad "3. rc=$rc reloads $n0 -> $(reloads); drop-in $(cmp -s "$t/etc/dropin.conf" "$t/good.conf" && echo same || echo differs)"; fi

# 4. the same with no earlier drop-in
rm -f "$t/etc/dropin.conf" "$t/etc/live.conf" "$t/etc/reloads"
run
if [[ $rc -ne 0 && ! -e $t/etc/dropin.conf && $(reloads) -eq 0 ]]; then ok "4. a first apply that sshd refuses leaves no drop-in and reloads nothing"; else bad "4. rc=$rc reloads=$(reloads)"; fi
rm -f "$t/etc/refuse"

# 5. a box with no local key logins: stop before writing
rm -rf "$t/etc/dropin.conf" "$t/etc/principals" "$t/etc/principals2" "$t/etc/ca.pub" "$t/etc/lab.krl" "$t/etc/live.conf" "$t/etc/reloads"
STUB_NO_KEYS=1 run
if [[ $rc -ne 0 && ! -e $t/etc/dropin.conf && ! -e $t/etc/ca.pub && $out == *break-glass* ]]; then ok "5. a box that takes no local key logins: apply stops and writes nothing"; else bad "5. rc=$rc"; fi

# 6. undo
run
rm -f "$t/etc/reloads"
run -e ssh_ca_trust_remove=true
if [[ $rc -eq 0 && $(reloads) -ge 1 ]] && ! grep -q 'missing=1' "$t/etc/reloads" && grep -q 'dropin=no ca=yes krl=yes' "$t/etc/reloads"; then
  ok "6a. undo reloads sshd after the drop-in is gone and while the CA key and KRL still exist"
else bad "6a. rc=$rc reloads: $(cat "$t/etc/reloads" 2>/dev/null)"; fi
if [[ ! -e $t/etc/dropin.conf && ! -e $t/etc/ca.pub && ! -e $t/etc/lab.krl && ! -e $t/etc/principals && ! -e $t/etc/live.conf ]]; then
  ok "6b. undo removes every file, and the live config no longer holds the drop-in"
else bad "6b. files left: $(ls "$t/etc")"; fi
exit $fail
