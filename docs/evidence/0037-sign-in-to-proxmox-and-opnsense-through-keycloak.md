---
record: D-0037
batch: RB-0211 (2026-11-14), with the FOSS check RB-0208 of the same night for licences and paid tiers
researched: 2026-11-14 to 2026-11-17
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
17. **Proxmox keeps an OpenID Connect realm's client secret in `domains.cfg`.** `client-key` is a property of the OpenID realm type [2], and realms live in `/etc/pve/domains.cfg` [15]. All files in `/etc/pve` belong to root with group www-data, which "can read most files"; only files below `/etc/pve/priv/` are root's alone [15]. So the secret is readable by root and group www-data at rest, whatever way it is set.
18. **A second community OIDC plugin, `os-openid-connect`, is BSD-2-Clause** [16].
    - Its README at `v1.0.0-beta5` calls it "a pre-release package for OPNsense Community Edition 26.1 and 26.7", says "Every accepted external identity is durably bound by its exact issuer and subject to a local OPNsense account", and "Your normal local OPNsense login remains available as the recovery path" [16].
    - It is installed by `pkg add` of a release package, with a published checksum and a GitHub build attestation; it "does not add a package repository or enable automatic updates" [17]. Removing it "leaves its settings in `/conf/config.xml`" [17].
    - The repository names no paid edition [16].
    - Its releases are five betas, `v1.0.0-beta1` to `v1.0.0-beta5`, all marked pre-release, from one maintainer [16].
    - The forum thread announcing it, of 2026-08-26, asks for testers and security review; no OPNsense staff reply is in it [18].
    - [measured: the repository's LICENSE, README and releases page, 2026-11-17]
19. **OPNsense's plugin repository has no OIDC plugin.** Issue search in `opnsense/plugins` finds no OIDC plugin request or pull request, and the users page lists "OpenID connect (BE only)" next to LDAP and RADIUS [19]. [measured: GitHub issue search, 2026-11-17]
20. **The `v1.0.0-beta5` package matches its tag's source.** Tag `v1.0.0-beta5` is commit `e7f5f7b3ed0dc6d71463bd7cbc08d65cbc794e12`. The package `os-openid-connect-1.0.0.beta5.pkg` has SHA-256 `4b222b0de4ff9523cf3c86b23e984507e21c9a92a02bafe7cc01e406a41b117c`, the value on the release page, and its files under `usr/local/opnsense`, its two `sbin` scripts and its cron file are byte-identical to `src/opnsense` and `packaging/watch` at that commit. [measured: download, `sha256sum`, `diff -rq` and `cmp`, 2026-11-17]
21. **Its sign-in code, read at that commit** (paths under `src/opnsense/mvc/app/`):
    - ID tokens: only RS, PS, ES and EdDSA signatures, and only an algorithm the provider advertises (`library/OPNsense/OpenIDConnect/JwtVerifier.php` lines 36-41, 91-99); exact `iss`, `aud` holding the client id, `azp` when needed, `exp`, `iat`, `nbf` and `nonce` (lines 456-508).
    - The flow: code with PKCE `S256`, `state` compared in constant time, and each login transaction used once (`RelyingParty.php` 207-235, 1099-1119; `TransactionRegistry.php` 64-110).
    - The account: disabled and expired local accounts are refused, and root unless allowed (`library/OPNsense/Auth/OpenIDConnect.php` 2415-2443). The connector never checks a password (163-170).
    - Outbound: https only, no redirects, TLS verified (`HttpClient.php` 243, 346-349, 359).
    - [measured: a clone at the tag, 2026-11-17]
22. **It runs a root job every minute.** `openid-connect-refresh` fetches the provider's discovery document and keys when the cache is near stale. It also probes pushed authorization requests when its PAR mode is `auto`, which is the default (`OpenIDConnect.php` 1220, 4401-4403), and polls shared signals only when they are on (`packaging/watch/openid-connect-refresh` lines 72-172). A nightly `openid-connect-watch` hashes the core files the plugin hooks into and fetches the login page over loopback (`openid-connect-watch` lines 112, 145). [measured: the same clone]
23. **It plugs into core's own interfaces.** The connector implements core's `IAuthConnector` and the login button `SSOProviders\ISSOContainer`; it patches no core file (`OpenIDConnect.php` 53; `Auth/SSOProviders/OpenIDConnectContainer.php` 44). [measured: the same clone]

## How the decision used it

- **Proxmox (rule 1).** Findings 1 and 2 are why the role makes `lab-admins-sso` and `lab-viewers-sso` itself and leaves group autocreate off. Finding 3 is why the role stops on a changed username claim and why realm lab sets `editUsernameAllowed: false`. Finding 4 is why the client allows exactly `https://<name>`.
- **Second factor (rule 6).** Findings 14 and 15 are why each admin's seed is imported as a base32 OTP credential and no custom flow is needed.
- **FOSS only (rule 4).** Findings 6 to 8 put Proxmox and Keycloak inside the owner's FOSS rule, and OPNsense's own OIDC outside it.
- **OPNsense's route (rule 5).** Findings 18 to 23 lead to os-openid-connect: it is FOSS, on the community edition, and a sign-in at Keycloak, and its sign-in code and package hold up to a read. Findings 20 to 22 are why the package is pinned and checked, and why PAR mode is set to `disabled`. Findings 18 and 19 are why the record calls it a beta from one maintainer and proves it on a test OPNsense first. The other routes: Lachee's plugin is not open source (10). The RADIUS plugin trails the Keycloak version and would need a custom Keycloak image (11). LDAP needs a new directory (9, 12). The proxy is not a sign-in (13).

## Limits

- Nothing has run on the real host yet: no sign-in through Keycloak, no reach from the host to c1's Gateway on 443.
- The os-openid-connect route has not run anywhere yet: the test OPNsense proof is its first run. The code read covers the sign-in path and the root jobs, not the plugin's DPoP, PAR, shared-signals and setup code, which the record leaves off.
- The OPNsense LDAP and RADIUS routes are read from the documentation, not tried.
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
15. Proxmox VE wiki, "Proxmox Cluster File System (pmxcfs)", file access rights and files: <https://pve.proxmox.com/wiki/Proxmox_Cluster_File_System_(pmxcfs)>
16. os-openid-connect at `v1.0.0-beta5`, README and LICENSE: <https://github.com/jpawlowski/opnsense-openid-connect/tree/v1.0.0-beta5>; releases: <https://github.com/jpawlowski/opnsense-openid-connect/releases>
17. os-openid-connect, `docs/setup/install.md`: <https://github.com/jpawlowski/opnsense-openid-connect/blob/v1.0.0-beta5/docs/setup/install.md>
18. OPNsense forum, "Beta testers and reviewers wanted: OpenID Connect for OPNsense Community Edition": <https://forum.opnsense.org/index.php?topic=52815.0>
19. OPNsense docs, "Access / User Management": <https://docs.opnsense.org/manual/users.html>
