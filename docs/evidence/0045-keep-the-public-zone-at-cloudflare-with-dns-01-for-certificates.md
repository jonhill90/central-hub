---
record: D-0045
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: provider licence read from its repository; cert-manager's DNS-01 page and Let's Encrypt's about page opened; central-hub searched for every file naming the piece; on 2026-11-14 at about 09:35 UTC, the reach re-counted at main 3d90375, the token code read, ACME-DNS's licence read, and Cloudflare's DNS overview, DNS records page and account API tokens page opened for the free-plan reading
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages before the record is accepted"
---

# Evidence for D-0045: the public zone at Cloudflare

This file summarises the research behind D-0045. It adds nothing the research, the pages listed below and Council A's measurement did not find.

## Question

What does the lab depend on Cloudflare for, is there a free way off, is the lab on Cloudflare's free plan only, and is Let's Encrypt free with no paid tier?

## Findings

1. **Cloudflare** is a closed service; the OpenTofu provider for it is Apache-2.0 [1] (measured). The lab pins it to one version in each folder's `versions.tf` [4] (measured).
2. **Way off.** cert-manager has RFC 2136 and ACME-DNS solvers built in [2] (sourced). ACME-DNS is MIT-licensed [5] (measured).
3. **Let's Encrypt** gives certificates "at zero cost", is run by the nonprofit ISRG, and its issuance protocol is "published as an open standard" [3] (sourced).
4. **Reach.** At main 3d90375, 42 files in 19 `hosts/` folders and 7 runbooks name Cloudflare. D-0038, D-0041 and D-0042 name it as a token to store or an account the pipeline changes; no record chose it [4] (measured, 2026-11-14).
5. **Tokens.** Both tokens get the zone-scoped "DNS Write" and "Zone Read" groups on the one zone and an expiry, and are replaced on a timer. Only the cert-manager token also has a client address condition [4] (measured, `hosts/terraform/home/dns-token/main.tf` and `certificates/main.tf`).
6. **Free plan.** Cloudflare's DNS overview says DNS is "Available on all plans" [6]. Its account API tokens page says they are "generally available for all accounts" and marks DNS as supported [7]. Its DNS records page caps a free zone at 200 records if added on or after 2024-09-01, and 1,000 if older [8] (sourced).
7. **The zone.** On 2026-11-14 at 09:39 UTC Council A measured the zone on the free plan, added on 2026-07-26, so its cap is 200 records [9] (measured by Council A).

## How the decision used it

(Written from the record, not from the batch.)

Finding 1 sets rule 1 and the "Bad" consequence. Finding 2 is options 2 and 3, the exit path and option 2's licence line. Finding 3 is rule 1's line on Let's Encrypt. Finding 4 is the context. Finding 5 is rule 4. Finding 6 is rule 2 and the "Neutral" consequence, and finding 7 fixes which cap applies.

## Limits

- The zone's live record count was not measured.
- Cloudflare's terms of service were not read; only the documentation pages above were.
- No self-hosted authoritative DNS server was chosen or checked.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. Cloudflare Terraform provider repository (LICENSE). <https://github.com/cloudflare/terraform-provider-cloudflare>
2. cert-manager, "DNS01". <https://cert-manager.io/docs/configuration/acme/dns01/>
3. Let's Encrypt, "About Let's Encrypt". <https://letsencrypt.org/about/>
4. Repository search and code read of central-hub at 3d90375 (this repository).
5. ACME-DNS repository (LICENSE). <https://github.com/joohoi/acme-dns>
6. Cloudflare, "Cloudflare DNS". <https://developers.cloudflare.com/dns/>
7. Cloudflare, "Account API tokens". <https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/>
8. Cloudflare, "Manage DNS records", record limits. <https://developers.cloudflare.com/dns/manage-dns-records/>
9. Council A's measurement of the zone's plan and creation date, 2026-11-14 at 09:39 UTC, reported in the project's council review of this PR.

The batch is RB-0208; its working files are private.
