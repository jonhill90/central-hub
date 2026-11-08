---
title: Check c1's health from its dashboard and alerts
status: draft
kind: manual
trigger: when something on c1 seems wrong, after any change synced by Argo CD, or once a week
runner: the owner, or an agent lane with the Grafana URL
outcome: you know whether every node, Argo CD Application and app on c1 is healthy, and which runbook to open if not
needs: a browser on the lab network; Grafana's admin password (Secret monitoring/kube-prometheus-stack-grafana) or a lab sign-in once Grafana uses Keycloak
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/clusters/c1/apps/monitoring-extras/]
last-tested: not yet run on c1
superseded-by:
---

# Check c1's health from its dashboard and alerts

Grafana at `https://grafana.apps.c1.prod.<zone>/` has a dashboard made for this cluster, **c1 lab overview**, and Prometheus has a small set of c1 alerts. Both come from git (`apps/monitoring-extras/`), so a rebuild brings them back. A change made by hand in the Grafana UI is lost on the next sync: change the JSON file by PR instead.

Alertmanager is off until a place to send alerts is picked, so alerts are not sent anywhere yet. They show in Grafana under Alerting, and in the dashboard's "Alerts firing" tile.

## Steps

1. Open Grafana, then Dashboards, then **c1 lab overview**.
   expect: the top row is green: both nodes ready, 0 Applications out of sync, 0 not healthy, 0 alerts firing.

2. If "Argo CD apps not Synced" or "not Healthy" is red, read the Applications table below it.
   expect: each row shows the Application, its namespace, Sync and Health. Open that component's runbook, `docs/runbooks/move-<component>-to-argo-cd.md`, section "If it fails". While a component is still being taken over (automatic sync off), OutOfSync is expected until its manual sync.

3. If "Alerts firing" is red, open Alerting, then Alert rules, and filter on `C1`.
   expect: the rule's summary says what is wrong. The table below says what each one means.

4. Read the logs panel at the bottom for errors around the time the trouble began.

## The alerts

| Alert | Means | First look |
|---|---|---|
| C1ArgoAppNotSynced | An Application hasn't matched git for 30 minutes | the Application's diff in the Argo CD UI |
| C1ArgoAppUnhealthy | An Application is Degraded or Missing for 15 minutes | its pods: `kubectl -n <namespace> get pods` |
| C1ArgoCDNotScraped | Prometheus can't read Argo CD's metrics, so the two above can't fire | `kubectl -n argocd get svc argocd-metrics` |
| C1DataDiskFillingUp | Less than 15% free on a node's data disk, where every volume lives | Prometheus and Loki retention, Jellyfin's media |
| C1JellyfinDown | Jellyfin has no ready pod for 10 minutes | [Jellyfin runbook](move-jellyfin-to-argo-cd.md) |
| C1LokiDown | Loki has no ready pod; new logs are lost | [logging runbook](move-logging-to-argo-cd.md) |
| C1PodCrashLooping | A container restarted more than 5 times in 30 minutes | `kubectl -n <namespace> logs <pod> --previous` |

## Change it

- A rule: edit `apps/monitoring-extras/templates/rules.yaml` by PR. Prometheus picks it up within a few minutes of the sync.
- The dashboard: build it in Grafana, then Share, Export, "Export for sharing externally" off, and paste the JSON into `apps/monitoring-extras/dashboards/c1-lab.json` by PR. Keep `uid: c1-lab`.
- A new dashboard: add one more JSON file in that folder. Each file becomes its own ConfigMap.

## Related

- [Move monitoring on c1 from Ansible to Argo CD](move-monitoring-to-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 144-146
