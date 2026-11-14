---
record: D-0037
batch: RB-0211 (2026-11-14), with the FOSS check RB-0208 of the same night for licences and paid tiers
researched: 2026-11-14
method: Proxmox and OPNsense documentation and source files fetched and read; the candidate OPNsense routes' repositories cloned and their licence files and build files read; the role run against stand-ins
checks: the reviewing agent re-read the Proxmox sources and Keycloak's OTPCredentialModel.java and DefaultAuthenticationFlows.java at 26.4.0 and at 26.8.1, the lab's version, and found the cited lines the same (2026-11-14)
---

# Evidence for D-0037: sign-in to the Proxmox host and OPNsense through Keycloak

This file summarises what was read and measured for D-0037. It adds nothing beyond that.

## Question

How do the Proxmox host and OPNsense sign their administrators in through Keycloak, using only FOSS with no paywalled feature, while keeping a way in that doesn't need c1?

## Findings

1. **Proxmox: it has an OpenID Connect realm type** with issuer, client ID and key, `autocreate`, `username-claim`, `groups-claim`, `groups-autocreate` and `groups-overwrite` [1].
2. **Claimed group names get `-<realm name>` added**, for example `my-openid-group` in realm `oidc` becomes `my-openid-group-oidc`. Groups that don't exist in Proxmox are ignored unless `groups-autocreate` is set [1].
3. **The username claim is fixed once the realm is made**: `"username-claim" => { optional => 1, fixed => 1 }` [2]. The wiki warns that a claim users can edit lets them take another account [1].
4. **The web UI sends its own origin as the redirect**: `const redirectURL = location.origin;` … `'redirect-url': redirectURL` [3].
5. **The `pveum realm add` options** include `--client-key`, `--comment` and `--default` [4].
6. **Proxmox VE is AGPL-3.0 or later.** The pricing page says "all other Proxmox VE features are available at every level"; the plans differ by support and the Enterprise Repository [5] (the FOSS audit).

7. **Keycloak is Apache-2.0** [6]. Realm lab already imports clients as code and checks the import in CI against a real Keycloak (D-0025; `.github/hosts-check/identity/`).

8. **OPNsense's OIDC sign-in is in the Business Edition only**: "The business edition includes OpenID Connect support for some parts of the system" [7]. The core is BSD-licensed [8].
9. **The community edition can log in against LDAP and RADIUS.**
   - LDAP: "Synchronize groups" reads `memberOf`, and "Automatic user creation" applies; "Groups … will only be considered when already existing in OPNsense" [9].
   - RADIUS: groups come from the CLASS attribute [10].
10. **The community OIDC plugin, `Lachee/opnsense-oidc`, has no licence.**
    - No LICENSE file, and no licence in its README, `package.json` or `pkg-descr`.
    - It is version 0.2 (Makefile), about 2,900 lines of PHP, JS and templates.
    - Its newest commit is 2025-10-05.
    - The author announced it on OPNsense's forum, where a project administrator pointed to the Business Edition [11].
    - [measured: a shallow clone, 2026-11-14]
11. **`keycloak-radius-plugin` is Apache-2.0**, built against `<keycloak.version>26.5.4</keycloak.version>`, with its newest commit on 2026-02-25. The lab runs Keycloak 26.8.1 (`k8s_identity_version`). [measured: a shallow clone, 2026-11-14]
12. **lldap is GPL-3.0**, with its newest commit on 2026-09-26 and release tags up to v0.6.3. [measured: a shallow clone and `git ls-remote`, 2026-11-14]
13. **oauth2-proxy is MIT-licensed** [12]. In front of OPNsense it would add a gate and leave OPNsense's own login in place [inferred from finding 9: OPNsense's login takes local, LDAP or RADIUS accounts, not a header].

14. **Keycloak can import a base32 TOTP seed.** `OTPCredentialModel.getDecodedSecret()` reads `credentialData.secretEncoding` and, for `BASE32`, decodes the stored value; without it, the value's UTF-8 bytes are the key [13].
15. **Keycloak's built-in flows ask for a code from any user who has an OTP credential.** The browser flow's "Browser - Conditional 2FA" subflow runs `conditional-user-configured`, then `auth-otp-form`; the direct grant flow's "Direct Grant - Conditional OTP" runs `conditional-user-configured`, then `direct-grant-validate-otp` [14]. CI's realm test signs each admin in with the password alone (refused) and with a TOTP code from the imported seed (accepted), on the direct grant flow.

16. **Role `proxmox_sso` passed against stand-ins** (`.github/hosts-check/tests/test_proxmox_sso.sh`).
    - A stand-in `pveum` and `pvesh` kept state in a file, and a local HTTPS server served the discovery document.
    - A check run changed nothing.
    - The first run made both groups, their ACLs, the realm and the hosts line, and its proof passed. A second run changed nothing.
    - A new secret changed only the realm, and the secret never showed in the output.
    - A changed username claim stopped the run, and a wrong redirect failed the proof.
    - [measured, 2026-11-14]

## How the decision used it

- **Proxmox (rule 1).** Findings 1 and 2 are why the role makes `lab-admins-sso` and `lab-viewers-sso` itself and leaves group autocreate off. Finding 3 is why the role stops on a changed username claim and why realm lab sets `editUsernameAllowed: false`. Finding 4 is why the client allows exactly `https://<name>`.
- **Second factor (rule 6).** Findings 14 and 15 are why each admin's seed is imported as a base32 OTP credential and no custom flow is needed.
- **FOSS only (rule 4).** Findings 6 to 8 put Proxmox and Keycloak inside the owner's FOSS rule, and OPNsense's own OIDC outside it.
- **OPNsense's route (rule 5).** Findings 9 to 13 lead to LDAP; the directory is compared in its own record's evidence. The plugin is not open source (10). The RADIUS plugin trails the Keycloak version and would need a custom Keycloak image (11). The proxy is not a sign-in (13).

## Limits

- Nothing has run on the real host yet: no sign-in through Keycloak, no reach from the host to c1's Gateway on 443.
- The OPNsense LDAP route is read from the documentation, not tried. lldap's `memberOf` support is not checked here.
- Findings 14 and 15 were read at Keycloak's tag 26.4.0; the lab runs 26.8.1, which CI's realm test (Keycloak 26.8.1) exercises for the direct grant flow only. The browser flow's code prompt is proven only by the first real sign-in.
- WebAuthn and passkeys were not researched.
- The paid tiers come from the vendors' own pages as the FOSS audit read them; nothing was bought or tried.

## References

1. Proxmox VE wiki, "User Management", OpenID Connect and Groups mapping: <https://pve.proxmox.com/wiki/User_Management>
2. pve-access-control, `src/PVE/Auth/OpenId.pm`: <https://git.proxmox.com/?p=pve-access-control.git;a=blob_plain;f=src/PVE/Auth/OpenId.pm;hb=HEAD>
3. pve-manager, `www/manager6/window/LoginWindow.js`: <https://git.proxmox.com/?p=pve-manager.git;a=blob_plain;f=www/manager6/window/LoginWindow.js;hb=HEAD>
4. `pveum(1)`: <https://pve.proxmox.com/pve-docs/pveum.1.html>
5. Proxmox VE pricing: <https://www.proxmox.com/en/products/proxmox-virtual-environment/pricing>
6. Keycloak licence: <https://raw.githubusercontent.com/keycloak/keycloak/main/LICENSE.txt>
7. OPNsense docs, Deciso OIDC: <https://docs.opnsense.org/vendor/deciso/oidc.html>
8. OPNsense core licence: <https://raw.githubusercontent.com/opnsense/core/master/LICENSE>
9. OPNsense docs, LDAP how-to: <https://docs.opnsense.org/manual/how-tos/user-ldap.html>
10. OPNsense docs, RADIUS how-to: <https://docs.opnsense.org/manual/how-tos/user-radius.html>
11. OPNsense forum, "OpenID Connect SSO plugin": <https://forum.opnsense.org/index.php?topic=48884.0>
12. oauth2-proxy licence: <https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/master/LICENSE>
13. Keycloak 26.4.0, `server-spi/src/main/java/org/keycloak/models/credential/OTPCredentialModel.java`: <https://github.com/keycloak/keycloak/blob/26.4.0/server-spi/src/main/java/org/keycloak/models/credential/OTPCredentialModel.java>
14. Keycloak 26.4.0, `server-spi-private/src/main/java/org/keycloak/models/utils/DefaultAuthenticationFlows.java`: <https://github.com/keycloak/keycloak/blob/26.4.0/server-spi-private/src/main/java/org/keycloak/models/utils/DefaultAuthenticationFlows.java>
