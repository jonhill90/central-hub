---
id: D-0022
title: Reach home-lab clusters by SSH to the control plane for now, keep the admin kubeconfigs on the node for break-glass, and give the owner a least-privilege user of their own next
status: proposed
date: 2026-10-27
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001]
supersedes: []
superseded-by:
revisit-when: the owner's own user exists; an identity provider is chosen for cluster sign-in (BUILD-PATH S15); a second person or an agent needs cluster access; or the API server is opened to the home LAN
---

# Reach home-lab clusters by SSH to the control plane for now, keep the admin kubeconfigs on the node for break-glass, and give the owner a least-privilege user of their own next

## Context and Problem Statement

kubeadm writes two admin kubeconfigs on the first control-plane node. `super-admin.conf` is in the group `system:masters`, which bypasses RBAC. `admin.conf` is in `kubeadm:cluster-admins`, which is bound to the `cluster-admin` role. Either can do anything, and the Kubernetes docs say not to share them and to use least-privilege access for everything but break-glass.

c1's API is on the prod VLAN, which the owner's computer does not reach without a new firewall rule. The runbook copies `admin.conf` into root's kubeconfig on the control plane.

On 2026-10-26 at 21:22 UTC the owner said yes to the proposed option c on a choice card: reach the cluster by SSH to the control plane now, and later get a user of the owner's own, made with RBAC, never the admin file. This record writes that down.

## Decision Drivers

- **Least privilege** (the Kubernetes docs, and the pattern already used for Proxmox, where `root@pam` is break-glass and Terraform has its own limited account).
- **Works today** with no new firewall rule.
- **Learning Kubernetes** (PRD goal 1): making a user with RBAC is a CKA exercise.
- **Replaceable** (REQ-0011): a later sign-in through an identity provider can replace the user certificate.

## Considered Options

1. **SSH to the control plane through the Proxmox host, run kubectl there.**
2. **A kubeconfig on the owner's computer**, with the home LAN allowed to reach the API on port 6443.
3. **Option 1 now; option 2 later, with a user of the owner's own** made by RBAC, never the admin file.

## Decision Outcome

Chosen option: **3**. The owner said yes to it on 2026-10-26 at 21:22 UTC.

```mermaid
flowchart LR
  O[Owner's computer] -->|SSH via the Proxmox host| N[Control-plane node]
  N --> A["admin.conf, super-admin.conf<br/>stay on the node: break-glass"]
  O -. later .->|"own kubeconfig, port 6443"| API[API server]
  U["Own user: client certificate<br/>+ RBAC binding"] -. later .-> API
```

*In words:* today the owner opens an SSH session on the control-plane node and runs kubectl there. The admin kubeconfigs never leave the node. Next, the owner gets a user of their own with only the rights it needs, and only then does a kubeconfig sit on the owner's computer.

### Rules

1. **Admin kubeconfigs stay on the node.** `admin.conf` and `super-admin.conf` are never copied off the control-plane node or into this repository (CLAUDE.md rule 4). They are break-glass.
2. **Daily access is by SSH for now**, through the Proxmox host as jump host, with the node's key-only SSH.
3. **The owner's own user comes next.** It is a client certificate made with `kubeadm kubeconfig user`, with a short validity period, because Kubernetes can't revoke a certificate before it expires, and an RBAC binding to the rights it needs (agent pick for the method; the owner's answer named RBAC). When it exists, port 6443 opens to the owner's computer only.
4. **Agents** that reach the cluster use the same SSH route until per-agent identities exist (Activation gate item 1).

### Not decided here

- the RBAC role the owner's user gets;
- sign-in through an identity provider (BUILD-PATH S15, research batch RB-0087);
- whether `super-admin.conf` stays on the node or moves to an offline store, which the Kubernetes docs suggest for clusters with an external CA (agent note).

### Consequences

- Good: the admin credential never travels; nothing new is open on the network.
- Good: the next step is also CKA practice.
- Bad: until the own user exists, daily work runs as cluster-admin on the node, which is what the Kubernetes docs warn against.
- Bad: kubectl runs on the node, not on the owner's computer, so local tools that read a kubeconfig don't work yet.
- Bad: a user certificate can't be revoked in Kubernetes 1.37. A lost one is cut off by deleting its RBAC binding and runs out at its validity period; a lost `super-admin.conf`, which bypasses RBAC, would need the cluster CA rotated, which is why it never leaves the node.

### Confirmation

- No file under `hosts/` or `docs/` holds a kubeconfig (the docs check and secret scanning).
- When the own user exists, `kubectl auth can-i --list` as that user shows only its granted rights.

## Pros and Cons of the Options

### 1. SSH only

- Good: simplest; nothing to open.
- Bad: no end point; daily work stays as cluster-admin.

### 2. A kubeconfig on the owner's computer

- Good: local tools work.
- Bad: needs a firewall rule now; with only the admin file available it would copy the admin credential off the node.

## More Information

- **Evidence:** [../research/0022-reach-clusters-by-ssh-now-and-keep-admin-kubeconfigs-for-break-glass.md](../research/0022-reach-clusters-by-ssh-now-and-keep-admin-kubeconfigs-for-break-glass.md), from research batch RB-0088, with research batch RB-0078 behind it.
- **Exit path:** delete the user's RBAC binding (the certificate then has no rights) and let it expire; or move to identity-provider sign-in. The admin kubeconfigs are untouched either way.
- Related records: D-0013, D-0017. Related runbooks: `docs/runbooks/build-kubeadm-cluster.md` steps 8 and 19.
