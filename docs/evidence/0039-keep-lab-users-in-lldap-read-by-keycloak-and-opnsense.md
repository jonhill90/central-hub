---
record: D-0039
batch: RB-0212 (2026-11-14), with the FOSS check RB-0208 of the same night for licences and paid tiers
researched: 2026-11-14
method: each candidate's licence file fetched from its own repository; vendor and project pages opened for paid editions and support; lldap's repository cloned and its Keycloak and OPNsense guides, FAQ and bootstrap script read; Keycloak's and Kanidm's documentation read
checks: none independent yet; the reviewing agent checks the sources with the PR
---

# Evidence for D-0039: which FOSS directory holds the lab's users for Keycloak and OPNsense

This file summarises what was read for D-0039. Nothing in it was run against the lab.

## Question

Which free and open-source LDAP directory should hold the lab's users and groups, so that Keycloak federates them and OPNsense's community edition signs administrators in against them, and where should it run?

## Findings

1. **OPNsense's LDAP sign-in.** With "Read properties" and "Synchronize groups", it reads `memberOf`. Groups "will only be considered when already existing in OPNsense". "Automatic user creation" makes the user at first sign-in [1].
2. **Keycloak's LDAP federation has three edit modes** [2]:
   - `READ_ONLY`: mapped attributes can't change, and "Password updates are not supported".
   - `WRITABLE`: changes and passwords sync to LDAP.
   - `UNSYNCED`: changes are kept in Keycloak's own storage.
3. **lldap.**
   - Licence: GPL-3.0 [3].
   - "Testing group membership through `memberOf` is supported"; LDAPS is supported; data in SQLite, MySQL, MariaDB or PostgreSQL [4].
   - Its Keycloak guide: "LLDAP is _read-only_", with Edit Mode `READ_ONLY` and the LDAPv3 Password Modify extended operation [5]. Its OPNsense guide binds as a user in `lldap_strict_readonly` [6].
   - `scripts/bootstrap.sh` creates users, groups and memberships from config files, and sets passwords with `lldap_set_password` [7]. It calls `lldap_set_password` for every user whose config gives `password` or `password_file`, on every run, whether or not the user already existed. `DO_CLEANUP_USERS` and `DO_CLEANUP_GROUP_MEMBERSHIP` default to `false`, so without them a user or membership dropped from the config stays in lldap; the `admin` user is never removed.
   - No commercial support: "volunteer-developed free-software on a best-effort basis" [8].
   - Newest commit 2026-09-26; tags up to v0.6.3.
   - [measured: a shallow clone, 2026-11-14]
4. **Kanidm.**
   - Licence: MPL-2.0 [9].
   - It hosts "a read-only LDAP interface"; "writes are rejected for all users"; "the LDAP bind for any DN will use its configured posix password"; "StartTLS is not supported", LDAPS only; groups through `memberof` [10].
   - It is an identity server with its own OIDC, beside Keycloak [10].
5. **OpenLDAP.** Licence: the OpenLDAP Public License 2.8 [11]. Symas "delivers enterprise support, tested software builds, maintenance" for OpenLDAP [12]. No feature was seen behind it; the paid build's contents were not read.
6. **389 Directory Server and FreeIPA.**
   - 389 DS: "GPLv3+" (with OpenSSL and MIT exceptions) [13]. Its project page: "can be downloaded for free" and "supports multi-supplier replication" [14].
   - FreeIPA: GPL-3.0 [15].
   - Red Hat sells Red Hat Directory Server [16]; its feature list against 389 DS was not compared.
   - Keycloak names "Red Hat Directory Server" among its LDAP vendors [2].

## How the decision used it

- **The pick.** Findings 1, 2 and 3 are why lldap with `READ_ONLY` federation is picked: it is FOSS with no paid edition, gives `memberOf` to OPNsense, and keeps users and groups as code through its bootstrap script.
- **Kanidm.** Finding 4 is why it is turned down: a second identity server, and LDAP binds on a separate POSIX password.
- **OpenLDAP, 389 DS and FreeIPA.** Findings 5 and 6 are why they are turned down: heavier to run for what the lab needs.
- **Rule 5.** It holds the switch because nothing here shows how a seeded OTP credential (D-0037 rule 6) attaches to a federated user.

## Limits

- Nothing was run: no lldap, no federation, no OPNsense LDAP test.
- Maintainers and release cadence were not measured beyond the newest commit of lldap.
- The commercial builds of OpenLDAP and 389 DS were not compared feature by feature.
- How lldap's data is backed up and restored on c1 is not designed yet.

## References

1. OPNsense docs, LDAP how-to: <https://docs.opnsense.org/manual/how-tos/user-ldap.html>
2. Keycloak Server Administration Guide, LDAP and Active Directory: <https://www.keycloak.org/docs/latest/server_admin/index.html>
3. lldap licence: <https://github.com/lldap/lldap/blob/main/LICENSE>
4. lldap README: <https://github.com/lldap/lldap/blob/main/README.md>
5. lldap Keycloak guide: <https://github.com/lldap/lldap/blob/main/example_configs/keycloak.md>
6. lldap OPNsense guide: <https://github.com/lldap/lldap/blob/main/example_configs/opnsense.md>
7. lldap bootstrap script: <https://github.com/lldap/lldap/blob/main/scripts/bootstrap.sh>
8. lldap FAQ: <https://github.com/lldap/lldap/blob/main/docs/faq.md>
9. Kanidm licence: <https://github.com/kanidm/kanidm/blob/master/LICENSE.md>
10. Kanidm book, LDAP: <https://kanidm.github.io/kanidm/stable/integrations/ldap.html>
11. OpenLDAP licence: <https://git.openldap.org/openldap/openldap/-/raw/master/LICENSE>
12. Symas: <https://www.symas.com/>
13. 389-ds-base licence: <https://github.com/389ds/389-ds-base/blob/main/LICENSE>
14. 389 Directory Server: <https://www.port389.org/>
15. FreeIPA licence: <https://github.com/freeipa/freeipa/blob/master/COPYING>
16. Red Hat Directory Server: <https://www.redhat.com/en/technologies/cloud-computing/directory-server>
