---
title: Turn on sign-in to the Central Hub app through the lab's Keycloak
status: draft
kind: automated
trigger: after a change to the Central Hub app's sign-in (the app's spec 0007, the chart's `auth` values, or the `central-hub-app` client in realm lab), and as part of every c1 rebuild
runner: an agent lane; the rebuild's identity stage does the realm and Secret part, the app's pod does the rest on its own
outcome: opening the app's address without a session goes to Keycloak's sign-in page for client `central-hub-app`; after sign-in the app opens; the data API answers 401 without a session
needs: the app deployed on c1 (Argo CD app `central-hub-app`, built from a commit that holds the sign-in code), realm lab with the client, Secrets `central-hub-app-sso` and `central-hub-app-oidc` in namespace `central-hub-app`
private-values: [k8s_identity_zone, CENTRAL_HUB_APP_CLIENT_SECRET]
files: [hosts/ansible/roles/k8s_identity/templates/realm.yaml.j2, hosts/ansible/roles/k8s_identity/tasks/secrets.yml, hosts/kubernetes/home/c1/apps/central-hub-app/, hosts/kubernetes/home/c1/apps/login-probe/values.yaml]
last-tested: not yet; written with the pull request that adds it
superseded-by:
---

# Turn on sign-in to the Central Hub app through the lab's Keycloak

The app (`jonhill90/central-hub-app`) signs visitors in with the authorization code flow and PKCE, and keeps its session in a signed cookie (its spec 0007). Nothing about this lab is in the app's repository: three files mounted into the pod carry it.

| What | Where it comes from |
|---|---|
| The client `central-hub-app` (confidential, PKCE S256, redirect `https://<app host>/auth/callback` for the short and the long name) | `realm.yaml.j2`, so it is in every realm import |
| Its secret, key `CENTRAL_HUB_APP_CLIENT_SECRET` | the values file (`identity.env`), or `c1/identity` in OpenBao; copied to `central-hub-app/central-hub-app-sso`, key `client-secret` |
| The realm's address and the app's public origins | `central-hub-app/central-hub-app-oidc`, keys `issuer` and `public-urls`, made by the same role from the zone |
| Which accounts may open it | `HUB_OIDC_ALLOWED_GROUPS` in the chart: `lab-admins` and `lab-viewers` |

The pod mounts the two Secrets as one folder (optional, so the pod starts before they exist) and reads the files on each request. Until they exist the app is up but answers 503 on everything except `/api/v1/health`, which says `signIn: not configured`. The rebuild waits for every app to be healthy before it makes the Secrets, so the probe must stay green; that is why.

## Before you start

- The Central Hub app runs from a commit that holds the sign-in code: `source.commit` in `hosts/kubernetes/home/c1/apps/central-hub-app/values.yaml` is at or after the merge of the app's spec 0007.
  why: the chart sets `HUB_AUTH=oidc` and probes `/api/v1/health`; older code has no such path.

## Steps

1. On a rebuild, nothing to do: the `identity` stage (`hosts/rebuild-k8s.sh`) imports the realm with the client and makes both Secrets, after the `apps` stage has made the namespace.
2. On a live c1 that is not being rebuilt, add the client without ending any session, from the controller: `ansible-playbook -i inventories/home/ playbooks/k8s-identity.yml --tags secrets,clients -e '{"k8s_identity_ensure_clients": ["central-hub-app"]}'` ([set-up-lab-sign-in.md](set-up-lab-sign-in.md)). The agent box's `c1-ansible clients` names only `proxmox` (`hosts/ansible/roles/agent_box/files/c1-ansible.sh`); naming this client there is a box-limit change with its own pull request and install ([set-up-the-agent-box.md](set-up-the-agent-box.md#change-c1-from-the-box)), not part of this one.
   why: a realm replace (tag `keycloak`) deletes and imports realm `lab`, which ends every open sign-in.
   expect: the run prints `client central-hub-app: ok` and ends with `failed=0`; the two Secrets exist (`c1-read get secrets -n central-hub-app`).
3. Prove it without a password:
   - Keycloak knows the client: the login-probe Job's newest log has `PASS: keycloak sign-in page for client central-hub-app and its redirect (HTTP 200)` (`c1-read logs -n login-probe job/<newest>`).
   - The app asks for sign-in: `curl -sI https://central-hub-app.<zone>/` answers 307 to `/auth/login`, and `curl -sI https://central-hub-app.<zone>/auth/login` answers 307 to `https://sso.<zone>/realms/lab/protocol/openid-connect/auth?...client_id=central-hub-app...code_challenge_method=S256`; `curl -s -o /dev/null -w '%{http_code}' https://central-hub-app.<zone>/api/v1/catalog` is 401; `/api/v1/health` is 200.
   expect: all of the above.
4. A typed sign-in is the owner's: open the app, sign in with the lab account and its code, and the home page opens.
   expect: the home page; closing the browser's cookies for the app sends it back to sign-in.

## If it fails

- **503 on every page:** the Secrets are missing or malformed. `c1-read get secrets -n central-hub-app` and `curl -s https://<app>/api/v1/health` (`signIn: not configured`); run step 2.
- **Keycloak says "Invalid parameter: redirect_uri":** the host in the address bar is not one the client lists. The short and long names are listed; another name needs `k8s_identity_central_hub_app_hosts` extended.
- **"the identity provider's keys are not available":** the pod cannot reach `sso-service.identity.svc:8080`; the chart's egress rule for the identity namespace is missing.
- **Signed in, "not in a group that may open the app":** the account has no group in `HUB_OIDC_ALLOWED_GROUPS`.
- **The way back:** set `auth.mode: "off"` in the chart values (the app is then open again) and sync, or revert the app's pin.

## Afterwards

- Set `last-tested` here, with the date, who ran it and on what.

## Related

- [Set up sign-in for lab apps on c1](set-up-lab-sign-in.md)
- The app's spec: `docs/specs/0007-sign-in-with-openid-connect.md` in `jonhill90/central-hub-app`.
