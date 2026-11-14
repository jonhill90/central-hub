---
id: D-0052
title: Run Jellyfin as c1's media server, the first app built for people to use
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: Jellyfin adds a paid tier or changes licence; the owner wants features Jellyfin does not have; c1's storage moves off local-path; or media moves to its own machine
---

# Run Jellyfin as c1's media server, the first app built for people to use

## Context and Problem Statement

Jellyfin runs on c1 in namespace `media`, with its configuration and media on two claims on the default StorageClass (D-0051), behind the Gateway on its own name (D-0021). It lives in `hosts/kubernetes/home/c1/apps/jellyfin/` and role `k8s_jellyfin`, under agent picks 113 to 118. Pick 113 records that it was named as c1's first app with stored data in the build path's S17 hand-off. The spec [2026-11-c1-apps-under-argo-cd](../specs/2026-11-c1-apps-under-argo-cd.md) calls it "the first app built for people to use".

The owner's words this rests on:

- 2026-11-08 at 07:06 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwNNp8M1Uu2RmiKR53RXNQVLR): he asked the agents to finish the lab, set up Jellyfin and the other apps, and write the runbooks from doing it.

At main 37eb02d, 33 files in `hosts/`, 12 runbooks and D-0037 name Jellyfin. No record chose it.

Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that no piece of the lab may hold something back behind a paywall (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). STD-0006 rule 2 turns that into a test: a component fails when its owner or lead company sells an edition that holds features back from the free one. Media servers are a field where paid tiers are common. This record states Jellyfin's licence, its paid side and its way out.

## Decision Drivers

- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **The owner's ask to set up the lab's apps** (2026-11-08).
- **Replaceable** (CLAUDE.md rule 6).

## Considered Options

1. **Jellyfin.**
2. **No media server on c1.**

## Decision Outcome

Proposed: **option 1**, what runs and what the owner named. No other media server was compared; the research checked only Jellyfin's licence and its statement on paid features.

Diagram: not applicable. One app; its route and storage follow D-0021 and D-0051.

### Rules

1. **Licence.** Jellyfin, GPL-2.0. The project says it has "no premium licenses or features". The register lists it as a pass.
2. **Image** pinned by digest (STD-0003, pick 113): `docker.io/jellyfin/jellyfin`, the project's own image.
3. **Data kept.** Its claims sit in the local-path folder, which the off-box backup copies whole (D-0033, role `k8s_backup`). Jellyfin's configuration claim is the backup's app-level restore check.

### Consequences

- Good: a free media server with no paid tier.
- Bad: its data sits on one node's disk between backups (D-0051).

### Confirmation

- Jellyfin's pod in `media` is ready, and its route's `/health` check answers `Healthy` (pick 118).
- The backup's restore check brings back Jellyfin's configuration claim.

### Exit path

Media files are plain files on a volume. Another media server reads the same folder; only Jellyfin's own settings and watch history would be lost.

## Pros and Cons of the Options

### Option 1: Jellyfin

- Good: GPL-2.0; no premium features.
- Bad: not compared with other media servers.

### Option 2: No media server

- Good: one app fewer to run.
- Bad: drops an app the owner asked for.

## More Information

- Evidence: [`docs/evidence/0052-run-jellyfin-as-c1s-media-server.md`](../evidence/0052-run-jellyfin-as-c1s-media-server.md).
- Related: D-0021 (the Gateway), D-0033 (backups), D-0051 (storage), STD-0003, STD-0006 and its register (`docs/standards/components.yaml`).
