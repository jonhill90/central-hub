#!/usr/bin/env bash
# pr-merge.sh sweep (D-0042 rule 2, rule 8) against a fake GitHub: it merges only a head whose ledger holds four passes, never
# while the halt flag is set, skips on a failed read, merges pinned to the head, posts the ledger as a PR comment, and never
# calls auto-merge. A copy of the script runs with its folders in a temp folder and a fake curl first on PATH.
set -uo pipefail
files=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
openssl genrsa -out "$t/github-app.pem" 2048 2>/dev/null || { echo "FAIL: openssl"; exit 1; }
mkdir -p "$t/work/state" "$t/bin" "$t/libexec"
echo '{"github_app_id": 1}' > "$t/work/ci-runner.json"
cp "$files/pr-merge-verdict.py" "$t/libexec/"
sed "s|^keys=/etc/agent-keys|keys=$t|; s|^work=/var/lib/agent-box|work=$t/work|; s|^libexec=/usr/local/libexec/agent-box|libexec=$t/libexec|; s|^export HOME=\$work PATH=.*|export HOME=\$work PATH=$t/bin:/usr/local/bin:/usr/bin:/bin|" "$files/pr-merge.sh" > "$t/pr-merge.sh"
H=$(printf 'a%.0s' $(seq 40))
cat > "$t/bin/curl" <<'F'
#!/bin/bash
cat > /dev/null
method=GET; for a in "$@"; do last=$a; done
prev=; for a in "$@"; do [[ $prev == -X ]] && method=$a; prev=$a; done
echo "$method $last" >> "$FAKE_CALLS"
reply() { printf '%s\n%s' "$1" "${2:-200}"; exit 0; }
case "$method $last" in
  *"/installation") reply '{"id":1}' ;;
  "POST "*access_tokens) reply '{"token":"T"}' 201 ;;
  "GET https://api.github.com/repos/jonhill90/central-hub/pulls?state=open"*) reply "[{\"number\":7,\"head\":{\"sha\":\"$FAKE_HEAD\"}}]" ;;
  "GET "*"/pulls?state=open"*) reply '[]' ;;
  "GET "*"/pulls/7") reply "{\"state\":\"open\",\"draft\":false,\"base\":{\"ref\":\"main\",\"sha\":\"c\"},\"head\":{\"sha\":\"$FAKE_HEAD\"},\"mergeable\":true,\"mergeable_state\":\"clean\",\"body\":\"Author-Lane: plan\"}" ;;
  "GET "*"/pulls/7/files"*) reply '[{"filename":"docs/runbooks/x.md"}]' ;;
  "GET "*"/check-runs"*) [[ -n ${FAKE_CHECKS_FAIL:-} ]] && reply '{"message":"boom"}' 500; reply '{"total_count":1,"check_runs":[{"name":"docs","status":"completed","conclusion":"success"}]}' ;;
  "GET "*"/status") reply '{}' ;;
  "PUT "*"/pulls/7/merge") reply '{"sha":"deadbeefdeadbeef"}' ;;
  "POST "*"/issues/7/comments") reply '{}' 201 ;;
esac
reply '{"message":"unexpected"}' 404
F
chmod +x "$t/bin/curl"
roles=(reviewer council-a council-b council-c)
ledger() { # roles...   (one file per head, in the passes folder)
  mkdir -p "$t/work/passes/central-hub"; : > "$t/work/passes/central-hub/$H.jsonl"
  for r in "$@"; do printf '{"role":"%s","repo":"jonhill90/central-hub","pr":7,"head":"%s","relay_ref":"cmsg_ABCDEFGHIJ","relay_time":"2026-11-14T13:00:00Z","recorder":"orchestrator","box_time":"2026-11-14T13:00:01Z"}\n' "$r" "$H" >> "$t/work/passes/central-hub/$H.jsonl"; done
}
run() { # script args...
  local s=$1; shift; : > "$t/calls"
  FAKE_CALLS="$t/calls" FAKE_HEAD=$H bash "$s" "$@" 2>&1; echo "rc=$?"
}
merged() { grep -q "^PUT .*pulls/7/merge" "$t/calls"; }
check() { if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
yes_() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
no_() { if eval "$2"; then echo "FAIL $1"; fail=1; else echo "ok   $1"; fi; }
rm -rf "$t/work/passes"; out=$(run "$t/pr-merge.sh" sweep); check "no ledger: the sweep exits 0 quietly" "$out" "rc=0"; no_ "no ledger: nothing merged" merged
no_ "no ledger: no check-runs read for the PR" "grep -q check-runs $t/calls"
ledger reviewer council-a council-b; out=$(run "$t/pr-merge.sh" sweep); check "three passes: not green" "$out" "ledger lacks council-c"; no_ "three passes: nothing merged" merged
ledger "${roles[@]}"; touch "$t/work/passes/HALT"; out=$(run "$t/pr-merge.sh" sweep); check "halt flag: the sweep says it is halted" "$out" "halt flag is set"; no_ "halt flag: nothing merged even with four passes" merged
no_ "halt flag: no GitHub call at all" "test -s $t/calls"
out=$(run "$t/pr-merge.sh" merge jonhill90/central-hub 7 "$H"); check "halt flag: pr-merge merge refuses too" "$out" "halt flag is set"; no_ "halt flag: merge did not call GitHub's merge" merged
# the mutation: no halt check, the same PR merges under the flag
sed 's|^halted() {.*|halted() { return 1; }|' "$t/pr-merge.sh" > "$t/mut.sh"; run "$t/mut.sh" sweep > /dev/null
yes_ "mutation: without the halt check the sweep merges under the flag" merged
rm -f "$t/work/passes/HALT"; ledger "${roles[@]}"; out=$(run "$t/pr-merge.sh" sweep)
check "four passes: GREEN" "$out" "${H:0:7}: GREEN"; yes_ "four passes: the squash merge is called" merged
check "the merge is pinned to the head and squashed" "$(cat "$t/calls")" "PUT https://api.github.com/repos/jonhill90/central-hub/pulls/7/merge"
yes_ "the ledger is posted as a PR comment" "grep -q '^POST .*issues/7/comments' $t/calls"
no_ "auto-merge is never called" "grep -qi 'auto' $t/calls"
ledger "${roles[@]}"; out=$(FAKE_CHECKS_FAIL=1 run "$t/pr-merge.sh" sweep); check "a failed GitHub read skips the PR" "$out" "skipped (a GitHub read failed)"
export FAKE_CHECKS_FAIL=; ledger "${roles[@]}"
out=$(run "$t/pr-merge.sh" check jonhill90/central-hub 7 "$H"); check "check prints the verdict and merges nothing" "$out" "GREEN"; no_ "check never calls merge" merged
out=$(run "$t/pr-merge.sh" lane jonhill90/central-hub 7); check "lane prints the Author-Lane label" "$out" "plan"
out=$(run "$t/pr-merge.sh" merge jonhill90/elsewhere 7 "$H"); check "another repository exits 2" "$out" "rc=2"
out=$(run "$t/pr-merge.sh" sweep extra); check "sweep takes no arguments" "$out" "rc=2"
exit $fail
