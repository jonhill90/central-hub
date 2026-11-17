---
title: Move logging on c1 (Loki and Alloy) from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 3 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Applications `loki` and `alloy` are Synced and Healthy, Grafana still shows new pod logs, and Ansible no longer installs either chart
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/root/values.yaml, hosts/kubernetes/home/c1/apps/loki/values.yaml, hosts/kubernetes/home/c1/apps/alloy/values.yaml, hosts/ansible/playbooks/k8s-observability.yml]
last-tested: not yet run on c1. On 2026-11-08 the git values and the role's values were each rendered with the same chart versions, and the output was the same, line for line
superseded-by:
---

# Move logging on c1 (Loki and Alloy) from Ansible to Argo CD

Loki stores the cluster's logs, on a 20Gi claim in namespace `logging`. Alloy is one pod that reads every pod's logs through the Kubernetes API and pushes them to Loki. Grafana reads Loki as a data source. Both move together: they are one job.

## What is in git

| File | What |
|---|---|
| `root/values.yaml`, entries `loki` and `alloy` | The chart, its version (the same as the role used) and namespace `logging`. |
| `apps/loki/values.yaml` | Monolithic Loki, filesystem storage, 168h retention, a 20Gi claim. |
| `apps/alloy/values.yaml` | One Alloy Deployment and its pipeline, which sends logs to `http://loki.logging.svc.cluster.local:3100`. |

Nothing here holds the zone.

## Before you start

- `kubectl -n logging get statefulset loki deploy alloy` shows both ready.
- `kubectl -n logging get pvc` lists Loki's claim, Bound.
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

Since 2026-11-10, `autoSync` is on for this app in `root/values.yaml` (the owner's card, 02:50 UTC), so Argo CD syncs it on its own and a fresh cluster installs it from git. It was already Synced on c1 when the switch went on. On a cluster where Ansible already runs it, steps 1 to 3 are now a check after the fact: read the app's sync result instead of syncing by hand. Step 4's Ansible switch is still needed, so the role stops applying the same objects.

1. Refresh the root Application `c1` in the Argo CD UI.
   expect: Applications `loki` and `alloy` appear, OutOfSync, or already synced now that auto-sync is on.

2. Read each diff.
   ※ [spec, "Taking over a running component"](../specs/2026-11-c1-apps-under-argo-cd.md#taking-over-a-running-component-agent-pick)
   expect: no difference except Argo CD's tracking labels and Helm's own labels. If the StatefulSet's claim template shows a change, stop: Kubernetes forbids changing it, and a sync would fail.

3. Sync `loki`, then `alloy`, by hand.
   expect: both Synced and Healthy. The Loki pod is not restarted. In Grafana, Explore, data source Loki, `{namespace="logging"}` shows lines from the last minute.

4. By PR, set `autoSync: true` for `loki` and `alloy` in `root/values.yaml`. In the private inventory, set `k8s_observability_logs_by_argocd: true`, then run `ansible-playbook -i inventories/home/ playbooks/k8s-observability.yml --tags logs,proof`.
   why: from now on git is the source of truth. Ansible stops installing both charts and deletes Helm's old release records, which Argo CD doesn't use.
   expect: the first run reports the Helm records deleted; a second run reports `changed=0`.

## Change it

Argo CD fetches the chart from its OCI copy, `oci://ghcr.io/grafana-community/helm-charts/loki`, by digest (pick 141 in [AGENT-PICKS.md](../../hosts/AGENT-PICKS.md)), so a re-pushed tag changes nothing. A new version changes `version` and `digest` together in `root/values.yaml`: `helm pull oci://ghcr.io/grafana-community/helm-charts/loki --version <version>` prints the digest, and CI's parity check fails if the chart at that digest has another version. Alloy stays on its HTTPS repository by version, because its project publishes no OCI copy.

Edit the values files or the chart version in `root/values.yaml` by PR. Read the chart's upgrade notes first: a change to Loki's claim template needs the StatefulSet deleted (not the claim) before the sync, as the role did when it moved off emptyDir.

## Rebuild from nothing

On a new cluster with the root Application made, Argo CD installs both. The logs themselves are on the claim; they come back only from a backup of it (TASK-0194, `back-up-c1-off-box.md`). Losing them loses at most 7 days of logs.

## If it fails

- **The way back:** delete the `loki` and `alloy` Applications. Neither has a resources finalizer, so every object stays. Set `k8s_observability_logs_by_argocd: false` and run the playbook with `--tags logs`; Helm installs over the same objects.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.
- Add the run to the spec's decision log.

## Related

- [Spec: move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md)
- [Move metrics-server on c1 from Ansible to Argo CD](move-metrics-server-to-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 132-135
