---
record: D-0049
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: AlmaLinux's and Debian's own pages on their terms opened; AlmaLinux's support page and TuxCare's support docs read after a web search for paid AlmaLinux offers; central-hub searched for every file naming each; on 2026-11-14 at about 11:05 UTC, the AlmaLinux home and support pages and TuxCare's documentation page opened again, and the reach and the machines' operating systems re-read at main d9139e7; at about 11:20 UTC, AlmaLinux's FIPS page opened after a web search for its free and paid FIPS terms, and the jumpbox rehearsal kit's code read for CT 259's template
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0049: AlmaLinux and Debian

This file summarises the research behind D-0049. It adds nothing the research and the pages listed below did not find.

## Question

Are AlmaLinux and Debian free with nothing held back behind a paywall, and which machines run each?

## Findings

1. **AlmaLinux.** Its home page calls it "An Open Source, community owned and governed, forever-free enterprise Linux distribution" [1] (sourced).
2. **AlmaLinux sponsors.** The support page lists sponsors' paid offers [4] (sourced):
   - TuxCare: technical support, certification help, FIPS 140-3 compliance and security hardening;
   - Cybertrust Japan: support;
   - Fujitsu: "AlmaLinux OS Advanced Longterm Support", with fixes for specific minor releases.
3. **TuxCare's FIPS packages.** TuxCare's Extended Security Updates include "the full suite of five FIPS-validated modules (kernel, openssl, libcrypt, nss and gnutls)", and "the product also unlocks commercial use of the FIPS-validated packages". Installing them needs an Extended Security Updates licence key [5] (sourced). The support page calls TuxCare "the founding sponsor of the AlmaLinux OS Project" [4] (sourced).
4. **AlmaLinux's FIPS page.** "The validation was sponsored by TuxCare, the enterprise support division of CloudLinux". "Anyone running AlmaLinux OS 9.2 can enable FIPS mode and meet the standard at no cost, for non-commercial use", from TuxCare's community packages, and "ongoing FIPS-compliant patching and commercial use are offered through TuxCare's Enterprise Support" [6] (sourced).
5. **Debian:** "We promise that the Debian system and all its components will be free" [2] (sourced).
6. **Machines.** At main d9139e7 [3] (measured):
   - c1's nodes, the agent box, the CI runner, the desktop and the secrets store are AlmaLinux 10 VMs from one pinned GenericCloud image;
   - the firewall VM is OPNsense;
   - the Talos rehearsal's node VMs (`k8s-talos`) run Talos Linux and are not clones of the AlmaLinux template;
   - the remote-access container uses Proxmox's Debian 13 template;
   - CT 259 is not in this repository: the jumpbox rehearsal kit, kept outside it, makes it as an unprivileged Debian 13 container from the same Proxmox template [7] (measured, 2026-11-14).
7. **Reach.** At main d9139e7, AlmaLinux is named in 26 files in `hosts/`, 7 runbooks and 2 records, and Debian in 10 files, 6 runbooks and 1 record [3] (measured, 2026-11-14).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 to 5 are the paywall weighing and rules 1 and 3. Findings 6 and 7 are the context, the CT 259 gap and the confirmation.

## Limits

- No distribution was compared on fit; options 2 and 3 rest on the record's reasoning only.
- The licences of individual packages were not checked.
- Whether TuxCare's FIPS-validated packages differ in code from the free ones was not checked, and nothing was tested hands-on.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. AlmaLinux, home page. <https://almalinux.org/>
2. Debian, "Debian Social Contract". <https://www.debian.org/social_contract.html>
3. Repository search and code read of central-hub at d9139e7 (this repository).
4. AlmaLinux, "Support". <https://almalinux.org/support>
5. TuxCare, "Enterprise Support for AlmaLinux". <https://docs.tuxcare.com/enterprise-support-for-almalinux/>
6. AlmaLinux, "AlmaLinux OS is FIPS 140-3 validated". <https://almalinux.org/security/fips-certification/>
7. The jumpbox rehearsal kit's OpenTofu code (`main.tf`, `variables.tf`), read 2026-11-14. It is not in this repository.

The batch is RB-0208; its working files are private.
