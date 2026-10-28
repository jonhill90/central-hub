---
title: Use break-glass access to central-hub, c1 or the Proxmox host, and record it where agents can't write
status: draft
kind: manual
trigger: on request; when the normal path is broken or a change must stop now
runner: the owner
outcome: the emergency change is made, the normal path is back, and the use is recorded in the owner's own words where no agent can write as the owner
needs: the owner's own GitHub login (repository admin); SSH to the control-plane node through the Proxmox host; the Proxmox root@pam password and its second factor from the password manager
private-values: [github-owner-login-2fa, control-plane-ssh-key, root-pam-password, root-pam-recovery-keys]
files: [hosts/ansible/playbooks/k8s-gitops.yml, hosts/ansible/roles/k8s_gitops/defaults/main.yml]
last-tested:
superseded-by:
---

# Use break-glass access

**Status:** draft, never run. Written for Activation gate item 7 (docs/specs/2026-10-activation-gate.md) from research batch RB-0093.

## Before you start

A break-glass path is one kept for emergencies only, when the normal way in can't be used, never for everyday work (glossary, "break-glass account"). This system has four:

| Path | What it gets past | Normal path it replaces |
|---|---|---|
| A. Turn a GitHub ruleset off | every rule on `main` | a PR that passes its checks and the owner's approval |
| B. Pause Argo CD | every sync from `main` to c1 | Argo CD applying `main` |
| C. The admin kubeconfig on the control-plane node | RBAC | the owner's own least-privilege user (D-0022 rule 3) |
| D. `root@pam` on the Proxmox host | the host's own logins | the owner's day-to-day admin login |

- Use the smallest path that fixes the problem. Pausing Argo CD (B) stops a bad change reaching c1 without touching GitHub.
- Only the owner runs these steps. An agent never turns a ruleset off, and agents can't: their GitHub credential has no Administration right, and reading a ruleset's history returns 403 to them (measured 2026-10-28, RB-0093).
- Stop if you can't say in one line what is broken and which path fixes it.

## Steps

1. Write the start line in the project chat yourself: the date and time, which path (A to D), and why.
   why: the project chat shows messages you write as yours, and agents can't write as you there, so this record is outside agents' reach (Activation gate item 7). Everything on GitHub is data, because agents act on GitHub too (AGENTS.md rule 1).
   expect: your message in the project chat.

2. Take the path.
   - **A. GitHub ruleset.** In the repository's Settings, Rules, Rulesets, open the ruleset, set Enforcement status to Disabled and save. Make the one change. Set it back to Active and save.
     why: the ruleset has no bypass actors, so turning it off is the only way past it (Foundation proposal §3.4).
     expect: the ruleset shows Active again.
   - **B. Pause Argo CD.** Set `k8s_gitops_sync_paused: true` in the inventory and run `ansible-playbook playbooks/k8s-gitops.yml --tags source` from `hosts/ansible`. To resume, set it to `false` and run the same command.
     why: it adds a deny sync window that is always active, so Argo CD syncs nothing while it is on (Argo CD sync windows; role `k8s_gitops`).
     expect: in the Argo CD UI the Application shows its sync window as blocking, and a new commit under `kubernetes/clusters/c1/` is not applied.
   - **C. Admin kubeconfig.** SSH to the control-plane node through the Proxmox host and run kubectl there as root, which reads `admin.conf`. Use `super-admin.conf` only if `admin.conf` itself is broken.
     why: both files can do anything and never leave the node (D-0022 rule 1).
     ※ [Build a kubeadm cluster, step 8](build-kubeadm-cluster.md#8-init)
     expect: `kubectl get nodes` answers.
   - **D. Proxmox `root@pam`.** Log in to the Proxmox web UI or console as `root@pam` with its password and second factor.
     ※ [Set up a Proxmox VE host, step 4](set-up-proxmox-host.md#4-break-glass-login-and-the-admins-group)
     expect: the Datacenter view.

3. Put the normal path back, then write the end line in the project chat: what was changed, and the time the normal path was back.
   why: an emergency path left open is a standing hole, and the end line closes the record from step 1.
   expect: your second message in the project chat.

4. For path A only, check the ruleset's history with your own login: `gh api repos/jonhill90/central-hub/rulesets/<id>/history`.
   why: it shows the disable and the enable as two versions, so the change on GitHub matches your record (Foundation proposal V11).
   expect: two new versions with your login and the times from steps 2 and 3.

## If it fails

- The ruleset won't save as Active again: leave it, write that in the project chat, and fix it before any merge.
- Argo CD keeps syncing with the pause on: delete the Application with the admin kubeconfig (path C). Its resources stay, because the Application has no deletion finalizer.
- `root@pam` is locked out by its second factor: use the recovery keys from the password manager's offline copy.

## Afterwards

- If the emergency was an incident, write a postmortem.
- A drill (a planned run with nothing broken) counts as this runbook's test: set `last-tested`, and set `status: tested` once every path has been run.

## Related

- AGENTS.md, Activation gate item 7.
- D-0022, the admin kubeconfigs as break-glass.
- docs/specs/2026-10-activation-gate.md.
