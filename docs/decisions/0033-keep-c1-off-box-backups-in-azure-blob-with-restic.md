---
id: D-0033
title: Keep c1's off-box backups in one Azure Blob container with restic, reached only through Entra ID, and leave the long-term credential to its own decision
status: proposed
date: 2026-11-09
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0011, TASK-0194]
supersedes: []
superseded-by:
revisit-when: the credential decision in TASK-0202 is made; a SAS renewal is missed and a nightly backup fails; the storage account costs more than a few dollars a month; a second cluster needs off-box backups; the home's public address changes often enough to break backups; or restic or Azure changes the repository format, the SAS limits or the prices this record uses
---

# Keep c1's off-box backups in one Azure Blob container with restic, reached only through Entra ID, and leave the long-term credential to its own decision

## Context and Problem Statement

c1 holds permanent home apps, and it is not to be rebuilt until it has backups and a proven restore (TASK-0194). Before 2026-11-09 the only copy of its data was the nightly Proxmox backup on one old disk in the same PC (TASK-0139).

On 2026-10-16 at 05:49 UTC the owner chose Azure Blob as the off-site backup target. On 2026-10-17 the owner put Azure work on hold. On 2026-11-08 at 23:42 UTC the owner asked for the Azure storage to be built with no raw keys, moving toward a managed or workload identity so that neither people nor agents see a plaintext secret. On 2026-11-09 at 03:33 UTC the owner gave the agents' service principal Owner on the subscription, on the condition that nothing billable is added beyond the backup storage account.

The agents then built it on 2026-11-08 and 2026-11-09 as agent picks 144 to 152 and 179 to 182 in `hosts/AGENT-PICKS.md`, with no decision record. This record writes down what was built and why, with tonight's drill as evidence, so the owner can accept, change or reject it. Every choice below except the target is an agent pick.

## Decision Drivers

- **A copy off the Proxmox host** that survives losing the PC, its disks or the house's power.
- **Proven restores**, not just backups: the copy must come back, tested on a schedule.
- **No raw keys** (the owner, 2026-11-08 23:42 UTC): no account key, no long-lived secret on the nodes.
- **Cheap**, and nothing billable beyond the storage account (the owner, 2026-11-09 03:33 UTC).
- **Replaceable** (CLAUDE.md rule 6): the target and the tool can each be swapped without losing the backups.

## Considered Options

1. **restic to one Azure Blob container**, from systemd timers on the nodes (as built).
2. **restic to another provider's object store** (an S3-compatible service): same tool, different target.
3. **A second disk or NAS in the house:** off the Proxmox host, but not off-site.
4. **Velero to object storage:** Kubernetes-level backups instead of node-level ones.

## Decision Outcome

**Proposed: option 1, as built.** The target is the owner's choice of 2026-10-16. The tool, the account settings and the credential are agent picks.

Option 2 gives the same protection, but the owner already chose Azure and its identity is the one the "no raw keys" path leads to (TASK-0200). Option 3 does not survive losing the house. Option 4 was ruled out in pick 144, because Velero's file-system backup does not support hostPath volumes and c1's Local Path Provisioner makes hostPath volumes.

### Rules

1. **One repository.** c1's etcd bundle and every volume folder go to one restic repository in container `c1-backup` of a storage account in resource group `rg-c1-backup`. That account is built only from `hosts/terraform/azure/backup`. The account's name is a private value.
2. **No keys.** Shared key access stays off, so no account key or key-signed SAS works. Every request carries an Entra ID token or a user delegation SAS that an Entra ID identity signs.
3. **One door.** The data endpoint answers only the home's public address, with no bypass. Managing the account works from anywhere.
4. **Retention and proof.** The policy keeps 7 daily, 4 weekly and 6 monthly snapshots. A restore test runs every Sunday without touching the live system. The playbook's `drill` tag backs up and restores on request.
5. **Spend.** This storage account is the only billable Azure resource. Anything else in Azure needs the owner's approval first.
6. **Interim credential.** Until TASK-0202's decision, the nodes hold a user delegation SAS for the container only, valid for at most 7 days. An agent lane renews it from the owner's Mac at least every 5 days.

### Not decided here

- **The long-term credential.** The options are to keep the SAS, use a backup-only service principal, use an Azure Arc managed identity, or use workload identity federation. They are parked in TASK-0202 for the owner, and federation is part of TASK-0200. Only the last two meet the owner's request of 2026-11-08 in full.
- **Protection against deletion.** The SAS can delete, because restic's `forget` and `prune` need to. Soft delete keeps deleted blobs and containers for 7 days. There is no versioning or immutability policy: research on 2026-10-16 proposed a short lock, and pick 180 left it out because it can't be undone before its date. If the owner wants one, a separate prune-only credential is the usual pair for it (model).
- **The access tier.** The account uses Hot, because restic's weekly check and prune read data back. Cool or Cold cost less to store but charge to read and to delete early (see Cost).
- **Proxmox's own backups.** These stay with TASK-0139.

### Consequences

- Good: a copy off the host exists, and on 2026-11-09 a restore of both etcd and the volumes was proven from it (see Evidence).
- Good: no one holds a key that opens the account. The SAS can't outlive 7 days, and Azure ties each SAS to the identity that signed it.
- Good: the repository is encrypted on the node before it leaves, so the storage account holds only ciphertext.
- Bad: the SAS needs renewing every 5 days. A missed renewal stops the nightly backups after 7 days, and no alert says so yet.
- Bad: if the home's public address changes, backups fail until `tofu apply` sets the new address. A restore from anywhere else needs that address added first.
- Bad: one region, LRS. That's three copies in one Azure datacenter, which is enough as the second copy of data whose first copy is at home (pick 180).

### Cost

These prices are from the Azure Retail Prices API, read on 2026-11-09, for East US 2, General Block Blob v2, LRS:

| Meter | Hot | Cool | Cold |
|---|---|---|---|
| Data stored, per GB per month | $0.0184 | $0.01 | $0.0036 |
| Write operations, per 10,000 | $0.05 | $0.10 | $0.18 |
| Data retrieval, per GB | none | $0.01 | $0.03 |
| Early delete, per GB | none | $0.01 | $0.0036 |

The repository's size has not been measured yet. Read it from the account's `UsedCapacity` metric before choosing a tier. As a model, 50 GB on Hot is about $0.92 a month to store, plus a few cents of operations for one nightly run. Moving to Cool saves under $0.50 a month at that size, and adds charges each time restic reads data back (model).

### Exit path

restic's repository format is documented and doesn't depend on the backend. `restic copy` moves snapshots into a new repository on any target restic supports, such as S3, SFTP, a REST server or a local disk. Any blob copy tool can also move the container's objects as they are. The role reads only `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and the target's credentials. So moving off Azure means three steps:

1. Copy the repository to the new target.
2. Point the env file at it and set `k8s_backup_azure_sas: false`.
3. Run `tofu destroy` in `hosts/terraform/azure/backup` once the copy has passed a drill.

Leaving restic means restoring the newest snapshots with restic and backing them up again with the new tool.

## More Information

- **Evidence:** no research batch of its own. This record rests on the owner's statements above, the agent picks, and these measurements:
  - **CI.** On every PR the CI job `backup` runs the same scripts against etcd 3.7.0 and a local restic repository, including a missing-key and a damaged-pack case.
  - **First drill.** On 2026-11-09 the first drill on c1 against Azure found two faults, and both were fixed in code before the second drill:
    - Two nodes initialised the repository at the same moment, which left two keys (fixed with a once-only init and one node at a time).
    - The volume restore test failed on SELinux labels (#113).
    - The repository was then wiped and made again at 04:44 UTC.
  - **Second drill.** At about 05:09 UTC, after a full apply at `db8b158`:
    - Backups OK, and `restic check` clean.
    - The etcd restore test passed with revision 3014172 and 1072 keys under `/`.
    - The volume restore test passed on 2 folders.
- **Runbooks:** [back-up-c1-off-box.md](../runbooks/back-up-c1-off-box.md), [test-etcd-restore.md](../runbooks/test-etcd-restore.md), [give-agents-access-to-azure.md](../runbooks/give-agents-access-to-azure.md).
- **Code:** `hosts/terraform/azure/backup/`, `hosts/ansible/roles/k8s_backup/`.
- **Agent picks:** 144 to 152 (the backup role) and 179 to 182 (the Azure side) in `hosts/AGENT-PICKS.md`.
