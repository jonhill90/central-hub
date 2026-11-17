#!/usr/bin/env bash
# bootstrap/opnsense-backup-user.sh removes the key line and the PHP file from the firewall however the run ends,
# against a stand-in `ssh` that logs each guest command and answers like `qm guest exec`. Fake values only.
#   1. a run whose PHP step succeeds: both files are removed (once, by the exit trap);
#   2. a run whose PHP step fails: the script fails and both files are still removed;
#   3. a run whose cleanup also fails: it says so and names the files, and still exits non-zero;
#   4. a run whose first SSH call fails: nothing was written, so no cleanup call and no notice.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
script=$root/hosts/ansible/bootstrap/opnsense-backup-user.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
cmd=${*: -1}
printf '%s\n' "$cmd" >> "$LOG"
rc=0
case $cmd in
  *": > /root/box-backup-apikey.line.b64"*) [[ ${FAIL_FIRST:-0} == 1 ]] && rc=1 ;;
  *"php /root/box-backup-user.php"*) [[ ${FAIL_PHP:-0} == 1 ]] && rc=1 ;;
  *"rm -f /root/box-backup-user.php"*) [[ ${FAIL_RM:-0} == 1 ]] && rc=1 ;;
esac
printf '{"exited":1,"exitcode":%s,"out-data":""}\n' "$rc"
FAKE
chmod +x "$tmp/bin/ssh"
fail=0
run() { # name, expected exit (ok|bad), FAIL_PHP, FAIL_RM, FAIL_FIRST (default 0), expected cleanup calls (default 1)
  : > "$tmp/log"
  if PATH="$tmp/bin:$PATH" HOME="$tmp/home" LOG="$tmp/log" FAIL_PHP=$3 FAIL_RM=$4 FAIL_FIRST=${5:-0} \
       bash "$script" fake-host 100 > "$tmp/out" 2> "$tmp/err"; then got=ok; else got=bad; fi
  removed=$(grep -c "rm -f /root/box-backup-user.php /root/box-backup-apikey.line" "$tmp/log" || true)
  want_msg=0; [[ $4 == 1 && ${5:-0} == 0 ]] && want_msg=1
  has_msg=$(grep -c "remove them by hand" "$tmp/err" || true)
  if [[ $got == "$2" && $removed == "${6:-1}" && $has_msg == "$want_msg" ]]; then echo "ok: $1"; else echo "FAIL: $1 (exit $got, cleanup calls $removed, hand-removal notice $has_msg)"; fail=1; fi
}
run "PHP step succeeds, files removed once"            ok  0 0
run "PHP step fails, files still removed"              bad 1 0
run "PHP step fails and cleanup fails, notice printed" bad 1 1
run "PHP step succeeds but cleanup fails, still non-zero" bad 0 1
# A failure at the very first SSH call (the wrong key) wrote nothing: no cleanup call, no hand-removal notice, even if
# the cleanup would also have failed.
run "first SSH call fails, nothing written, no cleanup"  bad 0 0 1 0
run "first SSH call fails and cleanup would fail, still silent" bad 0 1 1 0
exit $fail
