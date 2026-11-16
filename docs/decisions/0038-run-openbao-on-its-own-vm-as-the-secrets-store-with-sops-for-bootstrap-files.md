---
id: D-0038
title: Run OpenBao as the lab's secrets store, unsealed by a static key with no person, and keep the private bootstrap files encrypted with SOPS and age
status: accepted
date: 2026-11-15
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0013, D-0023, D-0033, D-0035, D-0036]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-11-15T04:51:50Z
  approved-commit: b78f6c18e2b6cac4592c39fdaabff82abdc67f69
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNQKoGjY2FC2uXBaLLqXyH6C
  approval-names: "neither a PR nor a head; the owner picked option 0, Accept the picks, on the card that asks to accept D-0038's picks (OpenBao on its own VM, the static seal, SOPS S1, the prod seal key on the box); its option text adds no copy on his Mac and no prod recovery shares. The record matches main at the approved commit, the last commit to change it before the tap. It replaces his yes of 2026-10-15 01:58 UTC to root keys in his password manager plus an offline copy"
  check: the Plan thread read the owner's choice event (this approval-ref, 04:51:50Z, option 0) and the card it answers (cmsg_01X43rfNYp4H1dL1V2dkfkwNPp39HCn1ncNojBhxoDx9cE, posted 2026-11-15T04:46:58Z) in the project thread at about 04:53Z, and they match; the reviewer thread checked the same at 04:57Z
  merged: not yet
revisit-when: the dev build measures a seal, restore or External Secrets login that does not work as written here; the store needs to stay up while c1 is down; a hardware or virtual TPM route is ready to replace the static key; External Secrets moves its OpenBao support out of alpha or drops it; OpenBao or SOPS changes licence or adds a paid edition; a cluster other than c1 reads secrets from it; or the agents get accounts of their own (D-0030); or the owner picks a home for the prod store's recovery shares
---

# Run OpenBao as the lab's secrets store, unsealed by a static key with no person, and keep the private bootstrap files encrypted with SOPS and age

## Context and Problem Statement

The lab has no secrets store. Its secrets sit in files: the private files on the owner's Mac that a rebuild needs (the Proxmox token, the OPNsense API key, the Secrets-at-rest key, the Cloudflare tokens, the lab CA, the restic password and the OpenTofu state), copies in the agent box's keys folder, and, on c1, a namespace `secret-source` that External Secrets (ESO) reads through its Kubernetes provider ([rebuild-home-lab-from-scratch.md](../runbooks/rebuild-home-lab-from-scratch.md), private-files table; [seed-secret-source.md](../runbooks/seed-secret-source.md)).

The owner's words that lead here:

- 2026-10-15 01:58 UTC (project decisions inbox, row 81), yes to the secrets layer shape (research batch RB-0012, its question 1): no secret values and no ciphertext in the public repository; ESO as the layer in the middle, apps reading plain Kubernetes Secrets; root keys in his password manager plus an offline copy; OpenBao later.
- 2026-10-22 04:47 UTC (inbox row 232), card: machine addresses are blanks filled at apply time from GitHub secrets or the secret store; no new repository and no SOPS for them.
- 2026-10-27 03:45 UTC (inbox row 360): the long-term home for provider tokens is "sops or openbao".
- 2026-11-09 03:54 UTC (inbox row 431): agents make every password now, and all of them are rotated once OpenBao or SOPS exists.
- 2026-11-10 21:22 UTC (inbox row 463): agents get access like employees, least privilege per role, and in the end reach vaults through deterministic processes or CI/CD rather than directly.
- 2026-11-14 05:13 UTC: "openboa will be setup" (05:13:35, inbox row 506), and "pretty sure SOPs as well" (05:13:44, message `cmsg_01X43rfNYp4H1dL1V2dkfkwNHsud9z5We1v2MFgPjAFJVA`).

REQ-0032 asks for free and open-source components with an exit path off each vendor, and the owner's words of 2026-11-14 04:44 UTC sharpen it: "FOSS not OSS" (message `cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7`), nothing paywalled. REQ-0034 asks for evidence for and against. This record sets how to run both tools. The three choices marked **the owner's pick** below were the owner's, on a card; every other rule is an agent pick.

On 2026-11-16 the owner moved the store off its own VM and into c1, balanced with SOPS so it restores easily (messages of 03:42 and 03:48 UTC). D-0058 records that change and keeps its reasons. This record reads as the current rule, and each rule the move changed names the D-0058 rule it follows.

## Decision Drivers

- **Rebuild without a person** (the project's end goal, the owner's words of 2026-11-13): the store must start, unseal and come back from backup with no human paste, from the agent box (D-0035).
- **Hold what rebuilds the cluster:** c1's rebuild needs tokens and keys before the store is up, so they stay in SOPS, outside OpenBao (rule 11).
- **Least privilege per role** (the owner, 2026-11-10 21:22 UTC): each job reads only its own secrets, through a fixed process.
- **FOSS with no paid edition** (REQ-0032; the owner, 2026-11-14 04:44 UTC).
- **Replaceable** (REQ-0011, CLAUDE.md rule 6): apps keep reading plain Kubernetes Secrets through ESO, so the store behind it can change.
- **Nothing private in the public repository** (CLAUDE.md rule 4; the owner's yes of 2026-10-15).

## Considered Options

Where OpenBao runs:

1. **Its own VM in each environment** on the Proxmox host (dev first, then prod).
2. **Inside c1**, from the OpenBao Helm chart, three replicas.
3. **Both**: a VM for the lab's own secrets and an instance in c1 for apps.

How it unseals:

- A. **Static key** in a file where the store runs (built into OpenBao).
- B. **Azure Key Vault** through OpenBao's KMS plugin.
- C. **The VM's virtual TPM** through the PKCS#11 KMS plugin.
- D. **Shamir**, a person pastes key shares at every start.

What SOPS does:

- S1. **Encrypts every copy of the private bootstrap files that leaves its machine**, with age: the box's copy and a nightly off-site bundle. Never committed anywhere.
- S2. **No SOPS.** The files stay plain, mode 0600, on the Mac and the box until their secrets move into OpenBao.
- S3. **Encrypted files committed to a repository**, a new private one or central-hub.

## Decision Outcome

Chosen: **option 2 with seal A and SOPS S1.** Each of the three is **the owner's pick**: option 1 with seal A and SOPS S1 on a card, then option 2 in place of option 1 on 2026-11-16 (D-0058). The rest are agent picks.

Option 2 can't hold c1's own rebuild secrets and must be restored before anything on c1 can start, so those secrets stay in SOPS (rule 11) and each c1 rebuild restores the store first (rule 13; D-0058 keeps the reasons for the move). Option 3 adds a second store with no need for one yet. Seal B adds a paid cloud resource (D-0033 rule 5 puts any new billable Azure resource before the owner) and still needs a credential where the store runs to reach it. Seal C is the stronger route but runs through a plugin and the host's TPM state, so it is the exit path rather than the start. Seal D needs a person at every start, which the end goal rules out. S2 leaves no copy of the bootstrap files off the Mac and the box, and the box's copy in plain text. S3 needs a new repository, which the owner's card of 2026-10-22 declined, or ciphertext in the public repository, which his yes of 2026-10-15 ruled out. His card of 2026-10-22 also said no SOPS, for machine addresses in the repository; S1 keeps them out of every repository, and his words of 2026-11-14 05:13 UTC, "pretty sure SOPs as well", bring SOPS back for this job.

### Rules

1. **Version and source.** OpenBao 2.7.2 from chart `openbao` 0.30.6 (appVersion v2.7.2), the newest chart at least two weeks old (STD-0003 rule 1), pinned by version and checked against its SHA-256 from the chart repository's index, and installed the way every other c1 app is (D-0058 rule 1). Licence MPL-2.0. External Secrets stays on its chart as now.
2. **Where.** Namespace `openbao` in c1, on dev's cluster and on prod's. No store VM is made, and the VM ID range 500 to 599 is not used for it (D-0058 rule 2).
3. **Storage and address.** Integrated storage (Raft) on local-path volumes (D-0051), in the chart's HA mode with Raft turned on, because its standalone mode stores in a different backend where Raft snapshots don't apply. One replica while c1 has one worker, and three once c1 has three nodes. It is reached by name on 443 like every c1 app, so clients and the web UI need no other port (the owner, 2026-11-14 03:51 UTC, message `cmsg_01X43rfNYp4H1dL1V2dkfkwN6Bf1nxMc9HHoCZ9eqA9CDr`). Whether TLS ends at c1's gateway or at OpenBao's own listener is an agent pick of the rework. On prod the certificate comes from the lab CA (D-0028). (D-0058 rule 4.)
4. **Unseal.** Seal `static`, its 32-byte key in a file on each c1 node, in a local volume that OpenBao's pod mounts read-only and that sits outside the folders c1's nightly backup copies. A c1 rebuild writes the file there from the key's SOPS copy (rules 11 and 13). The key's SOPS copy lives in the agent box's keys folder (`/etc/agent-keys/<env>/`, user `keys`, D-0036), so it also travels in the keys folder's encrypted off-box bundle (rule 10). There is no copy on the owner's Mac. The owner's message of 2026-11-14 07:47:50 UTC said he would no longer type go lines (that this is for the greenfield build-out is the agents' reading of his message of 2026-11-14 19:26 UTC, cmsg_01X43rfNYp4H1dL1V2dkfkwNWrXE8oivDrxhnfXaQEuvkN, which speaks of the PR-approval change), and the Mac session's auto-mode check lets a raw run go only on typed words (D-0057 rule 5), so a Mac copy would need a Mac step for every new store. The owner pastes nothing. Putting the prod key on the nodes is a secrets step, so it waits for the owner's tap at install (D-0042 rule 6). This departs from the owner's yes of 2026-10-15 (Context: root keys in their password manager plus an offline copy): no copy of the seal key is in their hands. Their tap of 2026-11-15 04:51 UTC on this rule as first written, with the key on the store's VM, accepted that. The key's move onto c1's nodes is D-0058 rule 3, accepted on the agents' pass, and it keeps no copy in the owner's hands. No plain copy goes in git, a log or a chat. (D-0058 rule 3.)
5. **First start.** OpenBao initializes itself from its `initialize` stanza: audit to a file, the KV v2 mount, the auth methods and the policies in rule 6. The root token it uses is revoked by OpenBao. Right after, the box's `secrets-store recovery` makes recovery keys through `sys/rotate/recovery/init`, three shares with a threshold of two, which a self-initialized store returns at once. On dev they stay in the box's keys folder, `/etc/agent-keys/dev/`, because the dev store holds nothing of value and the dev drills need them. On prod none are made. Self-initialization makes none, the store runs without them, and recovery mode does not work until some are made (evidence, findings 12 and 25). The box's wrapper makes shares only for the store in dev's c1, which it tells by that store's address in the dev inventory, and refuses every other store (D-0058 rule 10); nothing else calls the endpoint. They never go to the box: there they would sit next to the seal key and the admin IDs, so whoever got the box's keys folder would hold every way into the store. The prod shares are never made and then dropped, because dropping one destroys a secret, which is the owner's step (D-0042 rule 6). So prod's break-glass is the admin AppRole (rule 6) and the snapshots (rule 8). If the admin AppRole's IDs are lost, the prod store is rebuilt from code and its keys entered again. On dev, a root token is made from the shares only for break-glass and revoked after.
6. **Who reads what** (D-0058 rule 5).
   - **c1's ESO** logs in with OpenBao's Kubernetes login from inside c1, bound to ESO's service account. Its policy reads only `kv/data/c1/*`.
   - **An agent box wrapper** whose job never has to run while c1 is down gets its own AppRole, with its secret ID in the box's keys folder, bound to the box's address, and a policy that reads only that wrapper's paths. An agent session never holds an OpenBao token.
   - **The jobs that rebuild or repair c1 or the layers under it** (the c1 rebuild, Proxmox, the firewall, the tailnet connector and the store's own restore) read their secrets from files in the box's keys folder, mode 0600, as they do now.
   - **The store's manager** is one `admin` AppRole, used only by the box's `secrets-store` wrapper. It can write any policy and any login, so it can grant itself anything: it is root in effect. What limits it is where it runs: its IDs live only in the box's keys folder, it logs in only from the box's address, and its tokens last 15 minutes, an hour at most.
7. **Names.** Keys keep today's `<app>-<field>` names as `kv/<cluster>/<app>/<field>`, so moving an ExternalSecret changes only its store.
8. **Backups.** A CronJob in c1 takes a Raft snapshot every hour and keeps 48 on a volume of its own; the chart's own snapshot agent is not used, because it sends only to S3. The off-site copy is the box's, hourly while the box is up (agent pick 237): its timer pulls a snapshot with `secrets-store snapshot`, reaching the store at its c1 address, into the box's keys folder, keeping 24, and sends it with restic to the D-0033 target, in a repository path of its own per environment (`/openbao-<env>`) in pick 222's container, with pick 222's sign-in and escrowed password, so the store holds no Azure credential. It forgets hourly and prunes once a day. With no store it skips; a store that is not healthy fails the run (rule 9). If the box is down, nothing goes off-site, and the worst case is the store's own 48 hourly snapshots and Proxmox's nightly backup of the c1 node VMs, both on the lab's own hardware. On dev the pull signs in with the admin AppRole; on prod it waits for a box-bound login that can only take snapshots. `secrets-store restore` puts the newest copy in the keys folder back, never forced; those copies sit next to the seal key's SOPS copy. After c1 is torn down and rebuilt (Confirmation 5), `secrets-store restore-rebuilt` puts back the newest snapshot of the store's previous cluster: only onto a store that holds nothing but `configure`'s own check word, plain first, and forced only when OpenBao refuses the plain restore for the keys (agent pick 238). That restore is a delete under D-0042 rule 6, on dev too (rule 13). A weekly drill restores the newest snapshot into a throwaway server, signs in there with a known login, the store's snapshot AppRole, reads that login's policy back, and deletes the copy. It reads no key, so the drill needs no right the store does not already give (agent pick 235). The login proves that the restored barrier decrypts with the store's seal key and that the auth data came back; it does not read KV data directly. The drill runs as a Job in c1 whose pod gets a NetworkPolicy that blocks all its traffic, so it can't reach the live store. That holds only if c1's network plugin enforces NetworkPolicy; until the rework measures it, the drill runs on the box in a network namespace with only a loopback device. Its storage and the audit log that comes back with the restored data sit in temporary file systems that go with it. The live store's Raft peers, leader and term must be the same before and after (evidence, finding 27). (D-0058 rule 6.)
9. **Fail loudly.** A failed OpenBao read fails the run that asked for it. Nothing falls back to a file.
10. **SOPS.** SOPS 3.13.3 (MPL-2.0) with age 1.3.2 (BSD-3-Clause) encrypts the private bootstrap files, the ones a rebuild needs before OpenBao is up: the private inventory, the `home.tfvars` files, the env files and the OpenTofu state. What it protects is every copy that leaves the machine that holds its key: the copy the Mac's keys wrapper sends to the box, and a nightly encrypted bundle of these files that the box sends with restic to the D-0033 target, so the lab can be rebuilt if either the Mac or the box is lost. It does not protect a file sitting next to its own key, so the working copies on each machine stay as they are now, 0600. The bundle is encrypted to the box's identity in its keys folder, and to the Mac's in `~/.config/central-hub/` only when the owner makes one; the Mac's is optional (agent pick 236), because making it is a Mac step and the owner takes no Mac steps (rule 4). The box sends the bundle daily into the same restic repository as its OPNsense copies, in the D-0033 storage account under pick 222's own container and identity, and reads it back. The box's identity has one off-box copy: the box writes it into pick 222's Key Vault, which the box can write but not read, and the owner reads it only at break-glass by granting their own account the role. So the off-box bundle opens without the box. No agent or pipeline identity may hold role-assignment rights on that vault or container; until that holds, the send is not installed. Old versions of the identity in the vault are never purged while a bundle encrypted to them is kept. It does not use OpenBao's transit engine, because these files are needed to rebuild OpenBao itself. The bundle is never committed to any repository. The SOPS copies of rule 11 (the seal key and every secret written into OpenBao) live only in the box's keys folder and that bundle, never on the Mac, and none is committed to central-hub, which is public. The box's age key then opens a copy of every app secret, which is a wider right for an existing credential, so turning those copies on waits for the owner's tap at install (access right, D-0042 rule 6). (D-0058 rule 9.)
11. **The split, and SOPS as the restore source.** SOPS holds what is needed before OpenBao starts, what the jobs of rule 6 need while c1 is down, the seal key, and a copy of every secret written into OpenBao. OpenBao is what c1's apps read at run time. A secret is written to its SOPS file and to OpenBao in the same run of the box's `secrets-store` wrapper, SOPS first, and the run fails if either write fails. A weekly `secrets-store compare` on the box hashes each OpenBao value and its SOPS copy and fails, naming only the keys that differ, never their values (Confirmation 9). Restore order: the newest snapshot first (rule 8); if none is usable, a fresh store is reseeded from SOPS. A read at run time still fails loudly and never falls back to a file (rule 9). (D-0058 rule 8.)
12. **Dev first.** Every step is built and measured on dev before prod, and each prod run follows D-0035 rule 3.
13. **Rebuild order.** A c1 rebuild puts the seal key back, then installs OpenBao and restores its newest snapshot with `secrets-store restore-rebuilt`, before any ExternalSecret syncs. The restore is a delete under D-0042 rule 6 (rule 8), so each c1 rebuild needs that one owner tap. A rebuild with no person at all waits until the owner says a restore onto a fresh, empty store is not a delete. (D-0058 rule 7.)

### Not decided here

- **Where prod's recovery shares would live**, if the owner wants them. Until he picks, prod has none (rule 5).
- **Rotating the seal key** with no recovery shares: OpenBao issue #3996 reports that rotating a static key fails at the next restart when no recovery key exists, with a workaround in the issue thread (evidence, finding 26). It is proved on dev before any prod rotation.
- **Rotation** of every secret agents made or saw (TASK-0247). It follows once the store runs, as its own change.
- **Moving c1's ExternalSecrets** from store `c1` to OpenBao. That is a later PR per app, after the dev measurements.

### Consequences

- Good: the store starts, unseals and comes back from backup with no person, so a full lab rebuild from the box needs no paste.
- Good: no store VM to build, patch or size, and the store moves with c1 to the EliteDesks, where three replicas give high availability.
- Good: the store can be lost entirely and rebuilt with no snapshot, by reseeding it from SOPS (rule 11).
- Good: every job has its own login and reads only its own paths, and OpenBao's audit log records each read.
- Good: the box's copy of the bootstrap files and their off-site bundle are ciphertext, and the lab can be rebuilt if either the Mac or the box is lost.
- Bad: root on a c1 node, or anyone with cluster-admin, can read the seal key file, and Proxmox's nightly backup of the node VMs holds the key and the data together. The off-site snapshots don't hold the key, but the box's keys folder holds the key's SOPS copy, snapshots and the admin IDs together, so the box is as sensitive as the store.
- Bad: each c1 rebuild restores the store before any app can read a secret, so a failed restore stops every app's secrets from refreshing, though Secrets already synced stay. One replica until c1 has three nodes.
- Bad: if every copy of the seal key is lost, no snapshot can be restored.
- Bad: prod has no recovery shares, so no root token can be made there and recovery mode does not work. A lost admin AppRole means a rebuilt store and its keys entered again. Compensating control: the hourly snapshots, and the store holds only a few keys while the lab is greenfield.
- Bad: the box is the only copy of the seal key off c1's nodes. Compensating control: the encrypted off-box bundle (rule 10) once its send step exists.
- Bad: ESO lists its OpenBao support as alpha, tested on older versions. It runs on ESO's stable Vault provider, and dev measures it before prod.
- Bad: two more tools in the rebuild path.
- Bad: every secret has two copies, in OpenBao and in SOPS, so a change writes both, and whoever holds the SOPS files and their age key holds every secret.
- Bad: the jobs of rule 6 that must run while c1 is down keep plain 0600 files on the box, with no per-read audit log and no per-job login.
- Bad: the backup Key Vault and the container, read together by one account, open every bootstrap file. Only the owner's account can read the vault's values, by granting itself the role at break-glass; losing that Azure account and the box together loses the bundle, and the Mac holds no copy unless the owner makes its identity.

### Confirmation

On dev, from the agent box, with the logs named in the card for prod. They wait on dev's rebuild (D-0058, Confirmation):

1. The chart installs, OpenBao starts and unseals itself, and its self-initialization's audit, mounts, auth methods and policies are all present.
2. ESO on dev's cluster syncs one ExternalSecret from OpenBao.
3. After a c1 rebuild, ESO's Kubernetes login works and the ExternalSecret syncs again.
4. A snapshot is restored into a throwaway server, a known login signs in there and its policy reads back, and the live store's Raft peers, leader and term do not change.
5. c1 is torn down and rebuilt from code, the seal key put back from its SOPS copy and the newest snapshot restored on the owner's one restore tap (rule 13), before any ExternalSecret syncs.
6. A wrapper's AppRole is refused a path outside its policy.
7. Before its recovery shares are made, the dev store unseals, takes a snapshot and restores it, as prod will with none.
8. A fresh dev store with no snapshot is reseeded from SOPS, and every ExternalSecret syncs.
9. A secret written through `secrets-store` is equal in OpenBao and SOPS, and one changed in OpenBao alone makes `secrets-store compare` fail, naming that key and no value.

### Exit path

- **Seal:** seal migration to the virtual TPM (PKCS#11 plugin) or any KMS, with both seals available and a snapshot first.
- **Store:** ESO's interface stays. Copy the keys to another store under the same paths, point a new ClusterSecretStore at it, and move each ExternalSecret's store. Wrappers change their one read call.
- **SOPS:** `sops decrypt` gives back the plain files, and age keys are plain files that move to any store.
- **Back to a VM:** the VM code stays in git history at the commit before the rework. Copy a snapshot out, restore it onto a VM made by that code, and move ESO's ClusterSecretStore to it (D-0058).
- **Back to today:** store `c1` and the private files keep working until the last app moves.

## Pros and Cons of the Options

### 1. Its own VM in each environment

- Good: c1 can be torn down and rebuilt without touching the store.
- Bad: one more VM to build, patch and size, for one service; the owner moved the store into c1 on 2026-11-16 (D-0058).

### 2. Inside c1

- Good: no store VM, and three replicas once c1 has three nodes.
- Bad: restored before any app starts in each c1 rebuild; can't hold c1's own rebuild secrets, which stay in SOPS (rule 11).

### 3. Both

- Good: apps keep their store inside the cluster.
- Bad: two stores, two seals and two backups, with no need for them yet.

### Seal B, Azure Key Vault

- Good: the key lives off the machines that run the store.
- Bad: a new billable Azure resource and a credential where the store runs to reach it; no unseal without the internet.

### Seal C, the VM's virtual TPM

- Good: the key can't be copied off as a file.
- Bad: a plugin and the host's TPM state in the path; a teardown of the VM loses the TPM unless its state is backed up.

### Seal D, Shamir

- Bad: a person at every start.

### SOPS S2, no SOPS

- Good: one tool fewer.
- Bad: the bootstrap files have no copy off the Mac and the box, so losing both loses the lab's private files; the box's copy travels and sits in plain text.

### SOPS S3, encrypted files in a repository

- Bad: a new repository was declined by the owner's card of 2026-10-22, and ciphertext in the public repository by his yes of 2026-10-15; key names stay in clear text.

## More Information

- **Evidence:** [docs/evidence/0038-run-openbao-on-its-own-vm-as-the-secrets-store-with-sops-for-bootstrap-files.md](../evidence/0038-run-openbao-on-its-own-vm-as-the-secrets-store-with-sops-for-bootstrap-files.md).
- **Licence check:** OpenBao, its plugins and SOPS are MPL-2.0, age is BSD-3-Clause and ESO is Apache-2.0; none has a paid edition (evidence findings 1 to 4).
- Related records: D-0013, D-0023, D-0028, D-0033, D-0035, D-0036, D-0051, D-0058.
