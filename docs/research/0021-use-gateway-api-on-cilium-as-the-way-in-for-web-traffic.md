---
record: D-0021
batch: RB-0088 (Gateway API controllers), with RB-0067 and RB-0045 (Kubernetes tool map) behind it
researched: 2026-10-27
method: reading of the Gateway API project's implementations page, each controller's own docs, release pages and licence files, and Microsoft Learn for vendor practice; a claim ledger with source labels; known-item recall check; independent check
checks: "known-item recall 25 of 25 after exclusions (24 of 30 before the last fix), by an agent that wrote no strand; the independent check sampled 25 of 49 rows in round 1 and re-checked all 38 added or changed rows in round 2, PASS WITH FIXES with all fixes applied"
---

# Evidence for D-0021: the Gateway API, served by Cilium

This file summarises the research behind D-0021. It adds nothing that the research did not find. Each finding traces to a ledger row of RB-0088 (letters and numbers) or RB-0067 (B-numbers).

## Question

Which Gateway API controllers fit a home-lab cluster that already runs Cilium, how do they compare on conformance, data plane, needs, licence and exit path, and what does Microsoft do?

## Findings

1. **The Kubernetes project recommends the Gateway API over Ingress**: "The Kubernetes project recommends using Gateway instead of Ingress. The Ingress API has been frozen." [1] (sourced, B40). A Gateway belongs to exactly one GatewayClass, which names its controller [2] (sourced, B41). The ingress-nginx project's best-effort maintenance ended in March 2026, with no further releases or fixes after it [13] (sourced, RB-0045 A3).
2. **All four controllers show as conformant** on the Gateway API site's badges: Cilium, Envoy Gateway and Traefik show v1.6.1, NGINX Gateway Fabric v1.6.3; none is listed as partially conformant [3] (sourced, G01, G03-G06).
3. **The controllers' own v1.6 conformance reports** pass the core tests in every profile, except Traefik's HTTP profile, which is "partial" with one test skipped (`HTTPRouteMultipleGateways`). Extended HTTP features supported: Envoy Gateway 36 of 38, Cilium 32 of 38, NGINX Gateway Fabric 30 of 38, Traefik 19 of 38, as the site's v1.6 comparison table also shows [14, 19] (measured, R01-R05, R08).
4. **Governance**: Cilium and Envoy are CNCF Graduated projects, and Envoy Gateway is an Envoy subproject; Traefik and NGINX Gateway Fabric are led by their vendors [15, 16] (sourced for Cilium and Envoy, V01-V04; inferred for Traefik and NGINX Gateway Fabric from their repositories' owners).
5. **Practitioners**: two home-lab repositories that run Cilium with kube-proxy replacement and L2 announcements use another way in: one Envoy Gateway, the other NGINX Ingress [17, 18] (sourced, H01-H05).
6. **The conformance figures for Cilium disagree.** The same site's Cilium text says v1.4.0 as of Cilium 1.19 [3], while Cilium's docs say it "supports Gateway API v1.6.3 ... all the Core conformance tests are passed" [4] (sourced, G02, C02).
7. **Cilium's controller needs kube-proxy replacement** and the L7 proxy, and in its default setting uses iptables TPROXY, so nodes need iptables and netfilter modules [4] (sourced, C01, C04).
8. **Data planes differ.** Cilium sends Gateway traffic through a per-node Envoy [4]; Envoy Gateway gives each Gateway its own Envoy fleet unless merged [5]; Traefik is its own proxy [6]; NGINX Gateway Fabric makes a dedicated NGINX Deployment per Gateway [7] (sourced, C03, E02, T01, N01).
9. **The other three name no CNI or kube-proxy need** on the pages read (inferred from absence, X02; not tested).
10. **Licences**: Cilium, Envoy Gateway and NGINX Gateway Fabric are Apache-2.0; Traefik is MIT; NGINX Plus is an optional paid data plane for NGINX Gateway Fabric [7, 8] (sourced, T03, T04, E04, N02, N04).
11. **Releases are current**: Envoy Gateway v1.9.3 on 26 October, Traefik v3.7.16 on 20 October, NGINX Gateway Fabric v2.8.0 (its report dated 2026-10-13), Cilium docs at 1.20.4; the release pages show no year, so 2026 is inferred from the reports [9, 10, 11, 14] (sourced, E03, T02, N03, R04, K06).
12. **`spec.addresses` on a Cilium Gateway** takes IP addresses and works with LB IPAM; the older address annotation is slated for deprecation [4] (sourced, C05).
13. **Microsoft's Application Gateway for Containers implements the Gateway API**, with an Azure-managed data plane outside the cluster and an in-cluster controller [12] (sourced, M01).
14. **Coupling**: with Cilium's controller, replacing the CNI also replaces the gateway controller; the Gateway and HTTPRoutes are the portable part (inferred, X01).

## How the decision used it

(Written from the record, not from the batch.)

D-0021 picks the Gateway API over Ingress (finding 1) and Cilium's controller among four conformant ones (findings 2, 3), because it adds no pods where Cilium already runs (finding 8) and D-0017 already set the switch it needs (finding 7). Its Consequences name the CNI coupling (finding 14), the TPROXY need (finding 7), the conformance disagreement and the extended-feature gap to Envoy Gateway (findings 3, 6). Its options weigh governance and what practitioners use (findings 4, 5). Its exit path is a GatewayClass change to any of the other three (findings 2, 9), checked against the target's report for extended features (finding 3).

## Limits

- Only Cilium's controller was run; the others were read, not tested.
- Release data came from release pages, because the GitHub API was not reachable from the research session; the pages show no year.
- Cilium's release cadence was not read.
- No benchmark or failure study was read.

## References

Relied on (the decision depends on these):

1. Kubernetes, "Ingress". <https://kubernetes.io/docs/concepts/services-networking/ingress/> (read 2026-10-22)
2. Kubernetes, "Gateway API". <https://kubernetes.io/docs/concepts/services-networking/gateway/> (read 2026-10-22)
3. Gateway API, "Implementations". <https://gateway-api.sigs.k8s.io/implementations/> (read 2026-10-27)
4. Cilium 1.20.4, "Gateway API Support". <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/> (read 2026-10-27)
5. Envoy Gateway v1.9, docs home and "Deployment Mode". <https://gateway.envoyproxy.io/docs/> and <https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/> (read 2026-10-27)
6. Traefik v3.7, "Kubernetes Gateway API provider". <https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/> (read 2026-10-27)
7. NGINX Gateway Fabric, "Gateway architecture". <https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-architecture/> (read 2026-10-27)

Background (read, not relied on):

- [8] Licence files: <https://github.com/cilium/cilium/blob/main/LICENSE>, <https://github.com/envoyproxy/gateway/blob/main/LICENSE>, <https://github.com/traefik/traefik/blob/master/LICENSE.md>, <https://github.com/nginx/nginx-gateway-fabric/blob/main/LICENSE> (read 2026-10-27)
- [9] Envoy Gateway releases. <https://github.com/envoyproxy/gateway/releases> (read 2026-10-27)
- [10] Traefik releases. <https://github.com/traefik/traefik/releases> (read 2026-10-27)
- [11] NGINX Gateway Fabric releases. <https://github.com/nginx/nginx-gateway-fabric/releases> (read 2026-10-27)
- [12] Microsoft Learn, "What is Application Gateway for Containers?". <https://learn.microsoft.com/azure/application-gateway/for-containers/overview> (read 2026-10-27)
- [13] Kubernetes blog, "Ingress NGINX Retirement", 2025-11-11. <https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/> (read 2026-10-18)
- [14] Gateway API conformance reports, v1.6: Cilium v1.20.0, Envoy Gateway v1.9.0, Traefik v3.7.10, NGINX Gateway Fabric v2.8.0. <https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports/v1.6> (read 2026-10-27)
- [15] CNCF, "Cilium". <https://www.cncf.io/projects/cilium/> (read 2026-10-27)
- [16] CNCF, "Envoy". <https://www.cncf.io/projects/envoy/> (read 2026-10-27)
- [17] onedr0p/cluster-template README. <https://github.com/onedr0p/cluster-template> (read 2026-10-27)
- [18] khuedoan/homelab README. <https://github.com/khuedoan/homelab> (read 2026-10-27)
- [19] Gateway API, "v1.6 implementation comparison". <https://gateway-api.sigs.k8s.io/docs/implementations/versions/v1.6/> (read 2026-10-27)

Research batches RB-0088, RB-0067 and RB-0045; their working files are in the owner's private research archive.
