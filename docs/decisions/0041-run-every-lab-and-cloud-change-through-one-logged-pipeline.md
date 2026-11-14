---
id: D-0041
title: Run every change to the lab and to its cloud accounts through one logged, tested pipeline on the agent box, with no raw runs, and the owner approving a saved plan by card tap
status: accepted
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-11-14T07:36:27Z
  approved-commit: c0408384f4b92610e20f3c30e5ecb1fa82f6208c
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNKdGN88LtVUDSiPpCPmtatT
  approval-names: "PR #286 and head c040838, in the message itself"
  check: the drafting agent read the message in the project chat at 2026-11-14T08:18Z; it accepts D-0041 as written at PR #286 head c040838 and asks for the merge when green, and that head holds this record. The owner's go in the orchestrator thread at 07:42:30Z (cmsg_01X43rfNYp4H1dL1V2dkfkwNHGFshMgp6jwdfeuyZWEdj6) came after the orchestrator posted the same line in that thread at 07:36:06Z (cmsg_01X43rfNYp4H1dL1V2dkfkwN62H7anJnP4HBGZPiMEVcz8). A reviewing agent checks it before the merge
  merged: PR #286 squash-merged at head c0408384 as 2fcfa73, with the status left at proposed; this PR sets it to accepted (D-0001)
revisit-when: the agents get a GitHub account of their own (D-0030), so the approval can move to a protected GitHub environment; a run applies something its saved plan did not show; a production or cloud apply starts without a card that names its plan; a key leaves the box's wrappers; GitHub Actions stops being usable for the lab, and the exit to Forgejo is taken; a raw run happens outside break-glass
---

# Run every change to the lab and to its cloud accounts through one logged, tested pipeline on the agent box, with no raw runs, and the owner approving a saved plan by card tap

## Context and Problem Statement

At 06:31:02 UTC on 2026-11-14 the owner asked when he would stop typing go lines and be able to approve instead (cmsg_01X43rfNYp4H1dL1V2dkfkwNNmDuqYAAd97e7MWLy7w5j9). At 06:36:44 UTC he said that everything should go through a workflow or pipeline anyway, for the logging and the tests (cmsg_01X43rfNYp4H1dL1V2dkfkwNT6RrSBdDUEXGjL6tdtauzz). That night several changes ran as raw commands on the owner's Mac, on his typed lines: a Proxmox firewall playbook, the Proxmox nginx playbook, an OPNsense DNS run, an OpenTofu apply of the tailnet stack, and the OPNsense backup-user script. One Mac wrapper was pinned too old to pass a needed variable. None of these runs left a log that anyone but the Mac could read.

D-0035 already lets agents tear down and rebuild the lab's guests from the agent box, each production run approved by the owner's card tap after dev. D-0036 lets the box apply its own setup. Neither covers the cloud accounts (Azure, Cloudflare, Tailscale), and neither says that the Mac and raw commands stop. This record makes one pipeline the only way a change reaches the lab or those accounts.

It changes how the owner approves: a card tap that names a saved plan replaces typed command lines, including for the firewall and tailnet changes that until now needed his words. So under D-0034 rule 4 it needs the owner's typed line.

## Decision Drivers

- **The owner's ask**: every change through a pipeline, for logging and tests.
- **Least privilege**: an agent asks, a fixed process acts, and the key stays with the process (D-0035).
- **PR code never meets a key**: CLAUDE.md rule 5 and D-0035 rule 4.
- **The owner sees what he approves**: the plan, not a command.
- **FOSS and an exit path** (STD-0006, REQ-0011).
- **The pipeline can't run on what it tears down.**

## Considered Options

1. **GitHub Actions `workflow_dispatch` workflows on `main`, keyed jobs on the agent box's runner through fixed wrappers**, plan first and apply the saved plan.
2. **A self-hosted FOSS forge and CI, Forgejo with Forgejo Actions, or Woodpecker**, on a lab VM.
3. **A tool-specific runner**: Semaphore UI or AWX for Ansible, Atlantis for OpenTofu.
4. **The box's wrappers only, started by agents in sessions, with no CI front**, as dev runs are today.

## Decision Outcome

Chosen option: **1**. It builds on what is already in place: the dev redeploy workflow, the box's runner hook and the box's wrappers. It adds no service to host, and keeps keys on the box. Option 2 is the exit path. The rules are agent picks, for the owner to accept or change with this record.

### Rules

1. **Scope.** Every change to the home lab within D-0035's scope, to the agent box (D-0036, through `box-apply`), and to the Azure, Cloudflare and Tailscale accounts the lab's code manages. Not the installation of Proxmox itself, and not the owner's own accounts outside the lab's code.
2. **One way in.**
   - A change runs only as a job of a `workflow_dispatch` workflow on `main`. The job runs on the agent box's runner, and calls one fixed wrapper per layer or stack, with fixed arguments.
   - The keys stay in the wrappers: the workflow never sees one.
   - The runner's job-started hook refuses any workflow not on its list, any ref but `main`, and any event but `workflow_dispatch`.
   - Agents start the jobs. The owner may too, from the Actions tab.
   - **The box's runner is registered now, with no GitHub environment.** The runbook for the dev redeploy workflow held the runner back until D-0030, because a GitHub environment that any agent can approve is not the owner's gate. This record does not use a GitHub environment for approval. The gate is the card tap on the saved plan (rule 6), and dev applies need none. So the runner is registered once this record is accepted, and only the environment still waits for D-0030. The runner hook's list holds this record's workflows and nothing else.
3. **No raw runs.** Nothing changes the lab or those accounts from the owner's Mac, a session's shell or a console, except break-glass (rule 9).
   - Until a layer or stack has its pipeline job, a raw run of it needs the owner's typed words naming the exact command.
   - Each such run is listed in the runbook of that layer, with the date, and stays listed until its job exists.
4. **Plan, then apply the saved plan.**
   - For OpenTofu: `tofu plan -out`, then an apply of that file only.
   - For Ansible: `--check --diff` first, then the same playbook and tags.
   - A run that would apply something its plan did not show stops.
   - Before a teardown, D-0035 rule 5's checks run.
   - After an apply, the layer's own proof tasks run.
5. **Tests before merge, dev before prod.**
   - The change has merged green, with the PR checks: OpenTofu validate and test, ansible-lint, docs and the FOSS check.
   - A lab layer passes on dev before production (D-0035 rule 3(a)).
   - The cloud accounts have no dev twin, so their gate is the saved plan.
6. **How an apply is approved.**
   - A dev apply needs no tap. Dev means only the dev guests (VMs 250 to 257, D-0035 rule 3).
   - A layer with no dev twin counts as production, so every change to it needs a tap: the Proxmox host's own configuration, OPNsense, the tailnet, and the Azure, Cloudflare and Tailscale accounts.
   - A production apply, and every apply to Azure, Cloudflare or Tailscale, waits for the owner's tap on a decision card in the project's chat. The card's question names:
     - the repository;
     - the commit;
     - the layer or stack;
     - the first 12 hex digits of the saved plan's SHA-256.
   - A reviewing agent checks the tap and the member before the apply job starts (D-0035 rule 3(c)).
   - The card's message ID is a required input of the apply job and is written to both logs.
   - A tap covers one apply of that plan and nothing after it.
   - Once the agents have a GitHub account of their own (D-0030), a later record may move this approval to a protected GitHub environment whose required reviewer is the owner (D-0035 rule 8).
7. **Logs.**
   - **GitHub's run log** can be read by any signed-in GitHub user, and it is kept at most 90 days on a public repository. So a job prints only a summary there: the layer or stack, the commit, the card ID, the plan's hash, counts of changes, and pass or fail. It prints no secret and no private name (CLAUDE.md rule 4).
   - **The full log** stays on the box, one JSON line per run plus the run's output, as `box-apply` keeps its own. It goes off the box with the box's existing off-box copy.
8. **Where it runs.**
   - Jobs that hold a lab or cloud key run only on the agent box.
   - PR code never runs there.
   - The CI runner VM holds no lab keys and can't reach the Proxmox API, so it takes PR tests only.
9. **Break-glass.**
   - The owner's Proxmox console and his own cloud consoles stay the way back when the pipeline or the box is down.
   - A break-glass change is written into the layer's runbook afterwards, and code catches up by PR before the next pipeline run of that layer.
10. **The Mac wrappers retire one by one.**
    - Each Mac wrapper, and each command that ran raw, gets one pipeline job.
    - A wrapper is deleted once its job has passed on dev and once on production. Removing it from the Mac is the owner's step.
11. **Changing the rules.** This record's rules, the runner hook's list and the wrappers a job calls change only by a reviewed PR to `main`. A change that widens what a job can do needs the owner's typed line (D-0034 rule 4; D-0036 rule 4 for the box's own limits).

### Consequences

- Good: every change has a log, a tested commit and a saved plan behind it, and the owner approves the plan in the chat he already uses.
- Good: no key is on the Mac or in a workflow. The Mac drops out as wrappers retire.
- Good: the tailnet, firewall and cloud changes, which need the owner's words today, get the same plan-and-tap gate as the rest.
- Bad: **the box still can't check the tap itself.** It is the same gap D-0035 accepts, with the same compensating controls: a reviewing agent's check, the card ID in the log, and a plan hash the tap must match. It closes when D-0030 lands (rule 6).
- Bad: the agent box now holds the Azure, Cloudflare and Tailscale keys as well as the Proxmox token. Compensating controls: the keys stay in wrappers, the hook lets only listed workflows run, PR code never runs on the box, and every apply to those accounts needs a tap.
- Bad: GitHub Actions is a closed hosted service. Its run logs are public and kept at most 90 days, so the full record lives on the box. The exit is Forgejo with Forgejo Actions (GPL-3.0); its workflows are similar to GitHub's but not compatible, so the workflow files need rewriting.
- Neutral: until each layer has its job, raw runs go on, on the owner's typed words, listed in the runbooks (rule 3).
- Neutral: the dev redeploy runbook's section "Not registered until D-0030 is met" changes with the PR that registers the runner: the runner is registered, and only the GitHub environment waits for D-0030.

### Confirmation

- Each production or cloud apply has a card, and the card names the plan's hash. A reviewing agent checks the hash in the box log against the card before the run counts as done.
- The first job built is the one for the tailnet stack, which ran raw on 2026-11-14. It is run once on its plan with a tap, and its summary in GitHub shows no private name.
- A list in the runbooks shows every Mac wrapper and raw command, and the job that replaced each.

## Pros and Cons of the Options

### 2. A self-hosted Forgejo or Woodpecker

- Good: FOSS, and no paid edition was found by the four checks in the evidence (Forgejo GPL-3.0, held by a non-profit; Woodpecker Apache-2.0). Its logs stay private.
- Bad: one more service to host and back up. Hosted on c1, it couldn't rebuild c1. Woodpecker still needs a forge to sign in with. Kept as the exit path.

### 3. Semaphore UI, AWX or Atlantis

- Bad: Semaphore UI's open-source build holds back its Pro features: its code has only empty stand-ins for secrets storage in Vault or OpenBao, file-based log export, workflows, project runners and high availability. So it fails STD-0006 rule 2. TOTP, LDAP and OIDC sign-in are not among them: its pricing table lists them as paid, but its MIT code and its docs have all three in the free build.
- Bad: AWX covers Ansible only and runs on Kubernetes, so on c1 it couldn't rebuild c1.
- Bad: Atlantis plans and applies from pull-request comments with the cloud keys, which breaks CLAUDE.md rule 5.

### 4. Box wrappers only

- Good: nothing new; the dev rebuild runs this way today.
- Bad: the owner can't see a run's log, and nothing stops a raw command. That is the gap the owner asked to close.

## More Information

- Evidence: [`docs/evidence/0041-run-every-lab-and-cloud-change-through-one-logged-pipeline.md`](../evidence/0041-run-every-lab-and-cloud-change-through-one-logged-pipeline.md).
- Related: D-0030, D-0034, D-0035, D-0036, STD-0006.
- Exit path: take the workflows to Forgejo Actions on a VM outside the layers it rebuilds, with the same wrappers and the same hook.
