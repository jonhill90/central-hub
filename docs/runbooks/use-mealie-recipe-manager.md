---
title: Deploy Mealie and sign in to it through the lab's Keycloak
status: draft
kind: automated
trigger: Mealie is added or changed on c1 (chart `hosts/kubernetes/home/c1/apps/mealie`, the `mealie` client in realm lab), and as part of every c1 rebuild
runner: an agent lane on the agent box (steps 2 to 4); Argo CD does the deploy; the rebuild's identity stage does steps 2 and 3 on a rebuild
outcome: https://mealie.<zone>/ sends a visitor to Keycloak's sign-in page for client `mealie`; after sign-in with a lab account Mealie opens, and an account in group `lab-admins` is a Mealie admin
needs: Argo CD app `mealie` Synced, realm lab with client `mealie`, Secret `mealie/mealie-sso` (key `client-secret`), the lab CA's public root in Secret `mealie/mealie-lab-ca`
private-values: [k8s_identity_zone, MEALIE_CLIENT_SECRET]
files: [hosts/kubernetes/home/c1/apps/mealie/, hosts/kubernetes/home/c1/apps/mealie/files/admin-guard.sh, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_identity/templates/realm.yaml.j2, hosts/ansible/roles/k8s_identity/tasks/secrets.yml, hosts/ansible/roles/agent_box/files/c1-ansible.sh]
last-tested: 2026-11-23, the Keycloak sign-in by the agent box's signin-check (step 6)
superseded-by:
---

# Deploy Mealie and sign in to it through the lab's Keycloak

Mealie is a self-hosted recipe manager (owner ask 38). It runs as one pod with its SQLite database on a 5 Gi volume (`/app/data`), pinned to v3.30.0 by digest (STD-0003: v3.31.0 was less than 14 days old when this was written). It uses Mealie's own OpenID Connect, so there is no plugin: the chart sets `OIDC_*` variables, and everything lab-specific (the zone, the client secret) arrives from the root Application and the identity role.

| What | Where it comes from |
|---|---|
| The pod, volume, Service and route (`mealie.<zone>`, `mealie.apps.c1.prod.<zone>`) | Argo CD app `mealie` (`root/values.yaml`, chart `apps/mealie`) |
| The client `mealie` (confidential, code flow, redirect `/login` on both names) | `realm.yaml.j2`, so it is in every realm import |
| Its secret, key `MEALIE_CLIENT_SECRET` | the values file (`identity.env`), or `c1/identity` in OpenBao; copied to `mealie/mealie-sso`, key `client-secret`; the Deployment restarts when it changes |
| The lab CA's public root, so Mealie trusts Keycloak's certificate | a cert-manager Certificate on `lab-ca` (`templates/lab-ca.yaml`); an init container builds a bundle for `OIDC_TLS_CACERTFILE` |
| Who is an admin | realm group `lab-admins` (`OIDC_ADMIN_GROUP`); other realm accounts sign up as ordinary users |

Mealie makes a first account on first start, with an e-mail and password the project publishes. Its API accepts that password whatever `ALLOW_PASSWORD_LOGIN` says (the setting only hides the form), so the chart never lets that account be reachable: the route is made only after a guard Job has replaced the password with a generated one and proved the published one is refused (see "The first account" below).

## Steps

0. On prod, where the apps' secrets are in OpenBao, put the first account's password there once, before the first sync, with the value on stdin and never printed: on the agent box, `openssl rand -hex 16 | tr -d '\n' | secrets-store-prod put c1/mealie-admin password`. On a cluster with the store off the password is generated inside the cluster and needs no step.
   expect: a `put` line for `c1/mealie-admin`; `c1-read get externalsecret -n mealie mealie-admin` shows `SecretSynced`.
1. On a rebuild, nothing to do: the `apps` stage makes the namespace, and the `identity` stage imports the realm with the client and makes the Secret.
2. On a live c1, from the agent box once the box has installed this change (`c1-ansible.sh` lists `mealie` in its clients): `secrets-store-prod put-apps` (OpenBao must hold `MEALIE_CLIENT_SECRET`), then `c1-ansible check clients` and `c1-ansible apply clients <clearance id>` (tags `secrets,clients`, no realm replace).
   why: a realm replace ends every open sign-in; the clients tag adds the one client in place.
   expect: `client mealie: ok`, `failed=0`; `c1-read get secrets -n mealie` lists `mealie-sso`.
3. The Deployment restarts by itself when the Secret first appears. `c1-read get pods -n mealie` shows `1/1 Running`.
4. Prove it without a password. Read the guard's proof first: `c1-read logs -n mealie job/<newest mealie-admin-guard job>` ends with `mealie-admin: PASS the published sign-in is refused and the generated one works; first-login banner off`. Then: `curl -sI https://mealie.<zone>/` answers 200 (the single-page app); `curl -sI https://mealie.<zone>/api/app/about` is 200; Mealie's `/api/app/about` says `oidcReady`/`enableOidc` true (`curl -s .../api/app/about`); and the Keycloak authorize URL for client `mealie` with redirect `https://mealie.<zone>/login` answers 200 (the sign-in page), not "Invalid parameter: redirect_uri".
   expect: all of the above.
5. A typed sign-in is the owner's: open the address, sign in as a lab account, and Mealie opens.
6. Prove the Keycloak sign-in from the agent box: the box's `signin-check` (its browser part) signs the lab test user in through Keycloak and reads `/api/users/self`; `signin-check log` shows the latest run. `expect`: the Mealie line says `passed: /api/users/self answers HTTP 200 for the test user`, ending at `mealie.<zone>/g/home`. Measured 2026-11-23, 06:23 UTC: that line passed, with 8 passed and 0 failed among the apps that have a Keycloak sign-in.

## The first account

- Sync waves (`templates/`): the Deployment and Service are wave 0, the guard Job (an Argo CD Sync hook, `files/admin-guard.sh`) is wave 1, and both HTTPRoutes are wave 2. Argo CD waits for each wave, so on a first sync the names answer only after the guard passed; a failing guard fails the sync and the route is never made.
- The guard signs in with the published e-mail and password. If that works it changes the password to the one in Secret `mealie/mealie-admin` (key `password`), then moves the account off the published e-mail to `adminGuard.adminEmail` (a reserved `.invalid` name), because Mealie shows a "first login" banner with the published pair for as long as any account has that e-mail (`isFirstLogin` in `/api/app/about/startup-info`). It then proves the published sign-in is refused and the generated one works, and reports whether the banner is off. A failed e-mail change is a warning, not a failed sync. It reads the password from a file and prints none.
- A CronJob runs the same script every 10 minutes, for the case that the pod's volume is replaced by an empty one while the route stands; its newest Job log must say PASS and end with `first-login banner off`; `curl -s https://mealie.<zone>/api/app/about/startup-info` then shows `isFirstLogin` false, because no account has the published e-mail any more.
- The account is kept: sign-in goes through Keycloak, and its generated password is in OpenBao (`c1/mealie-admin`), not anywhere in git.

## If it fails

- **The sync stops at the guard (wave 1):** `c1-read logs -n mealie job/mealie-admin-guard`. "did not answer" is the pod not starting; "FAIL the generated password is refused" means the account holds a password this chart did not set (the volume was used before): fix it in Mealie as admin, or delete the volume's data on a fresh app.
- **Login page shows only the password form:** Mealie did not read `OIDC_CLIENT_SECRET` (the Secret was missing at start). `c1-read get secret -n mealie mealie-sso`, then restart the Deployment.
- **Keycloak says "Invalid parameter: redirect_uri":** Mealie built an `http` redirect (`FORWARDED_ALLOW_IPS` not read) or the host is not one the client lists.
- **`SSLError` / "unable to get local issuer" in the pod's log:** `mealie-lab-ca` is missing; `c1-read get certificate -n mealie`.
- **The way back:** set `sso.enabled: false` in the chart values and sync; Mealie then has only its own login.

## Related

- [Set up sign-in for lab apps on c1](set-up-lab-sign-in.md)
- [Turn on sign-in to the Central Hub app](sign-in-to-the-central-hub-app-with-keycloak.md), the same client mechanism
- Mealie's OpenID Connect page: <https://docs.mealie.io/documentation/getting-started/authentication/oidc-v2/>
