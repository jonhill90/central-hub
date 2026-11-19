#!/usr/bin/env bash
# The box's pickup-note wrapper (hosts/ansible/roles/agent_box/files/pickup-note.sh), against a fake curl first on PATH
# and a throwaway App key, so no GitHub account is needed:
#   1. Anything but `post <project> <TASK-NNNN>`, `post-stale <project> <TASK-NNNN>` or `log` is a usage error before any call: a label that is not
#      TASK-0000, a project that is not a name, a pull request, a repository or an extra argument can't be passed.
#   2. `post`: the token is asked for with that project's one repository and Pull requests (write) alone, the pull
#      request is read, then one comment with the fixed text goes to the pull request the settings name for that
#      project; the token is revoked; one log line.
#   3. A project the settings don't name, one with no pull request number, or a repository the App isn't installed on:
#      refused before any call. No settings file: refused.
#   2b. `post-stale` does the same with the fixed text "pickup: TASK-NNNN is stale for <project>." and logs `post-stale`.
#   4. A pull request that is not open is refused before any comment, and logged.
#   5. The token is never in curl's arguments, the output or the log.
#   6. The role writes the settings file, the wrapper's sudo line gives sessions `log` only (the scan posts as the keys
#      user), and no other file names pickup.json except the scan, which only reads project names.
# Usage: .github/hosts-check/tests/test_pickup_note.sh   (needs python3, openssl, PyYAML)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
files=$root/hosts/ansible/roles/agent_box/files
role=$root/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/work/state" "$t/bin"
echo '{"github_app_id": 1}' > "$t/work/ci-runner.json"
openssl genrsa -out "$t/github-app.pem" 2048 2>/dev/null
sed "s|^keys=/etc/agent-keys|keys=$t|; s|^work=/var/lib/agent-box|work=$t/work|; s|^export HOME=\$work PATH=.*|export HOME=\$work PATH=$t/bin:/usr/local/bin:/usr/bin:/bin|" \
  "$files/pickup-note.sh" > "$t/pickup-note.sh"
grep -q "PATH=$t/bin" "$t/pickup-note.sh" || { echo "FAIL: the wrapper's paths were not found to replace"; exit 1; }

cat > "$t/bin/curl" <<'F'
#!/bin/bash
cat >> "$FAKE_STDIN"
method=GET body=; for a in "$@"; do last=$a; done
prev=; for a in "$@"; do [[ $prev == -X ]] && method=$a; [[ $prev == -d ]] && body=$a; prev=$a; done
echo "$method $last $body" >> "$FAKE_CALLS"
printf '%s\n' "$*" >> "$FAKE_ARGV"
reply() { printf '%s\n%s' "$1" "${2:-200}"; exit 0; }
case "$method $last" in
  "GET https://api.github.com/repos/jonhill90/agent-notebook/installation") reply '{"id":42}' ;;
  "POST https://api.github.com/app/installations/42/access_tokens") reply '{"token":"ghs_SECRETTOKEN123"}' 201 ;;
  "GET https://api.github.com/repos/jonhill90/agent-notebook/pulls/801") reply "{\"state\":\"${FAKE_STATE:-open}\"}" ;;
  "POST https://api.github.com/repos/jonhill90/agent-notebook/issues/801/comments") reply '{"id":555}' 201 ;;
  "DELETE https://api.github.com/installation/token") reply '' 204 ;;
esac
reply '{"message":"unexpected"}' 404
F
chmod +x "$t/bin/curl"
target() { printf '%s\n' "$1" > "$t/work/pickup.json"; }
target '{"projects": {"agent-notebook": {"repo": "agent-notebook", "number": 801}, "no-number": {"repo": "agent-notebook"}, "elsewhere": {"repo": "someone-else", "number": 5}}}'
run() { # VAR=value ... -- args
  : > "$t/calls"; : > "$t/argv"; : > "$t/stdin"
  local envs=(); while [[ $1 != -- ]]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" FAKE_CALLS="$t/calls" FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" bash "$t/pickup-note.sh" "$@" > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls")
}
lines() { [[ -f $t/work/state/pickup-note.log ]] && wc -l < "$t/work/state/pickup-note.log" || echo 0; }
comment_body() { sed -n 's|^POST https://api.github.com/repos/jonhill90/agent-notebook/issues/801/comments ||p' "$t/calls" |
  python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())["body"])'; }

# 1
r1=""; n=0
for args in "post" "post agent-notebook" "post agent-notebook TASK-1" "post agent-notebook TASK-12345" "post agent-notebook task-0001" \
            "post agent-notebook TASK-0001 extra" "post Agent-Notebook TASK-0001" "post agent-notebook;x TASK-0001" \
            "post 801 TASK-0001" "post agent-notebook TASK-0001;x" "log extra" "delete agent-notebook TASK-0001" "" \
            "post-stale" "post-stale agent-notebook" "post-stale agent-notebook TASK-1" "post-stale agent-notebook TASK-12345" \
            "post-stale agent-notebook task-0001" "post-stale agent-notebook TASK-0001 extra" "post-stale Agent-Notebook TASK-0001" \
            "post-stale agent-notebook;x TASK-0001" "post-stale 801 TASK-0001" "post-stale agent-notebook TASK-0001;x" \
            "post_stale agent-notebook TASK-0001" "poststale agent-notebook TASK-0001" "post-stale-x agent-notebook TASK-0001"; do
  # shellcheck disable=SC2086
  run -- $args; r1+="$rc:$([[ -s $t/calls ]] && echo called || echo none) "; n=$((n + 1))
done
if [[ $r1 == "$(printf '2:none %.0s' $(seq $n))" ]]; then
  ok "1. anything but post or post-stale <project> <TASK-0000>, or log, is a usage error before any call"
else bad "1. [$r1]"; fi

# 2
before=$(lines); run -- post agent-notebook TASK-0305
want=$'GET https://api.github.com/repos/jonhill90/agent-notebook/installation \nPOST https://api.github.com/app/installations/42/access_tokens {"repositories":["agent-notebook"],"permissions":{"pull_requests":"write"}}\nGET https://api.github.com/repos/jonhill90/agent-notebook/pulls/801 '
body2=$(comment_body)
if [[ $rc -eq 0 && $calls == "$want"$'\n'"POST https://api.github.com/repos/jonhill90/agent-notebook/issues/801/comments "*$'\n'"DELETE https://api.github.com/installation/token " &&
      $body2 == "pickup: TASK-0305 is ready for agent-notebook." &&
      $out == "pickup-note: posted comment 555 on jonhill90/agent-notebook#801: pickup: TASK-0305 is ready for agent-notebook." &&
      $(lines) -eq $((before + 1)) && $(tail -n 1 "$t/work/state/pickup-note.log") == *" post agent-notebook TASK-0305 agent-notebook#801 posted comment-555" ]]; then
  ok "2. post: token for that project's one repository with Pull requests (write) alone, the PR read, one fixed comment on its standing PR, token revoked, one log line"
else bad "2. rc=$rc [$calls] [$body2] [$out]"; fi

# 2b
before=$(lines); run -- post-stale agent-notebook TASK-0305
body2b=$(comment_body)
if [[ $rc -eq 0 && $calls == "$want"$'\n'"POST https://api.github.com/repos/jonhill90/agent-notebook/issues/801/comments "*$'\n'"DELETE https://api.github.com/installation/token " &&
      $body2b == "pickup: TASK-0305 is stale for agent-notebook." &&
      $out == "pickup-note: posted comment 555 on jonhill90/agent-notebook#801: pickup: TASK-0305 is stale for agent-notebook." &&
      $(lines) -eq $((before + 1)) && $(tail -n 1 "$t/work/state/pickup-note.log") == *" post-stale agent-notebook TASK-0305 agent-notebook#801 posted comment-555" ]]; then
  ok "2b. post-stale: the same token, PR read, one fixed stale comment on the standing PR, token revoked, one log line naming post-stale"
else bad "2b. rc=$rc [$calls] [$body2b] [$out]"; fi
run FAKE_STATE=closed -- post-stale agent-notebook TASK-0305
if [[ $rc -ne 0 && $calls != *"/comments"* && $out == *"is closed, not open; nothing posted"* ]]; then
  ok "2c. post-stale on a pull request that is not open is refused before any comment"
else bad "2c. rc=$rc [$calls] [$out]"; fi

# 3
r3=""
run -- post other-project TASK-0001; r3+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *"do not name project"* ]] && echo said) "
run -- post no-number TASK-0001; r3+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *"no standing pull request number"* ]] && echo said) "
run -- post elsewhere TASK-0001; r3+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *"not one the App is installed on"* ]] && echo said) "
rm -f "$t/work/pickup.json"; run -- post agent-notebook TASK-0001; r3+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *missing* ]] && echo said) "
if [[ $r3 == "1:none:said 1:none:said 1:none:said 1:none:said " ]]; then
  ok "3. an unnamed project, one with no number, a repository the App isn't on, or no settings file: refused before any call"
else bad "3. [$r3]"; fi
target '{"projects": {"agent-notebook": {"repo": "agent-notebook", "number": 801}}}'

# 4
before=$(lines); run FAKE_STATE=closed -- post agent-notebook TASK-0305
if [[ $rc -ne 0 && $calls != *"/comments"* && $out == *"is closed, not open; nothing posted"* && $calls == *"DELETE https://api.github.com/installation/token"* &&
      $(lines) -eq $((before + 1)) && $(tail -n 1 "$t/work/state/pickup-note.log") == *" refused not-open" ]]; then
  ok "4. a pull request that is not open is refused before any comment, the token revoked, and logged"
else bad "4. rc=$rc [$calls] [$out]"; fi

# 5
run -- post agent-notebook TASK-0305
if ! grep -q SECRETTOKEN "$t/argv" "$t/out" "$t/work/state/pickup-note.log" && grep -q SECRETTOKEN "$t/stdin"; then
  ok "5. the token reaches curl only on stdin: never in its arguments, the output or the log"
else bad "5. token found in: $(grep -l SECRETTOKEN "$t/argv" "$t/out" "$t/work/state/pickup-note.log" 2>/dev/null | tr '\n' ' ')"; fi

# 6
task=$(awk '/^- name: The pickup scan.s and the pickup wrapper.s one list of projects/{on=1} on{print} on && /^$/{exit}' "$role/tasks/main.yml")
sudo=$(python3 -I -c 'import sys, yaml
for w in yaml.safe_load(open(sys.argv[1]))["agent_box_wrappers"]:
    if w["name"] == "pickup-note": print(w.get("args"), w.get("session_args"))' "$role/defaults/main.yml" 2>&1)
others=$(grep -l 'pickup\.json' "$role"/files/* "$role"/templates/* 2>/dev/null | grep -v -E '/pickup-(note\.sh|scan\.py)$' || true)
if [[ $task == *"dest: \"{{ agent_box_work_dir }}/pickup.json\""* && $task == *"owner: root"* && $task == *'mode: "0644"'* &&
      $sudo == "['post *', 'log'] ['log']" && -z $others ]]; then
  ok "6. the role writes the settings file, sessions get pickup-note log only, and only the scan and this wrapper name the file"
else bad "6. [$sudo] [$task] [others: $others]"; fi

exit $fail
