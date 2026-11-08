# Cluster c1

What Argo CD on c1 reads from this repository (D-0023 rule 5, D-0027). The plan and the order are in the spec [Move c1's apps and add-ons under Argo CD](../../../../docs/specs/2026-11-c1-apps-under-argo-cd.md).

| Folder | What |
|---|---|
| `root/` | A small Helm chart. Argo CD renders it from the one root Application `c1`, which Ansible makes (role `k8s_gitops`), and it makes one child Application per entry in `root/values.yaml`. |
| `apps/<component>/` | That component's Helm values, read by its child Application. |

No private names go here (CLAUDE.md rule 4). The lab zone reaches the cluster only as the root Application's `zone` parameter.

## Components moved so far

| Component | Namespace | Runbook | State |
|---|---|---|---|
| metrics-server | kube-system | [move-metrics-server-to-argo-cd.md](../../../../docs/runbooks/move-metrics-server-to-argo-cd.md) | in git, not yet synced |
