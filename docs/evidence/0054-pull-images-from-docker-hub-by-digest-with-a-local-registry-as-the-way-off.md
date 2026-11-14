---
record: D-0054
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: on 2026-11-14 at about 12:20 UTC, every image and package address under `hosts/` read at main 3400f06, and the counts re-run unchanged at main 5fa9bb4; the chart list in the root app's `values.yaml` and the Alloy chart's default values read; Docker's pull-limit page opened; the licence files of Zot, Harbor and containerd read from their repositories; the register row for Docker Hub read
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0054: Docker Hub and Docker's package repository

This file summarises the research behind D-0054. It adds nothing the research and the pages listed below did not find.

## Question

Where do c1's images and its containerd package come from, how are they pinned, what limits come with that source, and what is the way off?

## Findings

1. **Images from Docker Hub.** At main 3400f06, six of the images named in `hosts/` come from `docker.io` [1] (measured):
   - `jellyfin/jellyfin:12.2` (role `k8s_jellyfin`), `binwiederhier/ntfy:v2.35.0` (the alerts app's `values.yaml`), `curlimages/curl:8.22.0` (the Jellyfin app's `values.yaml`), `library/busybox:1.37.0` and `rancher/local-path-provisioner:v0.0.37` (role `k8s_storage`), each pinned by digest;
   - `library/postgres:18.6` (roles `k8s_identity` and `k8s_backup`), pinned by tag only.
2. **Tag-only pins from other registries.** At the same commit, `quay.io/keycloak/keycloak:26.8.1` (the backup's restore check, role `k8s_backup`) and `registry.k8s.io/e2e-test-images/agnhost:2.53` (roles `k8s_certs` and `k8s_gateway`, and playbook `k8s.yml`) are pinned by tag only [1] (measured).
3. **containerd from Docker's repository.** Role `k8s_node` adds `https://download.docker.com/linux/centos/docker-ce.repo` (`tasks/main.yml` line 183), and runbook `build-kubeadm-cluster.md` gives the same step [1] (measured).
4. **Reach.** 12 files in `hosts/` and one runbook name `docker.io` or `download.docker.com`. D-0051 and D-0052 name their images' addresses; no record weighs where images come from. Indexes are not counted [1] (measured).
5. **Pull limit.** Docker's page says pulls without signing in are limited to 100 per 6 hours per IPv4 address or IPv6 /64 subnet, and signed-in Personal accounts get 200 [2] (sourced).
6. **Licences of the way off.** Zot [3], Harbor [4] and containerd [5] are Apache-2.0 (sourced).
7. **The register.** `docs/standards/components.yaml` lists "Docker Hub and Docker's package repository" as `hosted`, with a local pull-through registry (Zot or Harbor) and containerd from its own releases as the exit path [1] (measured).
8. **The pin standard.** STD-0003 is `active` and leaves open how a version is pinned (an exact version, a digest or a lock file) [1] (measured).
9. **Images chosen by charts, kubeadm, operators and manifests.** The root app's `values.yaml` installs six charts (metrics-server, Loki, Alloy, kube-prometheus-stack, External Secrets and cert-manager), each pinned by chart version; their images are not named in `hosts/` and were not counted. Role `k8s_identity` applies the Keycloak operator's manifests from `keycloak/keycloak-k8s-resources` at 26.8.1, and role `k8s_gitops` applies Argo CD's `install.yaml` at v3.5.5; the images these choose were not counted either [1] (measured). The Alloy chart's values default its image registry to `docker.io` [6] (sourced, the chart's main branch, not the pinned version).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 to 4 are the context and rule 2's known gap. Finding 5 is the pull-limit consequence. Findings 6 and 7 are the exit path and rule 1. Finding 8 is why the record sets digests as the pin form. Finding 9 scopes rule 2 and the Confirmation to the images named in `hosts/`.

## Limits

- Docker's paid plans and the terms of its package repository were not read.
- Zot and Harbor were not tried; neither was compared on cost or effort.
- How many pulls a full rebuild of c1 makes was not measured.
- The images that c1's Helm charts, kubeadm, and operators or install manifests choose were not counted, so neither their registries nor their pin form is listed here.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. Repository search and code read of central-hub at 3400f06 (this repository).
2. Docker Docs, "Docker Hub pull usage and limits". <https://docs.docker.com/docker-hub/usage/pulls/>
3. Zot LICENSE. <https://raw.githubusercontent.com/project-zot/zot/main/LICENSE>
4. Harbor LICENSE. <https://raw.githubusercontent.com/goharbor/harbor/main/LICENSE>
5. containerd LICENSE. <https://raw.githubusercontent.com/containerd/containerd/main/LICENSE>
6. Grafana Alloy Helm chart, `values.yaml` (main branch). <https://raw.githubusercontent.com/grafana/alloy/main/operations/helm/charts/alloy/values.yaml>

The batch is RB-0208; its working files are private.
