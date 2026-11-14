---
id: D-0037
title: Sign in to the Proxmox host and OPNsense through Keycloak, by FOSS routes only, with each one's local root kept as the way in when c1 is down
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0025, D-0028, D-0034]
supersedes: []
superseded-by:
revisit-when: Keycloak's second factor moves from seeded TOTP to WebAuthn or a passkey; the directory record for OPNsense's LDAP sign-in (rule 5) is accepted; OPNsense is replaced; Proxmox drops or changes its OpenID Connect realm type; or c1 stops being where Keycloak runs
---

# Sign in to the Proxmox host and OPNsense through Keycloak, by FOSS routes only, with each one's local root kept as the way in when c1 is down

## Context and Problem Statement

D-0025 put sign-in to lab apps on c1 behind Keycloak, over OIDC only. The two machines the lab is built on, the Proxmox host and the OPNsense firewall, still sign in with their own local accounts: root@pam with TOTP on Proxmox ([set-up-proxmox-host.md](../runbooks/set-up-proxmox-host.md) step 4, which planned an OpenID realm "later"), and local root on OPNsense.

On 2026-11-14 at 04:35 UTC the owner asked "when will it be keycloak logins?", and at 04:37:38 UTC tapped "Also OPNsense, now" on a decision card. Its text was "Same as Now, plus a second PR so OPNsense logs in through Keycloak too, with its local root kept", and "Now" was "Agents open a PR extending Keycloak to Proxmox; root stays the emergency login; one setting is rerun at the realm rename" (card cmsg_01X43rfNYp4H1dL1V2dkfkwN4dBi2ikHT5KAgDe98AQ8dg). Between 04:43:45 and 04:44:57 UTC he ruled that every piece of the lab is free and open source with no open core, nothing with a paywalled feature (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, and most plainly cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). At 05:11:29 UTC he said OPNsense stays for now and Keycloak sign-in goes ahead (cmsg_01X43rfNYp4H1dL1V2dkfkwNUCNWkCsmp5t7rH58x9gsJH). The project's reviewing agent then asked that no admin path be weaker than today's root@pam with TOTP. OPNsense's own OIDC sign-in is in its paid Business Edition only, so OPNsense needs another route.

## Decision Drivers

- **One sign-in** for the people who run the lab, as D-0025 gives the apps.
- **No paywalled feature** (the owner's rule of 2026-11-14): every piece used is FOSS in the edition the lab runs.
- **A way in that doesn't need c1**: Keycloak runs on c1, which these two machines host and route.
- **Protocol seam** (D-0025 rule 1): standard protocols only, so Keycloak can be swapped.

## Considered Options

1. **Proxmox's own OpenID Connect realm against Keycloak; OPNsense through LDAP against a FOSS directory Keycloak also reads; local root kept on both.**
2. **A Keycloak-gated proxy (oauth2-proxy) in front of each web UI**, keeping each one's own login behind it.
3. **Keep local accounts only.**

## Decision Outcome

Proposed option: **1**. The owner asked for both machines on Keycloak with local root kept (card of 04:37:38 UTC), and option 1 is the only one that signs in through Keycloak rather than adding a gate in front of an unchanged login. For OPNsense the route is LDAP (rule 5): among the free routes researched, it is the one that is FOSS, in OPNsense's community edition, and a sign-in rather than a gate.

### Rules

1. **Proxmox.** The web UI signs in through Proxmox's own OpenID Connect realm `sso` against Keycloak's realm `lab`, client `proxmox`, code flow (role `proxmox_sso`, [runbook](../runbooks/sign-in-to-proxmox-through-keycloak.md)). User names come from `preferred_username`, which realm lab doesn't let users change. Keycloak group `lab-admins` gives Administrator on `/` and `lab-viewers` gives PVEAuditor, through the Proxmox groups `lab-admins-sso` and `lab-viewers-sso`. Groups are set from the claim at every sign-in. No other Keycloak group grants anything in Proxmox.
2. **Ways in that don't need c1.** Proxmox keeps root@pam with TOTP, and SSH by key. OPNsense keeps its local root. Neither is changed or removed by this record. Agents' API tokens (iac@pve, the OPNsense API users) are not sign-ins and are not touched.
3. **Secrets.** Each client secret is made like the other client secrets of realm lab: a line in the controller's `identity.env`, in realm lab's Secret on c1 for the import (D-0025 rule 5), and copied to the machine at apply time. Never in this repository.
4. **FOSS only.** Every component used for these sign-ins is free and open source in the edition the lab runs, with no feature behind a paid tier. That rules out OPNsense's Business Edition OIDC.
5. **OPNsense signs in through LDAP.** A FOSS directory holds the lab's users and groups; Keycloak reads it through its own LDAP federation; and OPNsense signs in against it with its community LDAP server type, with group sync and automatic user creation. So Keycloak's user store moves from the realm import to the directory. Which directory, where it runs and how Keycloak uses it are decided by their own record, with a comparison of FOSS directories. Until that is accepted and applied, OPNsense signs in with its local root only.

6. **A second factor for admins, in place before the Proxmox realm.** Every member of `lab-admins` has a TOTP seed in the controller's `identity.env` (`TOTP_<USER NAME>`, base32), imported into realm lab as the user's OTP credential, so it survives each delete and import of the realm. Keycloak's built-in browser and direct grant flows ask any user who has an OTP credential for the code, so every admin is asked at every sign-in, Proxmox's included. The Proxmox realm (rule 1) is applied only after the realm import that adds the seeds, in the same change; the owner adds his seed to an authenticator app before his first sign-in.

### Not decided here

- Which directory, where it runs, and whether Keycloak writes to it: the directory's own record.
- The realm's new name (the spec's rename of `lab` to `home`). The rename re-runs `proxmox_sso` with the new issuer and group names.

### Consequences

- Good: Proxmox gets one sign-in with the apps, and leaving `lab-admins` in Keycloak removes Proxmox rights at the next sign-in.
- Bad: **when c1, its Gateway or Keycloak is down, the daily sign-in to Proxmox fails.** That is when the host is needed most. The way in is root@pam with TOTP or SSH by key (rule 2), and it must be tested: the runbook's step 5 at install, then every 90 days as set-up-proxmox-host.md step 4 says.
- Good: admins sign in with a password and a TOTP code (rule 6), the same strength as root@pam with TOTP, and so do their sign-ins to Grafana, Argo CD and Jellyfin.
- Bad: **the TOTP seed sits where the password sits**: in `identity.env` on the controller (and its copy on the agent box), and in realm lab's Secret on c1. Anyone who can read those, agents with that access included (D-0025 rule 5), has both factors. The second factor guards against a password that leaks on its own, not against that access.
- Bad: a user who has signed in can remove their own OTP credential in Keycloak's account console until the next import puts it back.
- Bad: a realm import (any change to realm lab's code or values) ends open sign-ins, Proxmox's included.
- Bad: the Proxmox host must reach c1's Gateway on 443 and resolve the issuer's name (one `/etc/hosts` line).
- Neutral: 8006 stays for root@pam. A Keycloak sign-in works only on the 443 names, because Keycloak allows only those redirects.

### Confirmation

[Sign in to the Proxmox web UI through Keycloak](../runbooks/sign-in-to-proxmox-through-keycloak.md):

- step 4 signs in through Keycloak with Administrator;
- step 5 signs in as root@pam with TOTP.

The role's own proof checks that Proxmox builds a sign-in link to Keycloak for client `proxmox`. CI checks the realm import with the client in a real Keycloak, and runs the role against stand-ins (`test_proxmox_sso.sh`).

## Pros and Cons of the Options

### 2. A Keycloak-gated proxy in front of each web UI

- Good: oauth2-proxy is MIT-licensed, and one pattern covers any web UI.
- Bad: it is a gate, not a sign-in. Each machine's own login still follows, so there are two logins, and the user's rights still come from local accounts.
- Bad: one more service in the path to the machines that host it.

### 3. Keep local accounts only

- Good: nothing depends on c1.
- Bad: no single sign-in, and the owner asked for one.

## More Information

- Evidence: [`docs/evidence/0037-sign-in-to-proxmox-and-opnsense-through-keycloak.md`](../evidence/0037-sign-in-to-proxmox-and-opnsense-through-keycloak.md).
- D-0025 (Keycloak over OIDC), D-0028 (the lab CA the host trusts), D-0034 (how the owner approves).
