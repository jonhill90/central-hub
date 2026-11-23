---
title: Run the Central Hub web app on c1, built at pod start from a pinned commit
status: proposed
date: 2026-11-20
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Run the Central Hub web app on c1, built at pod start from a pinned commit

## What and why

The owner asked on 2026-11-20 for the Central Hub web app (repository `jonhill90/central-hub-app`, public) to be his front door to the platform, and wants a first version he can click through. The app has no image of its own and no registry exists for one (the app's decision 0004 keeps that choice open: Docker Hub needs an account, which D-0054 rule 3 rules out, and a first publish to GHCR is private until someone changes it in a browser).

This change runs it on c1 without an image. One pod uses a stock Node image pinned by digest (Docker Hub by digest, D-0054). An init container fetches one commit of the app's repository by its full sha with git, checks the sha, runs `npm ci` and `npm run build` into an emptyDir, and the app container runs the result. The commit is a value in `apps/central-hub-app/values.yaml`; a new version is a reviewed pull request that changes it. Reachable at `hub.apps.c1.prod.<zone>` (first written as `central-hub-app.apps.c1.prod.<zone>`; see the 2026-11-21 rename entry below) through the shared Gateway, from the lab and the tailnet only. The short alias `hub.<zone>` gets its own Unbound host override and tailnet split-DNS entry through the short-names runbook, not in this change.

The app reads no secret, writes nothing, holds no data and, until the 2026-11-21 entry below, had no sign-in; it shows catalog files from its own repository.

## Out of scope

- Sign-in (a separate Keycloak client, added through c1-ansible's clients list).
- An image and a registry for it. This is the way off the build-at-start design (see Exit path).
- Any write path, data or secret in the app.

## Rules this keeps

- D-0027: Argo CD still reads only this repository; the app's repository is read by a pod, not by Argo CD, and the commit is a full sha in values (Activation gate items 3 and 6: no token, no image automation).
- Restricted pod security, no ServiceAccount token, egress to DNS and public addresses only (as `notebook-runner`), ingress only from the Gateway.
- Every restart needs github.com and the npm registry. Until a registry holds the image, an outage of either keeps a restarted pod from starting; the running pod is unaffected.

## Acceptance criteria

### Automated

- [ ] `helm template` of the root chart and `apps/central-hub-app` renders, and the hosts check (kubeconform, lint) passes.
- [ ] The app repository's CI at the pinned commit is green on its `app` and `image` jobs (that commit is on its `main`).

### Manual (what the owner checks)

- [ ] From the agent box, `c1-read -n central-hub-app get pods` shows the pod Running, and the `build` init container's log ends with `built <the pinned commit>`.
- [ ] `https://hub.apps.c1.prod.<zone>/` shows the Hub and its menu from the lab network, and `/api/v1/catalog` answers 200.
- [ ] The pod is Ready (its readiness probe is `GET /api/v1/catalog` inside the pod), and the owner opens the name above and sees the Hub. The gateway `name-check` does not list this app: the desktop role's trust check must list the same apps, and it checks short names that do not resolve yet.

## Points to

- [Run the Central Hub web app on c1](../runbooks/run-the-central-hub-app-on-c1.md): how it works, how to bump the commit, how to take it off.
- The app's spec 0004 and decision 0004 (public repository `jonhill90/central-hub-app`).

## Exit path

Build an image of the commit in the app's CI, store it in a registry chosen by the owner (a self-hosted Zot is the way D-0054 names), and change the chart to run that image by digest with no init container. Delete `apps/central-hub-app/`, its entry in `root/values.yaml` and its route in the gateway app to take it off c1; nothing else depends on it.

## Decision log

- 2026-11-20: built at pod start from a pinned commit, because no registry can hold our image today without an account or a browser step. The reviewer cleared the route with six conditions: fetch by full sha with git, `npm ci` with the lockfile, build in an init container with memory limits, say that every restart needs GitHub and npm and name the registry as the way off, copy notebook-runner's egress policy with ingress only from the Gateway, and leave sign-in to a separate Keycloak client change.
- 2026-11-21: sign-in through Keycloak, as the reviewer's last condition asked, in a separate change. The app gets the code flow (its spec 0007, decision 0005); realm lab gets client `central-hub-app` in `realm.yaml.j2`, so every rebuild's identity stage makes it; the role copies the client secret to `central-hub-app/central-hub-app-sso` and the realm address and public origins to `central-hub-app/central-hub-app-oidc`, which the pod mounts as optional files; the chart allows egress to Keycloak's Service, probes `/api/v1/health` (up while sign-in is not yet configured, because the rebuild waits for every app to be healthy before the identity stage), and the login probe checks the client. Runbook: `docs/runbooks/sign-in-to-the-central-hub-app-with-keycloak.md`.
- 2026-11-21: the owner named the app `hub`. Its route key is now `hub`, so it answers on `hub.<zone>` and `hub.apps.c1.prod.<zone>`, not on `central-hub-app.<zone>`; the Unbound override list, the tailnet split-DNS name and the realm client's redirect hosts follow (`k8s_identity_central_hub_app_host_label`). The Argo CD app, namespace, Service and Keycloak client id keep the name `central-hub-app`. The rename was applied on 2026-11-22 (commit 67d83032): `hub.<zone>` answers `200` from the agent box, and the old HTTPRoute is pruned. The old Unbound override `central-hub-app.<zone>` is removed, once the OPNsense apply has run, by the role's list `opnsense_lab_short_app_names_retired`.
