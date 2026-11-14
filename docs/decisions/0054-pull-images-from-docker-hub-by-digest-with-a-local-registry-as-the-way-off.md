---
id: D-0054
title: Pull c1's container images from Docker Hub pinned by digest, and containerd from Docker's package repository, with a local pull-through registry as the way off
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: a rebuild hits Docker Hub's pull limit; Docker changes its free pull terms or its package repository; a project the lab uses moves its images to another registry; or a local registry is built for any other reason
---

# Pull c1's container images from Docker Hub pinned by digest, and containerd from Docker's package repository, with a local pull-through registry as the way off

## Context and Problem Statement

Of the images named in `hosts/`, six come from Docker Hub: Jellyfin, ntfy, PostgreSQL, BusyBox, curl and the Local Path Provisioner (the apps' `values.yaml` files and the role defaults under `hosts/`). All but PostgreSQL are pinned by digest. PostgreSQL (`docker.io/library/postgres:18.6`, roles `k8s_identity` and `k8s_backup`) is pinned by tag only, as are two images from other registries: Keycloak from quay.io in the backup's restore check, and the `agnhost` test image from registry.k8s.io in roles `k8s_certs` and `k8s_gateway`. c1's nodes install containerd from Docker's package repository (role `k8s_node`, `download.docker.com`). At main 3400f06, 12 files in `hosts/` and one runbook (`build-kubeadm-cluster.md`) name Docker Hub or Docker's package repository. No decision record chose either; each image source followed where its project publishes.

c1's Helm charts (metrics-server, Loki, Alloy, kube-prometheus-stack, External Secrets and cert-manager, in the root app's `values.yaml`) and kubeadm choose more images. They are pinned by chart or Kubernetes version, not by digest, and the Alloy chart's current values default its image to `docker.io`. This record has not counted them.

Docker Hub and Docker's package repository are hosted services run by one company, and Docker Hub limits pulls by clients that are not signed in. STD-0006 rule 3 lets a hosted service pass only with a stated exit path, and the register lists both as `hosted` with one. D-0035 lets agents tear down and rebuild the lab, and a rebuild pulls every image again.

## Decision Drivers

- **An exit path off the vendor** (REQ-0032; STD-0006 rule 3).
- **Rebuilds without a person** (D-0035): a rebuild must not stall on a pull limit.
- **Pinned** (STD-0003, which leaves the form of a pin open): this record pins images by digest.

## Considered Options

1. **Pull from Docker Hub by digest**, without signing in, and containerd from Docker's repository.
2. **A local pull-through registry** (Zot or Harbor) in front of Docker Hub and the other registries.

## Decision Outcome

Proposed: **option 1 for now**, because it is what runs and c1's image count is small. Option 2 is the way off, and the fix if a rebuild meets the pull limit. Neither was compared on cost or effort.

This record stays `proposed`: it rests on two hosted services that pass STD-0006 only by their exit path, like D-0045's public zone, which makes it a weighed choice for the owner.

Diagram: not applicable. Each node pulls straight from the registry; option 2 would add one cache in between.

### Rules

1. **What it is.** Docker Hub and Docker's package repository are hosted services; the lab uses no paid Docker plan. containerd is Apache-2.0.
2. **Digests.** Every image named in `hosts/` is pinned by digest, so the registry it comes from can change without changing what runs. The images pinned by tag only today (PostgreSQL, the restore check's Keycloak, `agnhost`) get their digests in a later change; until then they are a known gap. The images that Helm charts and kubeadm choose are not yet counted, and how to pin them is left to the change that counts them.
3. **No account.** The lab pulls without a Docker account and keeps no Docker credential.

### Consequences

- Good: no change; nothing to run.
- Bad: pulls without signing in are limited to 100 per 6 hours per IPv4 address or IPv6 /64; a full rebuild from one home address shares that limit.
- Bad: two hosted services from one company sit in the rebuild path.
- Bad: three images pinned by tag only need their digests added.
- Bad: the images that charts and kubeadm choose are pinned by chart or version only, and count against the same pull limit where they come from Docker Hub.

### Confirmation

- Every image named in `hosts/` names a digest. Today this fails for the three images in rule 2. Images chosen by Helm charts and kubeadm are not covered yet.

### Exit path

Run Zot or Harbor (both Apache-2.0) on a lab VM as a pull-through cache, and point containerd's registry mirrors at it. Because images are pinned by digest, the same digests come from the cache. containerd can come from its own releases, as the register's row says.

## Pros and Cons of the Options

### Option 1: Docker Hub by digest

- Good: nothing to run; images pinned.
- Bad: pull limit; one company.

### Option 2: local pull-through registry

- Good: Apache-2.0; no pull limit after the first pull; rebuilds work while Docker Hub is down, for images already cached.
- Bad: one more server to run and back up.

## More Information

- Evidence: [`docs/evidence/0054-pull-images-from-docker-hub-by-digest-with-a-local-registry-as-the-way-off.md`](../evidence/0054-pull-images-from-docker-hub-by-digest-with-a-local-registry-as-the-way-off.md).
- Related: D-0035 (agent rebuilds), D-0045 (a hosted service kept as proposed), STD-0003, STD-0006 and its register (`docs/standards/components.yaml`).
