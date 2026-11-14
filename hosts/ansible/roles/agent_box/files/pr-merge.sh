#!/bin/bash
# /usr/local/libexec/agent-box/pr-merge.sh: check or squash-merge pull requests as the GitHub App
# "Central Hub Agents", under D-0031 and D-0042. It runs as user `keys`; sessions may run only `check` through sudo,
# so a session never sees the App key.
#   pr-merge check OWNER/REPO PR_NUMBER HEAD_SHA   read the PR and print its verdict; changes nothing.
#   pr-merge merge OWNER/REPO PR_NUMBER HEAD_SHA   the same, then squash-merge pinned to HEAD_SHA (no sudo line gives it to a session).
#   pr-merge lane  OWNER/REPO PR_NUMBER            print the PR body's Author-Lane label (pass-record uses it).
#   pr-merge sweep                                 what the systemd timer runs: for each open PR whose head holds four recorded
#                                                  passes (pass-record), the same checks, then merge. Skips everything while
#                                                  the halt flag is set. It is not GitHub's auto-merge.
# The verdict is decided by pr-merge-verdict.py from files this script fetches: the checks, a clean merge, the ledger of passes,
# the rule 11 files that also need an owner-tap line, and the fold-in checks for a status change. It never enables auto-merge,
# never passes --admin and does not delete the branch (the repositories delete merged branches themselves).
set -euo pipefail
umask 077

repos=(jonhill90/central-hub jonhill90/inpara jonhill90/agent-notebook jonhill90/obsidian-graph-3d)
usage() { echo "usage: pr-merge check|merge OWNER/REPO PR_NUMBER HEAD_SHA | lane OWNER/REPO PR_NUMBER | sweep" >&2; exit 2; }
action=${1:-}
case $action in
  check | merge) [[ $# == 4 ]] || usage ;;
  lane) [[ $# == 3 ]] || usage ;;
  sweep) [[ $# == 1 ]] || usage ;;
  *) usage ;;
esac
check_repo() {
  case $1 in
    jonhill90/central-hub | jonhill90/inpara | jonhill90/agent-notebook | jonhill90/obsidian-graph-3d) ;;
    *) echo "pr-merge: $1 is not one of the project's four repositories" >&2; exit 2 ;;
  esac
}
full=${2:-}; pr=${3:-}; head=${4:-}
if [[ $action != sweep ]]; then
  check_repo "$full"
  [[ $pr =~ ^[0-9]{1,6}$ ]] || { echo "pr-merge: PR_NUMBER must be a number" >&2; exit 2; }
  if [[ $action != lane ]]; then
    [[ $head =~ ^[0-9a-f]{40}$ ]] || { echo "pr-merge: HEAD_SHA must be the full 40-character head" >&2; exit 2; }
  fi
fi

keys=/etc/agent-keys
work=/var/lib/agent-box
passes=$work/passes
libexec=/usr/local/libexec/agent-box
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


# The installation token for one repository, cut down to what a merge needs. Commit statuses are asked
# for first and dropped if the installation has not accepted them: GitHub Actions reports check
# runs, and only older tools report statuses.
mint() {
  BEARER=$jwt api -X POST \
    -d "{\"repositories\":[\"$name\"],\"permissions\":$1}" \
    "https://api.github.com/app/installations/$inst/access_tokens" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["token"])'
}
errf=$(mktemp "$work/state/pr-merge-err.XXXXXX")
tmp=$(mktemp -d "$work/state/pr-merge.XXXXXX")
trap 'rm -rf "$tmp" "$errf"' EXIT

# Sets name, base, tok and have_status for one repository.
setup_repo() {
  full=$1; name=${full#*/}; base=https://api.github.com/repos/$full
  local now; now=$(date +%s)
  jwt="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)"
  jwt="$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$keys/github-app.pem" | b64url)"
  inst=$(BEARER=$jwt api "https://api.github.com/repos/$full/installation" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])') ||
    { echo "pr-merge: no App installation on $full" >&2; return 1; }
  have_status=1
  tok=$(mint '{"contents":"write","pull_requests":"write","checks":"read","statuses":"read"}' 2>"$errf") || {
    # Only a 422 from GitHub means a permission was not accepted; any other failure (network, 5xx,
    # a bad key) stops here instead of quietly dropping the status check.
    grep -q 'returned 422' "$errf" || { cat "$errf" >&2; echo "pr-merge: no installation token" >&2; return 1; }
    have_status=0
    tok=$(mint '{"contents":"write","pull_requests":"write","checks":"read"}') ||
      { echo "pr-merge: no installation token (has the installation accepted contents and pull requests write, and checks read?)" >&2; return 1; }
    echo "pr-merge: the installation has not accepted Commit statuses (read); legacy statuses are not checked" >&2
  }
}
gh() { BEARER=$tok api "$@"; }

# GitHub's compare, up to 3 pages of 100 files, merged into one JSON file.
fetch_compare() { # out basehead
  local out=$1 bh=$2 p
  for p in 1 2 3; do gh "$base/compare/$bh?per_page=100&page=$p" > "$tmp/cmp.$p.json" || return 1; done
  python3 -I - "$out" "$tmp"/cmp.[123].json <<'PY'
import json, sys
out, parts = sys.argv[1], [json.load(open(p)) for p in sys.argv[2:]]
merged = dict(parts[0]); seen = {}
for p in parts:
    for f in p.get("files", []): seen[f["filename"]] = f
merged["files"] = list(seen.values())
json.dump(merged, open(out, "w"))
PY
}

# Fetches everything the verdict needs into $tmp/d, then runs pr-merge-verdict.py. Sets verdict (last line) and
# out (all lines). Returns 1 if a fetch failed (nothing is decided on a failed read).
evaluate() { # pr head
  local pr=$1 head=$2 d=$tmp/d
  rm -rf "$d"; mkdir -p "$d/content/base" "$d/content/head" "$d/approved"
  gh "$base/pulls/$pr" > "$d/pr.json" || return 1
  gh "$base/pulls/$pr/files?per_page=100" > "$d/files.json" || return 1
  gh "$base/commits/$head/check-runs?per_page=100" > "$d/checks.json" || return 1
  if [[ $have_status == 1 ]]; then gh "$base/commits/$head/status" > "$d/status.json" || return 1; else echo '{}' > "$d/status.json"; fi
  [[ -f $passes/$name/$head.jsonl ]] && cp "$passes/$name/$head.jsonl" "$d/ledger.jsonl" || true
  if [[ $full == jonhill90/central-hub ]]; then
    local recs
    recs=$(python3 -I -c '
import json, re, sys
for f in json.load(open(sys.argv[1])):
    n = f["filename"]
    if re.match(r"^docs/(decisions|standards)/[^/]+\.md$", n) and not n.endswith("README.md"): print(n)
' "$d/files.json" | head -20)
    if [[ -n $recs ]]; then
      fetch_compare "$d/compare-head.json" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["base"]["sha"])' "$d/pr.json")...$head" || return 1
      local mb path q
      mb=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["merge_base_commit"]["sha"])' "$d/compare-head.json") || return 1
      while IFS= read -r path; do
        q=$(python3 -I -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$path")
        for side in base head; do
          ref=$mb; [[ $side == head ]] && ref=$head
          if gh "$base/contents/$path?ref=$ref" > "$tmp/c.json" 2>/dev/null; then
            python3 -I -c 'import base64,json,sys; sys.stdout.write(base64.b64decode(json.load(open(sys.argv[1]))["content"]).decode())' "$tmp/c.json" > "$d/content/$side/$q"
          fi
        done
        ac=$(sed -n 's/^  approved-commit: \([0-9a-f]\{40\}\)$/\1/p' "$d/content/head/$q" | head -1)
        if [[ -n $ac ]]; then
          fetch_compare "$d/approved/$ac.compare.json" "$mb...$ac" 2>/dev/null || rm -f "$d/approved/$ac.compare.json"
          [[ -f $passes/$name/$ac.jsonl ]] && cp "$passes/$name/$ac.jsonl" "$d/approved/$ac.jsonl" || true
        fi
      done <<< "$recs"
    fi
  fi
  out=$(python3 -I "$libexec/pr-merge-verdict.py" "$full" "$pr" "$head" "$d") || return 1
  verdict=${out##*$'\n'}
}

# Squash-merge pinned to the head, then say on the PR which passes it rested on.
do_merge() { # pr head
  local pr=$1 head=$2 res sha
  res=$(gh -X PUT -d "{\"merge_method\":\"squash\",\"sha\":\"$head\"}" "$base/pulls/$pr/merge") || return 1
  sha=$(printf '%s' "$res" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("sha",""))')
  echo "pr-merge: merged, commit ${sha:0:7}"
  python3 -I - "$tmp/d/ledger.jsonl" "$sha" "$head" > "$tmp/comment.txt" <<'PY' || true
import json, sys
path, sha, head = sys.argv[1:4]
print("Merged by the box's sweep (D-0042 rule 2) at head `%s` as `%s`, on these recorded passes:\n" % (head[:7], sha[:7]))
print("| role | relay | relay time | recorder |\n|---|---|---|---|")
for line in open(path):
    o = json.loads(line)
    print("| %s | `%s` | %s | %s |" % (o["role"], o["relay_ref"], o["relay_time"], o["recorder"]))
print("\nOne identity records all four, so a line is the recorder's word with the relay id it gave.")
PY
  python3 -I -c 'import json,sys; print(json.dumps({"body": open(sys.argv[1]).read()}))' "$tmp/comment.txt" > "$tmp/comment.json" 2>/dev/null &&
    gh -X POST -d @"$tmp/comment.json" "$base/issues/$pr/comments" > /dev/null || echo "pr-merge: the PR comment could not be posted (the merge stands)" >&2
}

halted() { [[ -e $passes/HALT || -L $passes/HALT ]]; }   # a flag that exists in any state, even unreadable, stops the sweep

case $action in
  lane)
    setup_repo "$full"
    lane=$(gh "$base/pulls/$pr" | python3 -I -c '
import json, re, sys
m = re.search(r"^Author-Lane:\s*([a-z0-9-]+)\s*$", json.load(sys.stdin).get("body") or "", re.M)
print(m.group(1) if m else "")') || exit 1
    [[ -n $lane ]] || { echo "pr-merge: no Author-Lane line" >&2; exit 1; }
    echo "$lane"
    exit 0
    ;;
  check | merge)
    if [[ $action == merge ]] && halted; then echo "pr-merge: the halt flag is set; nothing merged" >&2; exit 1; fi
    setup_repo "$full"
    evaluate "$pr" "$head" || { echo "pr-merge: a GitHub read failed; nothing decided" >&2; exit 1; }
    [[ $out == *$'\n'* ]] && echo "${out%$'\n'*}"
    echo "pr-merge: $full#$pr ${head:0:7}: $verdict"
    case $verdict in GREEN) ;; OWNER:*) exit 3 ;; *) exit 1 ;; esac
    [[ $action == merge ]] || exit 0
    halted && { echo "pr-merge: the halt flag is set; nothing merged" >&2; exit 1; }
    do_merge "$pr" "$head"
    ;;
  sweep)
    if halted; then echo "pr-merge sweep: the halt flag is set; nothing merged"; logger -t pr-merge "sweep skipped: halt flag set" 2>/dev/null || true; exit 0; fi
    for r in "${repos[@]}"; do
      setup_repo "$r" || { echo "pr-merge sweep: $r skipped (no token)"; continue; }
      gh "$base/pulls?state=open&per_page=100" > "$tmp/open.json" || { echo "pr-merge sweep: $r skipped (could not list PRs)"; continue; }
      while read -r n h; do
        [[ -f $passes/$name/$h.jsonl ]] || continue          # no ledger for this head: nothing to do, quietly
        evaluate "$n" "$h" || { echo "pr-merge sweep: $r#$n skipped (a GitHub read failed)"; continue; }
        [[ $out == *$'\n'* ]] && echo "${out%$'\n'*}"
        echo "pr-merge sweep: $r#$n ${h:0:7}: $verdict"
        [[ $verdict == GREEN ]] || continue
        halted && { echo "pr-merge sweep: halted before the merge of $r#$n"; exit 0; }
        do_merge "$n" "$h" || echo "pr-merge sweep: $r#$n merge call failed"
      done < <(python3 -I -c '
import json, sys
for p in json.load(open(sys.argv[1])): print(p["number"], p["head"]["sha"])' "$tmp/open.json")
    done
    ;;
esac
