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

On 2026-11-17 at 03:44:14 UTC an agent listed for the owner the steps agents had made up (cmsg_01X43rfNYp4H1dL1V2dkfkwNHKeS2oQYGdDzbxuBx6crRt); its item 4 names the RULE11 list of guarded files. The owner's message of 03:51:09 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNNiA9TRkEc5idx6DPuFfDEv) said to drop the steps agents made up, because the owner never asked for them. The owner's earlier standing rules keep one tap each for:

- firewall and tailnet applies;
- deletes;
- secrets.

Rule 11 is not one of those.

## Decision Drivers

- The owner's taps are for the steps the owner named (D-0042 rule 6), not for steps agents added.
- A change to a merge-guard script does nothing on the agent box until the box installs it, and that install is a box-limit change. Since the owner's order of 2026-11-17 06:21:09 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwN9ubbtsV3Wpcx228ZrApLVh), a box-limit change needs the agents' pass of its exact digest and no owner card (D-0042 rule 4, D-0044). The guard keeps that check, pinned to the bytes, where the change takes effect.

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
- Bad: agents can loosen the merge check without the owner seeing a card at merge time or at the box-limit install. Compensating controls: the install's approvals line pins the digest of every limit file it carries, the agents pass that digest, the orchestrator lists each install in its report (D-0042 rule 9), and the owner's no wins at once (D-0042 rule 8).
- Bad: records and `AGENTS.md` take effect at merge, not at an install. After this record, a PR that amends D-0042 rule 6 or `AGENTS.md` rule 1, the list of steps that keep the owner's tap (firewall and tailnet, deletes, secrets, access rights, money), merges on the agents' four passes with no owner card. The owner's no still wins at once (D-0042 rule 8), and the owner card for this PR must say so in plain words.

### Confirmation

`test_pr_merge_verdict.sh` checks that each former rule 11 file, and a record that amends D-0042, is GREEN on four passes with no owner-tap line. It also checks that a guard file still needs all four passes.

## More Information

This record replaces D-0042 rule 11 and D-0056 rule 4. It changes no other rule of D-0042 or D-0056.

- **How this record is accepted.** Since D-0042, D-0034 rule 4 lets the reviewer's clearance approve a PR that loosens AGENTS.md's rules for now. The installed verdict still asks for an `owner-tap` line on this PR under D-0042 rule 11, and that line's ref is the owner's tap on a card in D-0034 rule 1's form: its question names the repository, the PR and its head, and its text says in plain words that after this record a PR that changes D-0042 rule 6 or `AGENTS.md` rule 1, the owner's own tap list, merges with no owner card. The owner's message of 03:51:09 UTC dropped steps agents made up; it is not that tap, because the rule 6 taps are the owner's own.
- **Until it takes effect.** The verdict on the agent box changes only when a box-limit install carries this record's code. Until then the installed verdict still asks for an `owner-tap` line on rule 11 PRs, this one included, and AGENTS.md rule 2 says so.
- **Merge order.** This PR changes limit paths (`pr-merge-verdict.py`, `pr-merge.sh`). It merged, as 83c8dff, only after line A, the install from 492f6748 to 12c0aee, had applied, because a limit change merged after an approvals line's `to` commit makes that line unusable (D-0044). Its own install was line B, from 04eb8dc2 to 83c8dff (#428).
