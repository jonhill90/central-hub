#!/usr/bin/env bash
# pr-merge.sh sweep, several open PRs: it merges every green one in one run, oldest number first (GitHub lists the newest first),
# and a PR that GitHub reports as mergeable=null right after another merge is asked about again until it answers.
set -uo pipefail
files=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
openssl genrsa -out "$t/github-app.pem" 2048 2>/dev/null || { echo "FAIL: openssl"; exit 1; }
mkdir -p "$t/work/state" "$t/bin" "$t/libexec" "$t/work/passes/central-hub"
echo '{"github_app_id": 1}' > "$t/work/ci-runner.json"
cp "$files/pr-merge-verdict.py" "$t/libexec/"
sed "s|^keys=/etc/agent-keys|keys=$t|; s|^work=/var/lib/agent-box|work=$t/work|; s|^libexec=/usr/local/libexec/agent-box|libexec=$t/libexec|; s|^export HOME=\$work PATH=.*|export HOME=\$work PATH=$t/bin:/usr/local/bin:/usr/bin:/bin|" "$files/pr-merge.sh" > "$t/pr-merge.sh"
H5=$(printf '5%.0s' $(seq 40)); H7=$(printf '7%.0s' $(seq 40)); H9=$(printf '9%.0s' $(seq 40))
for p in "5 $H5" "7 $H7" "9 $H9"; do set -- $p
  printf '{"role":"reviewer","repo":"jonhill90/central-hub","pr":%s,"head":"%s","relay_ref":"cmsg_ABCDEFGHIJ","relay_time":"2026-11-14T13:00:00Z","recorder":"orchestrator","box_time":"2026-11-14T13:00:01Z"}\n' "$1" "$2" > "$t/work/passes/central-hub/$2.jsonl"
done
echo 0 > "$t/nullleft7"   # PR 7 answers mergeable=null this many times before it answers true
cat > "$t/bin/curl" <<'F'
#!/bin/bash
cat > /dev/null
method=GET; for a in "$@"; do last=$a; done
prev=; for a in "$@"; do [[ $prev == -X ]] && method=$a; prev=$a; done
echo "$method $last" >> "$FAKE_CALLS"
reply() { printf '%s\n%s' "$1" "${2:-200}"; exit 0; }
pr() { sed -E 's|.*/pulls/([0-9]+).*|\1|;s|.*/issues/([0-9]+).*|\1|' <<< "$last"; }
case "$method $last" in
  *"/installation") reply '{"id":1}' ;;
  "POST "*access_tokens) reply '{"token":"T"}' 201 ;;
  "GET https://api.github.com/repos/jonhill90/central-hub/pulls?state=open"*)
    reply "[{\"number\":9,\"head\":{\"sha\":\"$H9\"}},{\"number\":7,\"head\":{\"sha\":\"$H7\"}},{\"number\":5,\"head\":{\"sha\":\"$H5\"}}]" ;;
  "GET "*"/pulls?state=open"*) reply '[]' ;;
  "GET "*"/pulls/"[0-9]*"/files"*) reply '[{"filename":"docs/f.md"}]' ;;
  "GET "*"/pulls/"[0-9]*)
    n=$(pr); eval "h=\$H$n"
    if [[ $n == 7 && $(cat "$NULLLEFT") -gt 0 ]]; then echo $(( $(cat "$NULLLEFT") - 1 )) > "$NULLLEFT"
      reply "{\"state\":\"open\",\"draft\":false,\"base\":{\"ref\":\"main\",\"sha\":\"c\"},\"head\":{\"sha\":\"$h\"},\"mergeable\":null,\"mergeable_state\":\"unknown\",\"body\":\"Author-Lane: x\"}"; fi
    reply "{\"state\":\"open\",\"draft\":false,\"base\":{\"ref\":\"main\",\"sha\":\"c\"},\"head\":{\"sha\":\"$h\"},\"mergeable\":true,\"mergeable_state\":\"clean\",\"body\":\"Author-Lane: x\"}" ;;
  "GET "*"/check-runs"*) reply '{"total_count":1,"check_runs":[{"name":"docs","status":"completed","conclusion":"success"}]}' ;;
  "GET "*"/status") reply '{}' ;;
  "PUT "*"/merge") reply '{"sha":"deadbeefdeadbeef"}' ;;
  "POST "*"/comments") reply '{}' 201 ;;
esac
reply '{"message":"unexpected"}' 404
F
chmod +x "$t/bin/curl" "$t/pr-merge.sh"
export H5 H7 H9 NULLLEFT="$t/nullleft7" SWEEP_RECHECK_SECONDS=0
check() { if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
run() { : > "$t/calls"; FAKE_CALLS="$t/calls" bash "$t/pr-merge.sh" sweep 2>&1; }
out=$(run)
order=$(grep '^PUT .*merge' "$t/calls" | sed -E 's|.*/pulls/([0-9]+)/merge|\1|' | tr '\n' ' ')
check "every green PR merges in one run, oldest first" "$order" "5 7 9 "
echo 2 > "$t/nullleft7"; out=$(run)
order=$(grep '^PUT .*merge' "$t/calls" | sed -E 's|.*/pulls/([0-9]+)/merge|\1|' | tr '\n' ' ')
check "a mergeable=null answer is asked again, then the PR merges" "$order" "5 7 9 "
echo 9 > "$t/nullleft7"; out=$(run)
order=$(grep '^PUT .*merge' "$t/calls" | sed -E 's|.*/pulls/([0-9]+)/merge|\1|' | tr '\n' ' ')
check "an answer that stays null is asked about 4 times, then skipped; the others merge" "$order" "5 9 "
check "the skipped PR is reported not green" "$out" "mergeable=None"
exit "$fail"
