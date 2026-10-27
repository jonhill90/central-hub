---
record: D-0017
batch: RB-0067 (load-balancer addresses), with RB-0088 (kube-proxy replacement and L2 announcement costs)
researched: 2026-10-22 to 2026-10-27
method: reading of the Kubernetes, Cilium and MetalLB docs; three public home-lab repositories cloned at pinned commits (RB-0067); a claim ledger with source labels; known-item recall check; independent check
checks: "RB-0067: known-item recall 60 of 65, independent check PASS WITH FIXES with all fixes applied. RB-0088: known-item recall 25 of 25 after exclusions (24 of 30 before the last fix), independent check sampled 25 of 49 rows in round 1 and re-checked all 38 added or changed rows in round 2, PASS WITH FIXES with all fixes applied"
---

# Evidence for D-0017: Cilium in place of kube-proxy, and L2 announcements for load-balancer addresses

This file summarises the research behind D-0017. It adds nothing that the research did not find. Each finding traces to a ledger row of RB-0067 (B-numbers) or RB-0088 (letters and numbers).

## Question

How does traffic from outside reach a Kubernetes cluster on VMs behind a home-lab router, who answers for the load-balancer addresses, and what does it cost to let Cilium do it?

## Findings

1. **Kubernetes ships no load balancer outside a cloud.** "Kubernetes does not directly offer a load balancing component; you must provide one, or you can integrate your Kubernetes cluster with a cloud provider" [1]. Without one, a LoadBalancer Service stays pending (sourced, B01).
2. **Seven ways were listed**: MetalLB L2, Cilium LB IPAM with L2 announcements, BGP, HAProxy outside the cluster on NodePorts, kube-vip, a gateway on the node's own address, and the Tailscale operator; for the L2 options the pool sits inside the node subnet and outside DHCP (RB-0067 synthesis §3-4; sourced and inferred as labelled there).
3. **Cilium L2 announcements need kube-proxy replacement.** "Kube Proxy replacement mode must be enabled" [2] (sourced, B13, L02). Cilium's Gateway API needs it too [3] (sourced, B16, C01).
4. **Three public home-lab repositories run Cilium with kube-proxy replacement when they use LB IPAM**; two announce on L2 with a pool inside the node subnet, one of them a `/27` [6, 7, 8] (measured, B28-B31).
5. **L2 announcements are beta.** "This is a beta feature" [2] (sourced, L01).
6. **One node answers for each address.** One node receives all ARP and NDP requests for an address, there is no traffic balancing, and the feature is incompatible with `externalTrafficPolicy: Local` [2] (sourced, L03). MetalLB L2 has the same one-node shape [4] (sourced, L06).
7. **Failover is lease-based**, 10 to 20 seconds with the default settings, and the leases raise API server use; the default client rate limit is 5 queries per second with bursts of 10 [2] (sourced, L04, L05).
8. **kube-proxy replacement depends on socket load balancing in the kernel**; the agent stops when kernel support is missing. kubeadm skips the kube-proxy addon with `--skip-phases=addon/kube-proxy`, and Cilium says to delete the kube-proxy ConfigMap so a kubeadm upgrade does not reinstall it [5] (sourced, K01, K02, K07).
9. **Known limits of the replacement**: SCTP supported only in basic cases; NFS and SMB mounts to a Service cluster IP may break with socket load balancing; DSR NodePort mode and TCP Fast Open [5] (sourced, K03).
10. **Going back is disruptive.** Removing kube-proxy breaks existing Service connections, and switching the replacement on or off on a running cluster breaks existing connections; the page describes no full way back [5] (sourced, K04).
11. **With kube-proxy replaced, kube-proxy's iptables Service chains are absent**, so material that teaches Services through those chains does not match such a cluster (inferred, X03).

## How the decision used it

(Written from the record, not from the batch.)

D-0017 takes option 2 of RB-0067 because Cilium is already the CNI and the same switch serves D-0021 (findings 3, 4). Its Consequences list the beta status, the one-node limit, the failover time, the API load and the rebuild-to-go-back cost (findings 5-10), and the learning cost (finding 11). Its exit path moves the pool to MetalLB (finding 6).

## Limits

- MetalLB, BGP and kube-vip were read, not run; only Cilium was built.
- The repository sample is three home-lab repositories, not a survey.
- Cilium BGP with kube-proxy kept was not tested.

## References

Relied on (the decision depends on these):

1. Kubernetes, "Service", Service type list. <https://kubernetes.io/docs/concepts/services-networking/service/> (read 2026-10-22)
2. Cilium 1.20.4, "L2 Announcements / L2 Aware LB". <https://docs.cilium.io/en/stable/network/l2-announcements/> (read 2026-10-22 and 2026-10-27)
3. Cilium 1.20.4, "Gateway API Support". <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/> (read 2026-10-22 and 2026-10-27)
4. MetalLB, "Concepts" and "Layer 2 mode". <https://metallb.io/concepts/> and <https://metallb.io/concepts/layer2/> (read 2026-10-22)
5. Cilium 1.20.4, "Kubernetes Without kube-proxy". <https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/> (read 2026-10-27)

Background (read, not relied on):

- [6] onedr0p/cluster-template at 4f7508e795d6. <https://github.com/onedr0p/cluster-template> (cloned 2026-10-22)
- [7] khuedoan/homelab at 606a2557fb7b. <https://github.com/khuedoan/homelab> (cloned 2026-10-22)
- [8] onedr0p/home-ops at 50cfcd0d10d0. <https://github.com/onedr0p/home-ops> (cloned 2026-10-22)
- [9] Cilium 1.20.4, "LB IPAM". <https://docs.cilium.io/en/stable/network/lb-ipam/> (read 2026-10-22)

Research batches RB-0067 and RB-0088; their working files are in the owner's private research archive.
