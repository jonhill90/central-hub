---
title: Set up the owner's desktop VM
status: draft
kind: manual
trigger: once, when the owner wants a desktop in the lab to sign in to apps by hand; again after the VM is rebuilt
runner: an agent session on the agent box (the `desktop` wrapper), with the owner's two Mac steps `desktop-on` and `desktop-off` around each apply or destroy
outcome: one AlmaLinux 10 VM on VNet dev runs Xfce and xrdp, the owner signs in with an RDP client, and the VM holds no lab keys and no agent credentials
needs: the agent box; the agents' Proxmox token with rights on pool `desktop` only while the apply runs (`desktop-on`, then `desktop-off`, from the Mac); template 9001; a free dev address; the private inventory group `desktop`
private-values: [desktop-name, desktop-address, desktop-rdp-source, desktop-ssh-key]
files: [hosts/ansible/roles/agent_box/files/desktop.sh, hosts/terraform/home/bootstrap/agent-access.sh, hosts/terraform/home/desktop/, hosts/ansible/roles/desktop/, hosts/ansible/playbooks/desktop.yml]
last-tested: not yet run
superseded-by:
---

# Set up the owner's desktop VM

**Status:** draft. Written 2026-11-13 from the code in this change (tests offline only). Not run: the package names and the xrdp session below come from the EPEL 10 package lists and have not been installed on a VM yet.

**Isolation, by default (pick 219).** The agents configure the VM once and then keep no SSH login on it: the role removes the admin SSH key at the end of its first run, so later changes are a rebuild from teardown. This closes SSH only: the agents' token keeps AgentDev on `/pool/desktop` (VM.Config.Cloudinit, VM.PowerMgmt, VM.Config.Disk, VM.Clone), so a session could still add a cloud-init key and reboot the VM, or clone its disk. Taking those rights off after creation, or a narrower role for the pool, is the owner's decision (pick 219). Nobody but the owner sets the login password, at the Proxmox console, so it passes through no agent, transcript or keys folder. RDP is reachable from one address, not from VNet dev.

The owner asked for a desktop in the lab, to sign in over RDP or VNC and log in to apps by hand (2026-11-13 05:04 UTC). It is a separate VM so what the owner types never sits beside the agents' keys.

| Piece | Where |
|---|---|
| VM | `hosts/terraform/home/desktop`: one VM with an ID from 400-499 (STD-0001), on VNet dev, cloned from template 9001 into pool `desktop` (so the agents' rights survive a teardown, as pool `dev`'s do) |
| Software | role `desktop`: EPEL and CRB, the Xfce group, `xrdp`, `xorgxrdp`, Firefox, a login user without sudo and with its password locked, `.xsession` running `startxfce4`, firewalld accepting 3389/tcp from one address only, and the admin SSH key removed at the end |
| Playbook | `playbooks/desktop.yml`, hosts group `desktop` |
| Private values | the VM's name and address in `desktop.json` (the same shape as `home.tfvars.example`), the group in the inventory, `desktop_rdp_source` (the one address the owner connects from) |

## What is not built yet

- Nothing has been applied: the `desktop` wrapper is built (`plan|apply|configure|destroy`, on the box once `agent_box_desktop` is set in the private inventory), and it has not run.
- The Mac's `proxmox-agent-access.sh` must pass `desktop-on` and `desktop-off` through to `agent-access.sh` on the host. That script is the owner's, so the edit is too; until it is made, run `agent-access.sh desktop-on` and `desktop-off` as root on the host.
- An OPNsense rule that lets the owner's device reach 3389 on VNet dev. It stays the owner's: a firewall change needs the owner's words.

## Steps

1. The owner gives the agents rights on the pool for this run, on the Mac: `proxmox-agent-access.sh desktop-on`.
   why: the owner picked "No rights after build" (pick 219), so the agents hold none between runs.
   expect: `agent-access: done (node <node>, desktop-on)`.

2. Plan the VM from a session on the box: `desktop plan`.
   expect: `1 to add`: one VM, ID in 400-499, bridge `dev`, in pool `desktop`.

3. Apply it: `desktop apply`, then set up the VM: `desktop configure`.
   expect: `failed=0`; the VM answers on SSH as the admin user until the role removes its key at the end of the run.

4. The owner takes the rights away again, on the Mac: `proxmox-agent-access.sh desktop-off`.
   why: no agent keeps a way into the VM where the owner will type passwords.
   expect: `agent-access: done (node <node>, desktop-off)`; `pveum acl list` shows no entry for `/pool/desktop`.

5. The owner opens the VM's console in Proxmox (VM, Console). It asks "Set the password for owner."; the owner types a password twice. No one else sees it.
   expect: the prompt returns to a login; `/var/lib/desktop/password-set` exists and xrdp starts.

6. The owner connects with an RDP client to the VM's address, port 3389, as user `owner`, from the address in `desktop_rdp_source`.
   expect: an Xfce session.

## If it fails

- `dnf` cannot find the `Xfce` group or `xrdp`: EPEL 10 or CRB is not enabled, or the package set changed. The task `desktop | EPEL and CRB are on` and the next one name the step.
- The console shows a login prompt and never asks for the password: `desktop-set-password.service` did not run (the marker exists already, or getty took tty1). Check `systemctl status desktop-set-password` from the console as root, which is locked; rebuild the VM from teardown instead.
- The RDP client is refused: the owner has not set the password yet (xrdp waits for the marker), or the connecting address is not `desktop_rdp_source`.
- The RDP client connects and drops to a blank screen: `~owner/.xsession` or SELinux. Check `journalctl -u xrdp-sesman` on the VM.

## Exit

`desktop-on`, then `desktop destroy` (tofu destroy with this folder's state), then `desktop-off`. The VM holds nothing the rest of the lab needs.
