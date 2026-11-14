---
record: D-0043
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: each project's licence file read from its repository; Tailscale's open-source and pricing pages opened; central-hub searched for every file naming the piece; on 2026-11-14 at about 09:15 UTC, Headscale's ACL page and NetBird's access-control page opened for the policy-format reading
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch before the owner sees it"
---

# Evidence for D-0043: Tailscale as the way into the lab

This file summarises the research behind D-0043. It adds nothing the research did not find.

## Question

Is Tailscale free and open source with no feature held back, which parts are closed, and what free alternatives exist?

## Findings

1. **Licence.** The client daemon is BSD-3-Clause [1] (measured).
2. **Closed parts.** Tailscale runs "a closed source coordination server", and on closed operating systems "the GUI is closed source" [2] (sourced).
3. **Paid plans.** Paid plans hold back SCIM, more access-control groups, device posture and others; the free Personal plan is for up to 6 users [3] (sourced).
4. **Reach.** At central-hub 5626e8e, 30 files in 11 `hosts/` folders (tailnet, tailnet-policy, remote-access, agent_box, tailnet_connector), 11 runbooks, D-0036 and STD-0002 name it [4] (measured, 2026-11-14).
5. **Alternatives.** Headscale is BSD-3-Clause [5] (measured) and calls itself "An open source, self-hosted implementation of the Tailscale control server" [5] (sourced); its getting-started page connects the Tailscale client with `tailscale up --login-server <YOUR_HEADSCALE_URL>` [7] (sourced); its ACL page says it "implements the same policy ACLs as Tailscale.com, adapted to the self-hosted environment" and that "ACLs have to be written in huJSON" [8] (sourced, read in a mirror of the project's repository); its paid edition was not checked. NetBird's client is BSD-3-Clause, with its management, signal and relay under another licence (AGPL per its LICENSE header) [6] (measured); its access-control page describes deny-by-default groups and policies set in the NetBird interface, with peers "running the NetBird client", and names no policy file [9] (sourced); its paid cloud tiers were not checked.

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 to 3 set rules 1 and 2 and the "Bad" consequence about the closed server. Finding 4 is the context. Finding 5 lists options 2 and 3 and the exit path.

## Limits

- No feature comparison between Tailscale, Headscale and NetBird was made.
- The owner's answer of 2026-11-10 is a decision-card tap (19:09 UTC, card cmsg_01X43rfNYp4H1dL1V2dkfkwN94SWGX6ssfCizqji4VUhLp), also cited in STD-0006's `foss-exceptions.yaml`.
- The policy-format and client readings in finding 5 come from documentation; no policy was replayed into Headscale or NetBird.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. Tailscale repository (LICENSE). <https://github.com/tailscale/tailscale>
2. Tailscale, "Open source at Tailscale". <https://tailscale.com/opensource>
3. Tailscale, "Pricing". <https://tailscale.com/pricing>
4. RB-0208 findings (Research repository, batch `foss-check`): repository search of central-hub at 5626e8e.
5. Headscale repository (LICENSE). <https://github.com/juanfont/headscale>
6. NetBird repository (LICENSE). <https://github.com/netbirdio/netbird>
7. Headscale, "Getting started". <https://github.com/juanfont/headscale/blob/main/docs/usage/getting-started.md>
8. Headscale, "ACLs" (`docs/ref/acls.md`, read in a mirror of the repository on 2026-11-14). <https://git.laurivan.com/Mirrors/juanfont.headscale/blame/branch/main/docs/ref/acls.md>
9. NetBird, "Understanding Groups and Access Policies". <https://docs.netbird.io/manage/access-control>

The batch is RB-0208; its working files are private.
