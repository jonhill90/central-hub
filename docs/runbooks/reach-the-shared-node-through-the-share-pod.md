---
title: Reach the shared node through the share pod
status: draft
kind: manual
trigger: once, after another tailnet shares a node into this one; again to rotate the pod's key
runner: an agent lane, with the tailnet policy applied as D-0036 rule 8 says; seeding the pod's key is a secret step (D-0042 rule 6)
outcome: agents on the agent box open an SSH connection to the shared node through one pod on c1, and neither the agent box nor any lab machine is on the other tailnet
needs: external_tailnets filled in the private home.tfvars, share_pod_enabled set true there, and the tailnet policy applied from this commit; the other tailnet's admin has granted the tag; app share-pod Synced; the pod's key seeded
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

- **This tailnet's policy** ([`policy.hujson.tftpl`](../../hosts/terraform/home/tailnet-policy/policy.hujson.tftpl), only when `share_pod_enabled` is true and `external_tailnets` is set): `tag:agent-box` may reach `tag:share-pod` on tcp 2222 only. The pod has no grant, so it reaches nothing here. Policy tests deny the pod the Proxmox host, the VPS and the agent box, and deny the agent box the pod's port 22.
- **The other tailnet's policy:** its admin grants `tag:share-pod` (named in `allowExternalReferencesTo`) the one node and port. A grant is ignored unless this side lists the tag there [source: https://tailscale.com/docs/features/declarative-node-sharing]. `allowIncomingConnections` stays false. The Tailscale page does not say what false enforces, so the limit that holds is this side's policy: no rule here names the other tailnet's nodes, or `tag:share-pod`, as a source, and grants deny by default. The pod having no grant only limits what the pod itself can reach here [source: https://tailscale.com/docs/features/declarative-node-sharing; https://tailscale.com/kb/1324/grants].
- **The cluster:** a restricted namespace, no ServiceAccount token, a read-only root filesystem, state in memory, and a NetworkPolicy with no ingress and egress only to DNS and public addresses, with the private and tailnet ranges excepted. So the pod reaches its peers through public paths or the relays, never through a lab address.
- **The pod's own key:** an ephemeral, pre-approved auth key tagged `tag:share-pod` only. It is reusable, because the pod registers again each time it restarts, so a stolen key can join any number of devices with this tag until it expires (90 days) or is revoked. Each such device would reach only what the other tailnet grants the tag, and nothing here, since the tag has no grant of its own. The tailnet removes an ephemeral node 30 to 60 minutes after it goes away [source: https://tailscale.com/kb/1111/ephemeral-nodes].
- **Who approves:** the apply of the policy is a tailnet change (D-0036 rule 8), and making and seeding the key is a secret and an access right for a new tagged device (D-0042 rule 6). Each goes to the owner as those rules say, on a card naming the step and the commit.
- **The egress limit holds only if c1 enforces NetworkPolicy.** That has not been measured on c1 yet, and agents can't check it today; until it is proved, treat the egress limit as designed, not proven (step 7).

## Steps

1. Put the external tailnet in `home.tfvars` and apply the policy from this commit, following [the tailnet README](../../hosts/terraform/README.md#external-tailnets-declarative-node-sharing): the first plan's gate and the apply card come first. That first apply keeps `share_pod_enabled` false, so the live share stays as it is. Then set `share_pod_enabled = true` in `home.tfvars` and plan again: the sections that differ are `externalTailnets` (the tag added to `allowExternalReferencesTo`), `tagOwners`, `grants` and `tests`, and nothing else. That is its own tailnet apply (D-0036 rule 8), with its own card. The policy then holds `tag:share-pod`, its grant and its tests.

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
   ssh -p 2222 -o ForwardAgent=no -o IdentitiesOnly=yes -i <dedicated key> <user>@share-pod
   ```

   expect: the shared node's own SSH banner and host key. Use a key made for this node only, never forward the agent, and pin the node's host key in `known_hosts` the first time you check it with the other tailnet's admin. If the other side has not granted the tag yet, the connection hangs and then fails; that is the other tailnet's grant, not this side.

7. Prove the limits. Read the NetworkPolicy with `c1-read get networkpolicy -n share-pod -o yaml`: no ingress, egress to DNS and public addresses only. That it is enforced is not yet checkable by agents: c1's pod network is Cilium, which enforces NetworkPolicy (`hosts/ansible/roles/k8s_control_plane/defaults/main.yml`), but `c1-read` has no read on `cilium.io` kinds, and a live connection test needs a pod started with write access. Until a lane with that access runs it, or a follow-up adds the read to app `agent-read`, treat the egress limit as designed, not proven. From the agent box, `ssh -p 22 share-pod` and a connection to the shared node's address directly must both fail. Nothing here is reachable from the pod: the policy tests are the proof for the tailnet side.

## Rotate

Make a new key as in step 3, seed it, and delete the old key in the admin console. ExternalSecret refreshes within an hour; restart the pod to use it at once.

## Take it away

Remove the `share-pod` entry from `root/values.yaml` (prune is off, so delete the namespace too), delete `tag:share-pod` from `allowExternalReferencesTo` by setting `share_pod_enabled` back to false and applying (that keeps the share itself; emptying `external_tailnets` would remove it), and delete the key. The agent box then has no path to the shared node.
