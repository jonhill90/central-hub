---
title: Run the dev lab redeploy from GitHub Actions on the agent box
status: draft
kind: manual
trigger: once, when the owner wants to start a dev rebuild from a GitHub button instead of an agent session; again if the runner or the environment is removed
runner: the owner, for the GitHub settings and the runner registration; an agent session on the agent box for the rest
outcome: the owner starts `lab-redeploy-dev` from the Actions tab on main; read-only actions run at once, the ones that change the dev lab wait for the owner's tap on the `dev-redeploy` environment
needs: the agent box with the `rebuild` wrapper working; the owner's GitHub admin rights on the repository
private-values: [runner-user, runner-registration-token]
files: [.github/workflows/lab-redeploy-dev.yml, hosts/ansible/roles/agent_box/]
last-tested: not yet run
superseded-by:
---

# Run the dev lab redeploy from GitHub Actions on the agent box

**Status:** draft. Written 2026-11-13 from the code in this change; the workflow has not run yet. It is the dev slice of D-0035 (proposed): rules 3 and 4 only. The record is not accepted, so nothing here touches prod, and no production wrapper or environment exists.

## What the workflow does

`.github/workflows/lab-redeploy-dev.yml` starts only by hand (`workflow_dispatch`), only from `main`, on a runner labelled `central-hub-box` that lives on the agent box. It has no `pull_request` trigger of any kind, so code in a PR never reaches the runner (rule 4; the gate check bans the dangerous triggers).

| Action | What it does | Approval |
|---|---|---|
| `diag` (default) | read-only look at the dev cluster | none |
| `log` | the newest run's stage lines | none |
| `up`, `rebuild`, `teardown` | the box's `rebuild` wrapper, dev VMs 250-257 only | the owner, on environment `dev-redeploy` |

The runner's user can run only the `rebuild` wrapper, with those five arguments, through sudo as the keys user. It never sees a key. The wrapper itself refuses anything outside dev.

## What only the owner can do

These are repository settings and a registration, so they are the owner's. Do them in this order. Step 1 comes first because a workflow that names an environment which does not exist makes GitHub create it with no protection.

1. Create the environment `dev-redeploy`: repository Settings, Environments, New environment. Add the owner as required reviewer, tick "Prevent self-review" off (the owner is the only person), and under Deployment branches choose "Selected branches" with `main` only.
   why: the tap is the approval channel (D-0035 rule 3); a branch limit keeps a branch's copy of the workflow from using it.
   expect: the environment lists one required reviewer and one allowed branch.

2. Settings, Actions, General: leave "Fork pull request workflows" at their strictest, and keep the default workflow token read-only.
   expect: both read as before; this workflow asks for `contents: read` only.

3. Register the runner by hand on the box, as the runner user, never as the keys user: Settings, Actions, Runners, New self-hosted runner, Linux x64. Give it the label `central-hub-box` and run the registration commands GitHub shows. The registration token is single-use and short-lived; it is never written down here or in a file.
   why: registration is a human act (D-0035 rule 8); the runner's own software comes from GitHub's release and its pin is checked on the box.
   expect: the runner shows Idle in Settings, Actions, Runners with the label `central-hub-box`.

4. Accept D-0035 and D-0030 when the owner is ready. This slice runs without them for dev, but the record is what makes prod work possible.

## What an agent does on the box

1. Set `agent_box_runner_user` in the private inventory (for example a user named for its job) and run the `agent_box` role from the Mac or the box: it makes the user with no extra groups and adds the sudoers lines for the wrappers marked `runner: true`.
   expect: `failed=0`; `sudo -l -U <runner-user>` lists only `rebuild.sh up`, `rebuild`, `teardown`, `log` and `diag` as the keys user.

2. After the owner has registered the runner, start the workflow with the default action.
   expect: the `read` job runs `diag` and ends green.

3. Start it with `rebuild`, the owner taps approve.
   expect: the run reaches `all stages passed`, as in the [one-command rebuild runbook](rebuild-k8s-layer-with-one-command.md).

## Not built yet

- The prod environments (`prod-redeploy`, `lab-teardown`) and the per-layer actions behind them. They need prod wrappers on the box and D-0035 accepted, with its preconditions (rule 5: a fresh restic snapshot with a passing restore check, the firewall configuration saved off the box, and the box's own route not depending on what is destroyed).
- Capping and logging beyond the wrapper's own run log (rule 6).
