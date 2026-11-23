---
id: D-0065
title: Merge plain PRs on green checks, review only guarded changes, and ship a change without a rebuild
status: accepted
date: 2026-11-23
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0031, D-0035, D-0042, D-0044, D-0056, D-0061]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: agents
  approved-at: 2026-11-23T02:20:47Z
  approved-commit: c1772fd8402687a32d3ddf3a528cefdbc0845bf5
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNXhRg7JZG4oHckL4Cywu4HF
  approval-names: "the reviewer's pass of central-hub #926 at head c1772fd8402687a32d3ddf3a528cefdbc0845bf5, as recorded by the orchestrator; the record is D-0065 as proposed in #926, apart from these acceptance fields"
  check: "the reviewer's pass of the head is review post cmsg_01X43rfNYp4H1dL1V2dkfkwNEUkeYLQzESw51ZyDCXwQvk; the orchestrator's message recording it is the approval-ref; this PR changes only this record's status and accepted-evidence and its index row"
  merged: "PR #926 squash-merged at head c1772fd as 0180690 on 2026-11-23T02:22:52Z"
revisit-when: a merged plain PR breaks prod; the agents get GitHub identities of their own and GitHub can require their reviews; or the owner asks for review on every PR again
---

# Merge plain PRs on green checks, review only guarded changes, and ship a change without a rebuild

## Context and Problem Statement

This record **amends D-0042 rule 2 and D-0056**, which have every merge wait for the reviewer's recorded pass, and narrows D-0035 rule 3(a) to full prod rebuilds. Between 2026-11-15 and 2026-11-22, 530 PRs merged on `main`; 48 of them only approved a box install, and prod was torn down and rebuilt 9 times on 2026-11-21 to ship small fixes. Each PR waited for a reviewer turn, and each fix waited for a full dev run (25 to 32 minutes). On 2026-11-23 at 00:50:45 UTC the owner ordered the review steps that slow small changes removed and the pipeline made fast, and at 00:53 UTC he said a rebuild proof and a change are different things. The standing go of 2026-11-18 07:40:44 UTC (D-0061) covers the steps that rule 6 of D-0042 keeps.

## Decision Drivers

- A small change goes live in minutes, measured, with a check that fails when it does not.
- Review stays where it guards something: firewall, tailnet, secrets, access rights, the agents' rules, and code from outside the repository.
- "The cluster can be rebuilt from this repo and its runbooks alone" (PRD line 39) stays proven, on a schedule.

## Considered Options

1. Keep a reviewer pass on every PR (D-0042 rule 2 as written).
2. Green checks merge a plain PR; a guarded PR still needs the pass.
3. Green checks merge every PR.

## Decision Outcome

Chosen option: **2** [agent pick, on the owner's order of 2026-11-23 00:50:45 UTC].

1. **Plain PRs.** The merge sweep merges an open, non-draft PR whose checks are green and whose merge GitHub reports clean, with no recorded pass, when nothing in it is guarded.
2. **Guarded PRs.** A PR still needs the reviewer's pass for its exact head when it changes `.github/`, `AGENTS.md`, `CLAUDE.md` or `SECURITY.md`; in central-hub, the Mac's command wrappers, the Proxmox host job or the identity role, or a path naming opnsense, tailnet, tailscale, firewall, sops, secret, sudoers, openbao or realm; in central-hub-app, `docs/evidence/`; any file whose changed lines name a Secret, an ExternalSecret, a `secretKeyRef` or a password, or that GitHub sends no patch for; a record's status change; or when its head branch is in a fork. The list is `GUARDED_*` and `guarded_file` in `pr-merge-verdict.py`.
3. **Box limits.** A change to the agent box's limits is no longer guarded at merge: box-apply installs it only on the reviewer's digest pass (D-0044), which is the one review it gets.
4. **Shipping a change.** A merged app or manifest change goes live through Argo CD, which follows `main`. A role change goes live with `c1-ansible apply` for that stage, in place, with no dev run first. `rebuild` and `rebuild-prod` run on a schedule or when the rebuild code itself changes; prod is never torn down to ship a fix.
5. **Speed check.** The scheduled `lead-time` workflow fails when a plain PR took more than 30 minutes from open, or from leaving draft, to merge.

### Consequences

- Good: a small change is merge plus deploy, minutes, with no reviewer turn.
- Bad: a plain PR merges on tests alone; a mistake there reaches prod through Argo CD. Rule 2's content check and the fork check limit what can.

## Pros and Cons of the Options

- Option 1: a review of every change, at a measured cost of a reviewer turn per PR and a second PR per box install.
- Option 3: the fastest, with no review of firewall, secret or rule changes, which D-0042 rule 6 keeps.

## More Information

Exit path: set the guarded list to match everything, which restores option 1 without a code change elsewhere. Tests: `.github/hosts-check/tests/test_pr_merge_verdict.sh` and `test_pr_merge_sweep.sh`.
