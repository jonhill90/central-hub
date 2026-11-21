#!/usr/bin/env bash
# The handoff of the opnsense client's secret from the keys user to the host job (wrapper opnsense-sso-secret, called by proxmox-host.sh
# as hostops), run for real with a temp identity.env. Test values only.
#   1. read prints the one OPNSENSE_CLIENT_SECRET line and nothing else (other keys never leave the file).
#   2. a missing file, a missing line, a short secret and a symlink are refused with no secret on stdout.
#   3. any other argument, or none, or an extra one, is refused.
#   4. proxmox-host.sh keeps the line in its own 0600 file, asks through sudo -u keys, and never echoes it.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD; f=$root/hosts/ansible/roles/agent_box/files
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0; ok() { echo "ok   $*"; }; bad() { echo "FAIL $*"; fail=1; }
sed -e "s#^values=/etc/agent-keys/prod/identity.env\$#values=$t/identity.env#" "$f/opnsense-sso-secret.sh" > "$t/w.sh"; chmod +x "$t/w.sh"
grep -q "values=$t/identity.env" "$t/w.sh" || bad "the wrapper's path line did not match, so this test is not testing the file"
s=$(openssl rand -hex 32)
printf 'GRAFANA_CLIENT_SECRET=%s\nOPNSENSE_CLIENT_SECRET=%s\nPASSWORD_OWNER=zzz\n' "$(openssl rand -hex 32)" "$s" > "$t/identity.env"
out=$("$t/w.sh" read 2>&1); [[ $out == "OPNSENSE_CLIENT_SECRET=$s" ]] && ok "1. read prints only the opnsense line" || bad "1. got: ${out:0:40}"
rm -f "$t/identity.env"; out=$("$t/w.sh" read 2>/dev/null) && bad "2a. no file was accepted" || { [[ -z $out ]] && ok "2a. no file: refused, nothing on stdout" || bad "2a. output"; }
printf 'GRAFANA_CLIENT_SECRET=aa\n' > "$t/identity.env"; "$t/w.sh" read >/dev/null 2>&1 && bad "2b. no line was accepted" || ok "2b. no line: refused"
printf 'OPNSENSE_CLIENT_SECRET=abc\n' > "$t/identity.env"; "$t/w.sh" read >/dev/null 2>&1 && bad "2c. short secret accepted" || ok "2c. short secret: refused"
printf 'OPNSENSE_CLIENT_SECRET=%s\n' "$s" > "$t/real.env"; rm -f "$t/identity.env"; ln -s "$t/real.env" "$t/identity.env"
"$t/w.sh" read >/dev/null 2>&1 && bad "2d. symlink accepted" || ok "2d. symlink: refused"
rm -f "$t/identity.env"; cp "$t/real.env" "$t/identity.env"
for a in "" "write" "read extra" "READ"; do
  # shellcheck disable=SC2086
  "$t/w.sh" $a >/dev/null 2>&1 && bad "3. '$a' accepted" || ok "3. argument '$a' refused"
done
# 4: the wrapper's handoff block, run on its own with a stand-in sudo.
mkdir -p "$t/dir" "$t/bin"
printf '#!/bin/sh\nshift 3; exec "$@"\n' > "$t/bin/sudo"; chmod +x "$t/bin/sudo"
blk=$(sed -n '/^if \[\[ \$job == opnsense-sso \]\]; then$/,/^fi$/p' "$f/proxmox-host.sh")
[[ -n $blk ]] || bad "4. the opnsense-sso block was not found in proxmox-host.sh"
cp "$t/w.sh" "$t/opnsense-sso-secret.sh"
res=$(PATH="$t/bin:$PATH" job=opnsense-sso dir=$t/dir libexec=$t bash -c "$blk"$'\n''echo "${sso_args[*]}"' 2>&1)
[[ $(cat "$t/dir/opnsense-sso.env") == "OPNSENSE_CLIENT_SECRET=$s" && $(stat -c %a "$t/dir/opnsense-sso.env") == 600 ]] && ok "4a. the host user keeps the line, mode 0600" || bad "4a."
grep -q "$s" <<< "$res" && bad "4b. the secret was printed" || ok "4b. the secret is not printed"
grep -q "opnsense_sso_values_file=$t/dir/opnsense-sso.env" <<< "$res" && ok "4c. the playbook gets the file's path, not the value" || bad "4c. $res"
exit $fail
