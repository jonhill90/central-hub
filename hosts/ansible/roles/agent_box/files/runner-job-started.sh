#!/bin/bash
# /usr/local/libexec/agent-box/runner-job-started.sh: the Actions runner's job-started hook
# (ACTIONS_RUNNER_HOOK_JOB_STARTED in the runner's .env). The repository is public, so any workflow on any
# branch can ask for this runner by label; this hook refuses every job except the dev redeploy workflow
# as it is on main, started by hand. A non-zero exit fails the job before any step runs.
# Installed by the agent_box role, root-owned. Names no private value.
set -euo pipefail

want_ref="jonhill90/central-hub/.github/workflows/lab-redeploy-dev.yml@refs/heads/main"
if [[ ${GITHUB_WORKFLOW_REF:-} != "$want_ref" || ${GITHUB_EVENT_NAME:-} != workflow_dispatch ]]; then
  echo "runner-job-started: refused: this runner only runs lab-redeploy-dev.yml on main, started by hand (got ref '${GITHUB_WORKFLOW_REF:-}', event '${GITHUB_EVENT_NAME:-}')" >&2
  exit 1
fi
