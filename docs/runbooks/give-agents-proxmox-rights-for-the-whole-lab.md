---
title: Give agents Proxmox rights for the whole lab
status: draft
kind: manual
trigger: once, before agents rebuild lab layers other than dev from the agent box; again after VM 258, CT 259 or CT 900 is destroyed and made again, and after the token is made or renewed
runner: the owner, as root on the Proxmox host (an agent lane through the owner's Mac may run it on the owner's go)
outcome: user agentlab@pve and token agentlab@pve!lab may manage every guest on the host except VM 258 and CT 259, may only read CT 900, and may not change VNet dev
needs: root SSH to the Proxmox host; a central-hub checkout on main
private-values: [proxmox-host, proxmox-lab.env]
files: [hosts/terraform/home/bootstrap/agent-lab-access.sh]
last-tested: not yet run
superseded-by:
---

# Give agents Proxmox rights for the whole lab

The agents' first Proxmox user, `agent@pve`, reaches only the dev rebuild VMs ([agent-access.sh](../../hosts/terraform/home/bootstrap/agent-access.sh)). To rebuild the whole lab from the agent box, the owner picked "Everything on Proxmox" on 2026-11-13 at 05:08 UTC: every guest on the host, not the host install, and never VM 258 (the agent box) or CT 259. [agent-lab-access.sh](../../hosts/terraform/home/bootstrap/agent-lab-access.sh) makes a second user for that, `agentlab@pve`, and puts the limits in the token's own rights, so a bug in a wrapper can't cross them (pick 217 in [AGENT-PICKS.md](../../hosts/AGENT-PICKS.md)).

How the rights are laid out, and the Proxmox source that each part rests on:

- Role `AgentLab` (the same privileges as `IacOps`, the Terraform role) on `/vms`, propagated. Every guest ID gets it, one that exists now or one made later, so a create or a clone never waits for a per-ID ACL, and a destroy can't take the rights away from the next build. A pool ACL alone isn't enough: Proxmox checks a new VM's tags on `/vms/<id>` before the VM joins its pool ([qemu-server `API2/Qemu.pm`](https://git.proxmox.com/?p=qemu-server.git;a=blob;f=src/PVE/API2/Qemu.pm;hb=HEAD), `assert_tag_permissions` before `add_vm_to_pool`).
- `NoAccess` on `/vms/258` and `/vms/259`. An ACL on a deeper path replaces the roles that path inherits, and `NoAccess` is never trumped by a pool's roles ([pve-access-control `AccessControl.pm`](https://git.proxmox.com/?p=pve-access-control.git;a=blob;f=src/PVE/AccessControl.pm;hb=HEAD) `roles`, and `RPCEnvironment.pm` `compile_acl_path`). Proxmox drops a guest's ACLs only when that guest is destroyed, and the token can't destroy these two.
- `AgentLabAudit` (`VM.Audit`) on `/vms/900`. CT 900, the tailnet connector, has the `keyctl` feature and `/dev/net/tun` passed through, and Proxmox lets only `root@pam` set those ([pve-container `LXC.pm`](https://git.proxmox.com/?p=pve-container.git;a=blob;f=src/PVE/LXC.pm;hb=HEAD), `check_ct_modify_config_perm`). No token can make CT 900 again, so the token may not destroy it either: losing it would cut remote access with no way back from the box.
- `AgentLabUse` (`SDN.Audit`, `SDN.Use`) on `/sdn/zones/lab/dev`, the VNet the box sits on, under `AgentLab` on zone `lab`. An agent may rebuild the other VNets but not change or delete VNet dev, which Proxmox checks on `/sdn/zones/<zone>/<vnet>` ([pve-network `API2/Network/SDN/Vnets.pm`](https://git.proxmox.com/?p=pve-network.git;a=blob;f=src/PVE/API2/Network/SDN/Vnets.pm;hb=HEAD)). Zone `lab` itself can't be deleted while a VNet uses it ([`Zones/Plugin.pm`](https://git.proxmox.com/?p=pve-network.git;a=blob;f=src/PVE/Network/SDN/Zones/Plugin.pm;hb=HEAD), `on_delete_hook`).
- `AgentLab` without propagation on `/sdn` (the SDN applier), the firewall's two host bridges, storage `local-lvm` and `local`, and the node.

The rights reach every guest, so a guest someone adds by hand later is in reach too unless the script gets a `NoAccess` line for it. The host's own configuration (the `proxmox_*` playbooks) runs over root SSH and stays out of this token.

## Steps

1. Read the script at the commit you will run, on `main`.

   ```sh
   git -C central-hub fetch origin main && git -C central-hub checkout --detach origin/main
   less central-hub/hosts/terraform/home/bootstrap/agent-lab-access.sh
   ```

2. Run it as root on the host. Nothing is written on the host except users, roles and ACLs.

   ```sh
   ssh root@<proxmox-host> 'sh -s' < central-hub/hosts/terraform/home/bootstrap/agent-lab-access.sh
   ```

   expect: `agent-lab-access: done (node <node>)`. The script ends by asking Proxmox for the computed rights on `/vms/258`, `/vms/259`, `/vms/900` and VNet dev, and stops with `STOP` if any of them still allows more than it should.

3. Check the rights by hand once, as root on the host.

   ```sh
   pveum user permissions agentlab@pve --path /vms/258
   pveum user permissions agentlab@pve --path /vms/900
   pveum user permissions agentlab@pve --path /vms/200
   ```

   expect: no privileges on `/vms/258`; only `VM.Audit` on `/vms/900`; `VM.Allocate` and the `VM.Config.*` privileges on `/vms/200`.

4. Make the token only once the box has a wrapper that reads it, so it never sits unused on the box. The secret goes from the host straight into the box's keys folder as `/etc/agent-keys/proxmox-lab.env` (mode 0600, owner `keys`), in the same two lines as the dev token, and is never printed:

   ```text
   PROXMOX_VE_ENDPOINT=https://<Proxmox API name>:8006/
   PROXMOX_VE_API_TOKEN=agentlab@pve!lab=<secret>
   ```

   Mint it with `pveum user token add agentlab@pve lab --privsep 1 --expire <epoch 30 days on> --output-format json`, piped into the keys wrapper as [set-up-the-agent-box.md](set-up-the-agent-box.md) step 5 does for the dev token. Then run step 2 again: a privilege-separated token gets only its own ACLs, and the script adds them only once the token exists.
   expect: step 2 prints `done` again, and its checks now run against the token.

## Renew or revoke

Renew before the expiry: `pveum user token remove agentlab@pve lab`, then step 4. Revoke at once with the same `remove`. Run step 2 again after VM 258, CT 259 or CT 900 is destroyed and made again, because their limiting ACLs went with them.

## Exit

```sh
pveum user delete agentlab@pve
pveum role delete AgentLab; pveum role delete AgentLabUse; pveum role delete AgentLabAudit
pveum group delete agents-lab
```

Then delete `/etc/agent-keys/proxmox-lab.env` on the box.
