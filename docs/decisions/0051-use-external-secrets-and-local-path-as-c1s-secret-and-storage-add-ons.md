---
id: D-0051
title: Use External Secrets for c1's secrets and the Local Path Provisioner for its storage, both Apache-2.0 with no paid edition in use
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: a paid edition of External Secrets or the Local Path Provisioner appears with features the lab would need; a data-only VM disk or networked storage replaces local-path (spec 2026-11-c1-rebuild, P6); a second cluster needs shared storage; or either project changes licence or stops being maintained
---

# Use External Secrets for c1's secrets and the Local Path Provisioner for its storage, both Apache-2.0 with no paid edition in use

## Context and Problem Statement

Two of c1's add-ons were chosen in the owner's answers and in specs, but not in a decision record:

- **External Secrets (ESO)** turns entries in a secret store into Kubernetes Secrets (`hosts/kubernetes/home/c1/apps/external-secrets/` and `secret-store/`, role `k8s_secrets`). On 2026-10-15 at 01:58 UTC (project decisions inbox, row 81) the owner said yes to the secrets layer's shape: ESO as the layer in the middle, with apps reading plain Kubernetes Secrets, as D-0038 records. D-0038 (proposed) puts OpenBao behind it.
- **The Local Path Provisioner** is c1's default StorageClass, on nodes labelled as having a data disk (`hosts/kubernetes/home/c1/apps/local-path/`, role `k8s_storage`, agent pick 110). On 2026-11-11 at 02:38 UTC the owner chose to keep it for the rebuild (spec [2026-11-c1-rebuild](../specs/2026-11-c1-rebuild.md), P6).

At main c6ee84b, External Secrets is named in 29 files in `hosts/`, 8 runbooks and D-0038. The Local Path Provisioner is named in 27 files in `hosts/`, 7 runbooks and D-0011, D-0033 and D-0039. No record chose either.

cert-manager, the third add-on in the audit's list, is already in D-0028 and the c1 way-in spec, and is not covered here.

Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that no piece of the lab may hold something back behind a paywall (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). STD-0006 rule 2 turns that into a test: a component fails when its owner or lead company sells an edition that holds features back from the free one, and selling support, hosting, training or tested builds of the same code is allowed. This record states both add-ons' licences, paid sides and ways out.

## Decision Drivers

- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **Apps read plain Kubernetes objects** (the owner, 2026-10-15), so the store or storage behind them can change.
- **Replaceable** (CLAUDE.md rule 6).

## Considered Options

1. **External Secrets and the Local Path Provisioner**, as running.
2. **Each app reads its secrets from the store directly**, and **there is no default StorageClass** (each app names its volume).

## Decision Outcome

Proposed: **option 1**, the owner's earlier answers and what runs. Option 2 ties every app to one store and puts storage settings in every app.

Diagram: not applicable. Two independent add-ons with no order between them.

### Do the paid sides make either fail?

- **External Secrets.** A company backed by Open Core Ventures planned "a commercial enterprise offering" around it in 2024. The page now says that company "wound down operations as of December 2025". Nothing paid is sold by the project.
- **Local Path Provisioner.** Rancher, now part of SUSE, leads it. SUSE's Application Collection lists a Local Path Provisioner chart marked "Subscription: Prime". SUSE describes the Collection as applications "aligned with upstream", rebuilt on SUSE's container images when upstream releases, and "backed by enterprise-grade support". It names no feature beyond the open-source project.
- **The reading under STD-0006 rule 2: both pass.** ESO has no paid edition. SUSE's offer is a supported rebuild of the same project, which is a tested build, and rule 2 allows selling tested builds. The lab pulls the upstream image (`docker.io/rancher/local-path-provisioner`), not SUSE's.

### Rules

1. **Licences.** External Secrets, Apache-2.0. Local Path Provisioner, Apache-2.0. Both from their upstream projects' own charts or images.
2. **No paid offering.** No commercial External Secrets offering and no SUSE Application Collection build is used.
3. **Pinned versions** (STD-0003). The local-path images are pinned by digest.

### Consequences

- Good: no change; both free.
- Good: apps see only Secrets and volume claims, so the store (D-0038) and the storage can change under them.
- Bad: local-path ties each volume to one node's disk; losing that disk loses the data not yet backed up (D-0033).

### Confirmation

- c1's default StorageClass is `local-path`.
- c1's ExternalSecrets sync from a ClusterSecretStore.
- No image or chart for either comes from SUSE's Application Collection.

### Exit path

- **Secrets:** ESO supports many stores. A new ClusterSecretStore, and each ExternalSecret moved to it, moves an app, as D-0038 sets out.
- **Storage:** restore the backups into claims of another StorageClass. Apps change only the class name, or nothing if it becomes the default.

## Pros and Cons of the Options

### Option 1: ESO and local-path

- Good: Apache-2.0; running; apps stay neutral about the store and the storage.
- Bad: local-path has no replication.

### Option 2: direct reads and no default class

- Good: fewer add-ons.
- Bad: every app tied to one store; storage settings in every app.

## More Information

- Evidence: [`docs/evidence/0051-use-external-secrets-and-local-path-as-c1s-secret-and-storage-add-ons.md`](../evidence/0051-use-external-secrets-and-local-path-as-c1s-secret-and-storage-add-ons.md).
- Related: D-0028 (cert-manager), D-0033 (backups), D-0038 (OpenBao behind ESO), STD-0003, STD-0006 and its register (`docs/standards/components.yaml`).
