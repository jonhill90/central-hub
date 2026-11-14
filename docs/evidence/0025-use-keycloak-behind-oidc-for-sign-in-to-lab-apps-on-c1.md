---
record: D-0025
batch: RB-0087 (central identity), with RB-0092 (how Keycloak is installed on c1); licences and paid editions re-checked 2026-11-14 by the FOSS audit
researched: 2026-10-26 to 2026-11-14
method: reading of each identity provider's docs, pricing and release pages and each repository's licence; Keycloak's operator files downloaded and checksummed; on 2026-11-14, Keycloak's LICENSE file and Red Hat's page on its own build opened
checks: "RB-0087's independent check failed the first round and passed with fixes on the second; RB-0092's independent check sampled 22 of 33 rows, PASS WITH FIXES with the fixes applied. The 2026-11-14 re-check has no independent check yet"
---

# Evidence for D-0025: sign-in for lab apps on c1

This file summarises the research behind D-0025. It adds nothing the research did not find. It was added after the record was accepted, as a correction under D-0006, because the record had no evidence file.

## Question

Which self-hosted identity provider gives lab apps on c1 one sign-in, with nothing we need behind a paid tier, and how is it installed?

## Findings

1. **Licences.** Keycloak is Apache-2.0 [1, 2] (measured 2026-11-14; RB-0087 read the same from the repository). authentik's repository licence reads as several licences, not one; Zitadel moved from Apache-2.0 to AGPL-3.0 at v3 [1] (sourced).
2. **authentik's paid tier.** Its pricing page lists agent accounts for non-human identities, mTLS client certificates, Google Workspace and Entra integration, and OAuth2 authentication in SCIM under Enterprise; SCIM itself and OAuth 2.0 token exchange are under Open Source [3] (sourced). Agent accounts are marked Enterprise in its docs [4] (snippet).
3. **Keycloak's SCIM.** "the SCIM API is promoted from preview to supported" in Keycloak 26.8.0 (2026-10-01) [5] (sourced). It is Keycloak as a SCIM server; outbound SCIM needs third-party extensions [1] (sourced).
4. **Red Hat's build of Keycloak.** Red Hat's page on its build names no features beyond upstream; it says components "may be added or removed for dependency or compatibility purposes" [6] (sourced, 2026-11-14).
5. **Install.** The Keycloak operator installs from its upstream files at a tag; an operator Helm chart is "Experimental" [7] (sourced). The operator does not manage the database [8] (sourced). PostgreSQL 14 to 18 is supported and the `dev-file` database "is not suitable for production use-cases" [9] (sourced).
6. **Realm as code.** KeycloakRealmImport "only supports creation of new realms and does not update or delete those" [10] (sourced).
7. **Grafana's side.** Grafana signs in through Keycloak with its generic OAuth settings and supports PKCE [11] (sourced).

## How the decision used it

(Written from the record, not from the batch.)

D-0025 takes option 1. Findings 1 and 2 are the "No paywall on what we need" driver and the reason authentik was not chosen. Finding 5 sets rules 2 and 3; finding 6 sets rule 4 and the "Bad" consequence about realm changes; finding 7 is the Grafana wiring in the diagram. Finding 4 was added on 2026-11-14 and does not change the decision.

## Limits

- Keycloak's private_key_jwt support rested on a snippet plus model knowledge in RB-0087.
- The Red Hat page gives no feature-by-feature list; "no extra features" is what the page does not say, not something it states.
- Machine and agent identities were researched in RB-0087 but are not decided by D-0025.

## References

Relied on (the decision depends on these):

1. RB-0087 synthesis and its S2 strand ledger (Research repository, batch `0087-central-identity`).
2. Keycloak LICENSE. <https://raw.githubusercontent.com/keycloak/keycloak/main/LICENSE.txt>
3. authentik, "Pricing". <https://goauthentik.io/pricing/>
4. authentik, "Agent accounts". <https://docs.goauthentik.io/users-sources/user/account-types/agent-accounts/>
5. Keycloak, "Keycloak 26.8.0 released". <https://www.keycloak.org/2026/10/keycloak-2680-released>
6. Red Hat, "Red Hat build of Keycloak Component Details". <https://access.redhat.com/articles/7027683>
7. Keycloak, "Operator installation". <https://www.keycloak.org/operator/installation>
8. Keycloak, "Basic Keycloak deployment" (operator). <https://www.keycloak.org/operator/basic-deployment>
9. Keycloak, "Configuring the database". <https://www.keycloak.org/server/db>
10. Keycloak, "Realm import". <https://www.keycloak.org/operator/realm-import>
11. Grafana, "Configure generic OAuth authentication". <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/>
