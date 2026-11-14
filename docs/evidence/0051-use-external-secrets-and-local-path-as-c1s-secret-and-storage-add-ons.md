---
record: D-0051
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: licence files read from each repository; the page on a planned commercial External Secrets offering opened; central-hub searched for every file naming each; on 2026-11-14 at about 11:30 UTC, the External Secrets page opened again, SUSE's Application Collection entry for the Local Path Provisioner and its product page opened after a web search for paid Local Path Provisioner offers, and the reach re-counted at main e376aeb by the names `external-secrets`, `External Secrets`, `local-path` and `Local Path Provisioner`
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0051: External Secrets and the Local Path Provisioner

This file summarises the research behind D-0051. It adds nothing the research and the pages listed below did not find.

## Question

Are External Secrets and the Local Path Provisioner free, with nothing held back behind a paywall, and where are they used?

## Findings

1. **External Secrets** is Apache-2.0 [1] (sourced).
2. **A planned paid edition.** A company funded by Open Core Ventures planned "a commercial enterprise offering" around External Secrets. The page's banner says "External Secrets wound down operations as of December 2025" [2] (sourced, opened again 2026-11-14).
3. **Local Path Provisioner** is Apache-2.0 [3] (sourced).
4. **SUSE's offer.** SUSE's Application Collection lists a Local Path Provisioner chart marked "Subscription: Prime" [4] (sourced). SUSE's product page says the Collection's applications are "aligned with upstream", updated when upstream releases, built on SUSE's container images and "backed by enterprise-grade support"; it names no feature beyond the upstream projects [5] (sourced).
5. **What c1 runs.** The Local Path Provisioner image is `docker.io/rancher/local-path-provisioner`, pinned by digest, in `hosts/kubernetes/home/c1/apps/local-path/values.yaml` and role `k8s_storage`. c1's ExternalSecrets read from a ClusterSecretStore in `hosts/kubernetes/home/c1/apps/secret-store/` [6] (measured).
6. **Reach.** At main e376aeb: External Secrets in 29 files in `hosts/`, 8 runbooks and D-0038; the Local Path Provisioner in 24 files in `hosts/`, 7 runbooks and D-0033 and D-0039. Runbook and decision indexes are not counted [6] (measured, 2026-11-14).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 to 4 are the paywall weighing and rules 1 and 2. Findings 5 and 6 are the context, rule 3 and the confirmation.

## Limits

- No other secrets operator or storage provisioner was compared.
- Whether SUSE's Application Collection build of the Local Path Provisioner differs in code from the upstream one was not checked, and what a Prime subscription costs was not looked up.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. External Secrets LICENSE. <https://raw.githubusercontent.com/external-secrets/external-secrets/main/LICENSE>
2. Open Core Ventures, "Introducing External Secrets". <https://www.opencoreventures.com/blog/introducing-external-secrets-enterprise-secrets-management>
3. Local Path Provisioner LICENSE. <https://raw.githubusercontent.com/rancher/local-path-provisioner/master/LICENSE>
4. SUSE Application Collection, Local Path Provisioner. <https://apps.rancher.io/applications/local-path-provisioner/components>
5. SUSE, "SUSE Application Collection". <https://www.suse.com/products/rancher/application-collection>
6. Repository search and code read of central-hub at e376aeb (this repository).

The batch is RB-0208; its working files are private.
