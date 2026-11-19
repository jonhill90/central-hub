#!/bin/bash
# /usr/local/libexec/agent-box/repo-create.sh: create one empty public repository under the owner's account as the
# GitHub App "Central Hub Agents", with an installation token narrowed to Repository creation (write) alone. That
# permission covers making repositories (POST /user/repos, forks, template copies), not deleting them or changing
# their settings or collaborators, which are Administration (GitHub's permission table for Apps, read 2026-11-19).
# It runs as user `keys`, so a session never sees the App key or the token.
#   repo-create create NAME   create github.com/<owner>/NAME: empty (no README, licence or .gitignore), public. NAME is
#                             1 to 63 lowercase letters, digits and hyphens, not starting with a hyphen. A name that
#                             already exists is refused, and nothing is made.
#   repo-create log           the last 20 runs from the wrapper's own log.
# Every run of create appends one line to the log (time, name, result). The token is never printed, logged or
# passed as an argument, and it is revoked when the run ends.
set -euo pipefail
umask 077

owner=jonhill90   # the account the App is installed on; a repository is only ever made there
usage() { echo "usage: repo-create create NAME | log" >&2; exit 2; }
action=${1:-}
case $action in
  create) [[ $# == 2 ]] || usage ;;
  log) [[ $# == 1 ]] || usage ;;
  *) usage ;;
esac
name=${2:-}
if [[ $action == create && ! $name =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
  echo "repo-create: NAME must be 1 to 63 lowercase letters, digits and hyphens, not starting with a hyphen" >&2
  exit 2
fi

keys=/etc/agent-keys
work=/var/lib/agent-box
settings=$work/ci-runner.json   # holds github_app_id; private, written by the agent_box role
logf=$work/state/repo-create.log
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

if [[ $action == log ]]; then
  [[ -f $logf ]] || { echo "repo-create: no runs yet"; exit 0; }
  tail -n 20 "$logf"
  exit 0
fi

note() { # result, then detail: one line in the log and in the journal; never a token
  printf '%s create %s %s %s\n' "$(date -u +%FT%TZ)" "$name" "$1" "${2:-}" >> "$logf"
  logger -t repo-create "create $name $1 ${2:-}" 2>/dev/null || true
}
die() { note "$1" "${2:-}"; echo "repo-create: ${3:-$2}" >&2; exit 1; }

[[ -f $settings ]] || die failed "no-settings" "$settings is missing"
app_id=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["github_app_id"])' "$settings")

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
jsonget() { python3 -I -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d.get(k, "") if isinstance(d, dict) else ""
print(d)' "$1"; }

# One GitHub API call, with the bearer token in BEARER. The token goes to curl as a config line on stdin, never as
# an argument, because any local user can read arguments from /proc/<pid>/cmdline. Prints the body, then the HTTP
# status on its own last line; fails only when curl itself fails.
call() {
  printf 'header = "Authorization: Bearer %s"\n' "$BEARER" |
    curl -sS -K - -w '\n%{http_code}' -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}
split() { code=${out##*$'\n'}; body=${out%$'\n'*}; }
message() { printf '%s' "$body" | jsonget message 2>/dev/null || true; }

now=$(date +%s)
jwt="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)"
jwt="$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$keys/github-app.pem" | b64url)"

out=$(BEARER=$jwt call "https://api.github.com/users/$owner/installation") || die failed "curl" "GitHub did not answer"
split
[[ $code == 200 ]] || die failed "installation-$code" "no App installation on $owner (GitHub returned $code: $(message))"
inst=$(printf '%s' "$body" | jsonget id)

# The token: Repository creation (write) only, no repositories named.
out=$(BEARER=$jwt call -X POST -d '{"permissions":{"repository_creation":"write"}}' \
  "https://api.github.com/app/installations/$inst/access_tokens") || die failed "curl" "GitHub did not answer"
split
[[ $code == 201 ]] || die failed "token-$code" \
  "no token with Repository creation (GitHub returned $code: $(message)); has the installation accepted that permission?"
tok=$(printf '%s' "$body" | jsonget token)
[[ -n $tok ]] || die failed "token-empty" "GitHub's token answer held no token"
revoke() { out=$(BEARER=$tok call -X DELETE "https://api.github.com/installation/token") || true; }
trap revoke EXIT

# Refuse a name that already exists. A public repository answers 200 to any token; a private one the token can't
# see answers 404 here, and GitHub's create then answers 422, which is refused below the same way.
out=$(BEARER=$tok call "https://api.github.com/repos/$owner/$name") || die failed "curl" "GitHub did not answer"
split
case $code in
  404) ;;
  200) die refused "exists" "github.com/$owner/$name already exists; nothing was made" ;;
  *) die failed "lookup-$code" "could not tell whether $owner/$name exists (GitHub returned $code: $(message))" ;;
esac

out=$(BEARER=$tok call -X POST -d "{\"name\":\"$name\",\"private\":false,\"auto_init\":false}" \
  "https://api.github.com/user/repos") || die failed "curl" "GitHub did not answer"
split
case $code in
  201) ;;
  422) die refused "create-422" "GitHub refused to make $owner/$name ($(message)); it may already exist; nothing was made" ;;
  *) die failed "create-$code" "GitHub returned $code for the create: $(message)" ;;
esac
made=$(printf '%s' "$body" | jsonget full_name)
if [[ $made != "$owner/$name" ]]; then
  die made-elsewhere "$made" "GitHub made $made, not $owner/$name; look at it before anything else uses it"
fi
note created "$made"
echo "repo-create: made $made on GitHub (empty, public)"
