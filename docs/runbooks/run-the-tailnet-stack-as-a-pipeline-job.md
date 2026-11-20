---
title: Change the tailnet stack through the pipeline job
status: draft
kind: manual
trigger: every change to the tailnet stack, hosts/terraform/home/tailnet (the connector's subnet routes and split DNS), once D-0041 is accepted
runner: an agent session starts the job; the owner gives his go for the apply (D-0034 rule 9)
outcome: the stack is planned on main, the owner's go names the saved plan's hash, the same plan is applied, and both logs name the card
needs: D-0041 accepted; the agent_box role applied with the tailnet-stack wrapper (the owner's typed go, a limits change under D-0036); the runner registered; the controller's files on the box, with the tailnet state and its tfvars
private-values: [tailscale-oauth-client, tailnet-tfvars, tailnet-state]
files: [.github/workflows/lab-tailnet.yml, hosts/ansible/roles/agent_box/files/tailnet-stack.sh, hosts/ansible/roles/agent_box/files/runner-job-started.sh, hosts/terraform/home/tailnet/]
last-tested: not yet run
superseded-by:
---

# Change the tailnet stack through the pipeline job

**Status:** draft, held. Written 2026-11-14 from the code in this change. Nothing here has run, and it does not run until D-0041 is accepted and the box's wrapper list and runner hook (both limits) are applied by the owner's typed go.

The apply is the owner's go (his typed line, or his tap on a card option the card did not recommend (D-0034 rule 9)) naming the pull request, its head and the plan's hash, run by this `lab-tailnet` job: no Mac step. (Putting the wrapper on the box is a separate change to the box's limits.)

This is the first job of D-0041. Until now the tailnet stack ran as a raw OpenTofu apply on the owner's Mac. After it passes once on its plan with a tap, that raw run is retired.

## What the job does

`.github/workflows/lab-tailnet.yml` starts only by hand, only from `main`, on the box's runner. It calls the box's `tailnet-stack` wrapper, which runs as the keys user and holds the Tailscale OAuth client, the stack's tfvars and its state. The workflow sees none of them.

| Action | What the wrapper does | Approval |
|---|---|---|
| `plan` | `tofu plan -out` on `origin/main`; saves the plan with its commit and SHA-256 | none |
| `apply` | applies that saved plan only, if the hash named is the saved plan's and `main` has not moved | the owner's card tap naming the repository, the commit, `tailnet` and the first 12 hex digits of the plan's SHA-256 |
| `log` (on the box) | the newest run's summary lines | none |

The run prints only the commit, the plan's hash, the counts of changes (`N to add, N to change, N to destroy`), the card's message ID and pass or fail; on a failed init it also prints the last 12 lines of init's output, with IP addresses replaced. Split DNS names are private, so no resource address is printed. The full output stays on the box in `/var/lib/agent-box/logs/tailnet-stack/`, with one JSON line per run in `summary.jsonl`.

## Steps

1. From the Actions tab, or an agent's `gh` run, start `lab-tailnet` with `action: plan`.
   - expect: `tailnet-stack: plan <12 hex>: N to add, N to change, N to destroy`, then a line naming the commit and the hash.
2. A reviewing agent posts a decision card in the project chat that names the repository, the commit, `tailnet` and the 12-digit hash. The go option is never the recommended one (D-0034 rule 9).
3. The owner gives his go: his typed line, or his tap on a card option the card did not recommend (D-0034 rule 9). One go covers one apply of that plan.
4. A reviewing agent checks the go and the member, then starts `lab-tailnet` with `action: apply`, `card_id` (the message ID of his line or of the card he answered) and `plan_hash`.
   - expect: `tailnet-stack: applied plan <hash> (N to add, N to change, N to destroy), card <ID>`.
5. Run `plan` again.
   - expect: `0 to add, 0 to change, 0 to destroy`. A plan that still shows changes means the apply did not do what its plan showed; stop and read the box's log.

## From the box itself (D-0063)

A session on the box can also apply a saved plan with no workflow and no card, through the box's own ledger (the same shape as the policy job, [run-the-tailnet-policy-as-a-pipeline-job.md](run-the-tailnet-policy-as-a-pipeline-job.md)). The wrapper still runs as the `keys` user with the controller's OAuth client.

1. `sudo -n -u keys /usr/local/libexec/agent-box/tailnet-stack.sh plan`, run from `/tmp` (the keys user cannot read a session's home).
2. The reviewer records its pass: `tailnet-stack.sh pass <commit> <hash> <pass message ID> <ISO time> reviewer`. The orchestrator records the go: `tailnet-stack.sh go <commit> <go message ID> <ISO time> orchestrator`, with the owner's standing go (D-0061 rule 3).
3. `tailnet-stack.sh apply-recorded <hash>`. It applies the saved plan only if its hash is the one named, main has not moved since, and the ledger holds the pass and an unused go; otherwise it names what is missing and applies nothing.

expect: `applied plan <hash> (...), reviewer pass <ID>, go <ID>`, then `plan` again shows `0 to add, 0 to change, 0 to destroy`. A ledger line proves a recorder's word and its message ID, not the owner's; a reviewing agent checks the IDs. The card-ID `apply` stays the workflow's.

## What it refuses

- An `apply` with no card ID, a card ID that is not `cmsg_...`, or a hash that is not 12 lowercase hex digits, and an `apply-recorded`, `pass`, `go` or `ledger` call with a malformed argument or the wrong recorder (exit 2).
- An `apply-recorded` with no reviewer pass for the commit and hash, or no unused go for the commit: it names what is missing and applies nothing.
- An `apply` whose hash is not the saved plan's, or when `main` moved since the plan: run `plan` again, nothing is applied.
- Any workflow but the listed ones, any ref but `main`, and any event but `workflow_dispatch`: the runner's job-started hook refuses it before a step runs.

## What this does not close

The box cannot check the tap itself (D-0041 rule 6). The card ID is a required input and goes into both logs; a reviewing agent checks the tap before the apply starts. That gap closes when D-0030 lets the approval move to a protected GitHub environment. The agent session's own sudo line for this wrapper has `plan` and `log` only (`session_args` in the wrapper list); `apply *` is the runner user's alone, so a session on the box cannot apply from its shell, and an apply always leaves a GitHub run behind it. The agents that start the job still choose the card ID they pass, which is why a reviewing agent checks the tap first.

## Where its files come from

The wrapper reads, as the keys user, `/etc/agent-keys/prod/hosts.env` (only its two `TAILSCALE_OAUTH_*` lines), `/etc/agent-keys/prod/tfvars/tailnet.tfvars` and, once, the state `/etc/agent-keys/prod/state/home-tailnet.tfstate`. The agent_box role's prod-files copy puts them there from the controller. From the first run on, the box's own copy of the state, `/var/lib/agent-box/state/home-tailnet.tfstate`, is the state: do not run the stack raw again, or the two states drift. The tfvars `vlans_file` must be a path relative to the stack's folder, as in `home.tfvars.example`.

## Raw runs this retires

- The OpenTofu apply of `home/tailnet` that ran on the owner's Mac on 2026-11-14 (no wrapper existed for it).

When this job has passed once on its plan with a tap, the Mac's way to run this stack is deleted. Removing it from the Mac is the owner's step (D-0041 rule 10).
