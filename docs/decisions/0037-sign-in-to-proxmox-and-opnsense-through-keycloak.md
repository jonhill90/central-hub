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
revisit-when: Keycloak's second factor moves from seeded TOTP to WebAuthn or a passkey; the OPNsense plugin os-openid-connect (rule 5) is abandoned, changes its licence, or fails a code read of a new version; OPNsense's community edition gets its own OIDC sign-in; OPNsense is replaced; Proxmox drops or changes its OpenID Connect realm type; or c1 stops being where Keycloak runs
---

# Sign in to the Proxmox host and OPNsense through Keycloak, by FOSS routes only, with each one's local root kept as the way in when c1 is down

## Context and Problem Statement

D-0025 put sign-in to lab apps on c1 behind Keycloak, over OIDC only. The two machines the lab is built on, the Proxmox host and the OPNsense firewall, still sign in with their own local accounts: root@pam with TOTP on Proxmox ([set-up-proxmox-host.md](../runbooks/set-up-proxmox-host.md) step 4, which planned an OpenID realm "later"), and local root on OPNsense.

On 2026-11-14 at 04:35 UTC the owner asked "when will it be keycloak logins?", and at 04:37:38 UTC tapped "Also OPNsense, now" on a decision card. Its text was "Same as Now, plus a second PR so OPNsense logs in through Keycloak too, with its local root kept", and "Now" was "Agents open a PR extending Keycloak to Proxmox; root stays the emergency login; one setting is rerun at the realm rename" (card cmsg_01X43rfNYp4H1dL1V2dkfkwN4dBi2ikHT5KAgDe98AQ8dg). Between 04:43:45 and 04:44:57 UTC they ruled that every piece of the lab is free and open source with no open core, nothing with a paywalled feature (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, and most plainly cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). At 05:11:29 UTC they said OPNsense stays for now and Keycloak sign-in goes ahead (cmsg_01X43rfNYp4H1dL1V2dkfkwNUCNWkCsmp5t7rH58x9gsJH). The project's reviewing agent then asked that no admin path be weaker than today's root@pam with TOTP. OPNsense's own OIDC sign-in is in its paid Business Edition only, so OPNsense needs another route. A community plugin, os-openid-connect (BSD-2-Clause, first released as a beta in August 2026), adds OIDC sign-in to the community edition's web GUI.

## Decision Drivers

- **One sign-in** for the people who run the lab, as D-0025 gives the apps.
- **No paywalled feature** (the owner's rule of 2026-11-14): every piece used is FOSS in the edition the lab runs.
- **A way in that doesn't need c1**: Keycloak runs on c1, which these two machines host and route.
- **Protocol seam** (D-0025 rule 1): standard protocols only, so Keycloak can be swapped.

## Considered Options

1. **Proxmox's own OpenID Connect realm against Keycloak; OPNsense through the community OIDC plugin os-openid-connect against Keycloak; local root kept on both.**
2. **A Keycloak-gated proxy (oauth2-proxy) in front of each web UI**, keeping each one's own login behind it.
3. **Keep local accounts only.**
4. **OPNsense through LDAP**, against a FOSS directory that Keycloak also reads (Proxmox as in option 1).
5. **OPNsense through RADIUS**, against Keycloak's RADIUS provider `keycloak-radius-plugin` (Proxmox as in option 1).

## Decision Outcome

Proposed option: **1**. The owner asked for both machines on Keycloak with local root kept (card of 04:37:38 UTC), and option 1 is the only one that signs in through Keycloak rather than adding a gate in front of an unchanged login. For OPNsense the route is the community plugin os-openid-connect (rule 5): among the free routes researched, it is the only one that is FOSS, runs on OPNsense's community edition, and signs in at Keycloak itself, rather than adding a gate (option 2), a second user store (option 4) or a password typed into OPNsense's own form (option 5).

### Rules

1. **Proxmox.** The web UI signs in through Proxmox's own OpenID Connect realm `sso` against Keycloak's realm `lab`, client `proxmox`, code flow (role `proxmox_sso`, [runbook](../runbooks/sign-in-to-proxmox-through-keycloak.md)). User names come from `preferred_username`, which realm lab doesn't let users change. Keycloak group `lab-admins` gives Administrator on `/` and `lab-viewers` gives PVEAuditor, through the Proxmox groups `lab-admins-sso` and `lab-viewers-sso`. Groups are set from the claim at every sign-in. No other Keycloak group grants anything in Proxmox.
2. **Ways in that don't need c1.** Proxmox keeps root@pam with TOTP, and SSH by key. OPNsense keeps its local root. Neither is changed or removed by this record. Agents' API tokens (iac@pve, the OPNsense API users) are not sign-ins and are not touched.
3. **Secrets.** Each client secret is made like the other client secrets of realm lab: a line in the controller's `identity.env`, in realm lab's Secret on c1 for the import (D-0025 rule 5), and copied to the machine at apply time. Never in this repository.
4. **FOSS only.** Every component used for these sign-ins is free and open source in the edition the lab runs, with no feature behind a paid tier. That rules out OPNsense's Business Edition OIDC.
5. **OPNsense signs in through the community plugin os-openid-connect.** Its web GUI signs in through Keycloak's realm, client `opnsense`, code flow with PKCE S256 (role k8s_identity, `k8s_identity_opnsense_hosts`; [runbook](../runbooks/sign-in-to-opnsense-through-keycloak.md)).
   - **The plugin decides who gets in, not Keycloak.** Each Keycloak identity is bound by exact issuer and subject to a local OPNsense account, whose groups give its rights. Admission is `approval`: an unknown identity waits until an admin binds it. Accounts are never made at first sign-in, and root is never reachable through it.
   - **What is left off:** pushed authorization requests (PAR mode `disabled`), back-channel logout (logout notifications off) and shared signals. Those parts of the plugin were not read, and with them off the plugin's root job only fetches Keycloak's discovery document and keys.
   - **DPoP stays on.** The plugin uses DPoP whenever Keycloak offers it and has no setting to turn it off, so every sign-in binds its tokens to a key the firewall keeps. Its DPoP code was read with the rest (evidence finding 24).
   - **One pinned package, read before use.** The package is pinned by version and SHA-256 and checked against the release's build attestation. Its code is read before it goes on the firewall, and again for each new version. The plugin is installed by hand and is never updated by OPNsense's own updates.
   - **Proven on a throwaway OPNsense first.** The lab firewall gets it only after a test OPNsense in dev has shown a Keycloak sign-in, a refused unknown identity, and root's password sign-in with Keycloak stopped. The test signs in at a throwaway Keycloak on the agent box, so realm lab on c1 is not touched until the lab firewall step.
   - **The firewall step is the owner's.** Installing it on the lab firewall changes the firewall and who can sign in to it, so it waits for the owner's tap (D-0036 rule 8, D-0042 rule 6). Client `opnsense` is added to realm lab on c1 only in that step.

6. **A second factor for admins, in place before the Proxmox realm.** Every member of `lab-admins` has a TOTP seed in the controller's `identity.env` (`TOTP_<USER NAME>`, base32), imported into realm lab as the user's OTP credential, so it survives each delete and import of the realm. Keycloak's built-in browser and direct grant flows ask any user who has an OTP credential for the code, so every admin is asked at every sign-in, Proxmox's included. The Proxmox realm (rule 1) is applied only after the realm import that adds the seeds, in the same change; the owner adds their seed to an authenticator app before their first sign-in by scanning a QR code that `hosts/ansible/bootstrap/show-totp-qr.sh` shows on the controller's own screen for a short time and then deletes, so the seed is never typed, pasted, printed or logged.

7. **Exit.** Each part can be removed or replaced on its own, and no data is lost, because Proxmox keeps nothing from a sign-in except the user entry and the group membership the claim sets.
   - Proxmox: `pveum realm delete sso` and the two groups' ACL entries undo rule 1; root@pam and SSH (rule 2) are untouched. Leaving `k8s_identity_proxmox_hosts` empty drops client `proxmox` at the next realm import.
   - Keycloak: the realm uses only standard OpenID Connect (discovery, the code flow, a `preferred_username` claim and a `groups` claim). Any OpenID Connect provider that issues those two claims replaces it by a new `proxmox_sso_issuer` and client secret; users are made again at their first sign-in.
   - The second factor: each seed is a base32 RFC 6238 TOTP seed in `identity.env`, so it moves to any provider or authenticator that imports one.
   - OPNsense: disabling the plugin's server, or `pkg delete os-openid-connect`, leaves local sign-in as it was; the package's settings stay in `/conf/config.xml`. Leaving `k8s_identity_opnsense_hosts` empty drops client `opnsense` at the next realm import. The plugin speaks standard OpenID Connect, so any provider replaces Keycloak by a new issuer, client id and secret, with each identity bound again.

### Not decided here

- How the agent box puts the package on OPNsense (its API, SSH, or a local package repository): decided from the dev proof, in the runbook.
- The realm's new name (the spec's rename of `lab` to `home`). The rename re-runs `proxmox_sso` with the new issuer and group names.

### Consequences

- Good: Proxmox gets one sign-in with the apps, and leaving `lab-admins` in Keycloak removes Proxmox rights at the next sign-in.
- Bad: **when c1, its Gateway or Keycloak is down, the daily sign-in to Proxmox fails.** That is when the host is needed most. The way in is root@pam with TOTP or SSH by key (rule 2), and it must be tested: the runbook's step 5 at install, then every 90 days as set-up-proxmox-host.md step 4 says.
- Good: admins sign in with a password and a TOTP code (rule 6), the same strength as root@pam with TOTP, and so do their sign-ins to Grafana, Argo CD and Jellyfin.
- Bad: **the TOTP seed sits where the password sits**: in `identity.env` on the controller (and its copy on the agent box), and in realm lab's Secret on c1. Anyone who can read those, agents with that access included (D-0025 rule 5), has both factors. The second factor guards against a password that leaks on its own, not against that access.
- Bad: a user who has signed in can remove their own OTP credential in Keycloak's account console until the next import puts it back.
- Bad: a realm import (any change to realm lab's code or values) ends open sign-ins, Proxmox's included.
- Bad: the Proxmox host must reach c1's Gateway on 443 and resolve the issuer's name (one `/etc/hosts` line).
- Bad: **`pveum` gets the client secret on its command line** while it runs, so a local process on the Proxmox host can read it from `/proc` for those seconds. It stays that way for now, because Proxmox keeps the same secret in plain text in `/etc/pve/domains.cfg` anyway (`client-key` is a realm property, not under `priv/`), which group www-data, the web proxy's group, can read, and the host has no unprivileged users. Ansible doesn't log it (`no_log`). Revisit when the host gets other local users or Proxmox moves the key under `priv/`.
- Bad: **the OPNsense plugin is a beta from one maintainer**, not reviewed by OPNsense, installed by hand and never updated by OPNsense's own updates. Its code read covers the sign-in path and its root jobs, not all of it. An OPNsense upgrade can break it, so each upgrade is tried on the test OPNsense first, and the plugin's own nightly check logs when the core files it hooks into change.
- Bad: when c1 or Keycloak is down, the Keycloak sign-in to OPNsense fails, and local root (rule 2) is the way in.
- Bad: OPNsense must reach Keycloak's token endpoint for every sign-in, not only the browser.
- Neutral: 8006 stays for root@pam. A Keycloak sign-in works only on the 443 names, because Keycloak allows only those redirects.

### Confirmation

[Sign in to the Proxmox web UI through Keycloak](../runbooks/sign-in-to-proxmox-through-keycloak.md):

- step 4 signs in through Keycloak with Administrator;
- step 5 signs in as root@pam with TOTP.

[Sign in to the OPNsense web GUI through Keycloak](../runbooks/sign-in-to-opnsense-through-keycloak.md): the test OPNsense proof against a throwaway Keycloak, then the client in realm lab and the three checks on the lab firewall.

The role's own proof checks that Proxmox builds a sign-in link to Keycloak for client `proxmox`. CI checks the realm import with the client in a real Keycloak, and runs the role against stand-ins (`test_proxmox_sso.sh`).

## Pros and Cons of the Options

### 2. A Keycloak-gated proxy in front of each web UI

- Good: oauth2-proxy is MIT-licensed, and one pattern covers any web UI.
- Bad: it is a gate, not a sign-in. Each machine's own login still follows, so there are two logins, and the user's rights still come from local accounts.
- Bad: one more service in the path to the machines that host it.

### 3. Keep local accounts only

- Good: nothing depends on c1.
- Bad: no single sign-in, and the owner asked for one.

### 4. OPNsense through LDAP

- Good: OPNsense's community LDAP login is built in, with group sync and automatic user creation.
- Bad: Keycloak is not an LDAP server, so a new FOSS directory holds the users, Keycloak reads it by federation, and the realm's users move out of its import. It is the larger change.
- Bad: the user types the password into OPNsense's form, so it is not a Keycloak sign-in, and Keycloak's second factor is not asked.

### 5. OPNsense through RADIUS

- Good: `keycloak-radius-plugin` is Apache-2.0 and checks Keycloak's own passwords and OTP codes.
- Bad: it is built against an older Keycloak than the lab's, so it needs a custom Keycloak image and a check at each Keycloak upgrade.
- Bad: as with option 4, the password is typed into OPNsense's own form.

## More Information

- Evidence: [`docs/evidence/0037-sign-in-to-proxmox-and-opnsense-through-keycloak.md`](../evidence/0037-sign-in-to-proxmox-and-opnsense-through-keycloak.md).
- D-0025 (Keycloak over OIDC), D-0028 (the lab CA the host trusts), D-0034 (how the owner approves).
