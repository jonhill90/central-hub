---
title: Deploy Mealie and sign in to it through the lab's Keycloak
status: draft
kind: automated
trigger: Mealie is added or changed on c1 (chart `hosts/kubernetes/home/c1/apps/mealie`, the `mealie` client in realm lab), and as part of every c1 rebuild
runner: an agent lane on the agent box (steps 2 to 4); Argo CD does the deploy; the rebuild's identity stage does steps 2 and 3 on a rebuild
outcome: https://mealie.<zone>/ sends a visitor to Keycloak's sign-in page for client `mealie`; after sign-in with a lab account Mealie opens, and an account in group `lab-admins` is a Mealie admin
needs: Argo CD app `mealie` Synced, realm lab with client `mealie`, Secret `mealie/mealie-sso` (key `client-secret`), the lab CA's public root in Secret `mealie/mealie-lab-ca`
private-values: [k8s_identity_zone, MEALIE_CLIENT_SECRET]
files: [hosts/kubernetes/home/c1/apps/mealie/, hosts/kubernetes/home/c1/root/values.yaml, hosts/ansible/roles/k8s_identity/templates/realm.yaml.j2, hosts/ansible/roles/k8s_identity/tasks/secrets.yml, hosts/ansible/roles/agent_box/files/c1-ansible.sh]
last-tested: not yet; written with the pull request that adds it
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

Mealie's own password login stays (its default account is `changeme@example.com`); `OIDC_AUTO_REDIRECT` sends visitors to Keycloak, and the login page is still at `/login?direct=1`. Change that default account's password after the first start (step 5).

## Steps

1. On a rebuild, nothing to do: the `apps` stage makes the namespace, and the `identity` stage imports the realm with the client and makes the Secret.
2. On a live c1, from the agent box once the box has installed this change (`c1-ansible.sh` lists `mealie` in its clients): `secrets-store-prod put-apps` (OpenBao must hold `MEALIE_CLIENT_SECRET`), then `c1-ansible check clients` and `c1-ansible apply clients <clearance id>` (tags `secrets,clients`, no realm replace).
   why: a realm replace ends every open sign-in; the clients tag adds the one client in place.
   expect: `client mealie: ok`, `failed=0`; `c1-read get secrets -n mealie` lists `mealie-sso`.
3. The Deployment restarts by itself when the Secret first appears. `c1-read get pods -n mealie` shows `1/1 Running`.
4. Prove it without a password: `curl -sI https://mealie.<zone>/` answers 200 (the single-page app); `curl -sI https://mealie.<zone>/api/app/about` is 200; Mealie's `/api/app/about` says `oidcReady`/`enableOidc` true (`curl -s .../api/app/about`); and the Keycloak authorize URL for client `mealie` with redirect `https://mealie.<zone>/login` answers 200 (the sign-in page), not "Invalid parameter: redirect_uri".
   expect: all of the above.
5. A typed sign-in is the owner's: open the address, sign in as a lab account, and Mealie opens. Then, as that admin, change the password of Mealie's default account (Settings, Users).

## If it fails

- **Login page shows only the password form:** Mealie did not read `OIDC_CLIENT_SECRET` (the Secret was missing at start). `c1-read get secret -n mealie mealie-sso`, then restart the Deployment.
- **Keycloak says "Invalid parameter: redirect_uri":** Mealie built an `http` redirect (`FORWARDED_ALLOW_IPS` not read) or the host is not one the client lists.
- **`SSLError` / "unable to get local issuer" in the pod's log:** `mealie-lab-ca` is missing; `c1-read get certificate -n mealie`.
- **The way back:** set `sso.enabled: false` in the chart values and sync; Mealie then has only its own login.

## Related

- [Set up sign-in for lab apps on c1](set-up-lab-sign-in.md)
- [Turn on sign-in to the Central Hub app](sign-in-to-the-central-hub-app-with-keycloak.md), the same client mechanism
- Mealie's OpenID Connect page: <https://docs.mealie.io/documentation/getting-started/authentication/oidc-v2/>
