#!/bin/bash
# /usr/local/libexec/agent-box/checkpoint-note.sh: post one fixed-format comment, as the GitHub App "Central Hub Agents",
# on the one pull request the box's own settings name, so a session that watches that pull request wakes on a box
# finding and never on the clock (notebook note "Each scheduled model loop can become a box timer"). It runs as user
# `keys`, so a session never sees the App key or the token.
#   checkpoint-note post test   the wake-path test: "checkpoint: wake-path test from the agent box at <time>; no finding."
#   checkpoint-note post N      N findings (1 to 999): "checkpoint: N finding(s) on the agent box at <time>."
#   checkpoint-note log         the last 20 runs from the wrapper's own log.
# The pull request is never an argument: it is `repo` and `number` in /var/lib/agent-box/checkpoint-note.json, which
# the agent_box role writes from agent_box_checkpoint_note. That folder is the keys user's, so code running as keys could
# replace the file; what keeps a session out is that it runs as keys only through its sudo lines, and no wrapper but
# this one names the file, which it only reads (test_checkpoint_note.sh check 7). The comment's text is fixed here; no argument
# reaches it but the count. The token is narrowed to that one repository and Pull requests (write) alone, which
# GitHub accepts for an issue comment on a pull request; it is never printed, logged or passed as an argument, and it
# is revoked when the run ends. A pull request that is not open is refused, and nothing is posted.
set -euo pipefail
umask 077

owner=jonhill90   # the account the App is installed on
usage() { echo "usage: checkpoint-note post test|N | log" >&2; exit 2; }
action=${1:-}
case $action in
  post) [[ $# == 2 ]] || usage ;;
  log) [[ $# == 1 ]] || usage ;;
  *) usage ;;
esac
what=${2:-}
if [[ $action == post && $what != test && ! $what =~ ^[1-9][0-9]{0,2}$ ]]; then
  echo "checkpoint-note: post takes test or a count of findings from 1 to 999" >&2
  exit 2
fi

keys=/etc/agent-keys
work=/var/lib/agent-box
settings=$work/ci-runner.json          # holds github_app_id; private, written by the agent_box role
target=$work/checkpoint-note.json      # the one pull request, written by the agent_box role
logf=$work/state/checkpoint-note.log
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

if [[ $action == log ]]; then
  [[ -f $logf ]] || { echo "checkpoint-note: no runs yet"; exit 0; }
  tail -n 20 "$logf"
  exit 0
fi

ref="-"
note() { # result, then detail: one line in the log and in the journal; never a token
  printf '%s post %s %s %s %s\n' "$(date -u +%FT%TZ)" "$what" "$ref" "$1" "${2:-}" >> "$logf"
  logger -t checkpoint-note "post $what $ref $1 ${2:-}" 2>/dev/null || true
}
die() { note "$1" "${2:-}"; echo "checkpoint-note: ${3:-$2}" >&2; exit 1; }

[[ -f $target ]] || die failed "no-target" "$target is missing; set agent_box_checkpoint_note and run the agent_box role"
read -r repo number < <(python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1])); print(d.get("repo",""), d.get("number",""))' "$target") || die failed "bad-target" "$target is not readable JSON"
case $repo in
  agent-notebook|central-hub|inpara|obsidian-graph-3d) ;;
  *) die failed "bad-target" "the settings name repository '$repo', which is not one the App is installed on" ;;
esac
[[ $number =~ ^[1-9][0-9]{0,6}$ ]] || die failed "bad-target" "the settings' pull request number is not a number"
ref="$repo#$number"
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

out=$(BEARER=$jwt call "https://api.github.com/repos/$owner/$repo/installation") || die failed "curl" "GitHub did not answer"
split
[[ $code == 200 ]] || die failed "installation-$code" "no App installation on $owner/$repo (GitHub returned $code: $(message))"
inst=$(printf '%s' "$body" | jsonget id)

# The token: that one repository, Pull requests (write) only.
out=$(BEARER=$jwt call -X POST -d "{\"repositories\":[\"$repo\"],\"permissions\":{\"pull_requests\":\"write\"}}" \
  "https://api.github.com/app/installations/$inst/access_tokens") || die failed "curl" "GitHub did not answer"
split
[[ $code == 201 ]] || die failed "token-$code" "no token with Pull requests (write) on $repo (GitHub returned $code: $(message))"
tok=$(printf '%s' "$body" | jsonget token)
[[ -n $tok ]] || die failed "token-empty" "GitHub's token answer held no token"
revoke() { out=$(BEARER=$tok call -X DELETE "https://api.github.com/installation/token") || true; }
trap revoke EXIT

out=$(BEARER=$tok call "https://api.github.com/repos/$owner/$repo/pulls/$number") || die failed "curl" "GitHub did not answer"
split
[[ $code == 200 ]] || die failed "pull-$code" "could not read pull request $ref (GitHub returned $code: $(message)); nothing posted"
state=$(printf '%s' "$body" | jsonget state)
[[ $state == open ]] || die refused "not-open" "pull request $ref is $state, not open; nothing posted"

stamp=$(date -u +%FT%TZ)
if [[ $what == test ]]; then text="checkpoint: wake-path test from the agent box at $stamp; no finding."
else text="checkpoint: $what finding(s) on the agent box at $stamp."; fi
payload=$(python3 -I -c 'import json,sys; print(json.dumps({"body": sys.argv[1]}))' "$text")
out=$(BEARER=$tok call -X POST -d "$payload" "https://api.github.com/repos/$owner/$repo/issues/$number/comments") ||
  die failed "curl" "GitHub did not answer"
split
[[ $code == 201 ]] || die failed "comment-$code" "GitHub returned $code for the comment: $(message)"
cid=$(printf '%s' "$body" | jsonget id)
note posted "comment-$cid"
echo "checkpoint-note: posted comment $cid on $owner/$ref at $stamp"
