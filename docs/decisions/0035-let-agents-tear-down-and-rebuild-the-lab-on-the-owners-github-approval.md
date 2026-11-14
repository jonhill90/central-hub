---
id: D-0035
title: Let agents tear down and rebuild the home lab's guests and Proxmox configuration from reviewed main, each production run approved by the owner's card tap after the same change passed on dev
status: proposed
date: 2026-11-13
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0031, D-0034]
supersedes: []
superseded-by:
revisit-when: a production run starts without a card tap that names it, or before the same change passed on dev; a run touches VM 258, CT 259 or the VPS node; the Proxmox token's rights grow beyond the lab's guests and configuration; a run passes a precondition it should have failed; a tap is disowned after a run it approved; the agents get a GitHub account of their own (D-0030) and GitHub can require the owner's approval for every run
---

# Let agents tear down and rebuild the home lab's guests and Proxmox configuration from reviewed main, each production run approved by the owner's card tap after the same change passed on dev

## Context and Problem Statement

AGENTS.md "Rules for now" keep the owner's own hands on every step while he learns the system. Merges by agents were loosened in D-0031, and a card tap as the owner's go in D-0034, but a teardown or rebuild of the lab still needs the owner's Mac and his typed go for each production step.

On 2026-11-13 at 04:58 UTC the owner said the plan was for an agent to redeploy from a cloud session or the agent jump box, and at 05:04 UTC that the goal is for the agent to be able to tear down the home lab and rebuild it if needed. On decision cards he picked "Everything on Proxmox" (05:08 UTC) for what an agent may rebuild, and "Approve on GitHub, phone tap" (05:29 UTC) for how he approves it. A dev rebuild from the agent box passed all eight stages on 2026-11-12, and again on 2026-11-13, with no Mac step.

The first draft of this record used a protected GitHub environment for each run. That needs the agents to have a GitHub account of their own, because today they act as the owner's account, which could approve as him (D-0030). On 2026-11-14 at 03:20 UTC the owner wrote: "remember we are going to use natural language for all of this. And we need to be able to have you harden yourself in dev to prove it works before prod. So they both should be open for you right now. But the goal is to make it where you like i said just do stuff as your own account. But we are a while from there". At 03:22 UTC he tapped "Yes, set it up" on the card "Open prod to agents on your word in chat, after dev proves it?", whose option read: "Agents rewrite D-0035 to chat approval, ready #216 and the prod token; you accept with one typed line, then each prod run needs your card tap." This version records that choice. The GitHub approval moves to "Later, with D-0030".

This record loosens "Rules for now", so under D-0034 rule 4 it needs the owner's typed line, not a tap.

## Decision Drivers

- **The owner's answers** above, and his words of 2026-11-14 03:20 UTC: natural language for all of it, dev first, both open now.
- **Dev proves a change before prod.** Every production run follows a pass of the same change on dev.
- **Least privilege** (the owner's direction of 2026-11-10): an agent asks, a fixed process acts, and the key stays with the process.
- **What cannot be remade stays off the table:** the agent box itself, its sibling container and the VPS node.
- **Replaceable** (REQ-0011): the card tap gives way to a GitHub approval once the agents have their own account.

## Considered Options

1. **Agents run fixed teardown and rebuild layers from reviewed main on the agent box. Each run waits for the owner's approval on a protected GitHub environment.**
2. **The same, with each production run approved by the owner's tap on a decision card in the project's chat, after the same change passed on dev.**
3. **Keep the owner's Mac in the loop.**

## Decision Outcome

Chosen option: **2**. The owner picked the scope and, on 2026-11-14, chat approval after dev. Option 1 is kept as the later step, once the agents have their own GitHub account. The rules below are agent picks, for the owner to accept or change with this record.

### Rules

1. **Scope.** Everything that runs as a guest on the Proxmox host, and the host's configuration through the repository's playbooks: network and firewall guests, the tailnet connector, node VMs, certificates, DNS, sign-in, backups and apps. Not the installation of Proxmox itself, which needs a person at the machine.
2. **Never.** VM 258 (the agent box), CT 259 (its rehearsal sibling) and the VPS node. The Proxmox token has rights on every guest except 258 and 259, which are `NoAccess`, so a bug cannot reach them; the VPS node is not a guest on the host at all. Each run also refuses a plan whose destroy list names them.
3. **How a production run is approved.**
   (a) **Dev first.** The same change, at the same commit or the PR's head, has passed the same layer on dev (VMs 250 to 257), from the agent box. The dev run's log is named in the card.
   (b) **The owner's tap.** The owner taps "go" on a decision card in the project's chat whose question names the repository, the commit or PR with its head, and the layer, as D-0034 sets out for a card. A teardown of the whole lab has its own card, which says so in its question. A tap covers one run of that layer at that commit, and nothing after it.
   (c) **Checked before the run.** A reviewing agent reads the tap in the chat, checks that the member who tapped is the owner and that the card names this commit and layer, and only then the run starts. The run's log on the box names the card's message ID.
   Dev runs need no tap: they are where agents harden the change (the owner's words of 2026-11-14 03:20 UTC).
4. **What a run uses.** The code of `main` at a commit whose PR merged green, one fixed layer per run (no free arguments), the box's own wrappers and keys. No workflow in this repository takes a `pull_request`, `pull_request_target`, `issue_comment` or `issues` trigger and runs on the box's runner (AGENTS.md rule 5).
5. **Before a teardown.** The run first checks that the newest restic snapshot is under 24 hours old and its restore check passed, that a firewall configuration backup and a copy of the OpenTofu state exist off the box, and that the agent box's route to the Proxmox host does not depend on the guest being destroyed. If any check fails, nothing is destroyed.
6. **Logged and capped.** Every run keeps its stage log on the box. One run at a time. A cap on destroys per run, set in the wrapper.
7. **Changing the rules.** This record's rules, the box's wrappers that a run calls, and the Proxmox token's rights change only with the owner's typed line (D-0034 rule 4).
8. **Later, with D-0030.** When the agents have a GitHub account of their own (D-0030, Activation gate item 1), a later record may move production approval to a protected GitHub environment whose required reviewer is the owner, on a `workflow_dispatch` workflow on `main`, as option 1 describes. That record then splits the GitHub rights: the box's App gets no Administration and no Deployments write, runner registration moves to a separate App or to the owner by hand, and no agent holds a token that can approve as the owner.
9. **Break-glass.** The owner reaches the Proxmox host's own console to put things back by hand. The way back is the runbook (rebuild-home-lab-from-scratch.md), kept current by every run.

### Consequences

- Good: the owner approves in the same chat he already uses, in words and taps, and every production change has passed on dev first.
- Good: the teardown can't touch the box that runs it, because the token has no rights there.
- Bad: **the box can't check the tap itself.** The tap lives in the chat, which the box can't read, so an agent's word that the owner tapped is what starts the run. Compensating controls: a reviewing agent checks the tap and the member before the run (rule 3(c)); the run's log names the card; a disowned tap is a revisit trigger; and rule 8 replaces this with a GitHub approval once the agents have their own account.
- Bad: the agent box holds a Proxmox token that can destroy every lab guest. Compensating controls: reviewed main only, the dev pass first, the owner's tap, the 24-hour backup precondition, the destroy cap, and the exclusion by rights.
- Bad: a self-hosted runner on a public repository runs whatever a workflow on `main` says. Compensating control: rule 4, and a change to a workflow is a reviewed PR to `main` like any other.
- Neutral: AGENTS.md rule 1's sentence on D-0035 changes to point at the card tap. Nothing in this record weakens the owner's typed line for changes to these rules.

### Confirmation

- A reviewing agent checks each production run against its card: the commit, the layer, the member who tapped, and that the dev run and the preconditions passed.
- The first production run is a drill of one layer, after the same layer passed on dev.

## Pros and Cons of the Options

### 1. Approval on a protected GitHub environment

- Good: GitHub proves it was the owner, and the box can check the approval itself.
- Bad: today agents act as the owner's GitHub account, so any token for that account with Deployments write could approve as him. It needs the agents' own account first (D-0030), which the owner placed after the platform is laid down (2026-11-14 03:20 UTC). Kept as rule 8.

### 3. Keep the Mac in the loop

- Good: nothing new to trust.
- Bad: goes against the owner's answers of 2026-11-13 and 2026-11-14, and leaves the lab unbuildable when the Mac is away.

## More Information

- **Evidence:** the owner's messages of 04:58 and 05:04 UTC on 2026-11-13; his taps at 05:08 and 05:29 UTC on the cards "What can an agent tear down and rebuild without you on the Mac?" and "How do you approve an agent's teardown or rebuild?"; his message of 2026-11-14 03:20 UTC and his tap at 03:22 UTC on the card "Open prod to agents on your word in chat, after dev proves it?"; and dev rebuilds from the box that passed on 2026-11-12 and 2026-11-13. No research batch of its own.
- **What the first draft found about GitHub rights**, kept for rule 8: GitHub's table of App permissions puts the endpoints that set or delete an environment and its protection rules under Administration (write), and the endpoint that approves a pending deployment under Deployments (write) [source: https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps].
- **Exit path:** delete the box's production token; the Mac path in the runbooks still works.
- Related records: D-0001, D-0030, D-0031, D-0034, D-0036.
