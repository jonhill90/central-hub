---
record: D-0056
batch: RB-0232 (2026-11-14), the builder lane's reads and measurements for the merge-off-Mac design, 2026-11-14 12:46 to 13:10 UTC
researched: 2026-11-14
method: this repository's merge.yml, pr-merge.sh, the runner hook, the sudo list and D-0042 read at main; one workflow-start call to GitHub's integration; ssh calls to the box's wrappers from a cloud session; the repository's own tests
checks: Councils A, B and C passed design v5 and the code (central-hub #354); the reviewer cleared it
---

# Evidence for D-0056: merge with a sweep on the box

This file summarises what was read and measured for D-0056. Nothing in it changed the box.

## Question

Can a cloud session merge a passed PR with no Mac step, and what is the smallest change to the merge job that allows it?

## Findings

1. **A cloud session can't start a workflow here.** The GitHub tool's `run_workflow` on `lab-redeploy-dev.yml` (ref `main`, a read-only input) returned `403 Resource not accessible by integration` [measured: 2026-11-14 12:56 UTC]. So `merge.yml`, which runs only by `workflow_dispatch`, can't be started by a session.
2. **The merge job has never run.** GitHub's API lists 0 runs for `merge.yml`, `lab-redeploy-dev.yml` and `lab-tailnet.yml` [measured: Actions API, 2026-11-14 ~12:50 UTC].
3. **A session's ssh path to a keys-run wrapper was not refused today.** From a cloud session over the tailnet, `rebuild.sh log` and `pr-merge.sh check` ran and printed their output [measured: 2026-11-14 12:58 UTC]. This does not show a refusal can never come, and `pass-record add` was not run, because it didn't exist yet.
4. **Why not Actions write.** `lab-tailnet.yml` runs on the box with no environment gate [source: `.github/workflows/lab-tailnet.yml` lines 9 and 31-32], so a session that could start workflows could start a tailnet apply that no tap guards.
5. **What the checks don't cover.** `docs.yml`, `hosts.yml`, `foss.yml`, `gate.yml` and the scripts under `.github/` run on `pull_request` with the PR's own copy; only `fabrication.yml` takes its verifier from `main` [source: the workflow files]. The sweep reports edits under `.github/` and leaves the judgement to the reviewer.
6. **The code.** Tests for the verdict, the ledger, the sweep, the hook and the sudo lines pass, each with mutations that drop the guard [measured: central-hub #354 at b434cb7].

## Checks (the owner's rule of 2026-11-14 07:24 UTC)

| Claim | Web search | Issues and code | Docs index | Hands-on |
|---|---|---|---|---|
| A session can't start a workflow here | not applicable: this integration's own answer | the 403 above | GitHub's REST docs for workflow dispatch | the call in finding 1 |
| The ssh path carries a keys-run wrapper | not applicable | none | none | the calls in finding 3 |

## Not measured

- `pass-record add` over ssh from a session; the hook fetching a workflow by commit from the box and the box reaching its file host; the ruleset on `main` accepting the App's squash-merge.
