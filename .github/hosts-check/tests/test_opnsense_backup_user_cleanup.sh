#!/usr/bin/env bash
# bootstrap/opnsense-backup-user.sh removes the key line and the PHP file from the firewall however the run ends,
# against a stand-in `ssh` that logs each guest command and answers like `qm guest exec`. Fake values only.
#   1. a run whose PHP step succeeds: both files are removed (once, by the exit trap);
#   2. a run whose PHP step fails: the script fails and both files are still removed;
#   3. a run whose cleanup also fails: it says so and names the files, and still exits non-zero.
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
  *"php /root/box-backup-user.php"*) [[ ${FAIL_PHP:-0} == 1 ]] && rc=1 ;;
  *"rm -f /root/box-backup-user.php"*) [[ ${FAIL_RM:-0} == 1 ]] && rc=1 ;;
esac
printf '{"exited":1,"exitcode":%s,"out-data":""}\n' "$rc"
FAKE
chmod +x "$tmp/bin/ssh"
fail=0
run() { # name, expected exit (ok|bad), FAIL_PHP, FAIL_RM
  : > "$tmp/log"
  if PATH="$tmp/bin:$PATH" HOME="$tmp/home" LOG="$tmp/log" FAIL_PHP=$3 FAIL_RM=$4 \
       bash "$script" fake-host 100 > "$tmp/out" 2> "$tmp/err"; then got=ok; else got=bad; fi
  removed=$(grep -c "rm -f /root/box-backup-user.php /root/box-backup-apikey.line" "$tmp/log" || true)
  want_msg=0; [[ $4 == 1 ]] && want_msg=1
  has_msg=$(grep -c "remove them by hand" "$tmp/err" || true)
  if [[ $got == "$2" && $removed == 1 && $has_msg == "$want_msg" ]]; then echo "ok: $1"; else echo "FAIL: $1 (exit $got, cleanup calls $removed, hand-removal notice $has_msg)"; fail=1; fi
}
run "PHP step succeeds, files removed once"            ok  0 0
run "PHP step fails, files still removed"              bad 1 0
run "PHP step fails and cleanup fails, notice printed" bad 1 1
run "PHP step succeeds but cleanup fails, still non-zero" bad 0 1
exit $fail
