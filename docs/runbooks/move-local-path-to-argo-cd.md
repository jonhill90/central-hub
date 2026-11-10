---
title: Move c1's volume provisioner and default StorageClass from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 2 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Application `local-path` is Synced and Healthy, a new claim still binds, every existing claim is untouched, and Ansible no longer applies the provisioner
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/apps/local-path/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_storage/, hosts/ansible/playbooks/k8s-storage.yml]
last-tested: not yet run on c1. CI's parity check renders the role's manifest and this chart and finds them the same, object for object
superseded-by:
---

# Move c1's volume provisioner and default StorageClass from Ansible to Argo CD

The Local Path Provisioner makes each volume a folder on a node's data disk, under `/var/lib/c1-data/local-path`. The StorageClass `local-path` is the cluster's default, keeps a volume's folder when its claim is deleted (`Retain`), and allows only nodes labelled `central-hub/data-disk=true`. Grafana, Prometheus, Loki and Jellyfin keep their data on it.

Only the provisioner and the StorageClass move. The data disk itself (format, mount, node label) stays with Ansible (`k8s-storage.yml`, tag `disk`), because it is the machine, not the cluster.

## What is in git

| File | What |
|---|---|
| `apps/local-path/templates/local-path.yaml` | Upstream's deploy file at v0.0.37, as the role had it: namespace, RBAC, Deployment, StorageClass, ConfigMap. |
| `apps/local-path/values.yaml` | The images (pinned by digest), the folder path, the StorageClass's name, default flag, reclaim policy and node label. |

## Before you start

- `kubectl get storageclass local-path` shows `(default)`.
- `kubectl get pvc -A` shows every claim Bound. Write the list down: it must be the same at the end.
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

Since 2026-11-10, `autoSync` is on for every app in `root/values.yaml` (the owner's card, 02:50 UTC), so Argo CD syncs this app on its own and a fresh cluster installs it from git. On a cluster where Ansible already runs it, steps 1 to 3 are now a check after the fact: read the app's sync result instead of syncing by hand. Step 4's Ansible switch is still needed, so the role stops applying the same objects.

1. Refresh the root Application `c1`.
   expect: Application `local-path` appears, OutOfSync, or already synced now that auto-sync is on.

2. Read the diff.
   ※ [spec, "Taking over a running component"](../specs/2026-11-c1-apps-under-argo-cd.md#taking-over-a-running-component-agent-pick)
   expect: tracking labels only. A StorageClass can't be changed in place, so if its diff shows anything else, stop and fix the chart by PR.

3. Sync once, by hand.
   expect: Synced and Healthy. The provisioner pod is not restarted. `kubectl get pvc -A` shows the same list, all Bound. Run the role's proof (`ansible-playbook -i inventories/home/ playbooks/k8s-storage.yml --tags proof`): a new claim binds, and a pod writes and reads a file on it.

4. By PR, set `autoSync: true` for `local-path` in `root/values.yaml`. In the private inventory, set `k8s_storage_provisioner_by_argocd: true`, then run `ansible-playbook -i inventories/home/ playbooks/k8s-storage.yml`.
   expect: `changed=0`, because the role now only checks the data disks and runs the proof.

## Change it

Edit `apps/local-path/values.yaml` or the template by PR. To move to a newer provisioner, compare upstream's new `deploy/local-path-storage.yaml` with this template and carry over only the changes. Never prune this Application with claims on the class.

## Rebuild from nothing

The VMs come from Terraform, the data disks from `k8s-storage.yml --tags disk`, then Argo CD installs the provisioner and the StorageClass. The data in the volumes comes back only from a backup (TASK-0194, `back-up-c1-off-box.md`; the nightly Proxmox backup of the VM holds a second copy).

## If it fails

- **The way back:** delete the `local-path` Application. It has no resources finalizer, so the provisioner and the StorageClass stay. Set `k8s_storage_provisioner_by_argocd: false` and run `k8s-storage.yml --tags provisioner`.
- A claim stuck Pending after the move: check the provisioner's log, `kubectl -n local-path-storage logs deploy/local-path-provisioner`.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.
- Add the run to the spec's decision log.

## Related

- [Spec: move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 136-137
