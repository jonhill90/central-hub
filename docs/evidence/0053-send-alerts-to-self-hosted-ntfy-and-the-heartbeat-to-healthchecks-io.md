---
record: D-0053
batch: RB-0181 (alerting design), with RB-0208 (FOSS check) for licences and paid plans
researched: 2026-11-09 to 2026-11-14
method: vendor documentation and pricing pages; five public home-lab repositories cloned and read at fixed commits; central-hub's history searched; on 2026-11-14 at about 12:05 UTC, the licence files, ntfy's terms and configuration pages and Healthchecks.io's pricing page read again, and the reach, picks and code re-read at main 07408f9; at about 12:45 UTC, the VPS's place read in D-0035 and the PRD at main 3400f06, and Healthchecks' self-hosting settings and Gatus's README and licence read
checks: "RB-0181 had no independent check (its deviations file says so); RB-0208 had none. A reviewing agent checks every line here against the batches and the pages"
---

# Evidence for D-0053: ntfy and Healthchecks.io

This file summarises the research behind D-0053. It adds nothing the research and the pages listed below did not find.

## Question

How do c1's alerts and heartbeat reach the owner, what do comparable home labs use, and are the pieces free with nothing held back behind a paywall?

## Findings

1. **Licences.** ntfy is dual-licensed under Apache-2.0 and GPL-2.0 [1] (sourced). Healthchecks is BSD-3-Clause [2] (sourced).
2. **ntfy's paid plans** are for its hosted service: "These Terms apply specifically to the ntfy.sh hosted service" [3] (sourced).
3. **iOS.** For instant iOS notifications a self-hosted server must forward poll requests to ntfy.sh (`upstream-base-url`); without it, "notifications will still eventually get to your device, but delivery can take hours, depending on the state of the phone" [4] (sourced).
4. **Healthchecks.io's plans.** The free Hobbyist plan is $0 a month for 20 jobs and 100 log entries per job. Paid plans add jobs, log entries, SMS and phone-call credits and e-mail support [5] (sourced).
5. **How ntfy arrived.** ntfy reached c1 in PR #72 on 2026-11-08 ("add c1's alerts, dashboard, ntfy delivery and Argo CD sign-in through Keycloak"). Picks 171 and 213 record the owner's answers of 2026-11-12 at 22:20 and 22:21 UTC [6] (measured).
6. **Other home labs.** Of five public home labs read at fixed commits [7] to [11], Pushover and Discord are the most common receivers (two each) and ntfy one; four of the five send the Watchdog heartbeat to something outside the cluster (measured; five labs, not a survey).
7. **Alertmanager** has native receivers for many channels, including Discord and Pushover, and a generic webhook; ntfy is not native [12] (sourced).
8. **What c1 runs.** ntfy denies everyone by default (`NTFY_AUTH_DEFAULT_ACCESS: deny-all`). The Watchdog goes to a heartbeat receiver whose URL is the one secret `healthchecks-ping-url`, delivered by the ExternalSecret `alertmanager-heartbeat` in `monitoring-extras/` and read as a file, so it sits in no config [6] (measured).
9. **Reach.** At main 07408f9, ntfy is named in 22 files in `hosts/` and 8 runbooks, and Healthchecks in 7 files in `hosts/` and 3 runbooks; no record names either [6] (measured, 2026-11-14).
10. **The VPS.** The PRD's goal 1 says the rented VPS is not a c1 worker for now. D-0035 keeps "the VPS node" out of agent teardowns and rebuilds (its drivers and rule 2). PR #314, which proposes the VPS's first apps and host steps as D-0046, is open and not merged [6] (measured at main 3400f06, 2026-11-14).
11. **A self-hosted watcher's alarm.** Self-hosted Healthchecks needs `EMAIL_HOST`, a mail server; "If this environment variable is not set, Healthchecks will not be able to send any email" [13] (sourced). Gatus is Apache-2.0 and can alert by e-mail through a mail server, by ntfy and by many other providers [14] (sourced).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1, 2 and 4 are the paywall weighing and rules 1 and 2. Finding 3 is a Bad consequence. Findings 5, 6, 8 and 9 are the context, options 2, 3 and B, and rules 3 and 4. Finding 7 is the exit path for the channel. Findings 10 and 11 are the weighing of option B against A, and the heartbeat's exit path.

## Limits

- Pushover's and Discord's terms were not read in these batches.
- Gotify and other self-hosted channels were in the question but not compared on fit.
- The five home labs are a sample, not a survey.
- The VPS's uptime was not measured, and Gatus and self-hosted Healthchecks were not tried there.

## References

Relied on (the decision depends on these):

1. ntfy README, "License", and LICENSE, fetched 2026-11-14. <https://raw.githubusercontent.com/binwiederhier/ntfy/main/README.md>
2. Healthchecks LICENSE, fetched 2026-11-14. <https://raw.githubusercontent.com/healthchecks/healthchecks/master/LICENSE>
3. ntfy, "Terms of Service", fetched 2026-11-14. <https://docs.ntfy.sh/terms/>
4. ntfy, "Configuration" (iOS instant notifications), fetched 2026-11-14. <https://docs.ntfy.sh/config/>
5. Healthchecks.io, "Pricing", fetched 2026-11-14. <https://healthchecks.io/pricing/>
6. Repository search, history and code read of central-hub at 07408f9 (this repository).
7. onedr0p/home-ops at af95f62. <https://github.com/onedr0p/home-ops>
8. bjw-s-labs/home-ops at 58626a9. <https://github.com/bjw-s-labs/home-ops>
9. joryirving/home-ops at 8bb6911. <https://github.com/joryirving/home-ops>
10. billimek/k8s-gitops at 5888637. <https://github.com/billimek/k8s-gitops>
11. khuedoan/homelab at 385b52b. <https://github.com/khuedoan/homelab>
12. Prometheus, "Alertmanager configuration", fetched 2026-11-09. <https://prometheus.io/docs/alerting/latest/configuration/>
13. Healthchecks, "Server Configuration" (`EMAIL_HOST`), fetched 2026-11-14. <https://healthchecks.io/docs/self_hosted_configuration/>
14. Gatus README ("Alerting") and LICENSE, fetched 2026-11-14. <https://github.com/TwiN/gatus>

The batches are RB-0181 and RB-0208; their working files are private.
