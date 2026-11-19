#!/usr/bin/env bash
# The box's repo-create wrapper (hosts/ansible/roles/agent_box/files/repo-create.sh), against a fake curl first on
# PATH and a throwaway App key, so no GitHub account is needed:
#   1. A name outside ^[a-z0-9][a-z0-9-]{0,62}$, or a wrong argument count, is a usage error before any call.
#   2. A new name: the token is asked for with Repository creation (write) alone and no repositories, the name is
#      looked up, then POST /user/repos with private false and auto_init false; the token is revoked; one log line.
#   3. A name that exists (200 on the lookup) is refused before any create, and logged.
#   4. GitHub's 422 on the create (a name the token can't see) is refused, and logged.
#   5. An installation that has not accepted the permission (422 on the token) stops before any lookup or create.
#   6. A repository made under another account is reported, not taken as made.
#   7. The token is never in curl's arguments, the output or the log.
#   8. The sudo line passes `create *` and `log` only.
# Usage: .github/hosts-check/tests/test_repo_create.sh   (needs python3, openssl)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
files=$root/hosts/ansible/roles/agent_box/files
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/work/state" "$t/bin"
echo '{"github_app_id": 1}' > "$t/work/ci-runner.json"
openssl genrsa -out "$t/github-app.pem" 2048 2>/dev/null
sed "s|^keys=/etc/agent-keys|keys=$t|; s|^work=/var/lib/agent-box|work=$t/work|; s|^export HOME=\$work PATH=.*|export HOME=\$work PATH=$t/bin:/usr/local/bin:/usr/bin:/bin|" \
  "$files/repo-create.sh" > "$t/repo-create.sh"
grep -q "PATH=$t/bin" "$t/repo-create.sh" || { echo "FAIL: the wrapper's paths were not found to replace"; exit 1; }

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
  "GET https://api.github.com/users/jonhill90/installation") reply '{"id":42}' ;;
  "POST https://api.github.com/app/installations/42/access_tokens")
    [[ ${FAKE_TOKEN:-} == 422 ]] && reply '{"message":"The permissions requested are not granted to this installation."}' 422
    reply '{"token":"ghs_SECRETTOKEN123"}' 201 ;;
  "GET https://api.github.com/repos/jonhill90/"*)
    [[ ${FAKE_EXISTS:-} == yes ]] && reply '{"full_name":"jonhill90/x"}' 200
    reply '{"message":"Not Found"}' 404 ;;
  "POST https://api.github.com/user/repos")
    [[ ${FAKE_CREATE:-} == 422 ]] && reply '{"message":"Repository creation failed."}' 422
    n=$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$body")
    reply "{\"full_name\":\"${FAKE_OWNER:-jonhill90}/$n\"}" 201 ;;
  "DELETE https://api.github.com/installation/token") reply '' 204 ;;
esac
reply '{"message":"unexpected"}' 404
F
chmod +x "$t/bin/curl"
run() { # VAR=value ... -- args
  : > "$t/calls"; : > "$t/argv"; : > "$t/stdin"
  local envs=(); while [[ $1 != -- ]]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" FAKE_CALLS="$t/calls" FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" bash "$t/repo-create.sh" "$@" > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls")
}
lines() { [[ -f $t/work/state/repo-create.log ]] && wc -l < "$t/work/state/repo-create.log" || echo 0; }

# 1
r1=""
for args in "create" "create Upper" "create -lead" "create a.b" "create a_b" "create $(printf 'a%.0s' $(seq 64))" "create ok extra" "log extra" "delete ok" ""; do
  # shellcheck disable=SC2086
  run -- $args; r1+="$rc:$([[ -s $t/calls ]] && echo called || echo none) "
done
run -- create "$(printf 'a%.0s' $(seq 63))"; r1b=$rc
if [[ $r1 == "$(printf '2:none %.0s' $(seq 10))" && $r1b -eq 0 ]]; then
  ok "1. a bad name or argument count is a usage error before any call; 63 characters is taken"
else bad "1. [$r1] $r1b"; fi

# 2
before=$(lines); run -- create new-repo-1
want=$'GET https://api.github.com/users/jonhill90/installation \nPOST https://api.github.com/app/installations/42/access_tokens {"permissions":{"repository_creation":"write"}}\nGET https://api.github.com/repos/jonhill90/new-repo-1 \nPOST https://api.github.com/user/repos {"name":"new-repo-1","private":false,"auto_init":false}\nDELETE https://api.github.com/installation/token '
if [[ $rc -eq 0 && $calls == "$want" && $out == "repo-create: made jonhill90/new-repo-1 on GitHub (empty, public)" &&
      $(lines) -eq $((before + 1)) && $(tail -n 1 "$t/work/state/repo-create.log") == *" create new-repo-1 created jonhill90/new-repo-1" ]]; then
  ok "2. a new name: token with Repository creation alone, lookup, empty public create, token revoked, one log line"
else bad "2. rc=$rc out=[$out] calls=[$calls]"; fi

# 3
before=$(lines); run FAKE_EXISTS=yes -- create taken
if [[ $rc -eq 1 && $out == *"github.com/jonhill90/taken already exists; nothing was made"* && $calls != *"user/repos"* &&
      $calls == *"DELETE https://api.github.com/installation/token"* && $(tail -n 1 "$t/work/state/repo-create.log") == *" create taken refused exists" && $(lines) -eq $((before + 1)) ]]; then
  ok "3. a name that exists is refused before any create, the token revoked, the refusal logged"
else bad "3. rc=$rc out=[$out] calls=[$calls]"; fi

# 4
run FAKE_CREATE=422 -- create hidden
if [[ $rc -eq 1 && $out == *"GitHub refused to make jonhill90/hidden (Repository creation failed.)"* &&
      $(tail -n 1 "$t/work/state/repo-create.log") == *" create hidden refused create-422" ]]; then
  ok "4. GitHub's 422 on the create is refused and logged"
else bad "4. rc=$rc out=[$out]"; fi

# 5
run FAKE_TOKEN=422 -- create early
if [[ $rc -eq 1 && $out == *"no token with Repository creation (GitHub returned 422: The permissions requested are not granted to this installation.)"* &&
      $calls != *"/repos/"* && $(tail -n 1 "$t/work/state/repo-create.log") == *" create early failed token-422" ]]; then
  ok "5. an installation without the permission stops before any lookup or create"
else bad "5. rc=$rc out=[$out] calls=[$calls]"; fi

# 6
run FAKE_OWNER=someone-else -- create stray
if [[ $rc -eq 1 && $out == *"GitHub made someone-else/stray, not jonhill90/stray"* &&
      $(tail -n 1 "$t/work/state/repo-create.log") == *" create stray made-elsewhere someone-else/stray" ]]; then
  ok "6. a repository made under another account is reported, not taken as made"
else bad "6. rc=$rc out=[$out]"; fi

# 7
run -- create leak-check
if ! grep -q SECRETTOKEN "$t/argv" "$t/out" "$t/work/state/repo-create.log" && grep -q 'ghs_SECRETTOKEN123' "$t/stdin"; then
  ok "7. the token reaches curl only on stdin: never in its arguments, the output or the log"
else bad "7. the token leaked: $(grep -l SECRETTOKEN "$t/argv" "$t/out" "$t/work/state/repo-create.log" 2>/dev/null | tr '\n' ' ')"; fi

# 8
if python3 -I - "$root/hosts/ansible/roles/agent_box/defaults/main.yml" <<'PY'
import sys, yaml
w = [w for w in yaml.safe_load(open(sys.argv[1]))["agent_box_wrappers"] if w["name"] == "repo-create"]
sys.exit(0 if len(w) == 1 and w[0]["args"] == ["create *", "log"] and "runner" not in w[0] and "run_as" not in w[0] else 1)
PY
then ok "8. the sudo line passes create * and log only, as the keys user, and not to the runner"
else bad "8. the repo-create entry in agent_box_wrappers is missing or wider"; fi

exit $fail
