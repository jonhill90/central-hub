---
title: Set up the owner's desktop VM
status: draft
kind: manual
trigger: once, when the owner wants a desktop in the lab to sign in to apps by hand; again after the VM is rebuilt
runner: an agent session on the agent box, once the desktop wrapper exists (not built yet)
outcome: one AlmaLinux 10 VM on VNet dev runs Xfce and xrdp, the owner signs in with an RDP client, and the VM holds no lab keys and no agent credentials
needs: the agent box; the agents' Proxmox token with rights on the new VM's ID; template 9001; a free dev address; the private inventory group `desktop`
private-values: [desktop-name, desktop-address, desktop-password-file, desktop-ssh-key]
files: [hosts/terraform/home/desktop/, hosts/ansible/roles/desktop/, hosts/ansible/playbooks/desktop.yml]
last-tested: not yet run
superseded-by:
---

# Set up the owner's desktop VM

**Status:** draft. Written 2026-11-13 from the code in this change (tests offline only). Not run: the package names and the xrdp session below come from the EPEL 10 package lists and have not been installed on a VM yet.

The owner asked for a desktop in the lab, to sign in over RDP or VNC and log in to apps by hand (2026-11-13 05:04 UTC). It is a separate VM so what the owner types never sits beside the agents' keys.

| Piece | Where |
|---|---|
| VM | `hosts/terraform/home/desktop`: one VM with an ID from 400-499 (STD-0001), on VNet dev, cloned from template 9001, no pool |
| Software | role `desktop`: EPEL and CRB, the Xfce group, `xrdp`, `xorgxrdp`, Firefox, a login user without sudo, `.xsession` running `startxfce4`, firewalld open on 3389/tcp |
| Playbook | `playbooks/desktop.yml`, hosts group `desktop` |
| Private values | the VM's name and address in `desktop.json` (the same shape as `home.tfvars.example`), the group in the inventory, the password file |

## What is not built yet

- The wrapper that applies the VM from the box (`desktop plan|apply|destroy`, like `ci-runner`). Until then nobody applies this folder.
- Rights for the agents' token on the new VM's ID, and an OPNsense rule that lets the owner's device reach 3389 on VNet dev. A firewall change needs the owner's words.

## Steps (when the wrapper exists)

1. Plan the VM from a session on the box: `desktop plan`.
   expect: `1 to add`: one VM, ID in 400-499, bridge `dev`, no pool.

2. Apply it: `desktop apply`. The desktop playbook runs after it.
   expect: `failed=0`; the VM answers on SSH as the admin user.

3. Read the login password once, as the owner, from the password file on the box (made at the first run with random letters and digits, mode 0600, never printed in a log).

4. Connect with an RDP client to the VM's address, port 3389, as user `owner`.
   expect: an Xfce session.

## If it fails

- `dnf` cannot find the `Xfce` group or `xrdp`: EPEL 10 or CRB is not enabled, or the package set changed. The task `desktop | EPEL and CRB are on` and the next one name the step.
- The RDP client connects and drops to a blank screen: `~owner/.xsession` or SELinux. Check `journalctl -u xrdp-sesman` on the VM.

## Exit

`desktop destroy` (tofu destroy with this folder's state). The VM holds nothing the rest of the lab needs.
