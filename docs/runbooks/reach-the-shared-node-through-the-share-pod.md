---
title: Reach the shared node through the share pod
status: draft
kind: manual
trigger: once, after another tailnet shares a node into this one; again to rotate the pod's key
runner: an agent lane, with the tailnet policy applied as D-0036 rule 8 says; seeding the pod's key is a secret step (D-0042 rule 6)
outcome: agents on the agent box open an SSH connection to the shared node through one pod on c1, and neither the agent box nor any lab machine is on the other tailnet
needs: external_tailnets filled in the private home.tfvars and the tailnet policy applied from this commit; the other tailnet's admin has granted the tag; app share-pod Synced; the pod's key seeded
private-values: [external_tailnets, shareTarget, share-pod-authkey]
files: [hosts/kubernetes/home/c1/apps/share-pod/, hosts/kubernetes/home/c1/root/values.yaml, hosts/terraform/home/tailnet-policy/policy.hujson.tftpl, hosts/ansible/roles/k8s_gitops/]
last-tested: not yet run
superseded-by:
---

# Reach the shared node through the share pod

A node in another tailnet is shared into this one. The agent box is the lab's most sensitive machine, because its keys folder holds the secrets store's keys (D-0038), so it never joins that path itself. One small pod on c1 does instead. It has its own tailnet identity, tag `tag:share-pod`, holds no lab secret and no Kubernetes credential, and forwards one TCP port to the shared node. The agent's own SSH key and the shared node's host key check stay end to end through it, because the pod forwards raw TCP.

```text
agent box (tag:agent-box) --tcp 2222--> share pod (tag:share-pod) --tcp--> shared node (other tailnet)
```

What limits it, each in one place:

- **This tailnet's policy** ([`policy.hujson.tftpl`](../../hosts/terraform/home/tailnet-policy/policy.hujson.tftpl), only when `external_tailnets` is set): `tag:agent-box` may reach `tag:share-pod` on tcp 2222 only. The pod has no grant, so it reaches nothing here. Policy tests deny the pod the Proxmox host, the VPS and the agent box, and deny the agent box the pod's port 22.
- **The other tailnet's policy:** its admin grants `tag:share-pod` (named in `allowExternalReferencesTo`) the one node and port. A grant is ignored unless this side lists the tag there [source: https://tailscale.com/docs/features/declarative-node-sharing]. `allowIncomingConnections` stays false, so the other tailnet can't reach anything here.
- **The cluster:** a restricted namespace, no ServiceAccount token, a read-only root filesystem, state in memory, and a NetworkPolicy with no ingress and egress only to DNS and public addresses, with the private and tailnet ranges excepted. So the pod reaches its peers through public paths or the relays, never through a lab address.
- **The pod's own key:** an ephemeral, pre-approved auth key tagged `tag:share-pod` only. It is reusable, because the pod registers again each time it restarts, so a stolen key can join any number of devices with this tag until it expires (90 days) or is revoked. Each such device would reach only what the other tailnet grants the tag, and nothing here, since the tag has no grant of its own. The tailnet removes an ephemeral node 30 to 60 minutes after it goes away [source: https://tailscale.com/kb/1111/ephemeral-nodes].
- **Who approves:** the apply of the policy is a tailnet change (D-0036 rule 8). Making and seeding the key is a secret and an access right for a new tagged device (D-0042 rule 6). The owner covered both, and the policy change, in the message of 2026-11-16 04:54:26 UTC in this work's thread (cmsg_01X43rfNYp4H1dL1V2dkfkwNB33wsxYuc5AiJubmyZLrSX).
- **The egress limit holds only if c1 enforces NetworkPolicy.** That has not been measured on c1 yet; step 7 checks it.

## Steps

1. Put the external tailnet in `home.tfvars` and apply the policy from this commit, following [the tailnet README](../../hosts/terraform/README.md#external-tailnets-declarative-node-sharing): the first plan's gate and the apply card come first. The policy then holds `tag:share-pod`, its grant and its tests.

2. Ask the other tailnet's admin, on the shared notebook board, for a grant from `tag:share-pod` of this tailnet to the shared node on the one port. Word it with the neutral names and no ID in it.

3. Make the pod's key in the admin console or API: a reusable, ephemeral, pre-approved auth key, tag `tag:share-pod`, 90 days. Seed it into namespace `secret-source` as `share-pod-authkey` with field `value` ([seed-secret-source.md](seed-secret-source.md)). Never print it.

4. Set `k8s_gitops_source_share_target` to `<address>:<port>` of the shared node in the private inventory and apply `k8s_gitops`. The root Application then passes `shareTarget` to app `share-pod`, which renders nothing while it is empty.

5. Check the pod.

   ```sh
   c1-read get pods -n share-pod
   c1-read logs -n share-pod deploy/share-pod
   ```

   expect: one pod Running; the log says it is logged in with tag `tag:share-pod`.

6. From the agent box, open the connection through the pod. The pod's tailnet name is `share-pod`.

   ```sh
   ssh -p 2222 <user>@share-pod
   ```

   expect: the shared node's own SSH banner and host key. If the other side has not granted the tag yet, the connection hangs and then fails; that is the other tailnet's grant, not this side.

7. Prove the limits. First check that c1 enforces NetworkPolicy: from a throwaway pod in namespace `share-pod` with the same policy, a connection to a private lab address must fail. Then, from the agent box: `ssh -p 22 share-pod` and a connection to the shared node's address directly must both fail. From the pod, nothing here is reachable (`c1-read` can't run commands in the pod; the policy tests are the proof).

## Rotate

Make a new key as in step 3, seed it, and delete the old key in the admin console. ExternalSecret refreshes within an hour; restart the pod to use it at once.

## Take it away

Remove the `share-pod` entry from `root/values.yaml` (prune is off, so delete the namespace too), delete `tag:share-pod` from `allowExternalReferencesTo` by emptying `external_tailnets`, and delete the key. The agent box then has no path to the shared node.
