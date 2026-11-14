---
record: D-0024
batch: RB-0092 (c1 observability), with RB-0045 (Kubernetes tool map) behind it; licences and paid editions re-checked 2026-11-14 by the FOSS audit
researched: 2026-10-27 to 2026-11-14
method: reading of each project's docs, licence and chart index; chart files downloaded and read; a read-only kubectl run on c1; on 2026-11-14, each project's LICENSE file read from its repository and each vendor's edition page opened
checks: "RB-0092's independent check sampled 22 of 33 ledger rows (21 confirmed, 1 partly, 0 wrong), PASS WITH FIXES with the fixes applied. The 2026-11-14 re-check has no independent check yet"
---

# Evidence for D-0024: metrics and logs on c1

This file summarises the research behind D-0024. It adds nothing the research did not find. It was added after the record was accepted, as a correction under D-0006, because the record had no evidence file.

## Question

Which metrics and logs stack is the first build on c1 (kubeadm, Cilium with no kube-proxy, no StorageClass, 2-vCPU nodes), at which versions STD-0003 allows, and what licence and paid edition does each part carry?

## Findings

1. **Two stacks were compared.** kube-prometheus-stack plus Loki and Alloy, and the VictoriaMetrics k8s-stack plus VictoriaLogs [1] (sourced).
2. **Licences.** Prometheus, kube-prometheus-stack, Alloy and VictoriaMetrics are Apache-2.0; Grafana and Loki are AGPL-3.0 [2, 3, 4, 5, 6, 7] (measured from each LICENSE file, 2026-11-14). Loki is "distributed under AGPL-3.0-only" [8] (sourced).
3. **Paid editions.** Grafana Enterprise holds back from the free build, among others: SAML sign-in, team sync, role-based access control, enhanced LDAP, data source permissions, SCIM and reporting. OAuth sign-in and basic LDAP are in both [9] (sourced, 2026-11-14). Grafana Enterprise Logs lists its own access control and admin API [10] (sourced from the page's section titles only). The VictoriaLogs project says "Both the single-node and cluster versions of VictoriaLogs are open source and free to use" [11] (sourced). A VictoriaMetrics paid edition was not checked.
4. **What c1 uses.** Grafana signs in through Keycloak with its generic OAuth settings, which are in the free build [9, 12] (sourced).
5. **Versions on 2026-10-27 under STD-0003.** kube-prometheus-stack 92.3.1; Loki chart 18.15.1 (Loki 3.7.8) from the community chart repository; Alloy chart 1.13.1; metrics-server chart 3.14.0 [1] (measured from the chart indexes).
6. **Loki's chart moved to a community team in March 2026** [1] (sourced). Promtail reached end of life on 2026-03-02 and Grafana points users to Alloy [1] (snippet).
7. **Exit path.** VictoriaLogs "accepts logs in Loki JSON API format at /insert/loki/api/v1/push" [13] (sourced), so the log store changes by one URL; its queries use LogsQL, so dashboards and queries would be rewritten [14] (sourced). Single-node VictoriaMetrics accepts Prometheus remote_write [1] (sourced, prior batch).
8. **Fit.** c1 had no StorageClass and about 2.4 GB of free memory on its worker on 2026-10-27 [1] (measured).

## How the decision used it

(Written from the record, not from the batch.)

D-0024 takes option 1. Findings 5 and 6 set rule 2 (versions) and the log collector; finding 7 is rule 5 (exit path); finding 8 is rule 4 (data in `emptyDir` until storage). Finding 2 is the "Bad" consequence about AGPL-3.0. Finding 3 was not known when the record was accepted: the record does not weigh Grafana's or Loki's paid editions.

## Limits

- RB-0092 compared licences but not paid editions. The paid-edition rows were added on 2026-11-14 and have no independent check.
- The Grafana Enterprise Logs row rests on the page's section titles, not on a feature list.
- No traces, alerting or cost were compared in RB-0092.

## References

Relied on (the decision depends on these):

1. RB-0092 synthesis and ledger (Research repository, batch `0092-c1-observability`).
2. Prometheus LICENSE. <https://raw.githubusercontent.com/prometheus/prometheus/main/LICENSE>
3. prometheus-community helm-charts LICENSE. <https://raw.githubusercontent.com/prometheus-community/helm-charts/main/LICENSE>
4. Alloy LICENSE. <https://raw.githubusercontent.com/grafana/alloy/main/LICENSE>
5. VictoriaMetrics LICENSE. <https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/master/LICENSE>
6. Grafana LICENSE. <https://raw.githubusercontent.com/grafana/grafana/main/LICENSE>
7. Loki LICENSE. <https://raw.githubusercontent.com/grafana/loki/main/LICENSE>
8. Loki repository README. <https://github.com/grafana/loki>
9. Grafana Labs, "Grafana Enterprise" (comparison tables). <https://grafana.com/products/enterprise/grafana/>
10. Grafana Labs, "Grafana Enterprise Logs overview". <https://grafana.com/docs/enterprise-logs/latest/get-started/overview/>
11. VictoriaLogs repository README. <https://github.com/VictoriaMetrics/VictoriaLogs>
12. Grafana, "Configure generic OAuth authentication". <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/>
13. VictoriaLogs, "Data ingestion". <https://docs.victoriametrics.com/victorialogs/data-ingestion/>
14. VictoriaLogs, "LogsQL". <https://docs.victoriametrics.com/victorialogs/logsql/>
