---
id: D-0059
title: Drop the owner-tap line for files that guard the merge, so they merge on the agents' pass like any other PR
status: proposed
date: 2026-11-17
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0042, D-0056]
supersedes: []
superseded-by:
revisit-when: an agent change to a merge-guard file merges something the owner says should not have merged; or the agents get GitHub identities of their own (D-0030) and GitHub can require their approvals
---

# Drop the owner-tap line for files that guard the merge, so they merge on the agents' pass like any other PR

## Context and Problem Statement

D-0042 rule 11 and D-0056 rule 4 make the merge sweep hold back any PR that changes certain files until the ledger also holds an `owner-tap` line. The files are D-0042 and D-0034, the runner hook, `pr-merge.sh`, `pr-merge-verdict.py`, `pass-record.sh`, the sweep's unit templates, the Mac's checked merge, and the role's `defaults/main.yml` unless only five pinned-tool keys change. A record that supersedes or amends D-0042 or D-0034 is caught the same way. Both rules are marked as agent picks.

In practice, the rule sent the owner cards for changes that only touched wording, and for a defaults key that stays off until a later card (#401, #407).

On 2026-11-17 two agent lists named the steps agents had made up: one in a thread at 03:44:14 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNHKeS2oQYGdDzbxuBx6crRt), whose item 4 names the RULE11 list of guarded files, and a nine-step list in the project chat at 03:49:58 UTC, whose step 7 is the rule-file cards. The owner's message of 03:51:09 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNNiA9TRkEc5idx6DPuFfDEv) said to drop those steps, because the owner never asked for them. The owner's earlier standing rules keep one tap each for:

- firewall and tailnet applies;
- deletes;
- secrets.

Rule 11 is not one of those.

## Decision Drivers

- The owner's taps are for the steps the owner named (D-0042 rule 6), not for steps agents added.
- A change to a merge-guard script does nothing on the agent box until the box installs it, and that install is a box-limit change. Box-limit changes keep the owner's tap (D-0042 rules 4 and 6, D-0044). The guard keeps its owner check where the change takes effect.

## Considered Options

1. Drop the owner-tap line for merge-guard files and records.
2. Keep rule 11 as it is.

## Decision Outcome

Chosen option: 1.

### Rules

1. **No file needs an owner-tap line to merge.** A PR that changes a file D-0056 rule 4 listed, or a record that supersedes or amends D-0042 or D-0034, merges on the four passes and green checks, like any other PR. This replaces D-0042 rule 11 and D-0056 rule 4.
2. **What stays.**
   - `owner-tap` stays a ledger role for a record accepted on the owner's own tap (`approved-by: owner`, D-0056 rule 5), and only the orchestrator records it.
   - D-0042 rule 6's steps keep the owner's tap at the step itself.
   - A merged change to the merge's own scripts reaches the box only through a box-limit install (D-0044).
3. **The code.**
   - `pr-merge-verdict.py` drops the rule 11 list, the defaults block reader and the amend check, and no longer prints `OWNER:`.
   - `pr-merge.sh` and the Mac's checked merge keep their handling of `OWNER:` and of the rule 11 NOTE. The verdict no longer prints either, so both are dead paths, left alone to keep this PR off two more guard files.

### Consequences

- Good: PRs to the merge files, D-0042 and D-0034 no longer wait on an owner card.
- Bad: agents can loosen the merge check without the owner seeing a card at merge time. The owner sees it at the box-limit install, which names every limit file the install carries.
- Bad: records and `AGENTS.md` take effect at merge, not at an install. After this record, a PR that amends D-0042 rule 6 or `AGENTS.md` rule 1, the list of steps that keep the owner's tap (firewall and tailnet, deletes, secrets, access rights, money, the box's limits), merges on the agents' four passes with no owner card. The owner's no still wins at once (D-0042 rule 8), and the owner card for this PR must say so in plain words.

### Confirmation

`test_pr_merge_verdict.sh` checks that each former rule 11 file, and a record that amends D-0042, is GREEN on four passes with no owner-tap line. It also checks that a guard file still needs all four passes.

## More Information

This record replaces D-0042 rule 11 and D-0056 rule 4. It changes no other rule of D-0042 or D-0056.

- **How this record is accepted.** Since D-0042, D-0034 rule 4 lets the reviewer's and the councils' pass approve a PR that loosens AGENTS.md's rules for now, so this record is accepted on the agents' pass. The one owner step is the `owner-tap` line that the installed verdict still asks for under D-0042 rule 11, in D-0034 rule 1's form: a card naming the repository, the PR and its head. The owner's message of 03:51:09 UTC names no PR and no head; the orchestrator decides whether it serves as that line's ref or a card goes up.
- **Until it takes effect.** The verdict on the agent box changes only when a box-limit install carries this record's code. Until then the installed verdict still asks for an `owner-tap` line on rule 11 PRs, this one included, and AGENTS.md rule 2 says so.
- **Merge order.** This PR changes limit paths (`pr-merge-verdict.py`, `pr-merge.sh`). It merges only after the pending install from 88fd159f to 260de98c has applied, because a limit change merged after an approvals line's `to` commit makes that line unusable (D-0044). Its own install then needs a new approvals line.
