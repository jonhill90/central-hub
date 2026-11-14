---
title: Merge a pull request with the box's sweep
status: draft
kind: manual
trigger: each time a PR's head has CI green, the reviewer's clearance and the three council passes (D-0042)
runner: the orchestrator session records the passes over ssh; the box's timer merges
outcome: the PR is squash-merged at the head that was passed, and the PR carries a comment listing the recorded passes and the merge commit
needs: the box's limit install of the merge machinery (D-0042 rule 6, the owner's tap), the box's runner and App key (set-up-the-agent-box.md)
private-values: []
files: [hosts/ansible/roles/agent_box/files/pr-merge.sh, hosts/ansible/roles/agent_box/files/pr-merge-verdict.py, hosts/ansible/roles/agent_box/files/pass-record.sh, hosts/ansible/roles/agent_box/templates/pr-merge-sweep.service.j2, hosts/ansible/roles/agent_box/files/runner-job-started.sh]
last-tested: not yet run
superseded-by:
---

# Merge a pull request with the box's sweep

**Status:** draft. Written 2026-11-14 with the sweep. Until the owner's tapped install puts it on the box, merges go as they do today. D-0042 rule 2 still names `merge.yml`. The file stays on `main` for now, inert: the runner hook does not list it, so a run of it is refused. Its removal and the rule 2 amendment are PR 1b, which needs the owner's tap.

A cloud session cannot start a GitHub workflow here (the GitHub integration answers 403, measured 2026-11-14), so the merge does not run by dispatch. A timer on the agent box runs `pr-merge.sh sweep` as the keys user every few minutes. It merges a PR only when that PR's exact head holds four recorded passes: the reviewer's clearance and the passes of councils A, B and C. It is not GitHub's auto-merge, and it never passes `--admin`.

## Before you start

1. CI is green on the PR's head. The sweep checks it again itself: open, not a draft, base `main`, a clean merge, every check on the head completed and passed or skipped, at least one ran, fewer than 100 files.
2. You have read, in the project's chat, the reviewer's clearance of that exact head and a pass from each of councils A, B and C for that exact head. A pass for an older head does not count: the ledger is a file per head.

## Record the passes

The orchestrator records each pass over ssh, one call per role:

```text
pass-record add <role> jonhill90/<repo> <pr number> <40-character head> <relay message id> <relay time> orchestrator
```

- `<role>` is one of `reviewer`, `council-a`, `council-b`, `council-c`, `owner-tap`. `<relay message id>` is a `cmsg_` id and `<relay time>` an ISO time like `2026-11-14T13:00:00Z`. A wrong argument exits 2 and writes nothing.
- The builder lane records only when the orchestrator's session cannot reach the box, and never for a PR the builder wrote (the wrapper reads the PR body's `Author-Lane:` line and refuses a builder record when it says `builder` or cannot be read).
- One identity records all four roles, so a ledger line is the recorder's word and the relay id it gave, not four separate judgements. The sweep posts every line on the PR when it merges, for the owner to check.
- `pass-record show jonhill90/<repo> <head>` prints a head's ledger.

expect: `pass-record: <role> recorded for <repo>#<pr> <head7>`.

## What happens next

The timer's next turn reads the ledger. With four roles recorded and every check green, it squash-merges pinned to the head and comments on the PR. Anything else, it skips and tries again next turn. Read `journalctl -t pr-merge -u pr-merge-sweep` on the box for the reasons, or run the read-only check yourself:

```text
pr-merge check jonhill90/<repo> <pr number> <40-character head>
```

- `GREEN`: the sweep will merge it at its next turn.
- `NOT GREEN: ...`: every reason is printed (a missing role, a failed check, a moved head, a ledger that does not parse). Fix it or wait; a new head needs its own four passes.
- `OWNER: rule 11 PR ... needs an owner-tap line`: the PR changes a file that guards the merge itself (D-0042 rules 6 and 11, D-0034, the runner hook, `pr-merge.sh`, `pr-merge-verdict.py`, `pass-record.sh`, the sweep's unit files), or a record that supersedes or amends D-0042 or D-0034. The owner's decision card names the step and the commit; the orchestrator records the tap as role `owner-tap` with the card's message id, and the sweep merges it. Only the orchestrator may record that role (the wrapper refuses any other recorder), and the line is its word for a card tap the box cannot see. The owner never clicks merge.
- A changed record or standard whose content at the head cannot be read is never green (only a PR that removes the file may skip it), and a failed read of it stops the whole evaluation, so a 5xx or rate limit skips the PR until the next turn.
- A status change to `accepted`, `rejected`, `parked` or `active` is checked too (D-0042 rule 3): `approved-by: agents` for an acceptance, an `approved-commit` with four passes of its own, and the PR's net change equal to the approved commit's apart from the status, date and `accepted-evidence` lines and the index row. If it does not fit, reshape the PR (acceptance as its own PR on top of the passed proposal head) and record passes again.

## Stop the sweep (D-0042 rule 8)

```text
pass-record halt <relay message id>
pass-record resume <relay message id>
```

While the flag exists, the sweep merges nothing, including a merge it was about to make. Any session can run both, so the flag stops a mistake, not a determined agent; the owner's own stop is `systemctl stop pr-merge-sweep.timer` on the box from the controller.

## What the green checks do not prove

A PR that edits the workflows or scripts that make its own checks reports green on its own copy. The sweep does not guard those edits; the reviewer's clearance reads them. The sweep's output says `NOTE: this PR edits N files under .github/` with their names.

## Workflows that run on the box

The runner's job-started hook (`runner-job-started.sh`) lists each workflow file whose jobs run on the box (`lab-redeploy-dev.yml`, `lab-tailnet.yml`) with its sha256, fetches the file at the run's commit from the public repository and refuses a job whose file has another hash or cannot be fetched. A merged edit to one of these does nothing on the box until a tapped install updates the list. CI runs `.github/hosts-check/check-hook-allowlist.py`, so a PR that edits a box workflow without updating the list, or adds a `uses:` step to one, fails.

## Not measured yet

- That a session's safety check lets `pass-record add` through over ssh (only `rebuild.sh` and `pr-merge.sh check` were run).
- That the hook can fetch a workflow by commit and the box can reach `raw.githubusercontent.com`; the hook fails closed.
- Whether the ruleset on `main` accepts the App's squash-merge.
- The installed copies of the scripts, until the owner's install.
