---
title: Change the tailnet policy file through the pipeline job
status: draft
kind: manual
trigger: every change to the tailnet policy file, hosts/terraform/home/tailnet-policy (who may reach what, the SSH rules and the policy's tests)
runner: an agent session starts the job; the owner taps a decision card for the apply
outcome: the policy is planned on main, the owner taps a card that names the saved plan's hash, the same plan is applied, and both logs name the card
needs: D-0041; the agent_box role applied with the tailnet-policy wrapper (a box limit, so the agents' pass of its digest and no owner card, D-0042 rule 4); the runner registered; the controller's files on the box, with the policy's tfvars, including `external_tailnets`
private-values: [tailscale-oauth-client, tailnet-policy-tfvars, tailnet-policy-state]
files: [.github/workflows/lab-tailnet-policy.yml, hosts/ansible/roles/agent_box/files/tailnet-policy.sh, hosts/ansible/roles/agent_box/files/runner-job-started.sh, hosts/terraform/home/tailnet-policy/]
last-tested: not yet run
superseded-by:
---

# Change the tailnet policy file through the pipeline job

**Status:** draft, not run. Written on 2026-11-14 from the code in this change. It does not run until the box's wrapper list and runner hook (both limits) are applied.

**Before the first plan: put `external_tailnets` in the box's tfvars.** The live policy holds the owner's group and an `externalTailnets` entry. The template renders both only from the variable `external_tailnets` (#379), so unless the box's `/etc/agent-keys/prod/tfvars/tailnet-policy.tfvars` sets it, a run from the box would delete them. If it is missing, the controller adds `external_tailnets` to that file, with the alias, ID, group and members of the live entry, then copies the file to the box like its other files. Those values are private and never go in this repository. Until then, run no plan or apply. On the first plan, `groups` must not be in the sections that differ. `externalTailnets` can be: the template always lists the group and `tag:share-pod` in `allowExternalReferencesTo`, so if the live entry lists another tag there, the plan changes it. That change is the share pod's tailnet apply, and its card says in plain words which tag leaves the list and which comes in.

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

The rendered policy names the Proxmox host's address, so the run prints only the commit, the plan's hash, the counts of changes, the card's message ID and pass or fail; on a failed init it also prints the last 12 lines of init's output, with IP addresses replaced.

## Steps

1. Start `lab-tailnet-policy` with `action: plan`.
   - expect: `tailnet-policy: plan <12 hex>: N to add, N to change, N to destroy`, then `tailnet-policy: policy sections that differ: <names>`, then a line naming the commit and the hash. On the first run, the import comes first.
   - why the second line: the whole policy is one resource, so the counts only ever say `1 to change`, and only the keys user can read the plan itself. `policy_sections.py` (in the stack's folder) compares the live and the new policy as data, with comments and trailing commas removed, and prints only the names of the top-level sections that differ, such as `grants` or `externalTailnets`, never their contents. The provider compares the formatted text, so a first run can show the whole file as changed when the meaning is the same; the names line is what counts. `none` means only formatting differs.
   - On the first plan, if `groups` is in the names line, stop: the box's tfvars doesn't match the live entry yet. Other sections the template changes, such as `externalTailnets`, `tagOwners`, `grants`, `ssh` and `tests` for the share pod, go on the card in step 2.
   - If the plan fails because the Tailscale OAuth client may not write the policy file, the client needs that scope. A wider right for an agents' credential is the owner's tap (D-0042 rule 6, access rights).
2. A reviewing agent posts a decision card that names the repository, the commit, `tailnet-policy` and the 12-digit hash, and says in plain words what each changed section is (for example: `grants`, who may reach what; `ssh`, who may sign in where as which user; `groups`, named sets of people; `externalTailnets`, other tailnets that share devices in). One plan per card.
3. The owner taps it.
4. A reviewing agent checks the tap, then starts `lab-tailnet-policy` with `action: apply`, `card_id` and `plan_hash`.
   - expect: `tailnet-policy: applied plan <hash> (...), card <ID>`. The tailnet refuses to save a policy whose `tests` or `sshTests` fail, so a passed apply means they passed.
5. Run `plan` again.
   - expect: `0 to add, 0 to change, 0 to destroy`.

## Raw runs this retires

- The Mac's `tofu-tailnet-policy.sh` ([Allow a command for agents](allow-a-command-for-agents.md), "The wrappers on the owner's Mac today"). When this job has passed once on its plan with a tap, removing it from the Mac is the owner's step (D-0041 rule 10).
