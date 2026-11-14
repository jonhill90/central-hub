#!/bin/bash
# /usr/local/libexec/agent-box/runner-job-started.sh: the Actions runner's job-started hook
# (ACTIONS_RUNNER_HOOK_JOB_STARTED in the runner's .env). The repository is public, so any workflow on any
# branch can ask for this runner by label; this hook refuses every job except the listed workflow files (the dev
# redeploy workflow and the tailnet pipeline job), as they are on main, started by hand, and byte for byte the
# file whose sha256 is listed below. It fetches the file at the run's commit (GITHUB_WORKFLOW_SHA) from the public
# repository and refuses if it cannot (fail closed). A merged edit to a listed workflow therefore does nothing on
# the box until a tapped install updates this list. The merge job is not here: the box's sweep merges (D-0042 rule 2).
# A non-zero exit fails the job before any step runs. Installed by the agent_box role, root-owned. Names no private value.
set -euo pipefail

# One entry per workflow file whose jobs run here: "<sha256> <path in the repository>". A CI check
# (.github/hosts-check/check-hook-allowlist.py) recomputes these, so a PR that edits a listed file without
# updating this list fails; the list changes only by a reviewed PR (D-0041 rule 11) and acts after a tapped install.
allowed=(
  "45ba4675fa9d39e5953690e5861f4f74fd513eb504771b66f80d704c1bc79907 .github/workflows/lab-redeploy-dev.yml"
  "b61c975faa57620a94e4e2f4a178f30f33094543349c223b1f7c8bf29dfd378d .github/workflows/lab-tailnet.yml"
)
repo=jonhill90/central-hub
# GitHub's raw file host for this public repository's own workflow files (not a downloaded component).
host=raw.githubusercontent.com

refuse() { echo "runner-job-started: refused: $*" >&2; exit 1; }

[[ ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]] || refuse "this runner only runs the listed workflows on main, started by hand (event '${GITHUB_EVENT_NAME:-}')"
ref=${GITHUB_WORKFLOW_REF:-}
[[ $ref == "$repo/"*"@refs/heads/main" ]] || refuse "not a workflow of $repo on main (got '$ref')"
path=${ref#"$repo/"}; path=${path%@refs/heads/main}
sha=${GITHUB_WORKFLOW_SHA:-}
[[ $sha =~ ^[0-9a-f]{40}$ ]] || refuse "the run's commit is missing or malformed"
want=
for entry in "${allowed[@]}"; do
  [[ ${entry#* } == "$path" ]] && want=${entry%% *}
done
[[ -n $want ]] || refuse "$path is not a listed workflow"
got=$(curl -fsS --max-time 20 "https://$host/$repo/$sha/$path" | sha256sum | cut -d' ' -f1) || refuse "could not fetch $path at ${sha:0:7}"
[[ $got == "$want" ]] || refuse "$path at ${sha:0:7} is not the file whose hash is listed"
