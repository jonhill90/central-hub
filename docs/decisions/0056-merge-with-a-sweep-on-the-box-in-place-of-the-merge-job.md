---
id: D-0056
title: Merge with a sweep on the agent box, on a ledger of recorded passes, in place of the merge job
status: accepted
date: 2026-11-16
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0031, D-0042]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-11-16T03:24:45Z
  approved-commit: 20fb00acf45e6f48302e28021cb03bff4899fca7
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNYQdNsZFufy4SaM6a1D9P3u
  approval-names: "PR #372 at head 20fb00a (20fb00acf45e6f48302e28021cb03bff4899fca7), the content commit; the owner picked option 0, Accept the cleanup, on the card asking to accept the merge-rule cleanup in #372 at that head (the merge workflow goes; D-0056 is accepted), whose option text says D-0056 is then accepted and whose reason names D-0042, D-0056 and the runner hook as the files that need the owner's tap"
  check: "the builder read the owner's choice event (this approval-ref, 2026-11-16T03:24:45Z, option 0) and the card it answers (cmsg_01X43rfNYp4H1dL1V2dkfkwNVRGutKkRcm4nGmpJ9m9bur, posted 2026-11-16T03:07:09Z) by id in the project thread, and they match; the status commit differs from 20fb00a only in this record's status, date and accepted-evidence and its row in the decisions index (measured on 688d013 with git diff 20fb00a 688d013 over the files of the PR: this record's status, date and accepted-evidence, 10 added lines and 2 removed, and the index row; no other file of the PR differs; the head after this line's edit differs from 688d013 only in this line)"
  merged: not yet
revisit-when: a cloud session can start a GitHub workflow (the integration gets Actions write and the tailnet workflow gets an environment gate); the agents get GitHub identities of their own (D-0030) and GitHub can require their approvals; the ledger holds a line for a pass that was never given; or the owner says a merge was wrong
---

# Merge with a sweep on the agent box, on a ledger of recorded passes, in place of the merge job

## Context and Problem Statement

D-0042 rule 2 names a workflow, `merge.yml`, as the merge job. It is started by `workflow_dispatch` and has never run. Measured on 2026-11-14 at 12:56 UTC: a cloud session that asks GitHub's integration to start a workflow gets `403 Resource not accessible by integration` (evidence 0056, finding 1). So the owner's end goal, merges with no Mac step, cannot go through that job, and every squash-merge still runs through the orchestrator's Mac session.

This record **amends D-0042 rules 2 and 11**. It changes how a merge is started and checked. It does not change who approves: the agents' pass of rule 1 stays, and every step rule 6 keeps for the owner stays with him.

**Terms.** The *pass ledger* is a file the box keeps for each repository and head, one line per recorded pass. The *sweep* is a timer on the box that merges a pull request when its head's ledger is complete and its checks are green. The *halt flag* is a file that stops the sweep.

## Decision Drivers

- **The owner's delegation.** For the greenfield phase the owner has delegated PR approval to the reviewer and council passes (message of 2026-11-14, 07:42 to 07:44 UTC), keeping his own approval for the steps D-0042 rule 6 lists. The delegation is time-limited and is the owner's to change or withdraw. The owner asked whether he should remove his Mac from the work so that agents work from the box (message of 2026-11-14, 07:42:15 UTC).
- **No dispatch route.** A cloud session cannot start a workflow here (evidence, finding 1), and starting it by Actions write would let any session start the tailnet workflow, which has no environment gate (evidence, finding 4).
- **What a job can check, it checks.** The box can read GitHub's state itself: the head, a clean merge and every check.
- **What it can't check, it logs.** The box can't read the chat, so a pass is the recorder's word with the relay id it gave, shown on the PR after each merge.
- **Replaceable** (REQ-0011): undone by stopping the timer; the Mac lane still works.

## Considered Options

1. **A sweep on the box that reads a ledger of recorded passes.** The orchestrator records each pass over ssh; a timer merges a head whose ledger holds four roles.
2. **Keep `merge.yml` and give the sessions Actions write.** A session could start any box workflow, including the tailnet apply, which has no environment gate.
3. **Keep the Mac lane.** No Mac-free merge.

## Decision Outcome

Chosen option: **1**. It needs no workflow start and no new GitHub right, and the box checks everything it can.

### Rules

1. **The ledger.** `pass-record add <role> <repo> <pr> <head> <relay id> <relay time> <recorder>` appends a line to a file named by repository and head, so a new head starts empty and no pass carries over. The roles are `reviewer`, `council-a`, `council-b`, `council-c` and `owner-tap`. The wrapper checks every argument and writes nothing on a bad one.
2. **Who records.** The orchestrator records the passes the reviewer and the councils relay to it. The builder lane records only when the orchestrator can't reach the box, and never for a PR the builder wrote (the wrapper reads the PR's `Author-Lane` label and refuses a builder record when the label contains the word "builder" in any case (as in "agent box builder") or can't be read). Only the orchestrator may record `owner-tap` or run `resume`; any lane may run `halt`. One identity records everything on the box, so these are the recorder's word, not something the box can verify.
3. **The sweep.** A timer runs `pr-merge sweep` as the keys user. For each open PR it reads the head's ledger. Only a head with the four roles `reviewer`, `council-a`, `council-b` and `council-c` is considered. It then makes the checks rule 2 of D-0042 listed (open, not a draft, base `main`, the named head, a clean merge, every check on the head passed or skipped, at least one ran, fewer than 100 files) and squash-merges pinned to the head as the project's GitHub App. It never enables auto-merge and never passes `--admin`. A read that fails, a ledger that doesn't parse or a record whose content at the head can't be read stops the PR for that turn.
4. **Rule 11 files need the owner's tap.** The sweep merges the PRs that change the following only when the ledger also holds an `owner-tap` line for the head, whose relay id is the owner's card: D-0042 and D-0034; the runner hook; `pr-merge.sh`, `pr-merge-verdict.py` and `pass-record.sh`; the sweep's unit templates; and the role's `defaults/main.yml` unless the only blocks that differ are those of the five pinned-tool keys the box-apply limits list as free (`agent_box_tofu_version`, `agent_box_tofu_sha256`, `agent_box_kubectl_version`, `agent_box_kubectl_sha256`, `agent_box_tailscale_version`), each now a single `key: value` line whose value is a plain literal (a version of digits and dots, or 64 lowercase hex digits). The sweep reads the file by top-level blocks, the same way the box's self-apply does, so a line planted inside another key's list changes that key's block and needs the tap. A new, removed, repeated, quoted or re-spaced key, a Jinja or variable value, and unreadable content need the tap. Comments do not count. A record that supersedes D-0042 or D-0034, or whose body says it amends them, is caught the same way. The owner never clicks merge: the sweep merges after the tap.
5. **Status changes.** A PR that sets a record to `accepted`, `rejected` or `parked`, or a standard to `active`, merges only if the record says `approved-by: agents` (for an acceptance), its approved commit holds four passes of its own, and the PR's net change equals the approved commit's apart from the status, date and evidence lines and the index row.
6. **The stop.** `pass-record halt` sets a flag the sweep reads before everything and before each merge; while it exists the sweep merges nothing. The wrapper accepts `halt` from the recorders `orchestrator`, `builder`, `reviewer` and `council-a`, `council-b` and `council-c`, so a reviewer or a council can stop a merge. `pass-record resume` clears it. The wrapper accepts `resume` only from the recorder `orchestrator`, so a halt that the orchestrator relays from the owner is not undone by another lane's call, but any session can name itself the orchestrator. The owner's own stop is stopping the timer from the controller.
7. **Workflows that run on the box.** The runner hook lists each such workflow file with its sha256, fetches the file at the run's commit and refuses a job whose file differs or can't be fetched. A merged edit to a listed workflow does nothing on the box until a tapped install updates the list. CI checks the list against the files.
8. **What this changes in D-0042.** Rule 2: the merge job is the sweep, not `merge.yml`. The follow-up PR removes `merge.yml` and its retired entry in the runner hook and rewrites AGENTS.md rule 2; its owner-tapped status commit sets this record to accepted. Rule 11: the files that need the owner's tap are the list in rule 4 above. Rules 1, 3 to 10 stand.
9. **Installed by one tapped install.** The sweep, the wrappers and the hook reach the box only by a change to its limits, which keeps the owner's tap (D-0042 rule 6). One card names that install and this record's PR head.

### Consequences

- Good: merges need no Mac step and no session safety check.
- Good: the sweep merges only what passed, and shows its basis on the PR.
- Bad: **an agent can write a ledger line for a pass that was never given** (rule 2). Compensating controls: the PR's comment lists every line for the owner to check against the chat, the orchestrator lists every merge (D-0042 rule 9), the files that guard the merge itself need his tap, and his no wins (rule 8 of D-0042).
- Bad: any session can run `halt` under one of those recorder names, and the check on `resume` is only a name. The owner's stop is the timer.
- Bad: green checks come from the PR's own copy of the workflows. The reviewer reads those edits, and the sweep's output says when a PR changes files under `.github/`.

### Confirmation

- The tests in `.github/hosts-check/tests/` (verdict, pass-record, sweep, runner hook, sudo lines), each with a mutation that drops its guard.
- After the install, the first live proof: the sweep merges a docs-only test PR with four recorded passes and skips three, a new head, and a rule 11 PR with no `owner-tap` line. Not yet measured: `pass-record` over ssh from a session, the hook fetching a workflow by commit from the box, and the ruleset on `main` accepting the App's merge.

## Pros and Cons of the Options

### 2. Actions write for the sessions

- Good: GitHub's own run log.
- Bad: any session could start `lab-tailnet.yml`, which has no environment gate, so a tailnet apply would have no tap.

### 3. Keep the Mac lane

- Good: nothing new to trust.
- Bad: the Mac stays in every merge.

## More Information

- **Evidence:** [0056](../evidence/0056-merge-with-a-sweep-on-the-box-in-place-of-the-merge-job.md).
- **The code:** central-hub #354. Runbook: [Merge a pull request through the merge job](../runbooks/merge-a-pr-through-the-merge-job.md), now the sweep's page.
- **How this record is accepted:** as a change to rule 11 it needs the owner's tap on a card naming this PR and its head (D-0042 rule 11).
- **Exit path:** stop the timer on the box. Merges go back to the Mac lane. To remove the code too, a revert PR and an apply from the controller.
- Related records: D-0031, D-0034, D-0036, D-0042, D-0044.
