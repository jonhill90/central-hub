---
record: D-0042
batch: RB-0215 (2026-11-14), the drafting agent's reads and measurements for D-0042, between 07:40 and 08:00 UTC
researched: 2026-11-14
method: GitHub's documentation for the merge endpoint, rulesets and the GITHUB_TOKEN read; this repository's workflows, wrappers and recent merge commits read; web searches on GitHub Actions merges and signed squash merges; the four checks of the owner's rule of 2026-11-14 07:24 UTC for each claim that something works or doesn't
checks: none independent yet; the reviewer thread and the council check it with the PR
---

# Evidence for D-0042: the reviewer and the council approve in the owner's place

This file summarises what was read and measured for D-0042. Nothing in it was run against the lab, and the merge job has not run yet.

## Question

Can an agent's GitHub tools merge a PR without the owner's typed line, through a job whose own checks hold, under `main`'s protection? What does the change cost?

## Findings

1. **Why the owner types merge lines today.** The box's `pr-merge` wrapper merges as the project's GitHub App with an installation token, through GitHub's merge endpoint, pinned to the head [1]. It merged central-hub #280 on 2026-11-14. The box session's safety check refused it for other PRs that day. The Mac session's guard counts only the owner's typed words [measured, from the project's chat].
2. **What a cloud session can call.** Its GitHub tools include starting a `workflow_dispatch` workflow and have no merge call [measured: the session's tool list on 2026-11-14].
3. **The merge endpoint.** `PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge` takes `merge_method` (`merge`, `squash` or `rebase`) and `sha`, the "SHA that pull request head must match to allow merge". It answers 405 when the merge can't be done and 409 when the head did not match [2].
4. **Merges by the `GITHUB_TOKEN`.** "Events triggered by the `GITHUB_TOKEN` will not create a new workflow run", apart from `workflow_dispatch`, `repository_dispatch` and some pull request events [3]. No workflow in this repository runs on a push to `main`: `docs`, `foss`, `gate` and `hosts` run on pull requests (and `docs` weekly), and `lab-redeploy-dev` by hand [measured: `.github/workflows/`].
5. **Where a `workflow_dispatch` workflow can run.** "This event will only trigger a workflow run if the workflow file exists on the default branch" [4]. So the job can't be tried before this PR merges.
6. **Signatures and linear history.** GitHub's ruleset page says a linear-history rule needs a squash or rebase merge, and that "unsigned commits on the head branch can block a squash merge, even though GitHub would sign the final squash commit" [5]. The last 15 commits on `main` each carry a GPG signature and GitHub as committer, #280's App merge among them [measured: `git cat-file` on `main` at b1c5f6d].
7. **The job's own checks.** `.github/merge/verdict.py` decides the merge from the API's answers. Its 14 cases pass: green; a moved head; a draft; a closed PR; another base; a conflict; mergeable not yet known; a failed, a pending and a neutral check; no checks; more check runs than read; a red commit status; 100 files [measured: `.github/hosts-check/tests/test_merge_verdict.sh`]. actionlint passes on the workflow [measured].

## Checks (the owner's rule of 2026-11-14 07:24 UTC)

| Claim | Web search | Issues and code | Docs index | Hands-on |
|---|---|---|---|---|
| A `GITHUB_TOKEN` with contents and pull requests write can squash-merge a PR on `main` | Two searches found third-party guides and actions that merge PRs from workflows with the `GITHUB_TOKEN`; seen only in the result list, not opened | A search of GitHub's code outside this project's repositories was refused in this session; this repository's `pr-merge.sh` makes the same call with another installation token [1] | The merge endpoint [2] and the token's page [6] | Not done: the job can only run once it is on `main` (finding 5). The same call with the App's installation token merged #280, and its squash commit is signed by GitHub (finding 6) |
| `main`'s ruleset lets that merge through | The ruleset page [5] | Not searched | [5] | Not done: this session has no tool that reads a ruleset. D-0031's measurement of 2026-11-08 says it requires no reviews; D-0030 says it has no bypass actor |
| A cloud session may start the job | Not searched | Not searched | Not read | Not done until the job exists; the Confirmation tests it |

## How the decision used it

- **Rule 2.** Findings 2, 3 and 7 are why the merge is a `workflow_dispatch` job that checks the head itself and merges pinned to it.
- **The neutral consequence.** Finding 4 is why merges by the job lose no workflow on `main`.
- **The Confirmation.** Finding 5 and the checks table are why the first merge through the job is the test.

## Limits

- Nothing was run against the lab, and the merge job has not run.
- The ruleset's current contents were not read.
- RB-0215 had no independent research check; the reviewer thread and the council check this file.

## References

1. `hosts/ansible/roles/agent_box/files/pr-merge.sh`
2. GitHub REST API, "Merge a pull request": <https://docs.github.com/en/rest/pulls/pulls#merge-a-pull-request>
3. GitHub Docs, "Triggering a workflow", the `GITHUB_TOKEN` section: <https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow>
4. GitHub Docs, "Events that trigger workflows", `workflow_dispatch`: <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows>
5. GitHub Docs, "Available rules for rulesets": <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>
6. GitHub Docs, "Use GITHUB_TOKEN for authentication in workflows": <https://docs.github.com/en/actions/tutorials/authenticate-with-github_token>
