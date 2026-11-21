#!/usr/bin/env bash
# host-escrow.sh (hosts/ansible/roles/agent_box/files/host-escrow.sh): keeps one small secret file on the Proxmox host's store, over sftp
# with the box's ssh config, in escrow/<name> beside the restic repository. With a stand-in sftp that acts like the chrooted store:
#   1. a first call writes the file, reads it back, and says so (exit 0);
#   2. a second call with the same file writes nothing (the host already holds it);
#   3. a changed file is written again and reads back;
#   4. a write that fails stops it (exit 1, naming the write), with nothing printed of the value;
#   5. a read-back that differs stops it (exit 1, "differs");
#   6. a refused connection stops it and every sftp call is bounded, a missing file, a missing ssh config, a bad name and a wrong argument count stop it before sftp;
#   7. the value never appears in the output.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/bin" "$t/keys" "$t/remote/box"
sed -e "s|^cfg=.*|cfg=$t/keys/ssh_config|" -e "s|^export PATH=.*|export PATH=$t/bin:/usr/bin:/bin|" "$src/hosts/ansible/roles/agent_box/files/host-escrow.sh" > "$t/h.sh"
echo 'Host box-backup-target' > "$t/keys/ssh_config"
secret=SECRET-VALUE-DO-NOT-PRINT-0123456789abcdef
echo "$secret" > "$t/file"
# Stand-in sftp: commands on stdin; its behaviour comes from the words in $t/mode. The remote /box is $t/remote/box.
cat > "$t/bin/sftp" <<STUB
#!/usr/bin/env bash
mode=\$(cat "$t/mode"); r=$t/remote/box
has() { [[ " \$mode " == *" \$1 "* ]]; }
has refused && { echo "ssh: connect to host box port 22: Connection refused" >&2; exit 255; }
has stalled && { sleep 100; }
echo x >> "$t/sftp-calls"
while IFS= read -r line; do
  set -- \$line
  case "\$1" in
    -mkdir) mkdir -p "\$r/\$2" ;;
    put) has putfails && { echo "remote open(\"/box/\$3\"): Permission denied" >&2; exit 1; }; if has torn; then head -c 3 "\$2" > "\$r/\$3"; else cp "\$2" "\$r/\$3"; fi ;;
    get) has getfails && { echo "Permission denied" >&2; exit 1; }; [[ -f \$r/\$2 ]] || { echo "File \"/box/\$2\" not found." >&2; exit 1; }; cp "\$r/\$2" "\$3" ;;
    rename) has renamefails && { echo "Couldn't rename file" >&2; exit 1; }; mv "\$r/\$2" "\$r/\$3" ;;
  esac
done
STUB
chmod +x "$t/bin/sftp"
run() { echo "$1" > "$t/mode"; shift; rc=0; out=$(bash "$t/h.sh" "$@" 2>&1) || rc=$?; }

run "" restic-password "$t/file"
[[ $rc == 0 && $out == *"wrote the current restic-password to the host, and it reads back the same"* && $(cat "$t/remote/box/escrow/restic-password") == "$secret" && ! -e $t/remote/box/escrow/restic-password.part ]] \
  && ok "1 not held: written through .part, checked, renamed, read back; no .part left" || bad "1 rc=$rc $out"
n=$(wc -l < "$t/sftp-calls")
run "" restic-password "$t/file"
[[ $rc == 0 && $out == *"already holds the current restic-password"* && $(( $(wc -l < "$t/sftp-calls") - n )) == 1 ]] && ok "2 the same file again writes nothing (one read)" || bad "2 rc=$rc $out"
echo "${secret}-changed" > "$t/file2"
run "" restic-password "$t/file2"
[[ $rc == 1 && $out == *"FAIL: the host holds a different restic-password"* && $out == *"Nothing was sent"* && $(cat "$t/remote/box/escrow/restic-password") == "$secret" ]] \
  && ok "3 a held copy that differs is refused, said to be unsent, and left exactly as it was (never overwritten)" || bad "3 rc=$rc $out"
run getfails restic-password "$t/file2"
[[ $rc == 1 && $out == *"could not tell whether the host holds restic-password"* && $out == *"Nothing was sent"* && $(cat "$t/remote/box/escrow/restic-password") == "$secret" ]] \
  && ok "4 a read error that is not 'not found' refuses, writes nothing" || bad "4 rc=$rc $out"
run refused restic-password "$t/file2"
[[ $rc == 1 && $out == *"could not tell whether"* && $(cat "$t/remote/box/escrow/restic-password") == "$secret" ]] && ok "5 a refused connection refuses, and the held copy is untouched" || bad "5 rc=$rc $out"
echo "${secret}-b" > "$t/file3"
run putfails age-identity "$t/file3"
[[ $rc == 1 && $out == *"could not write age-identity"* && $out == *"Nothing was sent"* && ! -e $t/remote/box/escrow/age-identity ]] && ok "6 a failed write stops it, nothing at the final name" || bad "6 rc=$rc $out"
run torn age-identity "$t/file3"
[[ $rc == 1 && $out == *"differs from the file (a torn write); it was not kept"* && ! -e $t/remote/box/escrow/age-identity ]] && ok "7 a torn write fails at the .part and never reaches the final name" || bad "7 rc=$rc $out"
run renamefails age-identity "$t/file3"
[[ $rc == 1 && $out == *"could not rename"* && ! -e $t/remote/box/escrow/age-identity ]] && ok "8 a failed rename leaves nothing at the final name" || bad "8 rc=$rc $out"
# a good copy held, then a torn attempt with a different file: the good copy stays (refused at the read, never reaches the write)
run torn restic-password "$t/file2"
[[ $rc == 1 && $(cat "$t/remote/box/escrow/restic-password") == "$secret" ]] && ok "9 with a good copy held, a torn attempt cannot damage it" || bad "9 rc=$rc $out"
# a stalled connection: every sftp call is bounded (a real stall would take 30 s per call, so the test checks the bound, not the wait)
grep -q 'timeout 30 sftp .*-o ConnectTimeout=10' "$t/h.sh" && ok "10 every sftp call is bounded by timeout 30 and ConnectTimeout=10" || bad "6b sftp calls are not bounded"
before=$(wc -l < "$t/sftp-calls")
run "" restic-password "$t/missing"; [[ $rc == 1 && $out == *"is missing or empty"* ]] && ok "6c a missing file stops it" || bad "6c rc=$rc $out"
: > "$t/empty"; run "" restic-password "$t/empty"; [[ $rc == 1 && $out == *"is missing or empty"* ]] && ok "6d an empty file stops it" || bad "6d rc=$rc $out"
run "" "Bad_Name" "$t/file"; [[ $rc == 1 && $out == *"lowercase letters"* ]] && ok "6e a bad name stops it" || bad "6e rc=$rc $out"
run "" only-one; [[ $rc == 1 && $out == *usage* ]] && ok "6f a wrong argument count stops it" || bad "6f rc=$rc $out"
mv "$t/keys/ssh_config" "$t/keys/keep"; run "" restic-password "$t/file"; [[ $rc == 1 && $out == *"dev-worker-address.sh box-key writes it"* ]] && ok "6g a missing ssh config stops it" || bad "6g rc=$rc $out"
mv "$t/keys/keep" "$t/keys/ssh_config"
[[ $(wc -l < "$t/sftp-calls") == "$before" ]] && ok "6h none of those started sftp" || bad "6h sftp ran"
echo "$secret" > "$t/file"; run "" restic-password "$t/file"; run "" age-identity "$t/file"
[[ $out != *"$secret"* ]] && ok "7 the value is never printed" || bad "7 printed: $out"
exit "$fail"
