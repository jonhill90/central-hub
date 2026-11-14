#!/bin/bash
# /usr/local/libexec/agent-box/runner-job-started.sh: the Actions runner's job-started hook
# (ACTIONS_RUNNER_HOOK_JOB_STARTED in the runner's .env). The repository is public, so any workflow on any
# branch can ask for this runner by label; this hook refuses every job except the listed workflows
# (the dev redeploy workflow and the tailnet pipeline job) as they are on main, started by hand. A non-zero exit fails the job before any step runs.
# Installed by the agent_box role, root-owned. Names no private value.
set -euo pipefail

# The list of workflows that may run here changes only by a reviewed PR (D-0041 rule 11).
allowed=(
  "jonhill90/central-hub/.github/workflows/lab-redeploy-dev.yml@refs/heads/main"
  "jonhill90/central-hub/.github/workflows/lab-tailnet.yml@refs/heads/main"
)
ok=false
for want_ref in "${allowed[@]}"; do
  [[ ${GITHUB_WORKFLOW_REF:-} == "$want_ref" ]] && ok=true
done
if [[ $ok != true || ${GITHUB_EVENT_NAME:-} != workflow_dispatch ]]; then
  echo "runner-job-started: refused: this runner only runs the listed workflows on main, started by hand (got ref '${GITHUB_WORKFLOW_REF:-}', event '${GITHUB_EVENT_NAME:-}')" >&2
  exit 1
fi
