#!/usr/bin/env bash
# The box's checkpoint-note wrapper (hosts/ansible/roles/agent_box/files/checkpoint-note.sh), against a fake curl first
# on PATH and a throwaway App key, so no GitHub account is needed:
#   1. Anything but `post test`, `post N` (1 to 999) or `log` is a usage error before any call; a pull request number
#      or a repository can't be passed.
#   2. `post test`: the token is asked for with that one repository and Pull requests (write) alone, the pull request is
#      read, then one comment with the fixed test text goes to the pull request the settings file names; the token is
#      revoked; one log line.
#   3. `post 3`: the comment says "3 finding(s)" and nothing else from the arguments.
#   4. A pull request that is not open is refused before any comment, and logged.
#   5. No settings file, a repository the App isn't installed on, or a number that isn't one: refused before any call.
#   6. The token is never in curl's arguments, the output or the log.
#   7. The role writes the settings file root-owned and the sudo line passes `post *` and `log` only.
# Usage: .github/hosts-check/tests/test_checkpoint_note.sh   (needs python3, openssl)
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
  "$files/checkpoint-note.sh" > "$t/checkpoint-note.sh"
grep -q "PATH=$t/bin" "$t/checkpoint-note.sh" || { echo "FAIL: the wrapper's paths were not found to replace"; exit 1; }

# The fake curl: records method, URL, body and argv; the stdin config (which holds the bearer) goes to its own file.
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
  "GET https://api.github.com/repos/jonhill90/agent-notebook/pulls/729") reply "{\"state\":\"${FAKE_STATE:-open}\"}" ;;
  "POST https://api.github.com/repos/jonhill90/agent-notebook/issues/729/comments") reply '{"id":555}' 201 ;;
  "DELETE https://api.github.com/installation/token") reply '' 204 ;;
esac
reply '{"message":"unexpected"}' 404
F
chmod +x "$t/bin/curl"
target() { printf '%s\n' "$1" > "$t/work/checkpoint-note.json"; }
target '{"repo": "agent-notebook", "number": 729}'
run() { # VAR=value ... -- args
  : > "$t/calls"; : > "$t/argv"; : > "$t/stdin"
  local envs=(); while [[ $1 != -- ]]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" FAKE_CALLS="$t/calls" FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" bash "$t/checkpoint-note.sh" "$@" > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls")
}
lines() { [[ -f $t/work/state/checkpoint-note.log ]] && wc -l < "$t/work/state/checkpoint-note.log" || echo 0; }
comment_body() { sed -n 's|^POST https://api.github.com/repos/jonhill90/agent-notebook/issues/729/comments ||p' "$t/calls" |
  python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())["body"])'; }

# 1
r1=""
for args in "post" "post 0" "post 1000" "post -1" "post abc" "post 729 central-hub" "post test extra" "log extra" \
            "post jonhill90/central-hub#1" "delete 1" ""; do
  # shellcheck disable=SC2086
  run -- $args; r1+="$rc:$([[ -s $t/calls ]] && echo called || echo none) "
done
if [[ $r1 == "$(printf '2:none %.0s' $(seq 11))" ]]; then
  ok "1. anything but post test, post 1-999 or log is a usage error before any call"
else bad "1. [$r1]"; fi

# 2
before=$(lines); run -- post test
want=$'GET https://api.github.com/repos/jonhill90/agent-notebook/installation \nPOST https://api.github.com/app/installations/42/access_tokens {"repositories":["agent-notebook"],"permissions":{"pull_requests":"write"}}\nGET https://api.github.com/repos/jonhill90/agent-notebook/pulls/729 '
body2=$(comment_body)
if [[ $rc -eq 0 && $calls == "$want"$'\n'"POST https://api.github.com/repos/jonhill90/agent-notebook/issues/729/comments "*$'\n'"DELETE https://api.github.com/installation/token " &&
      $body2 =~ ^checkpoint:\ wake-path\ test\ from\ the\ agent\ box\ at\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\;\ no\ finding\.$ &&
      $out == "checkpoint-note: posted comment 555 on jonhill90/agent-notebook#729 at "* &&
      $(lines) -eq $((before + 1)) && $(tail -n 1 "$t/work/state/checkpoint-note.log") == *" post test agent-notebook#729 posted comment-555" ]]; then
  ok "2. post test: token for that one repository with Pull requests (write) alone, the PR read, one fixed comment, token revoked, one log line"
else bad "2. rc=$rc [$calls] [$body2] [$out]"; fi

# 3
run -- post 3; body3=$(comment_body)
if [[ $rc -eq 0 && $body3 =~ ^checkpoint:\ 3\ finding\(s\)\ on\ the\ agent\ box\ at\ [0-9T:-]{19}Z\.$ ]]; then
  ok "3. post 3: the comment says 3 finding(s) and the time, nothing else from the arguments"
else bad "3. rc=$rc [$body3]"; fi

# 4
before=$(lines); run FAKE_STATE=closed -- post test
if [[ $rc -ne 0 && $calls != *"/comments"* && $out == *"is closed, not open; nothing posted"* && $calls == *"DELETE https://api.github.com/installation/token"* &&
      $(lines) -eq $((before + 1)) && $(tail -n 1 "$t/work/state/checkpoint-note.log") == *" refused not-open" ]]; then
  ok "4. a pull request that is not open is refused before any comment, the token revoked, and logged"
else bad "4. rc=$rc [$calls] [$out]"; fi

# 5
r5=""
rm -f "$t/work/checkpoint-note.json"; run -- post test; r5+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *missing* ]] && echo said) "
target '{"repo": "someone-else", "number": 729}'; run -- post test; r5+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *"not one the App is installed on"* ]] && echo said) "
target '{"repo": "agent-notebook", "number": "729; x"}'; run -- post test; r5+="$rc:$([[ -s $t/calls ]] && echo called || echo none):$([[ $out == *"not a number"* ]] && echo said) "
target '{"repo": "agent-notebook", "number": 729}'
if [[ $r5 == "1:none:said 1:none:said 1:none:said " ]]; then
  ok "5. no settings file, a repository the App isn't on, or a bad number: refused before any call"
else bad "5. [$r5]"; fi

# 6
run -- post test
if ! grep -q SECRETTOKEN "$t/argv" "$t/out" "$t/work/state/checkpoint-note.log" && grep -q SECRETTOKEN "$t/stdin"; then
  ok "6. the token reaches curl only on stdin: never in its arguments, the output or the log"
else bad "6. token found in: $(grep -l SECRETTOKEN "$t/argv" "$t/out" "$t/work/state/checkpoint-note.log" 2>/dev/null | tr '\n' ' ')"; fi

# 7
task=$(awk '/^- name: The checkpoint-note wrapper.s one pull request/{on=1} on{print} on && /^$/{exit}' "$role/tasks/main.yml")
sudo=$(python3 -I -c 'import sys, yaml
for w in yaml.safe_load(open(sys.argv[1]))["agent_box_wrappers"]:
    if w["name"] == "checkpoint-note": print(w.get("args"))' "$role/defaults/main.yml" 2>&1)
if [[ $task == *"dest: \"{{ agent_box_work_dir }}/checkpoint-note.json\""* && $task == *"owner: root"* && $task == *'mode: "0644"'* &&
      $sudo == "['post *', 'log']" ]]; then
  ok "7. the role writes the settings file root-owned 0644, and the sudo line passes post * and log only"
else bad "7. [$sudo] [$task]"; fi

exit $fail
