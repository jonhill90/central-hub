---
title: Move c1's External Secrets and its store from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 5 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Applications `external-secrets` and `secret-store` are Synced and Healthy, ClusterSecretStore `c1` is Ready, and Ansible no longer installs either
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/apps/external-secrets/values.yaml, hosts/kubernetes/home/c1/apps/secret-store/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_secrets/, hosts/ansible/playbooks/k8s-secrets.yml]
last-tested: not yet run on c1. CI's parity check finds the chart values and the store manifest the same as the role's
superseded-by:
---

# Move c1's External Secrets and its store from Ansible to Argo CD

External Secrets (ESO) copies secrets from a store into plain Kubernetes Secrets that apps read. On c1 the store is ClusterSecretStore `c1`, ESO's Kubernetes provider, reading Secrets from the locked namespace `secret-source`. Those source Secrets come from a file on the controller ([Seed namespace secret-source](seed-secret-source.md)) and are not in git. Jellyfin's admin password generator also runs on ESO.

## What is in git

| File | What |
|---|---|
| `root/values.yaml`, entry `external-secrets` | Chart 2.14.0 (the same as the role), wave -2, server-side apply for the CRDs. |
| `apps/external-secrets/values.yaml` | `installCRDs: true`, the only value the role sets. |
| `apps/secret-store/` | A local chart, wave -1: namespace `secret-source` (never deleted by Argo CD), the store's service account and read-only role, and ClusterSecretStore `c1`. |

## Before you start

- `kubectl get clustersecretstore c1` shows Ready.
- `kubectl -n external-secrets get deploy` shows the three ESO deployments ready.
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

Since 2026-11-10, `autoSync` is on for every app in `root/values.yaml` (the owner's card, 02:50 UTC), so Argo CD syncs this app on its own and a fresh cluster installs it from git. On a cluster where Ansible already runs it, steps 1 to 3 are now a check after the fact: read the app's sync result instead of syncing by hand. Step 4's Ansible switch is still needed, so the role stops applying the same objects.

1. Refresh the root Application `c1`.
   expect: `external-secrets` and `secret-store` appear, OutOfSync, or already synced now that auto-sync is on.

2. Read both diffs.
   ※ [spec, "Taking over a running component"](../specs/2026-11-c1-apps-under-argo-cd.md#taking-over-a-running-component-agent-pick)
   expect: tracking labels only, and on the CRDs, the chart's own annotations. Anything else: fix the files by PR.

3. Sync `external-secrets`, then `secret-store`, by hand.
   expect: both Synced and Healthy; `kubectl get clustersecretstore c1` still Ready; the Secrets in `secret-source` are untouched (`kubectl -n secret-source get secrets` lists the same names as before).

4. By PR, set `autoSync: true` for both in `root/values.yaml`. In the private inventory, set `k8s_secrets_by_argocd: true`, then run `ansible-playbook -i inventories/home/ playbooks/k8s-secrets.yml`.
   expect: the first run deletes ESO's old Helm release records; a second run reports `changed=0`.

## Change it

ESO supports only its newest minor: raise the chart one minor at a time, by PR, after reading its release notes. Swapping the backend (a vault later) means replacing only ClusterSecretStore `c1` in `apps/secret-store/`; every ExternalSecret keeps its store name.

## Rebuild from nothing

Argo CD installs ESO (wave -2) and then the store (wave -1). Seed the source Secrets in `secret-source` again with [Seed namespace secret-source](seed-secret-source.md): their values are not in git. Generated secrets, such as Jellyfin's admin password, are made again.

## If it fails

- **The way back:** delete both Applications. Neither has a resources finalizer, so ESO, its CRDs and the store stay. Set `k8s_secrets_by_argocd: false` and run the secrets playbook.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.
- Add the run to the spec's decision log.

## Related

- [Spec: move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 138-140
