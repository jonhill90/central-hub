---
title: Check c1's health from its dashboard and alerts
status: draft
kind: manual
trigger: when something on c1 seems wrong, after any change synced by Argo CD, or once a week
runner: the owner, or an agent lane with the Grafana URL
outcome: you know whether every node, Argo CD Application and app on c1 is healthy, and which runbook to open if not
needs: a browser on the lab network; Grafana's admin password (Secret monitoring/kube-prometheus-stack-grafana) or a lab sign-in once Grafana uses Keycloak
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/apps/monitoring-extras/, hosts/kubernetes/home/c1/apps/openbao/values.yaml]
last-tested: 2026-11-18 on prod's c1, the agent parts only. "Read the panels without a browser" was run from the agent box at 04:32 UTC, on central-hub ab8caa1. Run panel-check-29916270 printed a value for every panel, including the OpenBao, Jellyfin and alert delivery rows. Its "Alerts firing, by name" line named C1ArgoAppUnhealthy, KubeCPUOvercommit and KubeMemoryOvercommit. Grafana's sidecar wrote c1-lab.json at 03:46:50 UTC. Nobody has yet looked at the dashboard in a browser (steps 1 to 6)
superseded-by:
---

# Check c1's health from its dashboard and alerts

Grafana at `https://grafana.apps.c1.prod.<zone>/` has a dashboard made for this cluster, **c1 lab overview**, and Prometheus has a small set of c1 alerts. Both come from git (`apps/monitoring-extras/`), so a rebuild brings them back. A change made by hand in the Grafana UI is lost on the next sync: change the JSON file by PR instead.

Alertmanager sends every alert to ntfy on c1 ([Get c1's alerts on a phone](get-c1-alerts-on-your-phone.md)). They also show in Grafana under Alerting, and in the dashboard's "Alerts firing" tile.

## Steps

1. Open Grafana, then Dashboards, then **c1 lab overview**.
   expect: the top row is green: both nodes ready, 0 Applications out of sync, 0 not healthy, 0 alerts firing.

2. If "Argo CD apps not Synced" or "not Healthy" is red, read the Applications table below it.
   expect: each row shows the Application, its namespace, Sync and Health. Open that component's runbook, `docs/runbooks/move-<component>-to-argo-cd.md`, section "If it fails". While a component is still being taken over (automatic sync off), OutOfSync is expected until its manual sync.

3. If "Alerts firing" is red, open Alerting, then Alert rules, and filter on `C1`.
   expect: the rule's summary says what is wrong. The table below says what each one means.

4. Read the logs panels for errors around the time the trouble began.

5. Read the **OpenBao**, **Jellyfin** and **Keycloak (sign-in)** rows.
   expect: OpenBao reads Unsealed, its pod is ready, the last snapshot is under 3 hours old, and there are 0 audit write failures. Jellyfin's pod is ready with 0 restarts in 24 hours, and its requests panel shows mostly `200`. Keycloak's pod is ready, its metrics are read (1), and failed logins in 24 hours are few: each mistyped password or code counts one. On a cluster without OpenBao inside it, the OpenBao panels show "No data".

6. Read the **Alert delivery** row.
   expect: "Alerts sent to ntfy, 24h" is above 0 whenever an alert fired or resolved in the last day, and "Failed sends to ntfy, 24h" is 0. Both count only the `ntfy` receiver, not the heartbeat, because Alertmanager runs with `receiver-name-in-metrics` (`apps/kube-prometheus-stack/values.yaml`). "No data" there means the flag is off.

## Read the panels without a browser

CronJob `monitoring/panel-check` asks Prometheus for the OpenBao, Jellyfin, Keycloak and alert delivery panels' values every half hour, plus "Alerts firing", and prints one line per panel, then the names of the alerts firing. It holds no token and reads only Prometheus, inside the cluster. A panel with no data fails the run. An agent reads it from the agent box with the read-only account ([give-agents-read-access-to-c1.md](give-agents-read-access-to-c1.md)):

1. `c1-read get jobs -n monitoring --sort-by=.metadata.creationTimestamp`
   expect: the newest `panel-check-<number>` job is listed with completions `1/1`.
2. `c1-read logs -n monitoring job/<that job>`
   expect: one line per panel, for example `OpenBao unsealed: 1`, then `Alerts firing, by name: none` (or each name with its count, such as `KubeJobFailed x2`; look each one up in the table below), ending `panel check: every panel has data`.

## The alerts

| Alert | Means | First look |
|---|---|---|
| C1ArgoAppNotSynced | An Application hasn't matched git for 30 minutes | the Application's diff in the Argo CD UI |
| C1ArgoAppUnhealthy | An Application is Degraded or Missing for 15 minutes | its pods: `kubectl -n <namespace> get pods` |
| C1ArgoCDNotScraped | Prometheus can't read Argo CD's metrics, so the two above can't fire | `kubectl -n argocd get svc argocd-metrics` |
| C1DataDiskFillingUp | Less than 15% free on a node's data disk, where every volume lives | Prometheus and Loki retention, Jellyfin's media |
| C1JellyfinDown | Jellyfin has no ready pod for 10 minutes | [Jellyfin runbook](move-jellyfin-to-argo-cd.md) |
| C1LokiDown | Loki has no ready pod; new logs are lost | [logging runbook](move-logging-to-argo-cd.md) |
| C1AlertsNotDelivered | Alertmanager failed to hand alerts to ntfy | [alerts runbook](get-c1-alerts-on-your-phone.md) |
| C1PodCrashLooping | A container restarted more than 5 times in 30 minutes | `kubectl -n <namespace> logs <pod> --previous` |
| C1JellyfinNotScraped | Prometheus can't read Jellyfin's `/metrics` for 15 minutes | [Jellyfin runbook, Metrics](move-jellyfin-to-argo-cd.md#metrics) |
| C1JellyfinErrors | Jellyfin answered more than 0.05 server errors (5xx) a second for 15 minutes | Jellyfin's log in the dashboard's logs panel |
| C1KeycloakDown | Keycloak has no ready pod for 10 minutes, so no app sign-in works | [sign-in runbook](set-up-lab-sign-in.md): `kubectl -n identity get pods` and the Keycloak object's status |
| C1KeycloakNotScraped | Prometheus can't read Keycloak's `/metrics` for 15 minutes, so the login alert can't fire | [sign-in runbook, Metrics and alerts](set-up-lab-sign-in.md#metrics-and-alerts): `k8s_identity_metrics` and `kubectl -n identity get endpoints sso-service` |
| C1KeycloakLoginFailures | More than 20 failed logins in realm lab in 15 minutes | the Logins panel by result; Keycloak's log in Loki (`{namespace="identity"}`) |
| C1OpenBaoNotReady | OpenBao has no ready pod for 10 minutes: sealed or down, so apps can't read secrets | [secrets store runbook](set-up-the-secrets-store.md#metrics-alerts-and-restarts) |
| C1OpenBaoSealed | OpenBao answers but is sealed | the same runbook, "If it fails" |
| C1OpenBaoNotScraped | Prometheus can't read OpenBao's metrics, so the seal and audit alerts can't fire | `kubectl -n openbao get endpoints openbao-active` and the NetworkPolicy |
| C1OpenBaoAuditFailing | OpenBao failed to write its audit log; it refuses requests it can't audit | the audit claim's free space: `kubectl -n openbao exec openbao-0 -- df -h /openbao/audit` |
| C1OpenBaoSnapshotStale | No successful hourly snapshot for 3 hours | `kubectl -n openbao logs job/<newest openbao-snapshot job>` |

The chart's own Kubernetes alerts fire too (for example `KubeJobFailed`, `KubePodNotReady`); each one's `runbook_url` explains it. `KubeCPUOvercommit` and `KubeMemoryOvercommit` are turned off on c1 (`defaultRules.disabled` in `apps/kube-prometheus-stack/values.yaml`): they ask whether the pods would still fit with the largest node lost, and with one worker they never would, so they fired for good. A pod that doesn't fit stays Pending, and `KubePodNotReady` fires for it. Turn the two back on once c1 has three nodes.

## Change it

- A rule: edit `apps/monitoring-extras/templates/rules.yaml` by PR. Prometheus picks it up within a few minutes of the sync.
- The dashboard: build it in Grafana, then Share, Export, "Export for sharing externally" off, and paste the JSON into `apps/monitoring-extras/dashboards/c1-lab.json` by PR. Keep `uid: c1-lab`.
- A new dashboard: add one more JSON file in that folder. Each file becomes its own ConfigMap.

## Related

- [Move monitoring on c1 from Ansible to Argo CD](move-monitoring-to-argo-cd.md)
- `hosts/AGENT-PICKS.md` picks 167-169
