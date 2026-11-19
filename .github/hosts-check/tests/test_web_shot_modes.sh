#!/bin/bash
# The agent_box role's task for Playwright's folders, run for real (ansible-playbook on localhost, a temp folder as the libexec
# directory): folders that pip and Playwright left drwx------ come out readable and enterable by others, still root-owned in
# the task (owner and group need root, so the run leaves them to the caller), and a file inside stays unwritable by others.
# Measured on the box on 2026-11-19: web-shot ended "playwright-venv/bin/python: Permission denied" for a session user.
set -euo pipefail
cd "$(dirname "$0")/../../.."
tasks=hosts/ansible/roles/agent_box/tasks/main.yml
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

# The task, taken from the role by its name, with owner and group dropped so a non-root run can apply it.
if ! python3 -I - "$tasks" "$t/play.yml" <<'PY'
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
found = [x for x in tasks if x.get("name", "").startswith("Playwright's environment and browsers")]
if len(found) != 1:
    print("no such task"); sys.exit(1)
task = found[0]
for key in ("owner", "group"):
    task["ansible.builtin.file"].pop(key, None)
task.pop("when", None)
task.pop("tags", None)
yaml.safe_dump([{"hosts": "localhost", "gather_facts": False, "connection": "local",
                 "vars": {"agent_box_libexec_dir": sys.argv[2].rsplit("/", 1)[0] + "/libexec"},
                 "tasks": [task]}], open(sys.argv[2], "w"))
PY
then bad "the role has no task for Playwright's folders"; echo "$fails failed"; exit 1; fi
ok "the role has one task for Playwright's folders"

mkdir -p "$t/libexec/playwright-venv/bin" "$t/libexec/playwright-browsers/chromium"
echo x > "$t/libexec/playwright-venv/bin/python"; echo x > "$t/libexec/playwright-browsers/chromium/chrome"
# Links out of the folders, as the venv's bin/python is an absolute link into /usr/bin: what they point at must keep its mode.
mkdir -p "$t/outside/dir"; echo secret > "$t/outside/file"; echo x > "$t/outside/dir/inner"
chmod 600 "$t/outside/file"; chmod 700 "$t/outside/dir"; chmod 600 "$t/outside/dir/inner"
ln -s "$t/outside/file" "$t/libexec/playwright-venv/bin/link-file"
ln -s "$t/outside/dir" "$t/libexec/playwright-browsers/link-dir"
chmod -R go-rwx "$t/libexec/playwright-venv" "$t/libexec/playwright-browsers"
ansible-playbook -i localhost, "$t/play.yml" > "$t/out" 2>&1 || { cat "$t/out"; bad "the task failed"; echo "$fails failed"; exit 1; }
for f in playwright-venv playwright-venv/bin playwright-browsers playwright-browsers/chromium; do
  m=$(stat -c %a "$t/libexec/$f")
  if [ "$m" = 755 ]; then ok "$f is 755"; else bad "$f is $m"; fi
done
m=$(stat -c %a "$t/libexec/playwright-venv/bin/python")
if [ "$m" = 644 ]; then ok "a file inside is 644, not writable by others"; else bad "file mode $m"; fi
for f in outside/file outside/dir outside/dir/inner; do
  m=$(stat -c %a "$t/$f")
  case $f in outside/dir) want=700 ;; *) want=600 ;; esac
  if [ "$m" = "$want" ]; then ok "$f, reached only through a link, keeps mode $want"; else bad "$f changed from $want to $m"; fi
done
if ansible-playbook -i localhost, "$t/play.yml" 2>&1 | grep -q "changed=0"; then ok "a second run changes nothing"; else bad "a second run changed something"; fi
[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
