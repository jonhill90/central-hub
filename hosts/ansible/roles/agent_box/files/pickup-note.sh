#!/bin/bash
# /usr/local/libexec/agent-box/pickup-note.sh: post one fixed-format comment, as the GitHub App "Central Hub Agents",
# on the standing pull request the box's own settings name for one project, so a session that watches that pull
# request wakes when the project has a ready task and never on the clock. It runs as user `keys`, called by
# pickup-scan.py; a session has no sudo line for `post`, so it never sees the App key or the token.
#   pickup-note post <project> <TASK-NNNN>   "pickup: TASK-NNNN is ready for <project>."
#   pickup-note log                          the last 20 runs from the wrapper's own log.
# The pull request is never an argument: it is `repo` and `number` under that project in
# /var/lib/agent-box/pickup.json, which the agent_box role writes from agent_box_pickup_projects. The comment's text is
# fixed here; the only values that reach it are a label of the form TASK-0000 and a project that the settings name.
# The token is narrowed to that one repository and Pull requests (write) alone (GitHub accepts that for an issue
# comment on a pull request), is never printed, logged or passed as an argument, and is revoked when the run ends. A
# pull request that is not open is refused, and nothing is posted. Same pattern as checkpoint-note.sh.
set -euo pipefail
umask 077

owner=jonhill90   # the account the App is installed on
usage() { echo "usage: pickup-note post <project> <TASK-NNNN> | log" >&2; exit 2; }
action=${1:-}
case $action in
  post) [[ $# == 3 ]] || usage ;;
  log) [[ $# == 1 ]] || usage ;;
  *) usage ;;
esac
project=${2:-}
label=${3:-}
if [[ $action == post ]]; then
  [[ $project =~ ^[a-z][a-z0-9-]{0,40}$ ]] || { echo "pickup-note: the project is not a project name" >&2; exit 2; }
  [[ $label =~ ^TASK-[0-9]{4}$ ]] || { echo "pickup-note: the label must look like TASK-0123" >&2; exit 2; }
fi

keys=/etc/agent-keys
work=/var/lib/agent-box
settings=$work/ci-runner.json          # holds github_app_id; private, written by the agent_box role
target=$work/pickup.json               # the standing pull request of each project, written by the agent_box role
logf=$work/state/pickup-note.log
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

if [[ $action == log ]]; then
  [[ -f $logf ]] || { echo "pickup-note: no runs yet"; exit 0; }
  tail -n 20 "$logf"
  exit 0
fi

ref="-"
note() { # result, then detail: one line in the log and in the journal; never a token
  printf '%s post %s %s %s %s %s\n' "$(date -u +%FT%TZ)" "$project" "$label" "$ref" "$1" "${2:-}" >> "$logf"
  logger -t pickup-note "post $project $label $ref $1 ${2:-}" 2>/dev/null || true
}
die() { note "$1" "${2:-}"; echo "pickup-note: ${3:-$2}" >&2; exit 1; }

[[ -f $target ]] || die failed "no-target" "$target is missing; set agent_box_pickup_projects and run the agent_box role"
read -r repo number < <(python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1])).get("projects", {}).get(sys.argv[2], {})
print(d.get("repo", ""), d.get("number", ""))' "$target" "$project") || die failed "bad-target" "$target is not readable JSON"
[[ -n $repo ]] || die failed "no-project" "the settings do not name project '$project'"
case $repo in
  agent-notebook|central-hub|inpara|obsidian-graph-3d) ;;
  *) die failed "bad-target" "the settings name repository '$repo', which is not one the App is installed on" ;;
esac
[[ $number =~ ^[1-9][0-9]{0,6}$ ]] || die failed "no-number" "the settings hold no standing pull request number for '$project'"
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

text="pickup: $label is ready for $project."
payload=$(python3 -I -c 'import json,sys; print(json.dumps({"body": sys.argv[1]}))' "$text")
out=$(BEARER=$tok call -X POST -d "$payload" "https://api.github.com/repos/$owner/$repo/issues/$number/comments") ||
  die failed "curl" "GitHub did not answer"
split
[[ $code == 201 ]] || die failed "comment-$code" "GitHub returned $code for the comment: $(message)"
cid=$(printf '%s' "$body" | jsonget id)
note posted "comment-$cid"
echo "pickup-note: posted comment $cid on $owner/$ref: $text"
