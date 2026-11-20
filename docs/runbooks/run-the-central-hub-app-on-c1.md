---
title: Run the Central Hub web app on c1
status: draft
kind: manual
trigger: when the app's commit changes, after a c1 rebuild, or when the app does not start
runner: an agent on the agent box, with the owner's say for any apply
outcome: the Central Hub web app answers on its Gateway names, built from the commit in values
needs: the agent box's read-only c1 account (c1-read); c1's Argo CD reading central-hub main
private-values: [k8s_gateway_zone]
files: [hosts/kubernetes/home/c1/apps/central-hub-app/, hosts/kubernetes/home/c1/root/values.yaml, hosts/kubernetes/home/c1/apps/gateway/values.yaml, docs/specs/2026-11-central-hub-app-on-c1.md]
last-tested: never, written with the change before its first sync
superseded-by:
---

# Run the Central Hub web app on c1

The app (public repository `jonhill90/central-hub-app`) runs as one pod in namespace `central-hub-app` (Argo CD app `central-hub-app`). An init container fetches the commit named in `apps/central-hub-app/values.yaml` (`source.commit`, a full sha) by git, checks it, runs `npm ci` and `npm run build`, and the app container runs the output. It has no image of its own; the [spec](../specs/2026-11-central-hub-app-on-c1.md) says why and names the way off. Names: `central-hub-app.apps.c1.prod.<zone>` and `central-hub-app.<zone>`.

## Steps

1. Pick the commit. In the app's repository, take a commit on `main` whose CI is green and read its full 40-character sha.
   expect: the sha, and green `app`, `docs` and `image` jobs on that commit.

2. Change `source.commit` in `hosts/kubernetes/home/c1/apps/central-hub-app/values.yaml` to it, by pull request to this repository.
   expect: the PR names the spec and passes the hosts check.

3. After the merge and Argo CD's sync, read the pod. On the agent box: `c1-read -n central-hub-app get pods`, then `c1-read -n central-hub-app logs deploy/central-hub-app -c build --tail=5`.
   expect: the pod is `Running 1/1`, and the log's last line is `built <the sha from step 1>`.

4. Open the app. `https://central-hub-app.apps.c1.prod.<zone>/` from the lab network or the tailnet.
   expect: the Hub with its menu; `/api/v1/catalog` answers 200.

## If it fails
- Init container `OOMKilled`: raise `resources.build.limits.memory` in values; the prod worker has about 7.9 GiB shared, so check node memory first (`c1-read top nodes`).
- Init container fails at `git fetch` or `npm ci`: the pod has no route to github.com or the npm registry; read the NetworkPolicy and the Cilium policy verdicts. The app stays on the old pod until the new one is ready (strategy Recreate stops the old one first, so it goes down).
- 503 from the Gateway with a Running pod: the Cilium ingress policy (`central-hub-app-ingress`) blocked it; check `c1-read -n central-hub-app get ciliumnetworkpolicy`.

## Take it off
Delete the app's folder here, its entry in `root/values.yaml` and its route in `apps/gateway/values.yaml`. Argo CD keeps no finalizer, so delete namespace `central-hub-app` with the owner's say (it holds no data).
