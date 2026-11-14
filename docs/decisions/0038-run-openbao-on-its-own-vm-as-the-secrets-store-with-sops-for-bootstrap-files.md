---
id: D-0038
title: Run OpenBao on its own VM in each environment as the lab's secrets store, unsealed by a static key with no person, and keep the private bootstrap files encrypted with SOPS and age
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0013, D-0023, D-0033, D-0035, D-0036]
supersedes: []
superseded-by:
revisit-when: the dev build measures a seal, restore or External Secrets login that does not work as written here; the store needs to stay up while its VM is down (high availability); a hardware or virtual TPM route is ready to replace the static key; External Secrets moves its OpenBao support out of alpha or drops it; OpenBao or SOPS changes licence or adds a paid edition; a cluster other than c1 reads secrets from it; or the agents get accounts of their own (D-0030); or the owner picks a home for the prod store's recovery shares
---

# Run OpenBao on its own VM in each environment as the lab's secrets store, unsealed by a static key with no person, and keep the private bootstrap files encrypted with SOPS and age

## Context and Problem Statement

The lab has no secrets store. Its secrets sit in files: the private files on the owner's Mac that a rebuild needs (the Proxmox token, the OPNsense API key, the Secrets-at-rest key, the Cloudflare tokens, the lab CA, the restic password and the OpenTofu state), copies in the agent box's keys folder, and, on c1, a namespace `secret-source` that External Secrets (ESO) reads through its Kubernetes provider ([rebuild-home-lab-from-scratch.md](../runbooks/rebuild-home-lab-from-scratch.md), private-files table; [seed-secret-source.md](../runbooks/seed-secret-source.md)).

The owner's words that lead here:

- 2026-10-15 01:58 UTC (project decisions inbox, row 81), yes to the secrets layer shape (research batch RB-0012, its question 1): no secret values and no ciphertext in the public repository; ESO as the layer in the middle, apps reading plain Kubernetes Secrets; root keys in his password manager plus an offline copy; OpenBao later.
- 2026-10-22 04:47 UTC (inbox row 232), card: machine addresses are blanks filled at apply time from GitHub secrets or the secret store; no new repository and no SOPS for them.
- 2026-10-27 03:45 UTC (inbox row 360): the long-term home for provider tokens is "sops or openbao".
- 2026-11-09 03:54 UTC (inbox row 431): agents make every password now, and all of them are rotated once OpenBao or SOPS exists.
- 2026-11-10 21:22 UTC (inbox row 463): agents get access like employees, least privilege per role, and in the end reach vaults through deterministic processes or CI/CD rather than directly.
- 2026-11-14 05:13 UTC: "openboa will be setup" (05:13:35, inbox row 506), and "pretty sure SOPs as well" (05:13:44, message `cmsg_01X43rfNYp4H1dL1V2dkfkwNHsud9z5We1v2MFgPjAFJVA`).

REQ-0032 asks for free and open-source components with an exit path off each vendor, and the owner's words of 2026-11-14 04:44 UTC sharpen it: "FOSS not OSS" (message `cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7`), nothing paywalled. REQ-0034 asks for evidence for and against. This record proposes how to run both tools. The three choices marked **the owner's pick** below wait on his cards; every other rule is an agent pick.

## Decision Drivers

- **Rebuild without a person** (the project's end goal, the owner's words of 2026-11-13): the store must start, unseal and come back from backup with no human paste, from the agent box (D-0035).
- **Hold what rebuilds the cluster:** c1's rebuild needs tokens and keys, so the store can't live only inside c1.
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

- A. **Static key** in a file on the VM (built into OpenBao).
- B. **Azure Key Vault** through OpenBao's KMS plugin.
- C. **The VM's virtual TPM** through the PKCS#11 KMS plugin.
- D. **Shamir**, a person pastes key shares at every start.

What SOPS does:

- S1. **Encrypts every copy of the private bootstrap files that leaves its machine**, with age: the box's copy and a nightly off-site bundle. Never committed anywhere.
- S2. **No SOPS.** The files stay plain, mode 0600, on the Mac and the box until their secrets move into OpenBao.
- S3. **Encrypted files committed to a repository**, a new private one or central-hub.

## Decision Outcome

Proposed: **option 1 with seal A and SOPS S1.** Each of the three is **the owner's pick** on a card; the rest are agent picks.

Option 2 can't hold c1's own rebuild secrets and must be restored before anything on c1 can start. Option 3 adds a second store with no need for one yet. Seal B adds a paid cloud resource (D-0033 rule 5 puts any new billable Azure resource before the owner) and still needs a credential on the VM to reach it. Seal C is the stronger route but runs through a plugin and the host's TPM state, so it is the exit path rather than the start. Seal D needs a person at every start, which the end goal rules out. S2 leaves no copy of the bootstrap files off the Mac and the box, and the box's copy in plain text. S3 needs a new repository, which the owner's card of 2026-10-22 declined, or ciphertext in the public repository, which his yes of 2026-10-15 ruled out. His card of 2026-10-22 also said no SOPS, for machine addresses in the repository; S1 keeps them out of every repository, and his words of 2026-11-14 05:13 UTC, "pretty sure SOPs as well", bring SOPS back for this job.

### Rules

1. **Version and source.** OpenBao 2.7.2, the newest release at least two weeks old (STD-0003), installed from the release RPM after checking it against the release's `checksums.txt`. Licence MPL-2.0. External Secrets stays on its chart as now.
2. **Where.** One AlmaLinux VM per environment, made by OpenTofu from reviewed main: one on VNet dev in pool `dev` and one on prod, each with a STD-0001 hostname kept in the private inventory (role `ap`, this repository being public). VM IDs from a new hundred, 500 to 599, for the job "secrets store": STD-0001's Proxmox VM IDs section gives a new job the next free hundred below 9000, and 300 (the CI runner) and 400 (the desktop) are taken. 550 for dev and 500 for prod. When this record is accepted, the range goes into STD-0001's table in the same PR. The IDs are agent picks.
3. **Storage and address.** Integrated storage (Raft), one node. The listener serves TLS on 443, so clients and the web UI reach it by name with no other port (the owner, 2026-11-14 03:51 UTC, message `cmsg_01X43rfNYp4H1dL1V2dkfkwN6Bf1nxMc9HHoCZ9eqA9CDr`). On prod the certificate comes from the lab CA (D-0028). On dev the role makes a self-signed one for the name, the address and 127.0.0.1 and hands its public half to the box (agent pick 227), so dev needs nothing from the lab CA.
4. **Unseal.** Seal `static`, its 32-byte key in a file readable only by the service. The key has one other copy, in the agent box's keys folder (`/etc/agent-keys/<env>/`, user `keys`, D-0036), so it also travels in the keys folder's encrypted off-box bundle (rule 10). There is no copy on the owner's Mac. The owner said on 2026-11-14 at 07:47:50 UTC that he will not type go lines anymore, and the Mac's guard takes only typed words (D-0044, Context), so a Mac copy would need a Mac step for every new store. The owner pastes nothing. Putting the prod store's key into the box's keys folder is a secrets step, so it waits for the owner's tap (D-0042 rule 6). This departs from the owner's yes of 2026-10-15 (Context: root keys in his password manager plus an offline copy): no copy of the seal key is in his hands, and his tap on this rule accepts that. No copy goes in git, a log or a chat.
5. **First start.** OpenBao initializes itself from its `initialize` stanza: audit to a file, the KV v2 mount, the auth methods and the policies in rule 6. The root token it uses is revoked by OpenBao. Right after, the box's `secrets-store recovery` makes recovery keys through `sys/rotate/recovery/init`, three shares with a threshold of two, which a self-initialized store returns at once. On dev they stay in the box's keys folder, `/etc/agent-keys/dev/`, because the dev store holds nothing of value and the dev drills need them. On prod none are made. Self-initialization makes none, the store runs without them, and recovery mode does not work until some are made (evidence, findings 12 and 25). The box's wrapper refuses to make shares for any store outside the dev IDs, and nothing else calls the endpoint. They never go to the box: there they would sit next to the seal key and the admin IDs, so whoever got the box's keys folder would hold every way into the store. The prod shares are never made and then dropped, because dropping one destroys a secret, which is the owner's step (D-0042 rule 6). So prod's break-glass is the admin AppRole (rule 6) and the snapshots (rule 8). If the admin AppRole's IDs are lost, the prod store is rebuilt from code and its keys entered again. On dev, a root token is made from the shares only for break-glass and revoked after.
6. **Who reads what.**
   - **c1's ESO** logs in with JWT auth, mount `jwt-c1`, checking c1's service-account tokens against c1's service-account public key, with a role bound to ESO's service account and an audience. Its policy reads only `kv/data/c1/*`.
   - **Each agent box wrapper** that needs a secret gets its own AppRole, with its secret ID in the box's keys folder, bound to the box's address, and a policy that reads only that wrapper's paths. An agent session never holds an OpenBao token.
   - **The rebuild** has one AppRole that may write only `auth/jwt-c1/config`, so a rebuilt c1 can register its new key.
   - **The store's manager** is one `admin` AppRole, used only by the box's `secrets-store` wrapper. It can write any policy and any login, so it can grant itself anything: it is root in effect. What limits it is where it runs: its IDs live only in the box's keys folder, it logs in only from the box's address, and its tokens last 15 minutes, an hour at most.
7. **Names.** Keys keep today's `<app>-<field>` names as `kv/<cluster>/<app>/<field>`, so moving an ExternalSecret changes only its store.
8. **Backups.** A timer on the VM takes a Raft snapshot every hour and sends it with restic to the D-0033 target, in a repository path of its own per environment. The box's `secrets-store snapshot` also copies snapshots into the box's keys folder, keeping 24, and `secrets-store restore` puts the newest back; those copies sit next to the seal key. Proxmox's nightly backup of the VM stays. A weekly drill restores the newest snapshot into a throwaway server on the same VM, signs in there with a known login, the store's snapshot AppRole, reads that login's policy back, and deletes the copy. It reads no key, so the drill needs no right the store does not already give (agent pick 235). The login proves that the restored barrier decrypts with the store's seal key and that the auth data came back; it does not read KV data directly. The throwaway runs in a network namespace with only a loopback device, so it can't reach the live store, and its storage and the audit log that comes back with the restored data sit in temporary file systems that go with it. The live store's Raft peers, leader and term must be the same before and after (evidence, finding 27).
9. **Fail loudly.** A failed OpenBao read fails the run that asked for it. Nothing falls back to a file.
10. **SOPS.** SOPS 3.13.3 (MPL-2.0) with age 1.3.2 (BSD-3-Clause) encrypts the private bootstrap files, the ones a rebuild needs before OpenBao is up: the private inventory, the `home.tfvars` files, the env files and the OpenTofu state. What it protects is every copy that leaves the machine that holds its key: the copy the Mac's keys wrapper sends to the box, and a nightly encrypted bundle of these files that the box sends with restic to the D-0033 target, so the lab can be rebuilt if either the Mac or the box is lost. It does not protect a file sitting next to its own key, so the working copies on each machine stay as they are now, 0600. It uses two age recipients, the box's identity in its keys folder and the Mac's in `~/.config/central-hub/`, so either machine alone can decrypt. It does not use OpenBao's transit engine, because these files are needed to rebuild OpenBao itself. The bundle is never committed to any repository.
11. **The split.** SOPS holds what is needed before OpenBao starts. OpenBao holds everything read at run time. Every secret moved into OpenBao is deleted from its old file in the same change.
12. **Dev first.** Every step is built and measured on dev before prod, and each prod run follows D-0035 rule 3.

### Not decided here

- **Where prod's recovery shares would live**, if the owner wants them. Until he picks, prod has none (rule 5).
- **Rotating the seal key** with no recovery shares: OpenBao issue #3996 reports that rotating a static key fails at the next restart when no recovery key exists, with a workaround in the issue thread (evidence, finding 26). It is proved on dev before any prod rotation.
- **Rotation** of every secret agents made or saw (TASK-0247). It follows once the store runs, as its own change.
- **Moving c1's ExternalSecrets** from store `c1` to OpenBao. That is a later PR per app, after the dev measurements.
- **High availability.** One node per environment. A three-node Raft cluster is a later record if downtime matters.

### Consequences

- Good: the store starts, unseals and comes back from backup with no person, so a full lab rebuild from the box needs no paste.
- Good: c1 can be torn down and rebuilt without touching the store, and the store holds what c1's rebuild needs.
- Good: every job has its own login and reads only its own paths, and OpenBao's audit log records each read.
- Good: the box's copy of the bootstrap files and their off-site bundle are ciphertext, and the lab can be rebuilt if either the Mac or the box is lost.
- Bad: the static key sits on the same VM as the data. Whoever gets the VM's disk, or its Proxmox backup, gets both. The off-site snapshots don't hold the key, but the box's keys folder holds the key, snapshots and the admin IDs together, so the box is as sensitive as the store.
- Bad: one node. While the VM is down, ESO can't refresh, though Secrets already synced stay.
- Bad: if every copy of the seal key is lost, no snapshot can be restored.
- Bad: prod has no recovery shares, so no root token can be made there and recovery mode does not work. A lost admin AppRole means a rebuilt store and its keys entered again. Compensating control: the hourly snapshots, and the store holds only a few keys while the lab is greenfield.
- Bad: the box is the only copy of the seal key off the VM. Compensating control: the encrypted off-box bundle (rule 10) once its send step exists.
- Bad: ESO lists its OpenBao support as alpha, tested on older versions. It runs on ESO's stable Vault provider, and dev measures it before prod.
- Bad: two more tools in the rebuild path, and one more VM to patch.

### Confirmation

On dev, from the agent box, with the logs named in the card for prod:

1. The VM is made, OpenBao starts and unseals itself, and the self-initialization's audit, mounts, auth methods and policies are all present.
2. ESO on dev's cluster syncs one ExternalSecret from OpenBao.
3. A dev teardown and rebuild of the cluster registers the new key, and the ExternalSecret syncs again.
4. A snapshot is restored into a throwaway server, a known login signs in there and its policy reads back, and the live store's Raft peers, leader and term do not change.
5. The OpenBao VM is destroyed and rebuilt from code, its seal key put back from the box and the newest snapshot restored, with no person.
6. A wrapper's AppRole is refused a path outside its policy.
7. Before its recovery shares are made, the dev store unseals, takes a snapshot and restores it, as prod will with none.

### Exit path

- **Seal:** seal migration to the virtual TPM (PKCS#11 plugin) or any KMS, with both seals available and a snapshot first.
- **Store:** ESO's interface stays. Copy the keys to another store under the same paths, point a new ClusterSecretStore at it, and move each ExternalSecret's store. Wrappers change their one read call.
- **SOPS:** `sops decrypt` gives back the plain files, and age keys are plain files that move to any store.
- **Back to today:** store `c1` and the private files keep working until the last app moves.

## Pros and Cons of the Options

### 2. Inside c1

- Good: three replicas and the chart's snapshot job.
- Bad: lost with every c1 teardown and restored before any app starts; can't hold c1's own rebuild secrets.

### 3. Both

- Good: apps keep their store inside the cluster.
- Bad: two stores, two seals and two backups, with no need for them yet.

### Seal B, Azure Key Vault

- Good: the key lives off the VM.
- Bad: a new billable Azure resource and a credential on the VM to reach it; no unseal without the internet.

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
- Related records: D-0013, D-0023, D-0028, D-0033, D-0035, D-0036.
