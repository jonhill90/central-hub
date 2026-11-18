#!/usr/bin/env bash
# When the c1 backups make their restic repository (role k8s_backup), offline, with a stand-in restic:
#   1. The role's task "Make the restic repository once" and c1-backup-lib.sh restic_ensure_repo leave a
#      repository that `restic cat config` reads (exit 0) alone, and do not run `restic init`.
#   2. Both run `restic init` only on exit 10, restic's "repository does not exist" (0.17 and later;
#      measured with 0.19.1: 10 for a missing local repository, 12 for a wrong password).
#   3. Any other failure to read it (1, 12) fails loudly with restic's message and never runs init. The
#      task once ran init on every failure, and on c1 (2026-11-18 07:25 UTC) init then refused a
#      repository that was there.
#   4. The task's env file still gates the rest: a missing file fails before restic runs.
# Usage: .github/hosts-check/tests/test_backup_repo_init.sh   (needs python3 with PyYAML)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/k8s_backup
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# A stand-in restic: `cat config` exits with $STUB_RC and says why on stderr; every call is logged.
mkdir -p "$w/bin"
cat > "$w/bin/restic" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_CALLS"
case $1 in
  cat) [ "$STUB_RC" -eq 0 ] && { echo '{"version":2}'; exit 0; }
       echo "Fatal: stand-in failure $STUB_RC" >&2; exit "$STUB_RC" ;;
  init) echo "created restic repository"; exit 0 ;;
esac
exit 1
SH
chmod +x "$w/bin/restic"
echo 'RESTIC_REPOSITORY=stand-in' > "$w/node.env"

# The task's shell, with the role's two paths filled in; nothing else may be left to template.
python3 - "$role/tasks/main.yml" "$w/bin" "$w/node.env" > "$w/task.sh" <<'PY'
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
hit = [t for t in tasks if t.get("name") == "timers | Make the restic repository once, if it is not there"]
assert len(hit) == 1, "task not found"
cmd = hit[0]["ansible.builtin.shell"]
cmd = cmd.replace("{{ k8s_backup_bin_dir }}", sys.argv[2]).replace("{{ k8s_backup_node_env_file }}", sys.argv[3])
assert "{{" not in cmd, cmd
print(cmd)
PY
[ -s "$w/task.sh" ] || { echo "FAIL could not read the task"; exit 1; }

task() { : > "$w/calls"; STUB_RC=$1 STUB_CALLS=$w/calls bash "$w/task.sh" > "$w/out" 2> "$w/err"; }
# shellcheck source=/dev/null
lib() { : > "$w/calls"; (set -euo pipefail; export RESTIC=$w/bin/restic STUB_RC=$1 STUB_CALLS=$w/calls
  . "$role/files/c1-backup-lib.sh"; restic_ensure_repo) > "$w/out" 2> "$w/err"; }
inits() { grep -c '^init' "$w/calls"; }

task 0; rc=$?
[[ $rc -eq 0 && $(cat "$w/out") == exists && $(inits) -eq 0 ]] && ok "task: a readable repository is left alone" \
  || bad "task with exit 0: rc $rc, out $(cat "$w/out"), $(inits) init"
task 10; rc=$?
[[ $rc -eq 0 && $(cat "$w/out") == made && $(inits) -eq 1 ]] && ok "task: exit 10 (does not exist) makes the repository" \
  || bad "task with exit 10: rc $rc, out $(cat "$w/out"), $(inits) init"
for code in 1 12; do
  task "$code"; rc=$?
  if [[ $rc -ne 0 && $(inits) -eq 0 ]] && grep -q "exit $code), so it was left alone: Fatal: stand-in failure $code" "$w/err"; then
    ok "task: exit $code fails with restic's message and runs no init"
  else bad "task with exit $code: rc $rc, $(inits) init, err $(cat "$w/err")"; fi
done
rm "$w/node.env"; task 0; rc=$?
[[ $rc -ne 0 && ! -s $w/calls ]] && ok "task: a missing env file fails before restic runs" || bad "task ran without its env file (rc $rc)"
echo 'RESTIC_REPOSITORY=stand-in' > "$w/node.env"

lib 0; rc=$?
[[ $rc -eq 0 && $(inits) -eq 0 ]] && ok "restic_ensure_repo: a readable repository is left alone" || bad "lib with exit 0: rc $rc, $(inits) init"
lib 10; rc=$?
[[ $rc -eq 0 && $(inits) -eq 1 ]] && grep -q "making one" "$w/out" && ok "restic_ensure_repo: exit 10 makes the repository" \
  || bad "lib with exit 10: rc $rc, $(inits) init, out $(cat "$w/out")"
for code in 1 12; do
  lib "$code"; rc=$?
  if [[ $rc -ne 0 && $(inits) -eq 0 ]] && grep -q "FAIL: could not read the repository (restic exit $code), so it was left alone: Fatal: stand-in failure $code" "$w/err"; then
    ok "restic_ensure_repo: exit $code stops the run with restic's message and runs no init"
  else bad "lib with exit $code: rc $rc, $(inits) init, err $(cat "$w/err")"; fi
done
exit "$fail"
