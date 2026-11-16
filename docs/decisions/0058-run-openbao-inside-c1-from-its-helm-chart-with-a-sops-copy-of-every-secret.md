---
id: D-0058
title: Run OpenBao inside c1 from its Helm chart in place of its own VM, with a SOPS copy of every secret and of the seal key so the store can be restored or reseeded
status: accepted
date: 2026-11-16
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0038, D-0050, D-0051]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: agents
  approved-at: 2026-11-16T05:10:01Z
  approved-commit: 6c440458305311dec3162e40aa4718895c4e3759
  approval-ref: the orchestrator thread's message to the Plan thread of 2026-11-16T05:10:01Z recording the reviewer's clearance (05:07:51Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNPe5RgyyXQfPSkPjiRsByrJ) and the passes of Councils A (05:07:17Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNRF8Z8DQndMeqCqdtgCV4LU), B (05:07:34Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNRriqAZJC2mWMqm4NWjRy8M) and C (05:07:36Z, cmsg_01X43rfNYp4H1dL1V2dkfkwN9aNucvGLEWQxmE1yMR2HbA) for this record as merged at 6c44045, each saying acceptance by the agents' pass under D-0042 rule 3 is fine; it reached the Plan thread as a thread relay, which carries no message id
  approval-names: "each pass names D-0058 and commit 6c440458305311dec3162e40aa4718895c4e3759, the squash merge of PR #381, whose tree (d4a1118) equals that of head d328a22ab161643f621241a0a49a61532ca51d0e, which the reviewer and the three councils had passed as proposed"
  check: "approved-by is agents under D-0042 rules 1 and 3, because the place and the SOPS balance are the owner's words of 2026-11-16 03:42 and 03:48 UTC and the rest goes on the agents' pass (this record's \"How this record is accepted\" line); the merge verdict's amend pattern finds no hit in this record, so D-0042 rule 11 does not send it to the owner; the records it waits on (D-0038, D-0050 and D-0051) are accepted. The Plan thread read the four passes by id at 05:08Z and the orchestrator's pass record at 05:10Z; the record names this record and the commit. This PR changes only this record's status, date and accepted-evidence and its row in the decisions index, which the reviewer checks against 6c44045 (D-0001). Acceptance builds nothing: the owner's taps this record keeps (the prod seal key, each restore, the box age key's wider right) stay at their own steps"
  merged: "PR #384 squash-merged at head 5d90396 as 17b1ffe, whose commit time is 2026-11-16T05:20:58Z (GitHub's merged_at for the PR is 05:20:59Z); #384 was the acceptance PR on its own, after #381 merged the record as proposed, so approved-commit is #381's merge commit 6c44045, not #381's passed head d328a22 (the merge check compares an acceptance PR's change with its approved commit's, and the passes for acceptance named 6c44045); the follow-up PR that adds this line changes only accepted-evidence (D-0001)"
revisit-when: the EliteDesks run c1 on bare metal (three Raft replicas, and each node's own TPM for the seal); a c1 rebuild cannot restore the store before its apps need it; the seal key's home changes; or a job that must run while c1 is down needs a secret that is not in a file on the box
---

# Run OpenBao inside c1 from its Helm chart in place of its own VM, with a SOPS copy of every secret and of the seal key so the store can be restored or reseeded

## Context and Problem Statement

D-0038 put OpenBao, the lab's secrets store, on a VM of its own on Proxmox in each environment (rule 2), because a store inside c1 "can't hold c1's own rebuild secrets and must be restored before anything on c1 can start" (D-0038, Decision Outcome). D-0038 was accepted on the owner's tap of 2026-11-15 04:51 UTC. No store VM was ever built: the agent box holds no secrets-store settings, and neither VM 550 nor VM 500 exists (read from the box, 2026-11-16 03:45 to 03:48 UTC). So moving the store off a VM is a change of design only, and nothing has to be removed from the lab.

On 2026-11-16 the owner asked that the infrastructure balance VMs against Kubernetes rather than give every service a VM (messages of 03:29 and 03:31 UTC), and then decided that OpenBao comes off its VM and runs in Kubernetes (message of 03:42 UTC, cmsg_01X43rfNYp4H1dL1V2dkfkwNMWGpQDNG8VEGuDiTM2GKrn). At 03:48 UTC they added that it be balanced with SOPS so it restores easily, as in their earlier project (cmsg_01X43rfNYp4H1dL1V2dkfkwNAQiLHkK7oeps6D8LrDNu2F). In that project, as the owner described it, the store could be restored from SOPS. This record writes that decision down and changes the D-0038 rules it touches. D-0038 is accepted, so its own text changes only through CORRECTIONS lines (D-0006) that point here.

D-0038 rule 11 already keeps outside OpenBao what a rebuild needs before OpenBao starts: the private bootstrap files, in SOPS (rule 10). So the store in c1 does not have to hold c1's rebuild secrets. What it cannot serve is a job that must run while c1 is down.

## Decision Drivers

- **The owner's decision** of 2026-11-16 03:42 UTC: OpenBao runs in Kubernetes, not on its own VM.
- **Hardware.** No VM per service. The planned store VMs (550 for dev, 500 for prod) are not built.
- **Rebuild with no person** (the end goal): the store in c1 must come back from its snapshot, with its seal key, as part of a c1 rebuild.
- **Easy restore, balanced with SOPS** (the owner, 03:48 UTC): the store comes back from its snapshot, or, when no snapshot is usable, is reseeded from SOPS.
- **Least privilege, as far as the move allows** (D-0038 rule 6).

## Decision Outcome

OpenBao runs inside c1 from OpenBao's Helm chart, and SOPS holds a copy of every secret and of the seal key. The rules below replace D-0038 rules 1 to 4 and 11, replace part of rule 8 (rule 6 below), and amend rules 5, 6 and 10. D-0038 rules 7, 9 and 12 stay as written.

### Rules

1. **Version and source** (replaces D-0038 rule 1). OpenBao 2.7.2 from chart `openbao` 0.30.6 (published 2026-10-27, appVersion v2.7.2), the newest chart at least two weeks old (STD-0003 rule 1; 0.30.7 came out on 2026-11-06), pinned by version and checked against its SHA-256 from the chart repository's index, and installed the way every other c1 app is. MPL-2.0. External Secrets stays on its chart.
2. **Where** (replaces D-0038 rule 2). Namespace `openbao` in c1, on dev's cluster and on prod's. No store VM is made. The VM ID range 500 to 599 is not used for it.
3. **Seal** (replaces D-0038 rule 4). Seal `static`, its 32-byte key in a file on each c1 node, in a local volume that OpenBao's pod mounts read-only and that sits outside the folders c1's nightly backup copies. A c1 rebuild writes the file there from the key's SOPS copy (rule 8). The key's SOPS copy lives in the agent box's keys folder and the box's encrypted off-box bundle, and there is no copy on the Mac, as D-0038 rule 4 has it. As D-0038 rule 4 says, this departs from the owner's yes of 2026-10-15 (root keys in their password manager plus an offline copy): no copy of the seal key is in the owner's hands, and that stays so here. No plain copy goes in git, a log or a chat. Putting the prod key on the nodes is a secrets step, so it waits for the owner's tap at install (D-0042 rule 6).
4. **Storage and address** (replaces D-0038 rule 3). Integrated storage (Raft) on local-path volumes (D-0051), in the chart's HA mode with Raft turned on, because its standalone mode stores in a different backend where Raft snapshots don't apply (chart 0.30.6 values.yaml: `standalone` at line 958 stores in `pebbledb`, line 982; `ha.raft` at line 1025 stores in `raft`, line 1052). One replica while c1 has one worker, and three once c1 has three nodes. It is reached by name on 443 like every c1 app. Whether TLS ends at c1's gateway or at OpenBao's own listener is an agent pick of the rework. On prod the certificate comes from the lab CA (D-0028).
5. **Who reads what** (amends D-0038 rule 6). The store's manager stays as D-0038 rule 6 has it. ESO logs in with OpenBao's Kubernetes login from inside c1, bound to ESO's service account, with the policy D-0038 rule 6 gives it. So the `jwt-c1` mount and the rebuild's AppRole, which only re-registered c1's key with a store outside c1, go away. A box wrapper gets its own AppRole as rule 6 says only when its job never has to run while c1 is down. The jobs that rebuild or repair c1 or the layers under it read their secrets from files in the box's keys folder, mode 0600, as they do now: the c1 rebuild, Proxmox, the firewall, the tailnet connector and the store's own restore.
6. **Backups** (replaces D-0038 rule 8's first sentence and its VM-only parts). A CronJob in c1 takes a Raft snapshot every hour and keeps 48 on a volume of its own. The chart's own snapshot agent is not used, because it sends only to S3. The box's hourly off-site pull (agent pick 237) stays as written, reaching the store at its c1 address. Proxmox's nightly backup of the c1 node VMs replaces its backup of the store VM. `secrets-store restore` keeps its rules. The weekly drill runs as a Job in c1 and keeps rule 8's limits: no network reach to the live store, and no key read. Its pod gets a NetworkPolicy that blocks all its traffic, which holds only if c1's network plugin enforces NetworkPolicy; the rework measures that, and until it is proved the drill runs on the box in a network namespace with only a loopback device, as rule 8 had it on the VM.
7. **Rebuild order** (new). A c1 rebuild puts the seal key back, then installs OpenBao and restores its newest snapshot with `secrets-store restore-rebuilt`, before any ExternalSecret syncs. The restore is a delete under D-0042 rule 6, as D-0038 rule 8 has it, so each c1 rebuild needs that one owner tap. A rebuild with no person at all waits until the owner says a restore onto a fresh, empty store is not a delete.
8. **SOPS is the restore source** (replaces D-0038 rule 11). SOPS holds what is needed before OpenBao starts, what the jobs of rule 5 need while c1 is down, the seal key, and a copy of every secret written into OpenBao. OpenBao is what c1's apps read at run time. A secret is written to its SOPS file and to OpenBao in the same run of the box's `secrets-store` wrapper, SOPS first, and the run fails if either write fails. A weekly `secrets-store compare` on the box hashes each OpenBao value and its SOPS copy and fails, naming only the keys that differ, never their values (Confirmation 9). Restore order: the newest snapshot first (rule 6); if none is usable, a fresh store is reseeded from SOPS. A read at run time still fails loudly and never falls back to a file (D-0038 rule 9).
9. **Where the SOPS files live** (amends D-0038 rule 10). The bootstrap files stay where D-0038 rule 10 has them: the working copies on the Mac and the box, and the box's nightly encrypted bundle off-site. The new SOPS copies of rule 8 (the seal key and every secret written into OpenBao) live only in the box's keys folder and that bundle, never on the Mac. None is committed to central-hub, which is public (AGENTS.md rule 4). The box's age key then opens a copy of every app secret, which is a wider right for an existing credential, so turning rule 8 on waits for the owner's tap at install (access right, D-0042 rule 6).
10. **Which store may get recovery shares** (amends D-0038 rule 5). D-0038 rule 5's wrapper makes recovery shares only for a store with the dev IDs, which meant the dev store VM, 550 (D-0038 rule 2). With no store VM, the wrapper makes shares only for the store in dev's c1, which it tells by that store's address in the dev inventory, and refuses every other store. The rest of D-0038 rule 5 stays: the dev shares stay in the box's keys folder, and prod gets none.

### Consequences

- Good: no store VM to build, patch or size. The VM's planned size (`hosts/terraform/home/secrets-store/home.tfvars.example` line 8) is never spent. OpenBao's pod is planned at a 256 MiB request and a 512 MiB limit on the c1 worker, an estimate until dev measures it. The store moves with c1 to the EliteDesks, where three replicas give high availability.
- Good: apps don't change. ESO's interface stays (D-0038, Exit path).
- Bad: each c1 rebuild restores the store before any app can read a secret, so a failed restore stops every app's secrets from refreshing. Secrets already synced stay.
- Good: the store can be lost entirely and rebuilt with no snapshot, by reseeding it from SOPS.
- Bad: the jobs of rule 5 keep plain 0600 files on the box, with no per-read audit log and no per-job login.
- Bad: every secret has two copies, in OpenBao and in SOPS, so a change writes both, and whoever holds the SOPS files and their age key holds every secret.
- Bad: root on a c1 node, or anyone with cluster-admin, can read the seal key file, and Proxmox's nightly backup of the node VMs holds the key and the data together, as it held the store VM's (D-0038 line 109). The local volume is not tested on c1 yet.
- Bad: the VM code (#275, #276, #358, #363) is reworked for the chart.

### Confirmation

On dev, from the agent box (replaces D-0038 Confirmations 1, 3 and 5; Confirmations 2, 4, 6 and 7 stay; 8 and 9 are new).

Waits on: dev's rebuild. The last dev rebuild was refused for memory: the Proxmox host had 13809 MiB free against the 14336 MiB the rebuild needs (measured 2026-11-15). Until the hardware thread's capacity plan frees that memory, none of these can run.

- **1.** The chart installs, OpenBao starts and unseals itself, and its self-initialization's audit, mounts, auth methods and policies are all present.
- **3.** (replaces D-0038 Confirmation 3) After a c1 rebuild, ESO's Kubernetes login works and the ExternalSecret syncs again.
- **5.** c1 is torn down and rebuilt from code, the seal key put back from its SOPS copy and the newest snapshot restored on the owner's one restore tap (rule 7), before any ExternalSecret syncs.
- **8.** (new) A fresh dev store with no snapshot is reseeded from SOPS, and every ExternalSecret syncs.
- **9.** (new) A secret written through `secrets-store` is equal in OpenBao and SOPS, and one changed in OpenBao alone makes `secrets-store compare` fail, naming that key and no value.

### Exit path

- Back to a VM: the VM code stays in git history at the commit before the rework. Copy a snapshot out, restore it onto a VM made by D-0038's role, and move ESO's ClusterSecretStore to it.

### How this record is accepted

The place and the SOPS balance are the owner's words of 2026-11-16 03:42 and 03:48 UTC. The rest goes on the reviewer's clearance and the three councils' passes of the same head (D-0042 rule 1).
