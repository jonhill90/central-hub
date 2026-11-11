---
title: Rebuild c1 on its permanent choices and restore its apps from backup
status: proposed
date: 2026-11-11
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Rebuild c1 on its permanent choices and restore its apps from backup

## What and why

c1 was built by agents who chose as they went, and `hosts/AGENT-PICKS.md` lists those picks. The owner said on 2026-11-08 at 19:01 UTC that card answers taken as the recommended option count as agent picks too. c1 now permanently hosts home apps (2026-11-08, 23:07 UTC). The owner also asked that central-hub can rebuild the lab from this repository alone (2026-11-08, 07:30 UTC).

This change tears c1 down and rebuilds it from central-hub `main` on the choices the owner made on 2026-11-10 and 2026-11-11. It restores the app data from the off-box backup, then walks the re-check list. When it is done, every pick a choice touches is either kept by the owner's answer or changed. The whole run is rehearsed on dev (VLAN 30, VM IDs 250 to 257) before it touches prod.

## The choices it builds on

All were answered on cards in the planning chat. The times are UTC.

| # | Decision | The owner's answer | What changes in code |
|---|---|---|---|
| P0 | Hardware | Today's one Proxmox host now, move to new machines later (11-11 02:37) | None. The move later is another run of this spec. |
| P1 | Install method | R1: kubeadm by this repository's Ansible. Talos is a later project (11-10 21:00) | None. `rebuild-k8s.sh` already builds R1. |
| P2 | Node OS | AlmaLinux 10, which follows from R1 (pick 24) | None |
| P4 | Naming | Keep c1 and its labels (11-09 01:10) | None |
| P5 | Node layout | 1 control plane + 1 worker (11-11 03:10) | None. VMs 200 and 201 are that layout today. |
| P6 | App storage | Keep today's local-path storage, and test a data-only VM disk after this rebuild (11-11 02:38) | None in this change. The data-disk test is a later change. |
| P9 | Keycloak realm | `home` (11-11 03:12) | `k8s_identity_realm` and every place that names realm `lab`: clients, issuer URLs, Grafana and Argo CD sign-in |
| P11 | Root CA key | First "the Mac only" (11-11 03:13), then moved with the rest of the controller's work to the agent box (11-11 04:11) | The lab PKI runbooks name the agent box as the key's home |
| P13 | Tailnet or public | Tailnet only; public later, per app (11-11 03:10) | None |

How the rebuild is run (re-asked 11-11, 03:13 to 03:15):

1. Scope: the Kubernetes layer only, as now.
2. One script now (`hosts/rebuild-k8s.sh`), with a pipeline engine later.
3. Prove it with R1 first. This is the P1 answer.
4. Every dev rebuild restores a copy of prod's newest backup, read-only from Azure.
5. Every dev rebuild also restores Keycloak's database.
6. The same-day backup test happens at the prod rebuild: step 3 below takes a fresh backup and checks its restore.

Other answers this change relies on:

- **Apps:** auto-sync stays on for every app, with prune off (11-10 02:50).
- **Controller:** everything the Mac does moves to the agent box (VM 258), credentials included (11-11 04:10 and 04:11). That move is its own change. This rebuild runs from whichever controller has passed one dev rebuild by the time of step 5.
- **Agent rights for the prod rebuild:** agents get Proxmox rights on VMs 200 and 201 (11-11 04:08), and the agent box may reach port 22 on them (11-11 04:09). Both arrive by their own PRs and are applied only after the owner's go.
- **State files:** OpenTofu state encryption and off-box copies of state are restarted, to be done before the prod rebuild (11-11 04:07).

## Before it starts (each must be true)

1. Backups use the self-rolling certificate identity. Done: the drill passed on 2026-11-10 at 02:47 UTC.
2. Postgres is backed up with `pg_dumpall`, not with a live file copy. Done: the dev restores in runs 21 and 22 used the dump.
3. A restore test passes into a scratch folder that doesn't fill the OS disk.
4. OpenTofu state is encrypted, and a copy is kept off the controller.
5. Realm `home` is merged and rehearsed on dev.
6. This spec is accepted.
7. The re-check list is written: every pick tied to a choice above, plus the orphan sweep's "decisions built on wrong premises" item.

## Out of scope

- **Other layers:** Proxmox, OPNsense, the tailnet, public DNS and the backup target. The one command rebuilds the Kubernetes layer only.
- **Hardware:** buying new hardware. Moving to it later is another run of this spec.
- **Storage:** changing app storage. The data-disk test comes after this rebuild.
- **Controller:** moving the controller to the agent box. That is its own change, as above.
- **Secrets:** picking a secrets tool, and rotating secrets. Both wait for the tool.
- **Other work:** new apps, the Keycloak version bump, and the Activation gate items for other clusters.

## Steps

1. **Dev rehearsal, twice clean.**
   - Build on dev from `main` with the answers above.
   - Restore a copy of prod's newest backup, Keycloak's database included.
   - Run the automated checks below.
   - Two clean runs in a row, each with a worklog in the agent notebook.
2. **Freeze.** Record the commit the second clean run used. Prod builds from that commit.
3. **Prod, fresh backup.** Run a backup now and check its restore. This is the same-day backup test.
4. **Prod, tear down.** A targeted destroy of the node VMs only. The backup target and DNS stay.
5. **Prod, build.** Build from the frozen commit, from the controller, under the guard that waits for the owner's go.
6. **Prod, restore.** Restore app data and Keycloak's database from the snapshot in step 3, then let Argo CD sync.
7. **Prod, checks.** Run the checks below, then walk the re-check list with the owner and record each pick as kept or changed.
8. **Runbooks.** A step that changed updates its runbook in the same PR.

## Acceptance criteria

### Automated

- [ ] `hosts/rebuild-k8s.sh` runs OpenTofu, the node build, the storage, the restore, Argo CD with its root app, the apps and the gateway, in order, and stops at the first failure.
- [ ] The only hand steps left are the one-time bootstraps named in the rebuild runbook, each marked as a bootstrap.
- [ ] `tofu plan` for the node VMs shows no change after the build.
- [ ] A second run of the node playbook reports `changed=0`.
- [ ] All nodes are Ready, and no pod is outside Running or Completed.
- [ ] Secrets are encrypted at rest, proven by reading etcd.
- [ ] Every Argo CD app is Synced and Healthy.
- [ ] The Keycloak realm is `home`, and no name in the cluster still says `lab`.
- [ ] A backup and a restore test pass on the rebuilt cluster with the certificate identity.
- [ ] central-hub CI is green on the frozen commit.

### Manual (what the owner checks)

- [ ] You sign in to each home app through Keycloak realm `home` and see your data.
- [ ] The apps open by name from your devices, with the lab certificate trusted and no warning.
- [ ] Every pick on the re-check list is marked kept or changed, and none is left open.

## Exit

The old cluster's data is in Azure: restic, 7 daily snapshots kept, and 7 days of soft delete. If the prod build fails, rebuild from the commit before this change and restore the same snapshot.

## Points to (read when)

- `hosts/rebuild-k8s.sh` and `docs/runbooks/rebuild-k8s-layer-with-one-command.md`: read when running steps 1 and 5.
- `docs/specs/2026-10-home-lab-and-c1.md`: read for the first build, which this one replaces.
- `docs/specs/2026-11-lab-pki.md`: read when moving the root CA key (P11).
- `hosts/AGENT-PICKS.md`: read when writing the re-check list.

## Decision log

- 2026-11-09: drafted before the owner's answers, so they could drop straight in.
- 2026-11-11: filled in from the owner's answers on 2026-11-10 and 2026-11-11.
