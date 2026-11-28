---
title: Run hill90-app on c1
status: draft
kind: manual
trigger: when the app's commit changes, after a c1 rebuild, or when the app does not start
runner: an agent on the agent box, with the owner's say for any apply
outcome: the hill90-app UI answers on its Gateway name, signs in through the lab's Keycloak, and talks to its API and database
needs: the agent box's read-only c1 account (c1-read); c1's Argo CD reading central-hub main; realm lab with client hill90-app
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/apps/hill90-app/, hosts/kubernetes/home/c1/root/values.yaml, hosts/kubernetes/home/c1/apps/gateway/values.yaml, hosts/ansible/roles/k8s_identity/]
last-tested: never, written with the change before its first sync
superseded-by:
---

# Run hill90-app on c1

hill90-app (public repository `jonhill90/hill90-app`) is the owner's earlier agent platform. On c1 it runs three pods in namespace `hill90-app` (Argo CD app `hill90-app`): a Postgres 16 for its own data, the API, and the UI. Each of the API and the UI has an init container that fetches the commit named in `apps/hill90-app/values.yaml` (`source.commit`, a full sha) by git, runs `npm ci` and the build, and the app container runs the output; there is no image of its own, the same way as the Central Hub app ([run-the-central-hub-app-on-c1.md](run-the-central-hub-app-on-c1.md)). Name: `hill90.apps.c1.prod.<zone>` (gateway route key `hill90`).

What runs and what does not: the UI, the API and Postgres. The model router, the knowledge manager, the agent runtime, the MCP gateway, the CLI and the Discord bridge are not on c1, so pages that need them (chat, agents that start containers, knowledge search) show errors. Not tested when this was written.

Sign-in: realm lab's client `hill90-app` (confidential). The API authorises on client roles, so the client has roles `admin` and `user`, and group `lab-admins` gets both and `lab-viewers` gets `user`. The client secret reaches the namespace as Secret `hill90-app-sso` and the realm address and origin as `hill90-app-oidc` (the identity role, as for the Central Hub app, [sign-in-to-the-central-hub-app-with-keycloak.md](sign-in-to-the-central-hub-app-with-keycloak.md)). Until they exist a stand-in answers 503 and `/api/health` 200.

## Steps

1. Add the client to the live realm without ending any session, from the agent box: `c1-ansible check clients`, then `c1-ansible apply clients <clearance id>`. The `secrets` tag adds `HILL90_APP_CLIENT_SECRET` to the box's `identity.env` if it is missing; then run `secrets-store put-apps`.
   expect: `client hill90-app: ok` and `failed=0`; Secrets `hill90-app-sso` and `hill90-app-oidc` exist (`c1-read get externalsecrets -n hill90-app`).
2. After Argo CD syncs, read the pods: `c1-read -n hill90-app get pods`, then `c1-read -n hill90-app logs deploy/hill90-app-api -c build --tail=3` and the same for `hill90-app-ui`.
   expect: `hill90-app-db-0`, the API and the UI `Running 1/1`; the build logs end with `built api <sha>` and `built ui <sha>`.
3. Open `https://hill90.apps.c1.prod.<zone>/` from the lab network or the tailnet and sign in with a lab account.
   expect: the app's dashboard; `curl -s https://hill90.apps.c1.prod.<zone>/api/health` answers 200.

## If it fails

- Build init container `OOMKilled`: raise `resources.build.limits.memory` in values; the worker has about 5 GiB free, check `c1-read top nodes`.
- API crash loop: `c1-read -n hill90-app logs deploy/hill90-app-api --tail=30`; a `[startup]` line names the cause (database, migrations).
- Keycloak says "Invalid parameter: redirect_uri": the client is not in the realm yet; run step 1.
- Signed in, API answers 403: the account is in no group, so the token has no client role.

## Take it off

Delete `apps/hill90-app/`, its entry in `root/values.yaml` and its route in `apps/gateway/values.yaml`; delete namespace `hill90-app` with the owner's say (it holds the Postgres volume, lab data only).
