---
record: D-0022
batch: RB-0088 (human access to a kubeadm cluster), with RB-0078 (certificates and PKI, Kubernetes strand) behind it
researched: 2026-10-23 to 2026-10-27
method: reading of the Kubernetes docs on kubeadm certificates and kubeconfig files; a claim ledger with source labels; known-item recall check; independent check
checks: "known-item recall 25 of 25 after exclusions (24 of 30 before the last fix), by an agent that wrote no strand; the independent check sampled 25 of 49 rows in round 1 and re-checked all 38 added or changed rows in round 2, PASS WITH FIXES with all fixes applied"
---

# Evidence for D-0022: SSH now, admin kubeconfigs for break-glass, an own user next

This file summarises the research behind D-0022. It adds nothing that the research did not find. Each finding traces to a ledger row of RB-0088 (letters and numbers) or RB-0078 (S3-numbers).

## Question

What admin credentials does kubeadm create, what do the Kubernetes docs say about using them day to day, and how is a limited user made?

## Findings

1. **kubeadm creates two admin kubeconfigs.** `super-admin.conf` carries `O = system:masters`, "a break-glass, super user group that bypasses the authorization layer (for example, RBAC)"; `admin.conf` carries `O = kubeadm:cluster-admins`, which is bound to the `cluster-admin` ClusterRole when RBAC is on [1] (sourced, A01, S3-04).
2. **The docs say not to share them.** "Avoid sharing the super-admin.conf or admin.conf files. Instead, create least privileged access even for people who work as administrators and use that least privilege alternative for anything other than break-glass (emergency) access." [1] (sourced, A02, S3-18).
3. **kubeadm makes user kubeconfigs.** `kubeadm kubeconfig user` writes a kubeconfig for another user, with a group (`--org`), a name (`--client-name`) and a validity period (`--validity-period 24h` in the docs' example) [1] (sourced, A03, S3-18).
4. **For clusters with an external CA**, the docs say to delete `super-admin.conf` or move it to a safe location after it is generated [1] (sourced, A04).
5. **Certificates can't be revoked.** "Kubernetes 1.37 does not support certificate revocation. Any certificate that is issued remains valid until it expires." A certificate's CN is the username and its organization fields are its groups [2] (sourced, A06, A07). So a lost limited-user certificate is cut off by removing its RBAC binding, while one in `system:masters`, which bypasses RBAC, would need the CA rotated (inferred).
6. **OpenID Connect** is the other sign-in route the docs list, using an ID token from an OAuth2 provider [2] (sourced, A08).
7. **An RBAC binding names users or groups** as its subjects [3] (sourced, A09).
8. **The runbook copies `admin.conf` into root's kubeconfig on the control-plane node** (measured, A05).
9. **The runbook's RBAC step proved a ServiceAccount with a Role**, not a user for a person (measured in the runbook, step 19); earlier research had found RBAC a gap in the runbook (sourced, A11).

## How the decision used it

(Written from the record, not from the batch.)

D-0022 keeps both admin kubeconfigs on the node as break-glass (findings 1, 2), uses SSH to the node until the owner has a user of their own made with `kubeadm kubeconfig user` and an RBAC binding (findings 3, 7), with a short validity period because certificates can't be revoked (finding 5), and leaves identity-provider sign-in (finding 6) and the handling of `super-admin.conf` (finding 4) open. Its Consequences name that daily work runs as cluster-admin until then (findings 2, 8).

## Limits

- The RBAC page was read only in its first part.
- Identity-provider sign-in (OIDC) was not compared here; research batch RB-0087 covers identity.
- No user certificate was made on c1 during the research.

## References

Relied on (the decision depends on these):

1. Kubernetes, "Certificate Management with kubeadm", section "Generating kubeconfig files for additional users" and the external CA section. <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/> (read 2026-10-23 and 2026-10-27)
2. Kubernetes, "Authenticating", sections "X.509 client certificates" and "OpenID Connect Tokens". <https://kubernetes.io/docs/reference/access-authn-authz/authentication/> (read 2026-10-27)

Background (read, not relied on):

- [3] Kubernetes, "Using RBAC Authorization". <https://kubernetes.io/docs/reference/access-authn-authz/rbac/> (read 2026-10-27, first part only)

Research batches RB-0088 and RB-0078; their working files are in the owner's private research archive.
