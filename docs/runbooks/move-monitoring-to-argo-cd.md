---
title: Move monitoring on c1 (kube-prometheus-stack) from Ansible to Argo CD
status: draft
kind: automated
trigger: on request (step 4 of spec 2026-11-c1-apps-under-argo-cd)
runner: an agent lane, through the owner's Mac (D-0022)
outcome: Argo CD's Application `kube-prometheus-stack` is Synced and Healthy, Grafana opens with the same admin password, Prometheus keeps its data, and Ansible no longer installs the chart
needs: the lab clone of central-hub with its private inventory; SSH to c1's control plane as D-0022 says; the root Application `c1` already made (metrics-server runbook, step 1)
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/root/values.yaml, hosts/kubernetes/home/c1/apps/kube-prometheus-stack/, hosts/ansible/playbooks/k8s-observability.yml]
last-tested: 2026-11-10, every step on c1, auto-sync took over at 03:31 UTC (#140), Synced and Healthy, Grafana rolled once to a new pod and still shows "Lab sign-in"; the admin user and password from the Secret signed in (/api/user 200, a wrong password 401); k8s-observability.yml changed=1 (the old Helm records)
superseded-by:
---

# Move monitoring on c1 (kube-prometheus-stack) from Ansible to Argo CD

kube-prometheus-stack is Prometheus, its operator, Grafana, kube-state-metrics and node-exporter, in namespace `monitoring`. It is the first component with CRDs, so it shows how CRDs are handled: Argo CD applies them server-side, because they are too large for a normal apply.

## What is in git

| File | What |
|---|---|
| `root/values.yaml`, entry `kube-prometheus-stack` | Chart 92.3.1 (the same as the role used). Grafana's `root_url` is a parameter, because it holds the zone. Server-side apply. Argo CD ignores the data in Secret `kube-prometheus-stack-grafana`, because the chart makes a new random admin password every time it is rendered. |
| `apps/kube-prometheus-stack/values.yaml` | The role's values: no Alertmanager, the kubeadm-bound scrapes off, Prometheus 15d or 16GB on a 20Gi claim, Grafana on a 1Gi claim with Loki as a data source. |
| `apps/kube-prometheus-stack/values-sso.yaml` | Grafana's sign-in through Keycloak. Used only when the inventory has `k8s_observability_grafana_sso: true`. |

## Before you start

- `kubectl -n monitoring get pods` shows Prometheus, Grafana, the operator and kube-state-metrics ready.
- Check `k8s_observability_grafana_sso` in the private inventory. It is true for c1, so `root/values.yaml` lists `values-sso.yaml` and the `auth_url` parameter. If it is false on another cluster, leave both out.
- `kubectl -n argocd get application c1` shows Synced.

Stop if any of these is not true.

## Steps

The owner chose auto-sync for every app (card, 2026-11-10 02:50 UTC). `kube-prometheus-stack` was OutOfSync on c1 at 02:54 UTC. The read at 03:08 UTC found Grafana's sign-in on the cluster but not in git (only the ConfigMap and the Deployment differed), so `values-sso.yaml` and the `auth_url` parameter are now in `root/values.yaml`, and auto-sync is on. Its first automatic sync is step 3. Step 4's inventory switch is still needed, so the role stops installing the chart.

1. Refresh the root Application `c1`.
   expect: Application `kube-prometheus-stack` appears, OutOfSync, automatic sync off.

2. Read the diff.
   ※ [spec, "Taking over a running component"](../specs/2026-11-c1-apps-under-argo-cd.md#taking-over-a-running-component-agent-pick)
   expect: tracking labels only. The CRDs may show the chart's newer annotations. The Grafana Secret shows no difference, because it is ignored. Anything else: fix the values by PR.

3. Sync once, by hand.
   expect: Synced and Healthy. Grafana rolls once to a new pod, because the sync rewrites its Deployment (2026-11-10). Grafana at `https://grafana.apps.c1.prod.<zone>/` signs in with the same admin password as before (Secret `monitoring/kube-prometheus-stack-grafana`). Prometheus's claim is the same one, and old graphs still show.

4. By PR, set `autoSync: true` in `root/values.yaml`. In the private inventory, set `k8s_observability_metrics_by_argocd: true`, then run `ansible-playbook -i inventories/home/ playbooks/k8s-observability.yml --tags metrics,proof`.
   why: Ansible stops installing the chart and deletes Helm's old release records. Grafana's route moves with the Gateway ([gateway runbook](move-gateway-to-argo-cd.md)).
   expect: the first run reports the Helm records deleted; a second run reports `changed=0`.

## Change it

Argo CD fetches the chart from its OCI copy, `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`, by digest (pick 141 in [AGENT-PICKS.md](../../hosts/AGENT-PICKS.md)), so a re-pushed tag changes nothing. A new version changes `version` and `digest` together in `root/values.yaml`: `helm pull oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack --version <version>` prints the digest, and CI's parity check fails if the chart at that digest has another version.

Edit the values or the version by PR. Before raising the chart past a Prometheus Operator minor, read the chart's upgrade notes: with server-side apply Argo CD updates the CRDs itself, which Helm never did.

## Rebuild from nothing

On a new cluster with the root Application made, Argo CD installs everything, and Grafana gets a new random admin password in its Secret. Dashboards made by hand in Grafana's UI live on its claim, not in git.

## If it fails

- **The way back:** delete the `kube-prometheus-stack` Application. It has no resources finalizer, so every object stays, CRDs included. Set `k8s_observability_metrics_by_argocd: false` and run the playbook with `--tags metrics`.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.
- Add the run to the spec's decision log.

## Related

- [Spec: move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md)
- [Move logging on c1 from Ansible to Argo CD](move-logging-to-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 132-135
