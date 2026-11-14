---
title: Merge a pull request through the merge job
status: draft
kind: manual
trigger: each time a PR's head has CI green, the reviewer's clearance and the council's three passes (D-0042)
runner: an agent session with the repository's GitHub tools, or the orchestrator's session if a session's safety check refuses the start
outcome: the PR is squash-merged at the head that was passed, and the run summary names the PR, the head, the merge commit and the two message ids
needs: D-0042 accepted and `.github/workflows/merge.yml` on `main`
private-values: []
files: [.github/workflows/merge.yml, .github/merge/verdict.py, .github/hosts-check/tests/test_merge_verdict.sh]
last-tested: not yet run
superseded-by:
---

# Merge a pull request through the merge job

**Status:** draft. Written 2026-11-14 with the job; the job has not run yet, because a `workflow_dispatch` workflow runs only once it is on `main`.

The job squash-merges one PR that the reviewer and the council passed, after checking the rest itself (D-0042 rule 2). It runs on GitHub's own runner with that run's `GITHUB_TOKEN`, so no lab key and no box is involved.

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

- **Success:** the run summary lists the PR, the head, the merge commit and the two message ids. Tell the orchestrator the merge commit; it lists the merge in its next report to the owner (D-0042 rule 9).
- **`NOT GREEN: ...`:** the job printed every reason. Fix the PR or wait for CI, get the new head passed, and start again.
- **409 from the merge step:** the head moved after the check. The new head needs its own pass.
- **Input refused (exit 2):** an input had the wrong shape. Nothing was read or merged.

## If it fails

- **The session's safety check refuses the start:** don't retry it there. Ask the orchestrator's session to start it, and add the refusal to this page.
- **GitHub refuses the merge (403 or 405):** read the run log. If `main`'s ruleset blocks merges made with the `GITHUB_TOKEN`, merges fall back to the box's `pr-merge` wrapper ([Set up the agent box](set-up-the-agent-box.md)), and this page records why.
