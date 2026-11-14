---
record: D-0040
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: each project's licence file read from its repository; each vendor's edition or pricing page opened; central-hub searched for every file naming the piece
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch before the owner sees it"
---

# Evidence for D-0040: OPNsense as the lab's router and firewall

This file summarises the research behind D-0040. It adds nothing the research did not find.

## Question

Is OPNsense free and open source with no feature held back in a paid edition, does the lab use any such feature, and what free alternatives exist?

## Findings

1. **Licence.** OPNsense core is BSD-2-Clause [1] (measured).
2. **Paid edition.** Deciso's Business Edition has "additional commercial features" [2] (sourced). "The business edition includes OpenID Connect support for some parts of the system" [3] (sourced). A reseller lists Business Edition only central management, web application firewall, advanced web proxy, GeoIP database access, user portal and tested updates [4] (sourced; a reseller page, not Deciso's).
3. **Unbound**, the resolver inside OPNsense: "All functionality is available in the open-source project, with no separate enterprise edition or gated features"; BSD-3-Clause [5] (sourced).
4. **How it got here.** The home-lab spec says the lab was set up by hand before code [6] (sourced). No decision record chose OPNsense [6] (measured).
5. **Reach.** 72 files in 41 folders of `hosts/`, 22 runbooks, records D-0011, D-0017, D-0021, D-0028 and D-0036, STD-0001 and four specs name it [6] (measured, 2026-11-14).
6. **Alternatives.** OpenWrt is GPL-2.0-only [7] (measured). VyOS's vyos-1x is LGPL-2.1 [8] (measured); LTS images go to contributors free and to others by "binary image subscription", rolling images are free, and "you will always be able to build LTS releases yourself" [9] (sourced, a 2018 post). IPFire says "Our software and everything else is free" without naming a licence on that page [10] (sourced). pfSense CE is Apache-2.0 [11] (measured); its paid sibling pfSense Plus was not checked.

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 to 3 set rules 1 and 2: the community edition and Unbound are free, and the Business Edition features are excluded. Finding 2's OIDC line is why sign-in goes another way (D-0037). Findings 4 and 5 are the context. Finding 6 lists options 2 to 5.

## Limits

- No feature or fit comparison of the alternatives was made; only licences and paid editions.
- The paid sides of OpenWrt, IPFire and a Debian router were not checked.
- The Business Edition list in finding 2 beyond OIDC rests on a reseller page.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. OPNsense core LICENSE. <https://raw.githubusercontent.com/opnsense/core/master/LICENSE>
2. OPNsense, "Business Edition releases". <https://docs.opnsense.org/BE_releases.html>
3. OPNsense, "OpenID Connect" (Deciso). <https://docs.opnsense.org/vendor/deciso/oidc.html>
4. Thomas-Krenn, "Additional Features of OPNsense Business Edition". <https://www.thomas-krenn.com/en/wiki/Additional_Features_of_OPNsense_Business_Edition>
5. NLnet Labs, "Unbound". <https://nlnetlabs.nl/unbound>
6. RB-0208 findings (Research repository, batch `foss-check`): repository search of central-hub at 5626e8e.

Background:

- [7] OpenWrt repository (COPYING). <https://github.com/openwrt/openwrt>
- [8] vyos-1x repository (LICENSE). <https://github.com/vyos/vyos-1x>
- [9] VyOS, "VyOS release model change". <https://blog.vyos.io/vyos-release-model-change>
- [10] IPFire, "IPFire is Open Source Software". <https://www.ipfire.org/blog/ipfire-is-open-source-software-and-it-going-to-be-open-source-for-forever>
- [11] pfSense repository (LICENSE). <https://github.com/pfsense/pfsense>

The batch is RB-0208; its working files are private.
