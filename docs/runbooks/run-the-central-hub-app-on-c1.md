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

The app (public repository `jonhill90/central-hub-app`) runs as one pod in namespace `central-hub-app` (Argo CD app `central-hub-app`). An init container fetches the commit named in `apps/central-hub-app/values.yaml` (`source.commit`, a full sha) by git, checks it, runs `npm ci` and `npm run build`, and the app container runs the output. It has no image of its own; the [spec](../specs/2026-11-central-hub-app-on-c1.md) says why and names the way off. Names: `hub.apps.c1.prod.<zone>` and the short alias `hub.<zone>` (the owner's name for it; the Gateway route key is `hub`). The short name resolves for people through its Unbound host override and tailnet split-DNS entry ([set-up-short-app-names.md](set-up-short-app-names.md)).

## Steps

1. Pick the commit. In the app's repository, take a commit on `main` whose CI is green and read its full 40-character sha.
   expect: the sha, and green `app`, `docs` and `image` jobs on that commit.

2. Change `source.commit` in `hosts/kubernetes/home/c1/apps/central-hub-app/values.yaml` to it, by pull request to this repository.
   expect: the PR names the spec and passes the hosts check.

3. After the merge and Argo CD's sync, read the pod. On the agent box: `c1-read -n central-hub-app get pods`, then `c1-read -n central-hub-app logs deploy/central-hub-app -c build --tail=5`.
   expect: the pod is `Running 1/1`, and the log's last line is `built <the sha from step 1>`.

4. Open the app. `https://hub.<zone>/` (or the long name `https://hub.apps.c1.prod.<zone>/`) from the lab network or the tailnet. The Gateway route key is `hub` (`apps/gateway/values.yaml`); the Argo CD app, the namespace and the Service stay `central-hub-app`.
   expect: the Hub with its menu; `/api/v1/catalog` answers 200.

## The notebook and the Proxmox snapshot (the feed)

With sign-in on (`auth.mode: oidc`), the app also shows the agents' notebook at `/notebook` and a Proxmox snapshot at `/systems`. Both are private, so the chart renders them only with sign-in on, and the app itself answers "closed" while `HUB_AUTH` is not `oidc`. How the data gets in:

1. The agent box's timer `hub-feed.timer` runs `ci-runner.sh hub-feed` every 30 minutes as the `keys` user. It puts two values into prod's store at `c1/hub-feed`: `notebook-token`, a one-hour GitHub App token with `contents: read` on the notebook repository only, and `proxmox-json`, a trimmed `/cluster/resources` read with the lab token `proxmox-lab.env` (status, cpu, memory, disk, uptime). Proxmox lists only what a token may audit: the dev token sees just the dev rebuild VMs, the lab token every guest except VM 258 and the desktop VM, which it has no access to on purpose; the dev token is the fallback when the box has no lab token (for example during the 30-day renewal): the run then prints a warning to stderr and the snapshot's `source` reads `proxmox-dev` instead of `proxmox-lab`, so a short list can be told from a real one. Neither value is printed or passed as an argument.
2. Two ExternalSecrets copy them every minute, one each, so a failure of one never holds back the other: `central-hub-app-feed-token` (the notebook token, seen only by the notebook containers) and `central-hub-app-feed-app` (the snapshot, the only part the app container mounts). The box writes both with `secrets-store-prod put-short`, OpenBao only: a value that lives an hour and is made again by the timer is not kept in the SOPS copy.
3. In the pod, an init container clones the notebook with the token and a sidecar pulls it every 300 seconds (`feed.syncSeconds`). The token is mounted only into those two containers; the app container mounts the snapshot file and the notebook folder and nothing else.

Check it from the box: `sudo -n -u keys /usr/local/libexec/agent-box/ci-runner.sh hub-feed` prints the two `ci-runner: ...is in prod's store` lines; `c1-read logs -n central-hub-app deploy/central-hub-app -c notebook-sync` shows `notebook-sync: at <sha>`; after sign-in, `/notebook` shows a note count and `/systems` shows the snapshot's time. The way back: set `feed.enabled: false` in the chart values.

Not proven when this was written: that the agents' Proxmox token sees nodes (its permissions are on the dev and ci pools, so `/cluster/resources` may list only the guests it can see), and the first live run of the timer.

## If it fails

- Init container `OOMKilled`: raise `resources.build.limits.memory` in values; the prod worker has about 7.9 GiB shared, so check node memory first (`c1-read top nodes`).
- Init container fails at `git fetch` or `npm ci`: the pod has no route to github.com or the npm registry; read the NetworkPolicy and the Cilium policy verdicts. Strategy Recreate stops the old pod first, so the app is down until the new pod's build has finished and it is ready.
- 503 from the Gateway with a Running pod: the Cilium ingress policy (`central-hub-app-ingress`) blocked it; check `c1-read -n central-hub-app get ciliumnetworkpolicy`.

## Take it off

Delete the app's folder here, its entry in `root/values.yaml` and its route in `apps/gateway/values.yaml`. Argo CD keeps no finalizer, so delete namespace `central-hub-app` with the owner's say (it holds no data).
