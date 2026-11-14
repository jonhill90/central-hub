---
title: Merge a pull request through the merge job
status: draft
kind: manual
trigger: each time a PR's head has CI green, the reviewer's clearance and the council's three passes (D-0042)
runner: an agent session with the repository's GitHub tools, or the orchestrator's session if a session's safety check refuses the start
outcome: the PR is squash-merged at the head that was passed, and the run summary names the PR, the head, the merge commit and the two message ids
needs: D-0042 accepted, `.github/workflows/merge.yml` on `main`, the agent box's runner registered, and the box's role applied from the Mac once with D-0042 rule 4's changes
private-values: []
files: [.github/workflows/merge.yml, hosts/ansible/roles/agent_box/files/runner-job-started.sh, hosts/ansible/roles/agent_box/files/pr-merge.sh, hosts/ansible/roles/agent_box/defaults/main.yml]
last-tested: not yet run
superseded-by:
---

# Merge a pull request through the merge job

**Status:** draft. Written 2026-11-14 with the job; the job has not run yet, because a `workflow_dispatch` workflow runs only once it is on `main`.

The job squash-merges one PR that the reviewer and the council passed (D-0042 rule 2). It runs on the agent box's runner and hands the merge to the box's `pr-merge` wrapper, which checks the head, a clean merge and every check itself, then merges as the project's GitHub App. The workflow's own token is read-only.

## Before you start

1. CI is green on the PR's head: every check completed and passed or was skipped.
2. You have read, in the project's chat:
   - the reviewer thread's clearance of that exact head;
   - the orchestrator's message that records a pass from each of council A, B and C for that exact head.
3. The PR is not one of D-0042 rule 6's steps that waits on a tap. A merge never is; the apply or the act after it may be.

## Start the job

Start workflow `merge.yml` on ref `main` with four inputs:

| Input | Value |
|---|---|
| `pr` | the PR number |
| `head_sha` | the full 40-character head that was passed |
| `review_ref` | the reviewer's clearance message id, `cmsg_...` |
| `council_ref` | the orchestrator's message id that records the three passes, `cmsg_...` |

From a cloud session, use the GitHub tools' "run workflow" call (`actions_run_trigger` with `run_workflow`, workflow `merge.yml`, ref `main`).

## Read the result

- **Success:** the run summary lists the PR, the head, the wrapper's verdict with the merge commit, and the two message ids. Tell the orchestrator the merge commit; it lists the merge in its next report to the owner (D-0042 rule 9).
- **`NOT GREEN: ...`:** the wrapper printed every reason. Fix the PR or wait for CI, get the new head passed, and start again. If the head moved after the check, GitHub refuses the merge; the new head needs its own pass.
- **`OWNER: touches ...`:** the box still has the `pr-merge` from before D-0042 rule 4's Mac apply. Tell the orchestrator.
- **Input refused (exit 2):** an input had the wrong shape. Nothing was read or merged.

## If it fails

- **The session's safety check refuses the start:** don't retry it there. Ask the orchestrator's session to start it, and add the refusal to this page.
- **The job waits for a runner, or the hook refuses it:** the box's runner is offline or not registered, or the job was started from another branch or event. Start it on `main` by `workflow_dispatch` only; see [Set up the agent box](set-up-the-agent-box.md) for the runner.
