---
id: D-0042
title: Let the reviewer and the council approve every reversible change in the owner's place
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0041]
supersedes: []
superseded-by:
revisit-when: the lab comes to hold personal data or anything of value; a change approved under this record has to be undone after it harmed the lab, a cloud account or the repository; the owner says a pass was wrong; the agents get a GitHub identity of their own (D-0030) and GitHub can require an approval itself; or a cluster other than c1 reads the repository
---

# Let the reviewer and the council approve every reversible change in the owner's place

## Context and Problem Statement

Today the owner types or taps a go for almost every step:

- a merge of a PR that accepts a record or a standard, or loosens the rules (AGENTS.md rules 1 and 2, D-0031 rules 3 and 4, D-0034);
- a production run of a lab layer (D-0035 rule 3) and every production or cloud apply (D-0041 rule 6);
- a change to the agent box's limits, applied from the Mac (D-0036 rule 6).

In practice he also types merge lines for ordinary green PRs. D-0031 already lets agents merge those, but two tools stop them: the box session's safety check refuses the `pr-merge` wrapper unpredictably, and the Mac session's guard counts only words the owner typed. The cloud sessions' GitHub tools have no merge call, but they can start a `workflow_dispatch` workflow (evidence, findings 1 and 2).

On 2026-11-14 the owner asked, more than once, to stop typing and tapping approvals for the lab:

- at 06:31:02 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNNmDuqYAAd97e7MWLy7w5j9) he asked when agents would approve these themselves;
- at 07:36:24 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwN1HaQyfWs523TENpj3y4GrB) he asked why he was still pasting approval prompts;
- at 07:36:52 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNVWniFNwFdxHd6saXpoKLKg) he said the greenfield lab should not need him to type or click anything;
- at 07:42:15 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNPCDvrtDZGccQzAi27X4YGH) he asked that this be the last thing he types;
- at 07:44:46 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNLj5JuE8JmYT3juteQ3eMJm) he said not to ask him to approve another PR, that he meant the lab for now rather than every PR, and that the lab is greenfield and holds no personal data or anything of value.

Since that morning, every plan, record and done-claim already passes a reviewer thread and a council of three threads before it reaches him. This record makes that pass the approval.

## Decision Drivers

- **The owner's requests of 2026-11-14** above.
- **What can't be undone stays with a person.** A merge can be reverted and a lab layer rebuilt from code; a deleted backup, money spent or a leaked secret can't be taken back.
- **Checks a machine runs.** What a job can check itself (the head, the checks, a clean merge) it checks, so it doesn't rest on the caller's word.
- **Everything logged.** Each approval names the reviewer's and the council's messages, in a log the owner can read.
- **Replaceable** (REQ-0011): undone by a PR that puts the old rules back.

## Considered Options

1. **The agents' pass approves every reversible change**: merges, acceptances, box limit changes and production and cloud applies. The few steps that can't be undone keep one tap.
2. **The agents' pass approves merges only**, records "as proposed" included. Acceptances, box limits and production and cloud applies keep the owner's tap.
3. **Keep the owner's typed lines and taps**, as today.

## Decision Outcome

Chosen option: **1**, because the owner asked to stop approving the lab himself, and option 2 would leave him a tap for every acceptance and every production apply. The owner's messages don't name what keeps a tap. Rule 6 keeps one for firewall and tailnet changes, deletes and secrets, which the project's standing rules already reserve to him and which the orchestrator thread named at 07:46 UTC, and for spending money, which the standing rules also reserve. That list, where in each step the tap falls, and rule 7, are agent picks.

```mermaid
flowchart LR
  pr["PR, CI green"] --> rv["reviewer thread clears the head"]
  rv --> cn["council A, B, C each pass the head"]
  cn --> job["merge job on main, box runner:<br/>pr-merge checks head, checks, clean merge,<br/>then squash pinned to the head"]
  job --> main["main"]
  main --> box["box-apply, limits included"]
  main --> dev["dev apply"]
  dev --> prod["production or cloud apply,<br/>no tap"]
  prod -. "firewall or tailnet, a delete,<br/>a secret, money" .-> tap["one tap from the owner"]
```

*In words:* a PR whose CI is green goes to the reviewer thread and then to the three council threads. When all four pass the same head, an agent starts the merge job on the agent box's runner. The box's `pr-merge` wrapper checks the head, the checks and the merge itself before it squash-merges. What lands on `main` is then applied as the other records set out, with no tap, except for the steps in rule 6: firewall and tailnet applies, deletes, secrets and money.

### Rules

1. **The agents' pass.** The agents' pass for a head is:
   - the reviewer thread's clearance of that head, and
   - a pass from each of the three council threads for the same head, recorded by the orchestrator thread in one message.

   It takes the place of the owner's go, typed or tapped, wherever these rules asked for it: AGENTS.md rules 1 and 2, D-0001's statuses, D-0031 rules 3 and 4, D-0034, D-0035 rule 3(b) and (c), D-0036 rule 6 and D-0041 rule 6. Rule 6 below is the exception.
2. **The merge job.** `.github/workflows/merge.yml` merges a PR that has the agents' pass.
   - It runs only by `workflow_dispatch`, only from `main`, on the agent box's runner, whose job-started hook refuses any other workflow, branch or event. Its own token is read-only (Activation gate item 3).
   - Its inputs are the PR number, the full head, and the message ids of the reviewer's clearance and of the council's passes.
   - It hands the merge to the box's `pr-merge` wrapper, which merges as the project's GitHub App with the key kept inside the wrapper (D-0031). The wrapper checks itself, and refuses otherwise:
     - the PR is open, not a draft, and targets `main` (the last added to `pr-merge` with rule 4's changes);
     - its head is the one named;
     - GitHub reports a clean merge;
     - every check on that head has completed and passed or was skipped, and at least one ran;
     - fewer than 100 files changed.
   - It squash-merges pinned to that head, and the run summary shows the PR, the head, the wrapper's verdict and merge commit, and the two message ids.
   - It can't read the project's chat, so it can't check the two message ids. The agent that starts it checks them first, and the ids stay in the log.
   - No session's safety check stands in this path, because a runner job is not a session.
3. **Records and standards.** An agent may set a record to `accepted`, `rejected` or `parked`, or a standard to `active`, with the agents' pass, the same way the owner did:
   - the proposal merges first, or the pass names the head that holds it (D-0001);
   - the acceptance PR changes only `status`, `date` and `accepted-evidence`, with `approved-by: agents`, `approval-ref` the orchestrator's message that records the pass, and `approval-names` naming the PR and head;
   - the reviewer compares the accepted text with the passed head, as D-0001 asks.
4. **The box's limits.** A change to a limit (D-0036 rule 3) that merged with the agents' pass is applied by `box-apply` on the box, with no apply from the Mac.
   - The changes that set this up are themselves limit changes, so they are the last ones applied from the Mac, together, with the owner's accept of this record as their go: `box-apply` applying limit changes; the runner hook and the wrapper list letting the runner start `pr-merge` for the merge job; and `pr-merge` no longer stopping on records, standards and `AGENTS.md`, which rule 3 moves to the agents' pass, and checking that the PR targets `main`. The box's runner is registered as D-0041 rule 2 says.
   - `box-apply` still logs each limit file that changed, with the commit.
   - The keys stay in the box's own key folders, as now.
5. **Production and cloud applies.** Dev is the dev guests, VMs 250 to 257, and the dev secrets store, VMs 550 to 599 (D-0038 rule 2; central-hub #276). The production secrets store, VM 500, is production. A production run (D-0035) or a production or cloud apply (D-0041) needs no tap, apart from rule 6:
   - a layer with a dev twin runs once the same commit passed that layer on dev (D-0035 rule 3(a));
   - a layer with no dev twin (the Proxmox host's own configuration, OPNsense, the tailnet, Azure, Cloudflare and Tailscale) runs once its saved plan's hash has the agents' pass;
   - the log names the pass's message id where it named the card.
6. **Still one tap.** These still need the owner's tap on a card that names the step and the commit (D-0034), at the step itself. A merge of their code needs no tap; the apply or the act does:
   - **firewall and tailnet:** an apply to the firewall layers (the Proxmox host's firewall, OPNsense's rules) or to the tailnet, which includes opening a lab service to the internet;
   - **deletes:** deleting data or a backup, tearing down a whole environment's guests outside dev, and a `destroy` or `restore` of the secrets store, on dev too, since it holds the lab's secrets (other dev teardowns and rebuilds need no tap, as now);
   - **secrets:** exposing a secret, copying secrets onto the agent box, or rotating the owner's own credentials;
   - **money:** anything that starts a charge, as the project's rules already say.
7. **What stays with the owner by choice.** Scanning his own sign-in code into his authenticator, the settings of his own claude.ai and GitHub accounts, and the Proxmox console when everything else is down (D-0035 rule 9).
8. **The owner's no.** A message from the owner that says no, stop or revert about a change wins at once. Agents stop starting jobs for it, and open a revert PR or run the layer's way back. A revert goes through the same pass and job.
9. **Logs.** The merge job's summary is public on GitHub for at most 90 days, so it holds only the PR, the heads and the message ids. The orchestrator lists every merge and apply made under this record in its next report to the owner.
10. **Unchanged.** Never enable auto-merge. No workflow on `pull_request_target`, `issue_comment` or `issues` that runs an agent or touches secrets. No secrets or private names in this repository. AGENTS.md rules 3 to 6 stand.
11. **Changing this record.** A change that narrows this record, or adds a check to the merge job, needs the agents' pass, like any other change. A change that removes a step from rule 6, or drops or loosens a check in `merge.yml`, the runner hook or `pr-merge`, is itself a rule 6 step and needs the owner's tap. Every change to either is listed in the orchestrator's report.

### Consequences

- Good: the owner stops typing and tapping for merges, acceptances, box changes and production and cloud applies. He keeps one tap for firewall and tailnet applies, deletes, secrets and money.
- Good: each approval names a reviewer's and a council's message, and the merge job's own checks don't rest on the caller.
- Good: merges made by the job show as the project's GitHub App in the PR's history, and each has a run on GitHub that names its pass.
- Bad: agents approve agents' work, and all four checkers are the same kind of model, so they can share a blind spot. Compensating controls: four separate threads, each told to look for what is missing; the four-check rule before any "supported" or "not supported" claim; the public run log; the owner's no at any time (rule 8); every merge can be reverted and every lab layer rebuilt from code.
- Bad: the merge job can't check the reviewer's and the council's messages. An agent could start it with made-up ids. Compensating controls: the ids are in the public log and the orchestrator's report, so a made-up one shows; the job checks everything GitHub can tell it. This is the same gap D-0035 and D-0041 accept for card taps.
- Bad: the merge job's checks live in this repository, so a PR can change them (Activation gate item 2 is still open). Compensating controls: a change that drops or loosens a check, or removes a step from rule 6, needs the owner's tap (rule 11); the job runs `main`'s copy, never a PR's; every change to it is in the orchestrator's report.
- Bad: a production or cloud apply now runs without the owner seeing its plan first. A wrong apply can break the lab until it is rebuilt. The owner gave his reason at 07:44:46 UTC: the lab is greenfield and holds no personal data or anything of value. If that stops being true, this record is revisited. Compensating controls: dev first for every layer that has a twin; the saved plan and the council's pass for those that don't; rule 6 for firewall, tailnet, deletes, secrets and money; the restore checks of D-0035 rule 5 before any teardown.
- Bad: rule 7's steps still need the owner in person.
- Bad: the merge job depends on the agent box and its runner. If the box is down, merges wait, or fall back to the owner's own merge on GitHub.
- Neutral: the Mac and its guard are no longer in any approval path, except the one apply in rule 4.

### Confirmation

- The first docs-only PR merged through the job shows the project's App as the merger, a merge commit signed by GitHub, and the run summary of rule 2.
- A cloud session starts the job with its GitHub tools. If its safety check refuses that, the orchestrator's session starts it, and the refusal is written into the runbook.
- The first box limit change merged under this record is applied by `box-apply` with no apply from the Mac.
- The first production apply under this record logs the pass's message id instead of a card's.

## Pros and Cons of the Options

### 2. Merges only

- Good: a smaller change; acceptances and applies keep the owner's eye.
- Bad: the owner still taps for every acceptance and every production or cloud apply, which he asked to stop.

### 3. Keep typed lines and taps

- Good: nothing changes.
- Bad: the owner keeps typing, the thing he asked to end; and merges stall whenever the box's safety check or the Mac's guard refuses.

## More Information

- **Evidence:** [0042](../evidence/0042-let-agents-approve-every-reversible-change-in-the-owners-place.md).
- **Records it changes, in this PR:** D-0001 (statuses), D-0031 rules 3 and 4, D-0034 rule 4, D-0035 rule 3, D-0036 rule 6, and AGENTS.md rules 1 and 2. D-0041 rule 6 changes in the same PR, since D-0041 is still proposed.
- **How to start the job:** [Merge a PR through the merge job](../runbooks/merge-a-pr-through-the-merge-job.md).
- **How this record is accepted.** It loosens AGENTS.md's rules for now, which D-0034 rule 4 sends to a line the owner types naming the PR and its head. His messages of 2026-11-14 from 07:36 to 07:44 UTC are typed and ask for this, but name no PR or head. Whether they count is the council's and the orchestrator's call, recorded in `accepted-evidence`.
