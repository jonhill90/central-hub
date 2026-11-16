---
title: Change the tailnet policy file through the pipeline job
status: draft
kind: manual
trigger: every change to the tailnet policy file, hosts/terraform/home/tailnet-policy (who may reach what, the SSH rules and the policy's tests)
runner: an agent session starts the job; the owner taps a decision card for the apply
outcome: the policy is planned on main, the owner taps a card that names the saved plan's hash, the same plan is applied, and both logs name the card
needs: D-0041; the agent_box role applied with the tailnet-policy wrapper (a box limit, the owner's tap under D-0042 rule 6); the runner registered; the controller's files on the box, with the policy's tfvars
private-values: [tailscale-oauth-client, tailnet-policy-tfvars, tailnet-policy-state]
files: [.github/workflows/lab-tailnet-policy.yml, hosts/ansible/roles/agent_box/files/tailnet-policy.sh, hosts/ansible/roles/agent_box/files/runner-job-started.sh, hosts/terraform/home/tailnet-policy/]
last-tested: not yet run
superseded-by:
---

# Change the tailnet policy file through the pipeline job

**Status:** draft, not run. Written on 2026-11-14 from the code in this change. It does not run until the box's wrapper list and runner hook (both limits) are applied.

**Hold (2026-11-16):** until the PR that adds the owner's group and the `externalTailnets` entry to the template merges, run no tailnet-policy plan or apply. The live policy holds them, and a run from the repository template would delete them.

Until now the policy file ran as a raw OpenTofu apply on the owner's Mac. This job does the same through the pipeline, so D-0046's tailnet steps S1 and S4 need no Mac. It has the same shape as [the tailnet stack's job](run-the-tailnet-stack-as-a-pipeline-job.md); only the differences are written here.

## What differs from the tailnet stack's job

| | Tailnet stack | Tailnet policy |
|---|---|---|
| Workflow | `lab-tailnet.yml` | `lab-tailnet-policy.yml` |
| Wrapper | `tailnet-stack` | `tailnet-policy` |
| Folder | `hosts/terraform/home/tailnet` | `hosts/terraform/home/tailnet-policy` |
| tfvars on the box | `/etc/agent-keys/prod/tfvars/tailnet.tfvars` | `/etc/agent-keys/prod/tfvars/tailnet-policy.tfvars` |
| State | copied once from the controller | the controller's copy if one was put on the box; otherwise the first `plan` adopts the live policy with `tofu import`, which only reads the tailnet |
| `vlans_file` | from the tfvars | always this checkout's `hosts/ansible/inventories/home/group_vars/all/vlans.yml`, since the tfvars names a path on the controller |
| Box log | `/var/lib/agent-box/logs/tailnet-stack/` | `/var/lib/agent-box/logs/tailnet-policy/` |

The rendered policy names the Proxmox host's address, so the run prints only the commit, the plan's hash, the counts of changes, the card's message ID and pass or fail.

## Steps

1. Start `lab-tailnet-policy` with `action: plan`.
   - expect: `tailnet-policy: plan <12 hex>: N to add, N to change, N to destroy`, then a line naming the commit and the hash. On the first run, the import comes first.
   - If the plan fails because the Tailscale OAuth client may not write the policy file, the client needs that scope. A wider right for an agents' credential is the owner's tap (D-0042 rule 6, access rights).
2. A reviewing agent posts a decision card that names the repository, the commit, `tailnet-policy` and the 12-digit hash.
3. The owner taps it.
4. A reviewing agent checks the tap, then starts `lab-tailnet-policy` with `action: apply`, `card_id` and `plan_hash`.
   - expect: `tailnet-policy: applied plan <hash> (...), card <ID>`. The tailnet refuses to save a policy whose `tests` or `sshTests` fail, so a passed apply means they passed.
5. Run `plan` again.
   - expect: `0 to add, 0 to change, 0 to destroy`.

## Raw runs this retires

- The Mac's `tofu-tailnet-policy.sh` ([Allow a command for agents](allow-a-command-for-agents.md), "The wrappers on the owner's Mac today"). When this job has passed once on its plan with a tap, removing it from the Mac is the owner's step (D-0041 rule 10).
