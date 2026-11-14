---
id: D-0039
title: Keep the lab's users and groups in lldap, a small FOSS LDAP directory on c1, read by Keycloak and by OPNsense's sign-in
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0025]
supersedes: []
superseded-by:
revisit-when: lldap stops being maintained or gains a paid edition; the admins' second factor (D-0037 rule 6) can't be carried over to federated users; OPNsense is replaced; or c1 stops being where Keycloak runs
---

# Keep the lab's users and groups in lldap, a small FOSS LDAP directory on c1, read by Keycloak and by OPNsense's sign-in

## Context and Problem Statement

D-0037 (proposed in pull request #271) has OPNsense sign its administrators in through LDAP, because OPNsense's own OIDC sign-in is in its paid Business Edition only, and the owner's rule of 2026-11-14 allows no paywalled feature (cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). Keycloak is not an LDAP server, so a directory is needed that both Keycloak and OPNsense read. **Keycloak's user store then moves from the realm import (D-0025 rule 4) to that directory.** This record picks the directory and where it runs. Nothing in it is measured on the lab yet.

## Decision Drivers

- **FOSS with no paid edition** (the owner's rule).
- **Small and deterministic**: users and groups as code, like realm lab today.
- **Fits both readers**: Keycloak's LDAP federation, and OPNsense's LDAP sign-in with group sync (`memberOf`).
- **No admin way in weaker than a password and a code** (D-0037 rule 6), on OPNsense too.
- **Backup and rebuild** the way c1's other data is backed up.

## Considered Options

1. **lldap** (GPL-3.0): a light LDAP server for authentication, with a web UI and a GraphQL API.
2. **Kanidm** (MPL-2.0): an identity server with its own OIDC, and a read-only LDAP interface.
3. **OpenLDAP** (OpenLDAP Public License): the full LDAP server.
4. **389 Directory Server** (GPL-3.0 or later), or **FreeIPA** around it (GPL-3.0).

## Decision Outcome

Proposed option: **1, lldap, on c1 next to Keycloak**, read-only to both readers.

### Rules

1. **lldap holds the lab's users, their passwords and their groups** (`lab-admins`, `lab-viewers`). They are written from code by lldap's own bootstrap script, with each password from the controller's `identity.env` as today. The script runs with `DO_CLEANUP_USERS` and `DO_CLEANUP_GROUP_MEMBERSHIP` set to `true`, because both default to false: a user or membership dropped from code is then removed from lldap, which is how an admin loses `lab-admins` and with it Proxmox rights (D-0037).
2. **Keycloak reads lldap through its LDAP user federation**, in `READ_ONLY` mode. Groups come from a group mapper. Realm lab no longer imports users. Clients, roles and the group-to-role map stay in the realm import.
3. **OPNsense reads lldap over LDAPS, with a code as well as the password.** The authentication server is of type "LDAP + Timebased One Time Password" (`ldap-totp`), which is in OPNsense's free core, with "Synchronize groups". It binds as a user in lldap's read-only group, not the admin. That bind user, and Keycloak's if it has one, are declared in the bootstrap config like any other user, so the cleanup in rule 1 never removes them. Its groups `lab-admins` and `lab-viewers` exist in OPNsense with the privileges each should have. Only that server is OPNsense's web UI sign-in, besides local root (rule 4).
   - **Each OPNsense sign-in user is made by code, with a seed.** The type reads the TOTP seed from the user's own entry in OPNsense's configuration, and refuses a user that has none, so "Automatic user creation" at first sign-in can't work. Code makes the entry in advance for each user allowed to sign in to OPNsense, with the same base32 seed as their `TOTP_<USER>` in `identity.env` (D-0037 rule 6), so one authenticator entry serves Keycloak and OPNsense. The entry gets OPNsense's scrambled password, a random one that is never stored or shown, so the "Local Database" server, which stays on for root, can't sign that user in with a local password and no code. The route that writes it, OPNsense's API or the role's collection, is picked when it is built.
   - **The code goes in the password field, before the password** (OPNsense's default; its "token after password" option reverses it).
4. **lldap runs on c1, in the identity namespace.** Its data is backed up with c1's other data. OPNsense's LDAP sign-in then depends on c1, as Proxmox's does (D-0037). Local root stays the way in on both, as the break-glass account.
5. **The admins' second factor (D-0037 rule 6) is carried over before Keycloak federates.** How a seeded OTP credential attaches to a federated user is not shown yet, and the realm delete-and-import also wipes the local credentials Keycloak keeps for federated users. Until both are shown on dev, the switch doesn't happen.
6. **lldap's data survives a rebuild, and dev proves it first.** lldap keeps its data on a claim under `/var/lib/c1-data/local-path`, which role `k8s_backup` already backs up with restic. The rebuild's restore stage (`hosts/rebuild-k8s.sh`, `playbooks/k8s-restore.yml`) puts it back before Argo CD starts lldap, so a password changed after bootstrap comes back. The restore check gains an lldap step: start the pinned lldap on the restored data in a throwaway namespace and bind as one lab user. The realm import keeps clients, roles and the federation settings, but no users. lldap's bootstrap script sets a user's password on every run when its config gives one, so the build passes a password only for a user lldap does not have yet; otherwise a run after a restore would undo a changed password. The dev rebuild with lldap is run and passes, restore check included, before prod changes (D-0035 rule 3).

### Consequences

- Good: one place for users and groups, read by everything that signs in.
- Good: lldap is small, and its users and groups are code through its bootstrap script.
- Bad: **Keycloak's user store moves out of the realm import.** A user's password lives in lldap, and a change made through Keycloak is refused in `READ_ONLY` mode.
- Bad: one more service on c1, and OPNsense must reach it on 636 (a firewall change, the owner's words).
- Bad: lldap's LDAP is deliberately partial, and it has no commercial support: "volunteer-developed free-software on a best-effort basis".
- Good: OPNsense's admins need a code as well as the password, with no paid feature.
- Bad: each admin's TOTP seed is held twice, in `identity.env` and in OPNsense's configuration, so a new seed is written to both. OPNsense's configuration already holds every secret on the firewall, and the box's daily copy of it is kept as such (0600, its own read-only key).

### Confirmation

Nothing below is measured yet. A dev rehearsal before prod:

- realm lab federated to lldap;
- an admin signs in to Grafana and Proxmox with a password and a code;
- OPNsense's Access Tester signs the admin in with a code and the password and shows the `lab-admins` group, and refuses the password alone and a user with no seed;
- c1 is restored from backup with lldap's data;
- the dev rebuild runs from scratch, and the same admin signs in again afterwards.

## Pros and Cons of the Options

### 2. Kanidm

- Good: MPL-2.0, no paid edition seen, LDAPS only (StartTLS refused by design), `memberOf` groups.
- Bad: it is a second identity server beside Keycloak, with its own OIDC.
- Bad: its LDAP is read-only, and "the LDAP bind for any DN will use its configured posix password", a separate password from its primary credentials.

### 3. OpenLDAP

- Good: full LDAP; `WRITABLE` federation would let Keycloak write users and passwords.
- Bad: much more to run and configure (schemas, overlays, ACLs).
- Bad: Symas sells "enterprise support, tested software builds"; the server itself is free.

### 4. 389 Directory Server or FreeIPA

- Good: full-featured, `memberOf` plugin. Keycloak names "Red Hat Directory Server" as a vendor.
- Bad: heavy, and FreeIPA adds Kerberos, DNS and a CA the lab doesn't need. Red Hat sells the same lines as Red Hat Directory Server and Identity Management.

## More Information

- Evidence: [`docs/evidence/0039-keep-lab-users-in-lldap-read-by-keycloak-and-opnsense.md`](../evidence/0039-keep-lab-users-in-lldap-read-by-keycloak-and-opnsense.md).
- D-0025 (Keycloak), D-0037 (Proxmox and OPNsense sign-in).
