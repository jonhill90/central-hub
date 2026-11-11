#!/bin/bash
# /usr/local/libexec/agent-box/pr-merge.sh: check or squash-merge one pull request as the GitHub App
# "Central Hub Agents", under D-0031. It runs as user `keys` through sudo, so the session that asks
# for it never sees the App key. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/pr-merge.sh check|merge OWNER/REPO PR_NUMBER HEAD_SHA
# check: reads the pull request and prints whether it is green; changes nothing.
# merge: does the same checks, then squash-merges pinned to HEAD_SHA. GitHub refuses the merge if
# the head moved after the check.
# Refuses (exit 3) any pull request that touches decision records, standards, specs, CLAUDE.md or
# AGENTS.md: those need the owner's named approval (D-0031 rules 3 and 4), so the owner's lane merges them.
# It does not delete the branch (the repositories delete merged branches themselves) and never
# enables auto-merge.
set -euo pipefail
umask 077

case ${1:-} in
  check | merge) action=$1 ;;
  *) echo "usage: pr-merge check|merge OWNER/REPO PR_NUMBER HEAD_SHA" >&2; exit 2 ;;
esac
full=${2:-}; pr=${3:-}; head=${4:-}
case $full in
  jonhill90/central-hub | jonhill90/inpara | jonhill90/agent-notebook | jonhill90/obsidian-graph-3d) ;;
  *) echo "pr-merge: $full is not one of the project's four repositories" >&2; exit 2 ;;
esac
[[ $pr =~ ^[0-9]{1,6}$ ]] || { echo "pr-merge: PR_NUMBER must be a number" >&2; exit 2; }
[[ $head =~ ^[0-9a-f]{40}$ ]] || { echo "pr-merge: HEAD_SHA must be the full 40-character head" >&2; exit 2; }
name=${full#*/}

keys=/etc/agent-keys
work=/var/lib/agent-box
settings=$work/ci-runner.json   # holds github_app_id; private, written by the agent_box role
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

[[ -f $settings ]] || { echo "pr-merge: $settings is missing" >&2; exit 1; }
app_id=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["github_app_id"])' "$settings")

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# One GitHub API call, with the bearer token in BEARER. The token goes to curl as a config line on
# stdin, never as an argument, because any local user can read arguments from /proc/<pid>/cmdline.
# On an error it prints the status and GitHub's message (never a token) and fails.
api() {
  local out code
  out=$(printf 'header = "Authorization: Bearer %s"\n' "$BEARER" |
    curl -sS -K - -w '\n%{http_code}' -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@") || return 1
  code=${out##*$'\n'}
  out=${out%$'\n'*}
  if [[ $code != 2* ]]; then
    printf 'pr-merge: GitHub returned %s for %s: %s\n' "$code" "${*: -1}" \
      "$(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("message", ""))' 2>/dev/null)" >&2
    return 1
  fi
  printf '%s' "$out"
}

now=$(date +%s)
jwt="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)"
jwt="$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$keys/github-app.pem" | b64url)"
inst=$(BEARER=$jwt api "https://api.github.com/repos/$full/installation" |
  python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])') ||
  { echo "pr-merge: no App installation on $full" >&2; exit 1; }
# Cut down to this one repository and the permissions a merge needs. Commit statuses are asked
# for first and dropped if the installation has not accepted them: GitHub Actions reports check
# runs, and only older tools report statuses.
mint() {
  BEARER=$jwt api -X POST \
    -d "{\"repositories\":[\"$name\"],\"permissions\":$1}" \
    "https://api.github.com/app/installations/$inst/access_tokens" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["token"])'
}
have_status=1
tok=$(mint '{"contents":"write","pull_requests":"write","checks":"read","statuses":"read"}' 2>/dev/null) || {
  have_status=0
  tok=$(mint '{"contents":"write","pull_requests":"write","checks":"read"}') ||
    { echo "pr-merge: no installation token (has the installation accepted contents and pull requests write, and checks read?)" >&2; exit 1; }
  echo "pr-merge: the installation has not accepted Commit statuses (read); legacy statuses are not checked" >&2
}
gh() { BEARER=$tok api "$@"; }
base=https://api.github.com/repos/$full

# The JSON goes to python through files in a private folder, not as arguments, so a large pull
# request can't hit the argument size limit.
tmp=$(mktemp -d "$work/state/pr-merge.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
gh "$base/pulls/$pr" > "$tmp/pr.json"
gh "$base/pulls/$pr/files?per_page=100" > "$tmp/files.json"
gh "$base/commits/$head/check-runs?per_page=100" > "$tmp/checks.json"
if [[ $have_status == 1 ]]; then gh "$base/commits/$head/status" > "$tmp/status.json"; else echo '{}' > "$tmp/status.json"; fi

# The verdict is decided in one place so check and merge can't disagree.
verdict=$(python3 -I - "$head" "$tmp" <<'PY'
import json, sys
head, tmp = sys.argv[1], sys.argv[2]
pr, files, checks, status = (json.load(open("%s/%s.json" % (tmp, n))) for n in ("pr", "files", "checks", "status"))
why = []
if pr.get("state") != "open": why.append("PR is not open")
if pr.get("draft"): why.append("PR is a draft")
if pr["head"]["sha"] != head: why.append("head is %s, not the one named" % pr["head"]["sha"][:7])
if pr.get("mergeable") is not True or pr.get("mergeable_state") == "dirty":
    why.append("GitHub reports no clean merge (mergeable=%s, state=%s)" % (pr.get("mergeable"), pr.get("mergeable_state")))
if len(files) >= 100: why.append("100 or more changed files; not checked")
guarded = [f["filename"] for f in files
           if f["filename"].startswith(("docs/decisions/", "docs/standards/", "docs/specs/")) or f["filename"] in ("CLAUDE.md", "AGENTS.md")]
if guarded:
    print("OWNER: touches " + ", ".join(guarded[:3]) + "; needs the owner's named approval (D-0031 rules 3, 4)")
    sys.exit(0)
runs = checks.get("check_runs", [])
if checks.get("total_count", len(runs)) != len(runs): why.append("read %d of %d check runs; not checked" % (len(runs), checks["total_count"]))
if not runs and not status.get("statuses"): why.append("no checks reported on this head")
for r in runs:
    if r["status"] != "completed": why.append("check %s is %s" % (r["name"], r["status"]))
    elif r["conclusion"] not in ("success", "skipped"): why.append("check %s: %s" % (r["name"], r["conclusion"]))
if status.get("statuses") and status.get("state") != "success": why.append("commit status is %s" % status.get("state"))
print("NOT GREEN: " + "; ".join(why) if why else "GREEN")
PY
)
echo "pr-merge: $full#$pr ${head:0:7}: $verdict"
case $verdict in
  GREEN) ;;
  OWNER:*) exit 3 ;;
  *) exit 1 ;;
esac
[[ $action == merge ]] || exit 0

gh -X PUT -d "{\"merge_method\":\"squash\",\"sha\":\"$head\"}" "$base/pulls/$pr/merge" |
  python3 -I -c 'import json,sys; d=json.load(sys.stdin); print("pr-merge: merged, commit", d.get("sha","")[:7])'
