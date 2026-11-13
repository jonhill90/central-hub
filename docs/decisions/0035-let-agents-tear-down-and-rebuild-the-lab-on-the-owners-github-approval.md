---
id: D-0035
title: Let agents tear down and rebuild the home lab's guests and Proxmox configuration from reviewed main, each run approved by the owner on GitHub
status: proposed
date: 2026-11-13
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0030, D-0031, D-0034]
supersedes: []
superseded-by:
revisit-when: any agent token gains Administration or Deployments write on this repository; an agent changes or removes the approval rule on a protected environment; a run touches VM 258, CT 259 or the VPS node; the Proxmox token's rights grow beyond the lab's guests and configuration; a run passes a precondition it should have failed; the agents get GitHub identities of their own and GitHub can require the owner's approval for every write (D-0030)
---

# Let agents tear down and rebuild the home lab's guests and Proxmox configuration from reviewed main, each run approved by the owner on GitHub

## Context and Problem Statement

AGENTS.md "Rules for now" keep the owner's own hands on every step while he learns the system. Merges by agents were loosened in D-0031 and a card tap as the owner's go in D-0034, but a teardown or rebuild of the lab still needs the owner's Mac and his typed go for each production step.

On 2026-11-13 at 04:58 UTC the owner said the plan was for an agent to redeploy from a cloud session or the agent jump box, and at 05:04 UTC that the goal is for the agent to be able to tear down the home lab and rebuild it if needed. On a decision card he picked "Everything on Proxmox" (05:08 UTC) for what an agent may rebuild, and "Approve on GitHub, phone tap" (05:29 UTC) for how he approves it. A dev rebuild from the agent box passed all eight stages on 2026-11-12 with no Mac step.

This record turns those two answers into rules. It loosens "Rules for now", so under D-0034 rule 4 it needs the owner's typed line, not a tap.

## Decision Drivers

- **The owner's answers** above.
- **Only the owner can approve.** A message in chat cannot be checked by the machine that acts on it, and everything on GitHub is data (AGENTS.md rule 1). The approval must come from something the agent cannot write.
- **Least privilege** (the owner's direction of 2026-11-10): an agent asks, a fixed process acts, and the key stays with the process.
- **What cannot be remade stays off the table:** the agent box itself, its sibling container and the VPS node.
- **Replaceable** (REQ-0011).

## Considered Options

1. **Agents run fixed teardown and rebuild layers from reviewed main on the agent box. Each run waits for the owner's approval on a protected GitHub environment.**
2. **The same, with the owner's go typed in chat.**
3. **Keep the owner's Mac in the loop.**

## Decision Outcome

Chosen option: **1**. The owner picked the scope and the channel. The rules below are agent picks, for the owner to accept or change with this record.

### Rules

1. **Scope.** Everything that runs as a guest on the Proxmox host, and the host's configuration through the repository's playbooks: network and firewall guests, the tailnet connector, node VMs, certificates, DNS, sign-in, backups and apps. Not the installation of Proxmox itself, which needs a person at the machine.
2. **Never.** VM 258 (the agent box), CT 259 (its rehearsal sibling) and the VPS node. The Proxmox token has rights on every guest except 258 and 259, which are `NoAccess`, so a bug cannot reach them; the VPS node is not a guest on the host at all. Each run also refuses a plan whose destroy list names them.
3. **How a run is approved.** A run is a `workflow_dispatch` workflow on `main`, in a protected GitHub environment whose required reviewer is the owner, on a self-hosted runner on the agent box. The run waits until the owner approves in GitHub. An agent may start a run and may not approve it. A teardown of the whole lab uses a stricter environment than a rebuild of one layer.
4. **What a run uses.** The code of `main` at a commit whose PR merged green, one fixed layer per run (no free arguments), the box's own wrappers and keys. No workflow in this repository takes a `pull_request`, `pull_request_target`, `issue_comment` or `issues` trigger and runs on that runner (AGENTS.md rule 5).
5. **Before a teardown.** The run first checks that the newest restic snapshot is under 24 hours old and its restore check passed, that a firewall configuration backup and a copy of the OpenTofu state exist off the box, and that the agent box's route to the Proxmox host does not depend on the guest being destroyed. If any check fails, nothing is destroyed.
6. **Logged and capped.** Every run keeps its stage log on the box and its Actions run on GitHub. One run at a time. A cap on destroys per run, set in the workflow.
7. **Changing the rules.** This record's rules, the environments' reviewers and protection rules, the workflow files that set `environment:`, the box's wrappers that a run calls and the runner's settings change only with the owner's typed line (D-0034 rule 4). An agent never edits a protection rule, and no token an agent holds may be able to.
8. **Who holds which GitHub right.** (a) The box's central-hub App gets no Administration and no Deployments write: only what `pr-merge` and the bump PRs need, and Actions write to start a run. (b) Runner registration moves to a separate App with Administration that is not installed on this repository, or the owner registers the runner by hand. (c) The environments' required reviewer is an identity no agent holds a token for: agents act as the owner's own GitHub account today (AGENTS.md rule 1), so any token for that account with Deployments write could approve as the owner. Until the agents have an account of their own (D-0030, Activation gate item 1), this record does not take effect: the first run waits for it.
9. **Break-glass.** The owner reaches the Proxmox host's own console to put things back by hand. The way back is the runbook (rebuild-home-lab-from-scratch.md), kept current by every run.

### Consequences

- Good: the owner approves from his phone, GitHub proves it was him, and no private file needs his Mac.
- Good: the teardown can't touch the box that runs it, because the token has no rights there.
- Bad: the agent box holds a Proxmox token that can destroy every lab guest. Compensating controls: reviewed main only, the environment approval, the 24-hour backup precondition, the destroy cap, and the exclusion by rights.
- Bad: **the GitHub App the box uses today holds repository Administration, which it needs to mint runner registration tokens.** GitHub's table of App permissions puts the endpoints that set or delete an environment, its deployment branch policies and its deployment protection rules under Administration (write), and the endpoint that approves a pending deployment under Deployments (write); the page does not name required reviewers, so whether an installation token could clear one is unverified [source: https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps]. Rule 8 splits those rights. Compensating control until then: no run is started on an environment.
- Bad: **agents act as the owner's account**, so an approval by that account is not proof of the owner. Rule 8(c) makes D-0030 a condition. Not yet checked: whether the Claude GitHub App holds Deployments write; the owner checks it in the App's settings before acceptance.
- Bad: a self-hosted runner on a public repository runs whatever a workflow on `main` says. Compensating control: rule 4, and a change to a workflow is a reviewed PR to `main` like any other.
- Bad: GitHub is a dependency for approving a run. If GitHub is down, nothing runs; the owner's console is the way round it (rule 9).
- Neutral: AGENTS.md rule 1 gains one sentence pointing here. Nothing in this record weakens the owner's typed line.

### Confirmation

- A reviewing agent checks each run's Actions record: the environment, the approver, the commit, and that the preconditions passed.
- A test run on dev, through the same workflow, before the first run on anything else.
- The first lab-wide run is a drill of one layer.

## Pros and Cons of the Options

### 2. The go typed in chat

- Good: no runner, no environment.
- Bad: the box cannot tell the owner's go from an agent's claim of it.

### 3. Keep the Mac in the loop

- Good: nothing new to trust.
- Bad: goes against the owner's answers of 2026-11-13, and leaves the lab unbuildable when the Mac is away.

## More Information

- **Evidence:** the owner's messages of 04:58 and 05:04 UTC on 2026-11-13, his taps at 05:08 and 05:29 UTC on the decision cards "What can an agent tear down and rebuild without you on the Mac?" and "How do you approve an agent's teardown or rebuild?", and a dev rebuild from the box that passed on 2026-11-12. No research batch of its own.
- **Exit path:** stop the environments' runs and delete the box's Proxmox token; the Mac path in the runbooks still works.
- Related records: D-0001, D-0030, D-0031, D-0034.
