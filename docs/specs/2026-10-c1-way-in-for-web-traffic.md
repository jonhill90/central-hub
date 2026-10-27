---
title: Let web traffic into c1's apps, with certificates browsers trust
status: proposed
date: 2026-10-27
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Let web traffic into c1's apps, with certificates browsers trust

## What and why

c1 runs, but no app on it can be reached by name from the home LAN. This change gives c1 one way in for web traffic and then HTTPS with certificates that browsers trust without any device setup. It serves PRD goal 1 (run upstream Kubernetes, starting with one home-lab cluster) and goal 6 (everything controllable from this repo). It crosses systems (the cluster, the firewall's DNS and the public DNS host for certificate challenges) and spans several sessions, so it gets a spec (D-0007 rule 2).

This spec is written after part 1 was built (BUILD-PATH S11, merged in PR #46) and while part 2 is being built (BUILD-PATH S12). Its acceptance criteria were written by an agent that wrote none of that code (D-0007 rule 4).

Parts, in order:

1. Load-balancer addresses on the node VLAN from Cilium, with Cilium in place of kube-proxy (D-0017).
2. One shared Gateway, served by Cilium's Gateway API controller, at a pinned address from the pool, with one wildcard name `*.apps.c1.prod.<zone>` in the lab DNS (D-0021).
3. cert-manager, with Let's Encrypt as the certificate source, proving the zone by DNS-01 (the owner's yes of 2026-10-26 at 23:05 UTC).
4. An HTTPS listener on the shared Gateway with a certificate for the app names; whether that is one wildcard certificate or one per app is the owner's open question in the S12 work.

## Out of scope

- Reaching any app from the internet. Names resolve only inside the lab.
- ExternalDNS and the DNS tool that replaces the OPNsense override (AdGuard Home, BL-0164).
- A private certificate authority.
- Other clusters and the VPS.

## Acceptance criteria

### Automated

- [ ] `kubectl -n kube-system get ds kube-proxy`: not found.
- [ ] `kubectl get gatewayclass cilium`: `ACCEPTED True`.
- [ ] `kubectl -n gateway get gateway apps`: `PROGRAMMED True`, with the pinned address from the pool in STD-0002.
- [ ] From a lab machine outside the cluster, a request for a test app's name under `apps.c1.prod.<zone>` returns the app's answer, and a name with no route returns 404 (the smoke test).
- [ ] From a node, the test app's name resolves to the Gateway's address.
- [ ] cert-manager's ClusterIssuer for Let's Encrypt shows `Ready True`, first against the staging server, then the real one.
- [ ] The certificate for the app names shows `Ready True`, and `openssl s_client` against the Gateway's HTTPS listener shows a chain to a Let's Encrypt root and the expected name.
- [ ] A second run of every playbook involved reports `changed=0`.
- [ ] The docs check passes, and a search of the diff finds no real hostname, domain, single address or token.

### Manual (what the owner checks)

- [ ] The owner opens a test app's name in a browser on the home LAN and sees no certificate warning.
- [ ] The owner can say, for each part, which record holds the choice and what the exit path is.
- [ ] The DNS token used for DNS-01 can change only the zone's challenge records, as far as the DNS host allows, and is not in the repository.

## Points to (read when)

- [D-0017](../decisions/0017-replace-kube-proxy-and-announce-lb-addresses-with-cilium.md): read when touching kube-proxy, Cilium's values or the pool.
- [D-0021](../decisions/0021-use-gateway-api-on-cilium-as-the-way-in-for-web-traffic.md): read when adding a route or a listener.
- [STD-0001](../standards/0001-names.md): read when naming an app (service names and wildcard certificates).
- [STD-0002](../standards/0002-ip-address-plan.md): read when giving the Gateway an address.
- [STD-0003](../standards/0003-version-choice.md): read when pinning cert-manager or the CRDs.
- [Build a kubeadm cluster](../runbooks/build-kubeadm-cluster.md): steps 9 and 10a.

## Decision log

- 2026-10-26: Load-balancer addresses from Cilium LB IPAM with L2 announcements, so Cilium replaces kube-proxy (owner's yes, 22:46 UTC; D-0017).
- 2026-10-26: Cilium's Gateway API is the way in for web traffic (owner's yes, 22:47 UTC; D-0021).
- 2026-10-26: Certificates from Let's Encrypt through cert-manager (owner's yes, 23:05 UTC).
- 2026-10-26: Agent choices for the owner's review: one shared Gateway `apps` in namespace `gateway`, its pinned address, the wildcard DNS override, Gateway API CRDs v1.6.3 on the standard channel, tcp 80 open in the nodes' firewall zone (`hosts/AGENT-PICKS.md` rows 48 to 56).
