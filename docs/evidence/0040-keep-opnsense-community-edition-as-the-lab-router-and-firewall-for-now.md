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
2. **Paid edition.** Deciso's Business Edition has "additional commercial features" [2] (sourced). "The business edition includes OpenID Connect support for some parts of the system" [3] (sourced). A reseller lists Business Edition only central management, web application firewall, advanced web proxy, GeoIP database access, user portal and tested updates [4] (sourced; a reseller page, not Deciso's). OPNsense's own documentation files OpenID Connect, Central Management, the Web Application Firewall, the User Portal, Authoritative DNS and Scheduled jobs under "Business Edition" [3] (sourced).
3. **OIDC outside the Business Edition.** A third-party plugin, `os-oidc` 0.2, adds OpenID Connect login to the community edition [7] (sourced). Its repository has no licence file and no releases; it is installed by hand with `pkg add` and is not in OPNsense's plugin repository [8] (measured). A maintainer saw no path for OAuth, OpenID or SAML in the community edition's generic sign-in model [9] (sourced). Not checked hands-on on the lab's firewall.
4. **Unbound**, the resolver inside OPNsense: "All functionality is available in the open-source project, with no separate enterprise edition or gated features"; BSD-3-Clause [5] (sourced).
5. **How it got here.** The home-lab spec says the lab was set up by hand before code [6] (sourced). No decision record chose OPNsense [6] (measured).
6. **Reach.** 72 files in 41 folders of `hosts/`, 22 runbooks, records D-0011, D-0017, D-0021, D-0028 and D-0036, STD-0001 and four specs name it [6] (measured, 2026-11-14).
7. **Alternatives.** OpenWrt is GPL-2.0-only [10] (measured). VyOS's vyos-1x is LGPL-2.1 [11] (measured); LTS images go to contributors free and to others by "binary image subscription", rolling images are free, and "you will always be able to build LTS releases yourself" [12] (sourced, a 2018 post). IPFire says "Our software and everything else is free" without naming a licence on that page [13] (sourced). pfSense CE is Apache-2.0 [14] (measured); its paid sibling pfSense Plus was not checked.

## How the decision used it

(Written from the record, not from the batch.)

Findings 1, 2 and 4 set rules 1 and 2: the community edition and Unbound are free, and the Business Edition features are excluded. Findings 2 and 3 are why sign-in goes another way (D-0037): Deciso's OIDC is paid, and the one third-party plugin has no licence. Findings 5 and 6 are the context. Finding 7 lists options 2 to 5.

## Limits

- No feature or fit comparison of the alternatives was made; only licences and paid editions.
- The paid sides of OpenWrt, IPFire and a Debian router were not checked.
- Advanced web proxy, GeoIP database access and tested updates in finding 2 rest on a reseller page.
- Finding 3 was not tested on the lab's firewall (for example with `pkg search oidc`).

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. OPNsense core LICENSE. <https://raw.githubusercontent.com/opnsense/core/master/LICENSE>
2. OPNsense, "Business Edition releases". <https://docs.opnsense.org/BE_releases.html>
3. OPNsense, "OpenID Connect" (Deciso). <https://docs.opnsense.org/vendor/deciso/oidc.html>
4. Thomas-Krenn, "Additional Features of OPNsense Business Edition". <https://www.thomas-krenn.com/en/wiki/Additional_Features_of_OPNsense_Business_Edition>
5. NLnet Labs, "Unbound". <https://nlnetlabs.nl/unbound>
6. RB-0208 findings (Research repository, batch `foss-check`): repository search of central-hub at 5626e8e, and its section 6.
7. OPNsense forum, "OpenID Connect SSO plugin". <https://forum.opnsense.org/index.php?topic=48884.0>
8. Lachee, opnsense-oidc repository (README and Makefile). <https://github.com/Lachee/opnsense-oidc>
9. opnsense/core issue 6110, "OpenID or SAML authentication". <https://github.com/opnsense/core/issues/6110>

Background:

- [10] OpenWrt repository (COPYING). <https://github.com/openwrt/openwrt>
- [11] vyos-1x repository (LICENSE). <https://github.com/vyos/vyos-1x>
- [12] VyOS, "VyOS release model change". <https://blog.vyos.io/vyos-release-model-change>
- [13] IPFire, "IPFire is Open Source Software". <https://www.ipfire.org/blog/ipfire-is-open-source-software-and-it-going-to-be-open-source-for-forever>
- [14] pfSense repository (LICENSE). <https://github.com/pfsense/pfsense>

The batch is RB-0208; its working files are private.
