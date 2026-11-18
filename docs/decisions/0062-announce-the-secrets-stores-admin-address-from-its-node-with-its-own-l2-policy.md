---
id: D-0062
title: Give the secrets store an admin address of its own, announced only from the node its pod is pinned to, so the admin login sees the agent box's address
status: proposed
date: 2026-11-18
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0017, D-0038, D-0058]
supersedes: []
superseded-by:
revisit-when: the store runs more than one pod or its pod can move off its node; Cilium L2 announcements learn externalTrafficPolicy Local or leave beta; the lab gets BGP; the admin login stops being bound to the box's address; or the CNI is replaced
---

# Give the secrets store an admin address of its own, announced only from the node its pod is pinned to, so the admin login sees the agent box's address

## Context and Problem Statement

The store's admin AppRole signs in only from the agent box's /32 (D-0038 rule 6; `hosts/kubernetes/home/c1/apps/openbao/values.yaml`, `secret_id_bound_cidrs` and `token_bound_cidrs`). The box's lasting path to the store is TLS passthrough through Gateway `apps` (D-0058 rule 4; `apps/openbao-store/templates/box-path.yaml`). Cilium's Gateway is an Envoy proxy that opens its own connection to the backend, with "the IPs used as the source address for connections from Ingress proxies" (Cilium v1.20.4, `Documentation/gettingstarted/terminology.rst` lines 211-212). So on that path the store sees a Cilium address, not the box's, and the admin login is refused. Without it the box can't run `put`, `put-apps`, `compare` or `reseed` on prod's store. Widening the binding to the Gateway's addresses was turned down (agent pick 252): anything that reaches the Gateway would then pass it.

A LoadBalancer Service with `externalTrafficPolicy: Local` keeps the client's address (Cilium v1.20.4, `Documentation/network/kubernetes/kubeproxy-free.rst` lines 324-328; with `Cluster`, only DSR or Hybrid mode keeps it, lines 330-334). But c1 announces its load-balancer addresses with Cilium L2 announcements (D-0017), and those are "incompatible with the externalTrafficPolicy: Local on services as it may cause service IPs to be announced on nodes without pods causing traffic drops" (`Documentation/network/l2-announcements.rst` lines 84-85, again at 545-549). D-0017 rule 3 has one announcement policy for the pool, and its `revisit-when` names a cluster that needs `Local`. This is that case.

## Decision Drivers

- The admin login stays bound to the box's /32: no wider binding.
- TLS still ends at OpenBao, and the box still checks the store's own CA by the store's name.
- Every other load-balancer address, the Gateway's included, is announced as before.
- No new tool beside Cilium (D-0017's reason for option 1).

## Considered Options

1. **An admin address with its own L2 policy.** A LoadBalancer Service for OpenBao's pod with `externalTrafficPolicy: Local`, its address asked for from the pool, and an L2 announcement policy for that Service alone whose node selector is the store's seal node. The general policy leaves that Service out.
2. **Widen the binding** to the Gateway's ingress addresses (turned down, agent pick 252).
3. **DSR or Hybrid load balancing** for the whole cluster, so `Cluster` keeps the client's address.
4. **A NodePort on the seal node's own address.**

## Decision Outcome

Chosen option: 1. OpenBao's one pod can run only on the seal node: its seal key's volume is a local PersistentVolume with node affinity on that node (`apps/openbao-store/templates/seal.yaml` lines 23-30). An L2 policy whose node selector is that same node announces the address only where the pod is, which is the case `Local` needs. Option 2 opens the admin login to anything that reaches the Gateway. Option 3 changes how every Service in the cluster is forwarded, to serve one. Option 4 puts the store on a node address and a port outside the load-balancer range, which the firewall and DNS plans don't cover.

### Rules

1. **One admin address.** When the root value `openbaoAdminAddress` is set, app `openbao-store` makes Service `openbao/openbao-admin`: type LoadBalancer, `externalTrafficPolicy: Local`, port 443 to OpenBao's 8200, its address asked for with the annotation `lbipam.cilium.io/ips` (`Documentation/network/lb-ipam.rst` lines 425-455), never the pool's first or last address. It carries the label `central-hub/l2-policy: openbao-admin`.
2. **Its own policy, from the seal node only.** The same app makes `CiliumL2AnnouncementPolicy` `openbao-admin`. Its service selector is that label in namespace `openbao` (`l2-announcements.rst` lines 112-128). Its node selector is the seal node, from the same root value as the seal volume (`openbaoSealNode`), so the two can't drift apart.
3. **The general policy leaves it out.** Role `k8s_control_plane`'s policy for the pool selects every Service without the label `central-hub/l2-policy`. This changes D-0017 rule 3: one policy for the pool, except a Service that brings its own policy under this record.
4. **Only the box reaches it.** A NetworkPolicy lets the box's /32 (`openbaoBoxCidr`) reach OpenBao's 8200 on this path, and nothing else from outside the cluster. The firewall rule from the box to a prod admin address is a firewall apply (D-0036 rule 8).
5. **Order.** The role's policy change is applied before the address is set, or the general policy would announce the address from every node too.

### Consequences

- Good: the admin login keeps its /32 and works from the box.
- Good: every other address keeps one policy, and nothing else changes how it is forwarded.
- Bad: if the seal node is down, nothing answers on the address. No other node announces it, so it never points at a node without the pod. The pod is down too in that case, so nothing is lost.
- Bad: a second policy in the pool, and a label the general policy must keep leaving out.
- Bad: `openbao-store` does not prune, so unsetting the address leaves the three objects until they are deleted.

### Confirmation

- On dev, before and after: `kubectl get svc -A` shows every LoadBalancer address it had, and the L2 leases (`kubectl -n kube-system get leases`) hold one for each, the Gateway's included. A call from the box to the Gateway still answers.
- `secrets-store status` from the box reaches the store on the admin address, and the store's audit log shows the box's own address for that call.
- The lease for `openbao-admin` is held by the seal node.

## More Information

- **What changes elsewhere.** D-0017 rule 3 reads as the current rule, in the same PR (D-0001: the later record keeps the reasons).
- **Where it is built:** `hosts/kubernetes/home/c1/apps/openbao-store/templates/admin-path.yaml`, `hosts/ansible/roles/k8s_control_plane/tasks/main.yml`, and the settings `admin_address` in `docs/runbooks/set-up-the-secrets-store.md`.
- **Exit path:** unset `openbaoAdminAddress`, delete the three objects, and drop the general policy's selector. With BGP or another announcer that honours `Local`, the Service keeps working without its own policy.
- Related records: D-0017, D-0036, D-0038, D-0058.
