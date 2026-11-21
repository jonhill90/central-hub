#!/usr/bin/env bash
# dev-worker-address.sh box-prove, with the script's folders in a temp folder and stand-in sftp and ssh programs that act like the host's
# chrooted store (a folder /box the key may use, a folder /c1 it may not). The script must:
#   1. pass all checks against the store as the host role makes it (exit 0, five ok lines, no FAIL);
#   2. FAIL (exit 1, naming the check) when / is writable;
#   3. FAIL when another folder in / opens;
#   4. FAIL when /etc/passwd can be read;
#   5. FAIL when a command over ssh runs a shell;
#   6. FAIL when the sign-in does not work (refused, timed out, refused connection) or the folder is not /box, naming the class of failure,
#      with no ok line (nothing passes for want of a sign-in), checks 2-5 reported as not run, and no address printed;
#   7. refuse, writing and printing nothing, when the ssh config, key or pinned host key is missing;
#   9. FAIL (check 6) when an installed off-box script differs from, or is missing against, the role's manifest, or the manifest is missing;
#   8. leave no test file behind in /box, and print no address or key.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
role=$src/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/work" "$t/handoff" "$t/libexec/ansible-venv/bin" "$t/keys/box-backup" "$t/hostkey" "$t/remote/box" "$t/remote/c1"
sed -e "s|^work=.*|work=$t/work|" -e "s|^handoff=.*|handoff=$t/handoff|" -e "s|^keys=.*|keys=$t/keys|" -e "s|^hostkey_file=.*|hostkey_file=$t/hostkey/proxmox-host.pub|" -e "s|^group=.*|group=$(id -gn)|" -e "s|^libexec=.*|libexec=$t/libexec|" \
  "$role/files/dev-worker-address.sh" > "$t/h.sh"
chmod +x "$t/h.sh"
bd=$t/keys/box-backup
echo 'Host box-backup-target' > "$bd/ssh_config"; echo key > "$bd/id_ed25519"; echo 'box-backup-target ssh-ed25519 AAAA' > "$bd/known_hosts"

# Stand-in sftp: reads batch commands on stdin; behaviour comes from the words in $t/mode.
cat > "$t/libexec/ansible-venv/bin/sftp" <<STUB
#!/usr/bin/env bash
mode=\$(cat "$t/mode"); r=$t/remote
has() { [[ " \$mode " == *" \$1 "* ]]; }
while IFS= read -r line; do
  set -- \$line
  case "\$1" in
    pwd) has nologin && { echo "Permission denied (publickey)." >&2; exit 255; }; has timedout && { echo "ssh: connect to host 10.9.9.9 port 22: Connection timed out" >&2; exit 255; }; has refused && { echo "ssh: connect to host 10.9.9.9 port 22: Connection refused" >&2; exit 255; }; if has wrongdir; then echo "Remote working directory: /"; else echo "Remote working directory: /box"; fi ;;
    put) dst=\$3; if [[ \$dst == /* ]]; then has rootwritable || { echo "remote open(\$dst): Permission denied" >&2; exit 1; }; cp "\$2" "\$r/\${dst#/}"; else cp "\$2" "\$r/box/\$dst"; fi ;;
    get) if [[ \$2 == /etc/passwd ]]; then has passwd && { echo root > "\$3"; exit 0; }; echo "File /etc/passwd not found." >&2; exit 1; fi; cp "\$r/box/\$2" "\$3" ;;
    rm) p=\$2; [[ \$p == /* ]] && f=\$r/\${p#/} || f=\$r/box/\$p; rm -f "\$f" ;;
    ls) if [[ \$2 == -1 ]]; then echo "sftp> ls -1 /"; echo /box; echo /c1; else d=\${2#/}; if [[ \$d == c1 ]] && ! has opens; then echo "Couldn't read directory: Permission denied" >&2; exit 1; fi; fi ;;
  esac
done
STUB
cat > "$t/libexec/ansible-venv/bin/ssh" <<STUB
#!/usr/bin/env bash
[[ " \$(cat "$t/mode") " == *" shell "* ]] && echo 1000
exit 0
STUB
chmod +x "$t/libexec/ansible-venv/bin/sftp" "$t/libexec/ansible-venv/bin/ssh"

# The off-box scripts and the manifest the role writes from them (check 6).
for n in opnsense-offbox.sh secrets-bundle-offbox.sh; do echo "script $n" > "$t/libexec/$n"; done
( cd "$t/libexec" && sha256sum opnsense-offbox.sh secrets-bundle-offbox.sh > backend-files.sha256 )

run() { echo "$1" > "$t/mode"; rc=0; out=$("$t/h.sh" box-prove 2>&1) || rc=$?; }
leftover() { find "$t/remote" -name 'boxprove-*' | wc -l; }

run ""
[[ $rc == 0 && $(grep -c 'box-prove: ok' <<<"$out") == 7 && $out != *FAIL* ]] && ok "1 a store set up as the host role makes it: seven ok lines (check 3 has two), exit 0" || bad "1 rc=$rc out=$out"
[[ $(leftover) == 0 ]] && ok "8 no test file left in /box" || bad "8 test file left"
! grep -Eq '10\.|ssh-ed25519|AAAA' <<<"$out" && ok "8 no address or key printed" || bad "8 printed a value: $out"

for case in "rootwritable|3 / is writable" "opens|3 .* other folder" "passwd|4 /etc/passwd was read" "shell|5 a command over ssh ran" "nologin|1 no sign-in.*sign-in refused" "timedout|1 no sign-in.*connection timed out" "refused|1 no sign-in.*connection refused" "wrongdir|1 no sign-in.*folder is not /box"; do
  m=${case%%|*}; pat=${case#*|}
  run "$m"
  [[ $rc == 1 ]] && grep -Eq "FAIL $pat" <<<"$out" && ok "2-6 mode '$m': exit 1 and FAIL names the check" || bad "mode '$m': rc=$rc out=$out"
  [[ $(leftover) == 0 ]] || bad "mode '$m' left a test file in the store"
  # With no sign-in nothing may pass by default, and no address or host is printed.
  if [[ $pat == 1* ]]; then
    [[ $out != *"box-prove: ok"* && $out == *"FAIL 2-5 not run"* && $out != *10.9.9.9* ]] && ok "6 mode '$m': no ok line, checks 2-5 reported as not run, no address printed" || bad "mode '$m' printed an ok, or an address: $out"
  fi
done

# check 6: a script left behind (differs), a script missing, no manifest
echo "old script" > "$t/libexec/opnsense-offbox.sh"; run ""
[[ $rc == 1 && $out == *"FAIL 6 opnsense-offbox.sh is missing or differs"* ]] && ok "9 an installed script that differs from the manifest fails check 6" || bad "9 differs: rc=$rc out=$out"
rm -f "$t/libexec/opnsense-offbox.sh"; run ""
[[ $rc == 1 && $out == *"FAIL 6 opnsense-offbox.sh is missing or differs"* ]] && ok "9 a missing installed script fails check 6" || bad "9 missing: rc=$rc out=$out"
echo "script opnsense-offbox.sh" > "$t/libexec/opnsense-offbox.sh"
mv "$t/libexec/backend-files.sha256" "$t/keep.sha"; run ""
[[ $rc == 1 && $out == *"FAIL 6"*"is missing"* ]] && ok "9 a missing manifest fails check 6" || bad "9 no manifest: rc=$rc out=$out"
mv "$t/keep.sha" "$t/libexec/backend-files.sha256"

for f in ssh_config id_ed25519 known_hosts; do
  mv "$bd/$f" "$bd/$f.keep"; run ""
  [[ $rc == 1 && $out != *"box-prove: ok"* && $out == *"needs the ssh config"* ]] && ok "7 refuses with $f missing, runs no check" || bad "7 $f missing: rc=$rc out=$out"
  mv "$bd/$f.keep" "$bd/$f"
done
# 10: the box's self-apply installs the off-box scripts and the manifest: their include carries no skip tag, and the manifest lists both scripts
if python3 -I - "$role" <<'PY'
import sys, yaml
role = sys.argv[1]
main = yaml.safe_load(open(role + "/tasks/main.yml"))
skip = set(yaml.safe_load(open(role + "/defaults/main.yml"))["agent_box_self_apply_skip_tags"])
inc = [t for t in main if (t.get("ansible.builtin.include_tasks") or {}).get("file") == "offbox_scripts.yml"]
assert len(inc) == 1, "one include of offbox_scripts.yml"
tags = set(inc[0]["tags"]) | set(inc[0]["ansible.builtin.include_tasks"]["apply"]["tags"])
assert "wrappers" in tags and not (tags & skip), (tags, skip)
tasks = yaml.safe_load(open(role + "/tasks/offbox_scripts.yml"))
man = [t for t in tasks if "backend-files.sha256" in str(t)]
assert len(man) == 1 and all(n in man[0]["ansible.builtin.copy"]["content"] for n in ("opnsense-offbox.sh", "secrets-bundle-offbox.sh"))
dests = str(tasks)
assert "secrets-bundle-offbox.sh" in dests and "opnsense-offbox.sh" in dests
PY
then ok "10 the self-apply installs the off-box scripts and the manifest (no skip tag on their include)"; else bad "10 the off-box scripts are behind a skip tag, or the manifest is wrong"; fi
exit "$fail"
