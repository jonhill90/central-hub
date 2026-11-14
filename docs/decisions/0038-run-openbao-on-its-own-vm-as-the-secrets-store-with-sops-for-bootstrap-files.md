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
revisit-when: the dev build measures a seal, restore or External Secrets login that does not work as written here; the store needs to stay up while its VM is down (high availability); a hardware or virtual TPM route is ready to replace the static key; External Secrets moves its OpenBao support out of alpha or drops it; OpenBao or SOPS changes licence or adds a paid edition; a cluster other than c1 reads secrets from it; or the agents get accounts of their own (D-0030)
---

# Run OpenBao on its own VM in each environment as the lab's secrets store, unsealed by a static key with no person, and keep the private bootstrap files encrypted with SOPS and age

## Context and Problem Statement

The lab has no secrets store. Its secrets sit in files: the private files on the owner's Mac that a rebuild needs (the Proxmox token, the OPNsense API key, the Secrets-at-rest key, the Cloudflare tokens, the lab CA, the restic password and the OpenTofu state), copies in the agent box's keys folder, and, on c1, a namespace `secret-source` that External Secrets (ESO) reads through its Kubernetes provider ([rebuild-home-lab-from-scratch.md](../runbooks/rebuild-home-lab-from-scratch.md), private-files table; [seed-secret-source.md](../runbooks/seed-secret-source.md)).

The owner's words that lead here:

- 2026-10-15 01:58 UTC, yes to the secrets layer shape (research batch RB-0012, its question 1): no secret values and no ciphertext in the public repository; ESO as the layer in the middle, apps reading plain Kubernetes Secrets; root keys in his password manager plus an offline copy; OpenBao later.
- 2026-10-22 04:47 UTC, card: machine addresses are blanks filled at apply time from GitHub secrets or the secret store; no new repository and no SOPS for them.
- 2026-10-27 03:45 UTC: the long-term home for provider tokens is "sops or openbao".
- 2026-11-09 03:54 UTC: agents make every password now, and all of them are rotated once OpenBao or SOPS exists.
- 2026-11-10 21:22 UTC: agents get access like employees, least privilege per role, and in the end reach vaults through deterministic processes or CI/CD rather than directly.
- 2026-11-14 05:13 UTC: "openboa will be setup", and "pretty sure SOPs as well".

REQ-0032 asks for free and open-source components with an exit path off each vendor, and the owner's words of 2026-11-14 04:44 UTC sharpen it: "FOSS not OSS", nothing paywalled. REQ-0034 asks for evidence for and against. This record proposes how to run both tools. The three choices marked **the owner's pick** below wait on his cards; every other rule is an agent pick.

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
2. **Where.** One AlmaLinux VM per environment, made by OpenTofu from reviewed main: `daldapbao01` on VNet dev in pool `dev`, and `paldapbao01` on prod. VM IDs from a new hundred, 500 to 599, for the job "secrets store": STD-0001's Proxmox VM IDs section gives a new job the next free hundred below 9000, and 300 (the CI runner) and 400 (the desktop) are taken. 550 for dev and 500 for prod. When this record is accepted, the range goes into STD-0001's table in the same PR. The names and IDs are agent picks.
3. **Storage and address.** Integrated storage (Raft), one node. The listener serves TLS on 443 with a certificate from the lab CA (D-0028), so clients and the web UI reach it by name with no other port (the owner, 2026-11-14).
4. **Unseal.** Seal `static`, its 32-byte key in a file readable only by the service. The key has exactly two other copies, in the two places the lab's private files already live: the agent box's keys folder (`/etc/agent-keys/<env>/`, user `keys`, D-0036) and the owner's Mac, in `~/.config/central-hub/` (mode 0600), put there by the Mac's keys wrapper. The owner pastes nothing. He may copy the Mac's file into his password manager himself if he wants one more copy; agents never open his password manager. No copy goes in git, a log or a chat.
5. **First start.** OpenBao initializes itself from its `initialize` stanza: audit to a file, the KV v2 mount, the auth methods and the policies in rule 6. The root token it uses is revoked by OpenBao. The playbook's last step makes recovery keys through `sys/rotate/recovery`, three shares with a threshold of two, and writes them only to the Mac's `~/.config/central-hub/`, by the same keys wrapper. A root token is made from them only for break-glass and revoked after.
6. **Who reads what.**
   - **c1's ESO** logs in with JWT auth, mount `jwt-c1`, checking c1's service-account tokens against c1's service-account public key, with a role bound to ESO's service account and an audience. Its policy reads only `kv/data/c1/*`.
   - **Each agent box wrapper** that needs a secret gets its own AppRole, with its secret ID in the box's keys folder, bound to the box's address, and a policy that reads only that wrapper's paths. An agent session never holds an OpenBao token.
   - **The rebuild** has one AppRole that may write only `auth/jwt-c1/config`, so a rebuilt c1 can register its new key.
7. **Names.** Keys keep today's `<app>-<field>` names as `kv/<cluster>/<app>/<field>`, so moving an ExternalSecret changes only its store.
8. **Backups.** A timer on the VM takes a Raft snapshot every hour and sends it with restic to the D-0033 target, in a repository path of its own per environment. Proxmox's nightly backup of the VM stays. A weekly drill restores the newest snapshot into a throwaway server on the same VM, reads one known key and deletes the copy.
9. **Fail loudly.** A failed OpenBao read fails the run that asked for it. Nothing falls back to a file.
10. **SOPS.** SOPS 3.13.3 (MPL-2.0) with age 1.3.2 (BSD-3-Clause) encrypts the private bootstrap files, the ones a rebuild needs before OpenBao is up: the private inventory, the `home.tfvars` files, the env files and the OpenTofu state. What it protects is every copy that leaves the machine that holds its key: the copy the Mac's keys wrapper sends to the box, and a nightly encrypted bundle of these files that the box sends with restic to the D-0033 target, so the lab can be rebuilt if either the Mac or the box is lost. It does not protect a file sitting next to its own key, so the working copies on each machine stay as they are now, 0600. It uses two age recipients, the box's identity in its keys folder and the Mac's in `~/.config/central-hub/`, so either machine alone can decrypt. It does not use OpenBao's transit engine, because these files are needed to rebuild OpenBao itself. The bundle is never committed to any repository.
11. **The split.** SOPS holds what is needed before OpenBao starts. OpenBao holds everything read at run time. Every secret moved into OpenBao is deleted from its old file in the same change.
12. **Dev first.** Every step is built and measured on dev before prod, and each prod run follows D-0035 rule 3.

### Not decided here

- **Rotation** of every secret agents made or saw (TASK-0247). It follows once the store runs, as its own change.
- **Moving c1's ExternalSecrets** from store `c1` to OpenBao. That is a later PR per app, after the dev measurements.
- **High availability.** One node per environment. A three-node Raft cluster is a later record if downtime matters.

### Consequences

- Good: the store starts, unseals and comes back from backup with no person, so a full lab rebuild from the box needs no paste.
- Good: c1 can be torn down and rebuilt without touching the store, and the store holds what c1's rebuild needs.
- Good: every job has its own login and reads only its own paths, and OpenBao's audit log records each read.
- Good: the box's copy of the bootstrap files and their off-site bundle are ciphertext, and the lab can be rebuilt if either the Mac or the box is lost.
- Bad: the static key sits on the same VM as the data. Whoever gets the VM's disk, or its Proxmox backup, gets both. The off-site snapshots don't hold the key.
- Bad: one node. While the VM is down, ESO can't refresh, though Secrets already synced stay.
- Bad: if every copy of the seal key is lost, no snapshot can be restored.
- Bad: ESO lists its OpenBao support as alpha, tested on older versions. It runs on ESO's stable Vault provider, and dev measures it before prod.
- Bad: two more tools in the rebuild path, and one more VM to patch.

### Confirmation

On dev, from the agent box, with the logs named in the card for prod:

1. The VM is made, OpenBao starts and unseals itself, and the self-initialization's audit, mounts, auth methods and policies are all present.
2. ESO on dev's cluster syncs one ExternalSecret from OpenBao.
3. A dev teardown and rebuild of the cluster registers the new key, and the ExternalSecret syncs again.
4. A snapshot is restored into a throwaway server, and a known key reads back.
5. The OpenBao VM is destroyed and rebuilt from code, its seal key put back from the box and the newest snapshot restored, with no person.
6. A wrapper's AppRole is refused a path outside its policy.

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
