---
title: Run hill90-app on c1, built at pod start from a pinned commit
status: proposed
date: 2026-11-28
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Run hill90-app on c1, built at pod start from a pinned commit

## What and why

The owner asked on 2026-11-28 for his earlier agent platform, `jonhill90/hill90-app` (public), to run on the lab cluster with sign-in, so he can click through its integrations and talk about them. It is expected to become the front end for the agent graph.

This change runs three pods in namespace `hill90-app`: a stock Postgres 16 (by digest, its own 2 GiB volume), the API and the UI. The API and the UI use the same route as the Central Hub app: a stock Node image by digest, an init container that fetches one full sha by git and builds it, the app container running the output. The commit is a value in `apps/hill90-app/values.yaml`; a new version is a reviewed pull request. The UI is reachable at `hill90.apps.c1.prod.<zone>` through the shared Gateway, from the lab and the tailnet only.

Sign-in is realm lab's client `hill90-app` (code flow). The API authorises on client roles, so the client has roles `admin` and `user`, mapped from groups `lab-admins` (both) and `lab-viewers` (`user`). The client secret and the realm's public names are copied into the namespace by the identity role, as for the Central Hub app.

## Out of scope

- The model router, knowledge manager, agent runtime, MCP gateway, CLI and Discord bridge. Pages that need them show errors until a later change adds them.
- An image and a registry for it (the way off, as for the Central Hub app).
- A shared database; the app's own Postgres is lab data only.

## Rules this keeps

- D-0027: Argo CD reads only this repository; the app's repository is read by a pod, and the commit is a full sha in values.
- Restricted pod security, no ServiceAccount token, ingress only through the Gateway to the UI, the API only from the UI, the database only from the API; egress to DNS, the app's own pods, Keycloak's Service and public addresses only.
- The database trusts connections because nothing but the API's pod can reach it (NetworkPolicy and Cilium policy).
- Every restart needs github.com and the npm registry.

## Acceptance criteria

### Automated

- [ ] `helm template` of the root chart, the gateway chart and `apps/hill90-app` renders, and the hosts check passes.

### Manual (what the owner checks)

- [ ] From the agent box, `c1-read -n hill90-app get pods` shows the database, API and UI Running, and both build logs end with `built <kind> <sha>`.
- [ ] `https://hill90.apps.c1.prod.<zone>/` sends an unsigned visitor to Keycloak's sign-in for client `hill90-app`, and after sign-in the app opens.

## Points to

- [Run hill90-app on c1](../runbooks/run-hill90-app-on-c1.md).

## Exit path

Build images of the commit in the app's CI, store them in the registry the owner picks, and run them by digest with no init container; or move the database to the shared one the platform chooses. Delete `apps/hill90-app/`, its entry in `root/values.yaml`, its route in the gateway app and the client in the identity role to take it off c1.

## Decision log

- 2026-11-28: built at pod start from a pinned commit, the same reason as the Central Hub app (no registry holds our image without an account or a browser step); UI, API and database only, to get a clickable, signed-in app quickly.
