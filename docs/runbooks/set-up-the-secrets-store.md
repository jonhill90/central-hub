---
title: Set up the lab's secrets store (OpenBao) on dev and prod
status: draft
kind: automated
trigger: once per env, after D-0058; again after a rebuild of the cluster
runner: "the dev rebuild on the agent box (`rebuild up`), and an agent session through the `secrets-store` wrapper, once the box's path to the store is set"
outcome: OpenBao 2.7.2 runs in namespace openbao in dev's cluster and in prod's, starts and unseals with no person from its seal key on one node, initializes itself with audit, KV v2, AppRole and Kubernetes logins, takes an hourly Raft snapshot, and serves External Secrets through its Kubernetes login
needs: the agent box with the agent_box role applied; the dev cluster; the private inventory values listed below
private-values: [seal-node, box-cidr, store-host, seal-key, admin-role-id, admin-secret-id, sops-copies]
files: [hosts/kubernetes/home/c1/apps/openbao/, hosts/kubernetes/home/c1/apps/openbao-store/, hosts/kubernetes/home/c1/apps/openbao-measure/, hosts/ansible/playbooks/k8s-openbao-measure.yml, hosts/ansible/playbooks/k8s-openbao-handover.yml, .github/hosts-check/tests/test_openbao_handover.sh, hosts/kubernetes/home/c1/apps/secret-store/, hosts/kubernetes/home/c1/root/, hosts/ansible/roles/k8s_gitops/, hosts/kubernetes/home/c1/apps/alerts/, hosts/kubernetes/home/c1/apps/monitoring-extras/, hosts/kubernetes/home/c1/apps/share-pod/, hosts/ansible/roles/agent_box/files/secrets-store.sh, .github/hosts-check/tests/test_secrets_store_wrapper.sh, .github/hosts-check/tests/test_rebuild_box_inventory.sh, hosts/ansible/roles/agent_box/files/secrets-store-kv.sh, .github/hosts-check/tests/test_secrets_store_kv.sh, hosts/ansible/roles/agent_box/templates/secrets-store-compare.service.j2, hosts/ansible/roles/agent_box/templates/secrets-store-compare.timer.j2, hosts/ansible/roles/agent_box/files/secrets-store-offbox.sh, hosts/ansible/roles/agent_box/files/secrets-store-restore.sh, .github/hosts-check/tests/test_secrets_store_restore.sh, hosts/ansible/roles/agent_box/files/secrets-store-snapshots.sh, .github/hosts-check/tests/test_secrets_store_snapshots.sh, hosts/ansible/roles/agent_box/tasks/secrets_store_offbox.yml, .github/hosts-check/tests/test_secrets_store_offbox.sh, hosts/ansible/playbooks/k8s-openbao-auth.yml]
last-tested: 2026-11-18 on prod's c1, the store only. Central-hub 6d59d49 started openbao-0 (1/1, unsealed at 02:15:58 UTC) and the ClusterSecretStore openbao was Ready at 02:20 UTC, checked from the agent box. Not yet run on dev. The dev rebuilds 20261117T043328Z and 20261117T053037Z (central-hub 69edf9b) on the agent box ran without the store, as neither stage list had openbao-seal or openbao-measure. The box's scripts and the hand-over are checked only by CI's stand-in tests (test_openbao_handover.sh and the five test_secrets_store_*.sh files)
superseded-by:
---

# Set up the lab's secrets store (OpenBao) on dev and prod

**Status:** draft. The store runs in prod's c1 since 2026-11-18 (below); the dev steps, the snapshots and the box's calls have not run. Written from the code and the OpenBao 2.7.2 docs; an "expect" below is what the docs say unless [What has run](#what-has-run) says it was seen. [What has run](#what-has-run) lists what has been run so far, and where. The records are [D-0038](../decisions/README.md) and [D-0058](../decisions/README.md), which moves the store into the cluster.

**Inside the cluster ([D-0058](../decisions/README.md)).** OpenBao runs inside the cluster from its own Helm chart, dev's cluster first, not on a VM of its own. No store VM was ever built, and its code is gone. [Inside the cluster](#inside-the-cluster-d-0058-dev-first) below is code only, not yet run. The box's calls to the store are listed after it. They are code only too, and they need the box's path to the store, which comes after the measurement below.

## What has run

| Part | On dev | Checked so far |
|---|---|---|
| The store in the cluster (stages `openbao-seal`, `openbao-measure`, `openbao-handover`) | No. Two dev rebuilds ran on 2026-11-17, `20261117T043328Z` (started 04:33 UTC) and `20261117T053037Z` (started 05:30 UTC, central-hub 69edf9b). Neither stage list had an `openbao-` stage, because the box set no `OPENBAO_SEAL_KEY_FILE`. The box's `rebuild.sh` sets one only when its in-cluster switch, the file `openbao-in-cluster` in its work folder, reads `true`. | CI renders `openbao-store`, `secret-store` and the root with the store on. `test_rebuild_dev_stages.sh` checks the stage order, and `test_openbao_handover.sh` checks the hand-over against a stand-in OpenBao. |
| The store in prod's c1 (apps `openbao-store` and `openbao`, the store `openbao`) | Prod, not dev. 2026-11-18: the first start failed because self-init made the audit device through the API, which OpenBao refuses by default. Central-hub 6d59d49 (#454) declares it in the server config. Then openbao-0 was 1/1 and unsealed at 02:15:58 UTC, and the ClusterSecretStore `openbao` was Ready at 02:20 UTC, checked from the agent box. It was started before `openbao-prod` (#452) was merged, so the steps [On prod](#on-prod) lists have not run as written. | CI renders both apps with the store on. |
| The hourly snapshot in the cluster (CronJob `openbao-snapshot`) | No | CI renders it with the `openbao-store` chart and checks it with `kubeconform -strict`. No test runs it. |
| The box's snapshot folder (`secrets-store-snapshots.sh`: rotate and keep) | No | `test_secrets_store_snapshots.sh` |
| The box's `secrets-store` calls (`status`, `put`, `compare`, `reseed`, `restore`, `restore-rebuilt`) | No. They need the box's path to the store and, for `put`, `compare` and `reseed`, `sops_copies` on. | `test_secrets_store_wrapper.sh`, `test_secrets_store_kv.sh` (real SOPS and age against a stand-in OpenBao) and `test_secrets_store_restore.sh` |
| The off-box copy | No | `test_secrets_store_offbox.sh` |

CI runs every test named here on each pull request (`.github/hosts-check/run.sh`). In [Rebuild the k8s layer with one command](rebuild-k8s-layer-with-one-command.md), the 05:30 run is in [Proven runs](rebuild-k8s-layer-with-one-command.md#proven-runs) and the 04:33 run in the worker row of [Dev node sizes](rebuild-k8s-layer-with-one-command.md#dev-node-sizes). Both runs' stage and PASS lines are in the box's `rebuild log`. The raw logs stay on the box (private), so there is no public link. When a part first runs on dev, change its row and `last-tested` to the date, the run and the commit.

## Inside the cluster (D-0058), dev first

Argo CD installs it when the root Application passes `openbaoInCluster` true, which Ansible sets from `k8s_gitops_source_openbao_in_cluster` (role `k8s_gitops`). c1 keeps false and renders exactly as before (the root chart's `enabledBy`). Three apps take part:

| App | What it makes | Wave |
|---|---|---|
| `openbao-store` (chart in this repository) | Namespace `openbao` (restricted Pod Security); the seal key's local PersistentVolume and claim `openbao-seal`; a self-signed CA and server certificate `openbao-tls` from cert-manager; ConfigMap `openbao-policies` (`admin`, `eso-c1`, `snapshot`, `bootstrap`); service account `openbao-bootstrap`, which no pod runs as; the hourly snapshot CronJob `openbao-snapshot` and its claim `openbao-snapshots` | -1 |
| `openbao` (openbao-helm 0.30.6, OpenBao v2.7.2; the chart file checked in CI against its pinned SHA-256 from the repository's index, though Argo CD's own pull at sync is not checked; the image pinned by digest) | StatefulSet `openbao`, one replica, HA mode with Raft on `local-path`; the static seal read from `/openbao/seal/<id>.key`; TLS on 8200; a NetworkPolicy that lets only namespace `external-secrets`, its own namespace and Prometheus (namespace `monitoring`, port 8200) reach it; ServiceMonitor `openbao` for its metrics; a config change restarts the pod on its own | 0 |
| `secret-store` | With `openbao.inCluster` true: ClusterSecretStore `openbao` at `https://openbao.openbao.svc:8200`, checking TLS against `ca.crt` in Secret `openbao/openbao-tls`, signing in with OpenBao's Kubernetes login, role `eso`, as service account `store-openbao`; ExternalSecret `openbao-check` | -1 |

Private values, set in the dev inventory and never in git (CLAUDE.md rule 4):

- `k8s_gitops_source_openbao_seal_node`: the node that holds the seal key's folder, by its `kubernetes.io/hostname` label. It must be a node with the data disk (label `central-hub/data-disk`), because the data and audit claims use `local-path` and follow the pod. Unset, no PersistentVolume is made, the claim stays Pending and OpenBao does not start.
- `k8s_gitops_source_openbao_box_cidr`: the agent box's address as a /32, the admin AppRole's only source. Unset, the app's default `127.0.0.1/32` applies. That is not a lock: a `kubectl port-forward` connection also arrives from 127.0.0.1, because the container runtime dials localhost inside the pod's network namespace, so anyone who may port-forward in namespace `openbao` and holds the admin IDs passes the binding. While it is unset, the box's hand-over (stage `openbao-handover`) hands nothing over and passes with a skip line.
- `k8s_gitops_source_openbao_store_host`: the dev store's name as the box reaches it, the same as `address` in the box's `agent_box_secrets_store`. The box's `secrets-store` wrapper reads it from the dev inventory and refuses every action unless the two are equal (D-0058 rule 10). No chart reads it.

The hourly snapshot (D-0058 rule 6): CronJob `openbao/openbao-snapshot` runs at minute 17 as service account `openbao-snapshot`, signs in at the Kubernetes login's role `snapshot`, and reads `kv/data/dev/snapshot-mark`. While that mark is missing, the store has only self-initialized, so the job prints `openbao-snapshot: no mark at ... yet, skipped` and exits 0. Any other read failure fails the job. Otherwise it saves `raft-<UTC time>.snap` on claim `openbao-snapshots` (2 GiB, `local-path`), keeps the newest 48, and revokes its token. The box's hourly off-site pull is separate (pick 237).

The claim `openbao-snapshots` carries `argocd.argoproj.io/ignore-healthcheck: "true"`. `local-path` binds a claim only when a pod first uses it, and the first pod is the CronJob's, at minute 17. Argo CD counts a Pending claim as Progressing (v3.5.5, <https://github.com/argoproj/argo-cd/blob/v3.5.5/gitops-engine/pkg/health/health_pvc.go>, line 33). So on a fresh build, `openbao-store` stayed Progressing until minute 17, and a dev `apps` stage that did not cross it timed out after 1200 s (dev run `20261118T071239Z`, 2026-11-18). The annotation leaves the claim's health out of the Application's (<https://github.com/argoproj/argo-cd/blob/v3.5.5/docs/operator-manual/health.md>, line 294). A snapshot that fails, or can't mount its claim, still fires `C1OpenBaoSnapshotStale`.

expect, once a mark exists: `kubectl -n openbao logs job/<newest openbao-snapshot job>` ends with `openbao-snapshot: saved raft-<time>.snap, kept <n>`.

Before the first start, the node folder `/var/lib/central-hub/openbao-seal` must hold the 32-byte seal key as `seal-1.key`, owned by uid 100, group 1000, mode 0400 (OpenBao's pod user), and nothing else. The folder is outside what c1's nightly backup copies (role `k8s_backup` copies only `/var/lib/c1-data/local-path`, which holds OpenBao's data volume, and `/var/lib/central-hub/identity-postgres`), so c1's nightly backup never holds the key with the data. Proxmox's nightly backup of the node VMs does hold both, as it held the store VM's (D-0058, Consequences). On dev the box puts it there (below).

The seal key on dev, from the box (D-0058 rule 3; dev's key needs no tap):

1. A run of the `agent_box` role from the controller sets `agent_box_openbao_in_cluster: true` in the private inventory (box-apply never writes its own inventory), so the role writes `/var/lib/agent-box/openbao-in-cluster`. The role refuses it unless `agent_box_secrets_bundle` is set too, because the rebuild wrapper keeps the seal key as a SOPS copy encrypted to the box's age identity, which the bundle's tasks make ([make-the-box-secrets-bundle.md](make-the-box-secrets-bundle.md)). Its change to the box's limits needs no card (D-0042 rule 4). It gives agents a new admin login in the dev store, an access right, so its install is the owner's tap (D-0042 rule 6). That admin login can give itself any right in the dev store, so it is root of that store ([below](#handing-the-admin-login-to-the-box)). If the box's age identity is not there yet, setting `agent_box_secrets_bundle` makes it. That is a secrets step with its own tap, and it comes first.
2. `rebuild up` (or `rebuild rebuild`) then:
   - keeps the key as its SOPS copy, `/etc/agent-keys/dev/openbao-seal.key.sops.json` (user `keys`, 0600), encrypted to the box's age identity (D-0058 rules 3 and 9). It makes that copy once, if it is missing, from the VM wrapper's `openbao-seal.key` when one exists or else from `openssl rand 32`, checks that it decrypts to the same bytes, and never replaces it. It refuses if the identity is missing. A plain `openbao-seal.key` from the VM wrapper (`secrets-store.sh`), if one exists, stays until it is removed, which is a delete and the owner's tap (D-0042 rule 6);
   - decrypts the copy for each run into a folder in memory (`/dev/shm`, only user `keys` can read it) and checks that it is 32 bytes; the folder is removed when the run ends. This run writes no plain copy to the box's disk, and none goes into git;
   - the keys folder is in the box's daily bundle, so the copy leaves the box only once the bundle's off-box send is installed (`agent_box_opnsense_offbox` set and `agent_box_secrets_bundle.offbox: true`, which is false by default; see [make-the-box-secrets-bundle.md](make-the-box-secrets-bundle.md)). Until then the dev key is only on the box and the node. The bundle is also encrypted to the owner's Mac key when `mac_recipient` is set. The seal key's SOPS copy inside it stays encrypted to the box's identity only, so the Mac cannot read it (D-0058 rules 3 and 9), but the admin ID files beside it are plain, so a Mac that opens the bundle can read those;
   - sets `k8s_gitops_source_openbao_in_cluster: true` and `k8s_gitops_source_openbao_seal_node` to the first `k8s_workers` host in its copy of the dev inventory (an inventory value from the Mac for these is dropped), and sets `k8s_gitops_source_openbao_box_cidr` only from `box_cidr` in the wrapper's settings (below), never from the Mac's inventory; with no `box_cidr` it stays unset. A `box_cidr` that is not one IPv4 address as a /32, or is loopback, stops the run (`test_rebuild_box_inventory.sh`);
   - runs stage `openbao-seal` after `storage` and before `gitops`: `playbooks/k8s-openbao-seal.yml` checks that the key is 32 bytes, that the node at that host's address has the same Kubernetes name and that it carries the label `central-hub/data-disk=true`, makes the folder (uid 100, group 1000, 0500) and copies the key in (0400). A different key already on the node fails the stage and is never replaced; neither key nor checksum is printed.
   - It refuses if the store VM's wiring (the AppRole `rebuild` IDs) is also set.

   expect: `rebuild log` shows `openbao-seal end rc=0`; a second run reports `changed=0` for the play.

The file audit device at `/openbao/audit/audit.log` is declared in the server config, not made by self-init, because OpenBao refuses audit devices made through the API by default and self-init then refuses to unseal (first prod start, 2026-11-18; <https://openbao.org/docs/configuration/audit/>). What the first start does (self-init, <https://openbao.org/docs/configuration/self-init/>): KV v2 at `kv/`; AppRole and Kubernetes logins; policies `admin`, `eso-c1`, `snapshot` and `bootstrap` from the ConfigMap; the Kubernetes login's config (`kubernetes_host` `https://kubernetes.default.svc`, checked with OpenBao's own service account, which the chart binds to `system:auth-delegator`) and its roles `eso` (service account `store-openbao` in `external-secrets`, policy `eso-c1`, 15-minute tokens), `snapshot` (service account `openbao-snapshot` in `openbao`, policy `snapshot`, for the hourly job) and `bootstrap`; the admin AppRole bound to the box's /32, with a random role ID and no secret ID; and the fixed, non-secret word `ok` at `kv/c1/check`, the value ExternalSecret `openbao-check` reads. That write may fail (`allow_failure`) without stopping the unseal. Then it revokes the root token it used. Later starts skip it, so a store that started before this block was added has no `kv/c1/check` until `secrets-store put c1/check value` writes it.

Self-init runs only on a store's first start. If that start fails part way, as the first prod start did, a fixed config and a restart do not run it again: OpenBao's way to repeat it is to "remove all storage and re-initialize from scratch" (<https://openbao.org/docs/configuration/self-init/>). See the self-init line in [If it fails](#if-it-fails).

### Metrics, alerts and restarts

- **Metrics.** The server config has a `telemetry` block, and the listener lets `/v1/sys/metrics` answer with no token (`unauthenticated_metrics_access`; <https://openbao.org/docs/configuration/telemetry/>, <https://openbao.org/docs/configuration/listener/tcp/>). The metrics are counts, timings and the seal state, no secret, and only the callers the NetworkPolicy lets in reach the port. The chart's ServiceMonitor `openbao` has Prometheus read the active pod every 60 s over TLS, checked against `ca.crt` in Secret `openbao-tls` as `openbao-active.openbao.svc`.
- **What was measured.** OpenBao 2.7.2 from the pinned image was run on 2026-11-18 with this listener and telemetry config. `/v1/sys/metrics?format=prometheus` answered 200 with no token. `vault_core_unsealed` read 0 while sealed and 1 once unsealed. A series with `cluster=""` stays at its value from before the unseal for the 24-hour retention, so a rule reads the max. `bao status`, the chart's readiness check, exited 2 while sealed, so a sealed pod is not ready.
- **Alerts and the dashboard.** These are in app `monitoring-extras`, only where `openbaoInCluster` is true: `C1OpenBaoNotReady`, `C1OpenBaoSealed`, `C1OpenBaoNotScraped`, `C1OpenBaoAuditFailing` and `C1OpenBaoSnapshotStale`, plus an OpenBao row on the **c1 lab overview** dashboard ([check-c1-alerts-and-dashboard.md](check-c1-alerts-and-dashboard.md)).
- **Restarts.** The chart puts a checksum of the config on the pod (`configAnnotation`), and the StatefulSet uses `RollingUpdate`, so a merged change to the config replaces the pod on its own. With one replica, that is a few seconds with no store. The static seal unseals the new pod, and ESO retries meanwhile. Self-init does not run again on a store that has data.

### Handing the admin login to the box

Once per new store, dev only, stage `openbao-handover` (`playbooks/k8s-openbao-handover.yml`, on the first control-plane node). `hosts/rebuild-k8s.sh` adds it after `openbao-measure` on a dev run with `OPENBAO_SEAL_KEY_FILE` set, and it needs `OPENBAO_ADMIN_ROLE_ID_FILE` and `OPENBAO_ADMIN_SECRET_ID_FILE`. With neither named, as from a box whose rebuild wrapper was installed before this stage, it hands nothing over and ends with `SKIP: openbao-handover: not handed over, no admin ID files named; role bootstrap stays open`; with one named but missing or empty, it fails. The box's `rebuild.sh` passes `/etc/agent-keys/dev/openbao-admin-role-id` and `openbao-admin-secret-id`, and makes them first when they are missing, by the same rule as the `secrets-store` wrapper: `openssl rand -hex 24`, no trailing newline, never replaced, never printed. The stage:

1. Refuses unless the in-cluster store is on. While `k8s_gitops_source_openbao_box_cidr` is unset, it hands nothing over and ends with `SKIP: openbao-handover: not handed over, no box address yet; role bootstrap stays open` (a SKIP line, never a PASS one, in `rebuild log`), so the rest of the run goes on. The box's `rebuild.sh` leaves that value unset until the box's path to the store is chosen. A CIDR that is not a /32, or is a loopback or `0.` address, fails it.
2. Reads both ID files on the machine that runs the play, and checks that each is 48 lowercase hex characters (`no_log`).
3. Checks that pod `openbao-0` is Ready, then mints a 10-minute token for service account `openbao/openbao-bootstrap` with `kubectl create token` (10 minutes is TokenRequest's shortest life).
4. Runs one `kubectl exec -i openbao-0 -- sh -s`, with the script and its values on stdin. Inside the pod, every `bao` call gets its JSON body on its own stdin through `printf`, so no value is in any process's arguments. It signs in at the Kubernetes login's role `bootstrap` (5-minute tokens, 4 uses), and uses the answer as the token only when it is one bare token. It writes the admin's role ID and the custom secret ID (a rerun after a stop before the delete takes the same secret ID's "already registered" as done), deletes role `bootstrap`, and revokes its own token. The calls go from OpenBao's pod to its own Service, which the store's NetworkPolicy allows. The play sets `ansible_pipelining: true`, so its values never land in a module file on the node.
5. If the login answers that role `bootstrap` does not exist, the store was handed over before: `PASS: openbao-handover: already handed over`, with nothing set. Any other login failure fails the stage with its `HANDOVER:` line, which holds no secret.

The admin AppRole's IDs never leave the box's keys folder and the store (D-0038 rule 6). Until the hand-over, anyone with cluster-admin could set the admin's IDs the same way, but they can already read the seal key and the data.

expect: `rebuild log` shows `openbao-handover end rc=0` and `PASS: openbao-handover: done` on a new store, `already handed over` on a later run, or the SKIP line while the box's address is unset. The texts OpenBao answers for a deleted role ("invalid role name") and for a secret ID registered twice ("already registered") are not yet seen on the lab; check them on the first dev run.

expect, after the box's run: `kubectl -n openbao get pod openbao-0` Ready; `kubectl -n openbao exec openbao-0 -- bao status` shows `Sealed false`; ExternalSecret `external-secrets/openbao-check` Ready, from the word self-init wrote at `kv/c1/check`.

### Measuring the box's path through the Gateway (dev only)

The admin AppRole accepts only the box's /32. Through c1's Gateway, OpenBao may see the Gateway's own address instead of the box's, so the path the box will use is chosen only after this is measured on dev: which address OpenBao sees on two paths, whether the Gateway adds `X-Forwarded-For`, and whether c1 enforces the store's NetworkPolicy. Nothing signs in: every probe is a login with a made-up role ID, which OpenBao refuses and writes to its audit log.

It turns on by itself on dev. When `ENV_NAME` is `dev` and `OPENBAO_SEAL_KEY_FILE` is set (the in-cluster store is on), `hosts/rebuild-k8s.sh` adds `-e k8s_gitops_source_openbao_measure=true` to every `k8s-gitops.yml` call (stage `gitops`, both branches, and stage `dev-ca`), so the root Application passes `openbaoMeasure` true, and it runs stage `openbao-measure` after `dev-ca`, which makes the https listener the probes go through. Prod never gets it: the `-e` needs `ENV_NAME=dev` too, the stage refuses any other env, and CI checks that the root renders the same with the value unset as with it false (`.github/hosts-check/run.sh manifests`, `test_rebuild_dev_stages.sh`).

The agent box sets `OPENBAO_SEAL_KEY_FILE` only when its switch `agent_box_openbao_in_cluster` is on, which also sets `k8s_gitops_source_openbao_in_cluster` in the dev inventory (`rebuild.sh`). A run by hand with the key file set and that inventory value off stops at stage `openbao-seal`, whose check needs `k8s_gitops_source_openbao_seal_node`, which `rebuild.sh` sets only with the store on; with that node set by hand it stops at `openbao-measure` instead, whose first check needs the in-cluster store. Leave the key file unset or turn the store on.

What the value turns on:

| App | While `openbaoMeasure` is true |
|---|---|
| `gateway` | Gateway `apps` accepts listeners from namespace `openbao` only (`allowedListeners`, selector on the namespace's name) |
| `openbao-store` | The store's certificate `openbao-tls` also names `openbao-pass.<zone>`, the passthrough host |
| `openbao` | Self-init block `measure`: the audit log records the `X-Forwarded-For` and `X-Measure-Nonce` request headers in plain text. Self-init runs only on a store's first start, so this setting stays in that dev store until it is rebuilt. Neither header carries a secret |
| `openbao-measure` (new, `prune: true`, made only with `openbaoInCluster`) | Namespace `openbao-measure` (restricted Pod Security), for the policy check's test Job. Path a, re-encrypt: HTTPRoute `openbao-measure` on listener `https-short`, host `openbao-measure.<zone>`, to Service `openbao` port 8200, and a BackendTLSPolicy that checks OpenBao's certificate against the store's CA by the name `openbao.openbao.svc`. Path b, passthrough: ListenerSet `openbao-measure` with one TLS Passthrough listener on 443, host `openbao-pass.<zone>`, and a TLSRoute to the same Service |

The BackendTLSPolicy reads the CA from ConfigMap `openbao-measure-ca`, because Cilium 1.20.4 accepts only a ConfigMap there (a code read at tag v1.20.4: `operator/pkg/model/ingestion/gateway.go`, lines 643-649, "Cilium only supports ConfigMap currently"). cert-manager writes the CA only to a Secret, so the stage copies the public `ca.crt` into that ConfigMap in namespace `openbao` on every run, owned by Namespace `openbao-measure`, so that the ConfigMap goes when the namespace goes (a namespaced object may name a cluster-scoped owner: <https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/>).

The four route objects carry `argocd.argoproj.io/ignore-healthcheck: "true"`, so their health does not count toward the `openbao-measure` Application's (Argo CD v3.5.5: <https://github.com/argoproj/argo-cd/blob/v3.5.5/docs/operator-manual/health.md>, line 294). On a fresh dev build the root renders them at stage `gitops`, but listener `https-short` comes only at `dev-ca` and the CA ConfigMap only at `openbao-measure`, both after `apps`. Until then the HTTPRoute and the BackendTLSPolicy are Degraded (Argo CD's own checks for both kinds read `Accepted` and `ResolvedRefs`), so the Application was Degraded and stage `apps` timed out after 1200 s (dev run `20261118T040207Z`, 2026-11-18). The value has to be on from `gitops`, because the `openbao` self-init block runs only at the store's first start. So the stage checks the route itself (step 2).

Stage `openbao-measure` (`playbooks/k8s-openbao-measure.yml`, on the first control-plane node, the probes from the box):

1. Checks that all four of the Gateway's listeners are `Programmed`, reads the ListenerSet's conditions, and reads the namespace `openbao-measure`'s uid (it fails if the namespace is missing).
2. Copies `ca.crt` alone from Secret `openbao/openbao-tls` into the ConfigMap; it reads only that field and prints nothing. Then it waits up to 2 minutes for HTTPRoute `openbao-measure` to show `Accepted=True` and `ResolvedRefs=True` and no condition `False`, and fails if it doesn't.
3. The policy check: two Jobs run `bao status` against `https://openbao.openbao.svc:8200`, the control from namespace `openbao` (allowed) and the test from namespace `openbao-measure` (not allowed). A Job answered only when it succeeded (`bao status` exits 0 only on an unsealed store); the stage reads each Job's succeeded and failed counts separately. The control succeeds and the test fails with a timeout: `enforced`. Both succeed: `not enforced`. Anything else: `not measured`, with both readings and the test's last log line.
4. Three probes from the box, each with its own random nonce header: path a, path a with a made-up `X-Forwarded-For: 192.0.2.1`, and path b. It reads the issuer of the certificate path b presents, so a TLS answer from the Gateway's wildcard certificate is not taken for OpenBao's.
5. Finds the three nonces in OpenBao's audit log and records, for each probe, the address OpenBao saw and the `X-Forwarded-For` it received. It also reads Cilium's Gateway addresses (`ciliumnodes`, `spec.ingress.ipv4`). It fails if a probe that OpenBao answered left no audit line, or if path a carries no `X-Forwarded-For`. On path a (and a with the made-up header), a 502, 503 or 504 is the Gateway's own answer when it can't reach OpenBao (for example under an enforced NetworkPolicy): when the control Job found the store unsealed, the line shows `refused at gateway` for that probe and expects no audit line. A sealed OpenBao answers 503 itself, so with a failed control Job the code is shown plain and its audit line is still required. Path b is passthrough, so any HTTP code there is OpenBao's own and always needs its audit line.

expect: `rebuild log` shows `openbao-measure end rc=0`, and the stage's last line is `PASS: openbao-measure: gateway=ok listenerset=... policy=<enforced, not enforced or not measured>; a=<HTTP code> remote=<address> xff=<header>; axff=...; b=...; b_cert=<issuer>; ingress=<addresses>`. A refused login answers 400. A probe with no answer shows curl's error in place of the code. `rebuild log` keeps the whole line, since it runs past 200 characters.

While the value is on, OpenBao's API can be reached from the dev network through the dev Gateway, on both hosts, if c1 does not enforce the NetworkPolicy for Gateway traffic. OpenBao still checks every login: the admin AppRole's /32 binding is unchanged and no forwarded header is trusted, so a login through the Gateway is refused by address, and on dev the admin AppRole has no secret ID until the hand-over. The dev store holds nothing of value (D-0038 rule 5).

Turning it off is a change to `hosts/rebuild-k8s.sh` (the pull request that writes the chosen path removes the `-e` and the stage), with no install. The `openbao-measure` app then renders nothing and Argo CD prunes its objects; the ConfigMap goes with its namespace; the store's certificate drops `openbao-pass.<zone>` and Gateway `apps` drops `allowedListeners`. On the next dev run, check those two fields are gone:

```sh
kubectl -n openbao get certificate openbao-tls -o jsonpath='{.spec.dnsNames}'
kubectl -n gateway get gateway apps -o jsonpath='{.spec.allowedListeners}'
```

expect: no `openbao-pass` name, and an empty `allowedListeners`. The audited-headers setting stays in that dev store until it is rebuilt. Two more ways the objects go: a run limited with `--only` to a stage that renders the root, without `OPENBAO_SEAL_KEY_FILE`, renders the value off, so they are pruned until the next full run; and if `openbaoInCluster` goes off while the value is on, the `openbao-measure` Application leaves the root and its objects stay (the root has no resources finalizer), until a dev teardown removes them.

Not in this part yet: the route itself, the agent box's path to OpenBao through the Gateway, chosen after the source address is measured above, so the admin AppRole's /32 binding still holds, and the CA file for the wrapper (below). Already in place for it: `box_cidr` reaches the hand-over, and every dev call goes to dev's Gateway by address (below).

## The box's calls to the store

The agent box's `secrets-store` wrapper calls the store inside the dev cluster, run as user `keys`: `status`, `recovery`, `snapshot`, `restore`, `restore-rebuilt [raft-<time>.snap]`, `clear-hold`, `put c1/<path> <key>` (the value on stdin), `put-apps`, `compare` and `reseed`, plus the hourly off-box copy and the weekly compare. The store VM's actions (`plan`, `apply`, `destroy`, `configure`) are gone from the wrapper and from its sudo line (D-0058: no store VM was ever built).

Settings, `agent_box_secrets_store` in the private inventory, written to `/var/lib/agent-box/secrets-store.json`:

- `address`: the store's name as the box reaches it. **Dev only (D-0058 rule 10):** every action refuses unless it equals the one `k8s_gitops_source_openbao_store_host` in the dev inventory the rebuild wrapper reads (`/etc/agent-keys/rebuild-dev/inventory/hosts.yml`). `recovery` checks it again before it makes shares.
- `box_cidr`: the box's own address as a /32. The dev rebuild passes it to the hand-over as `k8s_gitops_source_openbao_box_cidr` (above). Empty until the box's path to the store is set.
- `snapshot_box`: see `snapshot` below.
- `sops_copies`: false until the owner's access-right tap (D-0058 rule 9), then set by a run of the role from the controller. Until it is true, `put`, `compare` and `reseed` refuse, and the weekly compare timer is not installed (set back to false, the role stops it).

On dev every call goes to dev's Gateway by its address, the one `k8s_gitops_source_gateway_address` in the dev inventory, with curl's `--resolve <address>:443:<gateway address>`. Dev uses c1's names, and the lab's wildcard DNS sends them to prod's Gateway ([rebuild-k8s-layer-with-one-command.md](rebuild-k8s-layer-with-one-command.md), `k8s_lab_dns_points_here`). The wrapper refuses before any call when the dev inventory gives none, two, or a value that is not IPv4. The hourly off-box copy's health call does the same. Prod's calls go by name. Every call checks the store against `/etc/agent-keys/dev/secrets-store-ca.crt` and refuses while that file is missing. The box's path to the store writes it, so **none of these calls runs on the lab yet**: each stops with the missing value named (no address, no store name in the dev inventory, or no CA file).

The rebuild hold (`/var/lib/agent-box/state/secrets-store.rebuilding`): `rebuild.sh`, with the in-cluster store on, writes it before a run that leaves a fresh, empty store (`rebuild` and `teardown`, and `up` while no dev VM is in the dev state, as after an ephemeral-dev run), and only when the box holds snapshots of an earlier store. The run then ends with the hold in place: the dev rebuild never calls `restore-rebuilt`, because each restore is the owner's tap (D-0058 rule 7). `restore-rebuilt` or `clear-hold` removes it.

The wrapper makes the admin AppRole's role ID and secret ID once in `/etc/agent-keys/dev/` (user `keys`, 0600, `openssl rand -hex 24` each, no trailing newline) and never prints them. It no longer makes a seal key: the rebuild wrapper keeps the dev seal key as a SOPS copy ([above](#inside-the-cluster-d-0058-dev-first)).

- `status`: `sys/health`, which holds no secret.
- `snapshot`: writes `kv/dev/snapshot-mark` (the snapshot's own time, no secret), then copies a Raft snapshot into `/etc/agent-keys/dev/openbao-snapshots/` (keeps 24), with `raft-<time>.snap.cluster` beside it holding the store's cluster ID. It signs in as AppRole `snapshot-box` once the settings say `snapshot_box: true`, which only the owner's install tap sets (agent pick 240, an access right and a box limit), and with the admin AppRole until then. It refuses while a rebuild hold exists.
- `restore` (D-0038 Confirmations 4 and 7, pick 239). **The owner's go first** (D-0034 rule 9): a restore of the secrets store is a delete under D-0042 rule 6, on dev too. It runs `secrets-store-restore.sh same`: the newest snapshot of the store's own cluster, the mark set to `before-restore-<time>`, a plain restore, never forced, and a fresh login that must read the snapshot's own time back in the mark.
  expect: `PASS: restore: raft-<time>.snap restored (plain) onto the same store; its mark reads back`, and a line `measured: old token: refused` or `still works`.
- `recovery`: on dev only (D-0038 rule 5), once, 3 shares with a threshold of 2 from `sys/rotate/recovery/init` ([OpenBao's rotate init API](https://openbao.org/docs/api/system/rotate/init/)) into `/etc/agent-keys/dev/openbao-recovery.json`, never printed. It records their time in `openbao-recovery.made`, then takes a snapshot a second later, because `restore` and `restore-rebuilt` refuse any snapshot not strictly later than the shares: a restore brings back the recovery keys of the snapshot's time (source: [Performing restore from snapshot invalidates existing auto-unseal recovery keys](https://discuss.hashicorp.com/t/performing-restore-from-snapshot-invalidates-existing-auto-unseal-recovery-keys/55326), about Vault). It refuses while a rebuild hold exists.
- `restore-rebuilt` (D-0038 Confirmation 5, pick 238), after a rebuild of the store, on the owner's go (a delete). A teardown of dev's c1, which wipes the dev store inside it, is not a store `destroy` and needs no tap; a `restore` keeps the tap on dev and prod, and a `destroy` of the production store, which a teardown of prod's c1 counts as, keeps it (D-0042 rule 6). It runs `secrets-store-restore.sh rebuilt` under the wrapper's lock:
  1. picks the newest snapshot whose `.cluster` names another cluster than the store's current one, later than the recovery shares once they exist, or the one named exactly;
  2. refuses unless `kv/` holds nothing but `c1/check`;
  3. tries the plain restore, and the forced one only if OpenBao refuses it with "possibly the snapshot is using a different set of unseal keys" (a Vault user's report, not OpenBao's own text: [Raft: how to restore from 3-node HA cluster to 1-node DR instance](https://discuss.hashicorp.com/t/raft-how-to-restore-from-3-node-ha-cluster-to-1-node-dr-instance/20572)); any other refusal stops as `other refusal`;
  4. waits for `sys/health` 200 and for its own earlier token to be refused;
  5. reads `kv/dev/snapshot-mark`, which must hold the picked snapshot's time;
  6. removes the hold.

  expect: seven `ok` step lines, then `PASS: restore-rebuilt: raft-<time>.snap restored (<how>) onto the rebuilt store; its mark reads back; hold removed`.
- `put c1/<path> <key>`, the value on stdin (D-0058 rule 8), byte for byte, so give it with `printf '%s'`, not `echo`, which adds a newline: SOPS first, then the store. `secrets-store-kv.sh` writes the one key into `/etc/agent-keys/dev/openbao-kv.sops.json` with `sops set --value-stdin` (SOPS 3.13.3; the file is never decrypted and re-encrypted whole), encrypted to the box's own age identity, so it is in the box's daily bundle and never in git. A Mac key on the bundle opens the bundle, not this file (D-0058 rule 9). It makes the file the first time. Then it reads `kv/data/<path>`, merges the one key, and writes it back with check-and-set on the version it read (the admin policy has no `patch`), so a write in between is refused, not overwritten. Only paths under `c1/` (the ones External Secrets reads). No value, token or ID is in any process's arguments or the output.
  expect: `secrets-store put: kv/<path> key <key> written to SOPS, then OpenBao`. A failure names which write failed; after "SOPS is written, but ...", run `put` again, then `compare`.
- `put-apps`: every value the apps read through store `c1` today, from the file the rebuild seeds namespace `secret-source` from (dev: `/etc/agent-keys/rebuild-secret-source.env`, the box's own; prod: `/etc/agent-keys/prod/secret-source.env`, the controller's copy), each written as `put c1/<name> value`: SOPS first, then the store. It checks every line's name before the first write, skips blank and `#` lines, and prints only names. [The apps' secrets](#the-apps-secrets) says when to run it.
  expect: one `put` line per value, then `secrets-store: put-apps: <n> values from <file> written to SOPS, then OpenBao, at c1/<name> key value`.
- `compare`: every key of the SOPS file against the store, by SHA-256 in memory; it prints only the path and name of a key that differs, is only in SOPS, or is only in the store, never a value or a hash. The weekly timer (`secrets-store-compare.timer`, Mondays at 05:00 by the box's clock by default, up to 30 minutes later, `agent_box_secrets_store_compare_on_calendar`) runs it once `sops_copies` is true.
  expect: `PASS: compare: <n> keys equal in SOPS and OpenBao`.
- `reseed`: a fresh store, filled from SOPS, when no snapshot can bring it back. It refuses during a rebuild hold (run `restore-rebuilt`, or `clear-hold` first), and refuses unless `kv/` holds nothing but `c1/check` and the snapshot mark `dev/snapshot-mark` (a time, no secret; any snapshot writes it, so the hourly off-box send leaves one within the hour). It writes every path of the SOPS file, each only if still absent (check-and-set 0), then takes a snapshot. It replaces nothing, so it is not a delete.
  expect: `PASS: reseed: <n> paths written from SOPS into the fresh store`, then the snapshot line.
- `clear-hold`: when the rebuilt store is to stay as it is, with no restore (the owner's go, given with the one for `restore-rebuilt`). It needs `sys/health` 200, moves every snapshot not of the current cluster, with its `.cluster` file, into `/etc/agent-keys/dev/openbao-snapshots-kept/`, never overwriting a file there, then removes the hold. Rotation never reads the kept folder, and the kept snapshots are not sent off the box. **Removing anything from the kept folder is a delete under D-0042 rule 6, so it needs the owner's tap**, and no wrapper does it.

The admin policy can call the forced restore (`sys/storage/raft/snapshot-force`) only for `restore-rebuilt`. `secrets-store restore` stays plain and never forces.

### On prod

`secrets-store-prod` is the same wrapper for the store inside prod's c1: it runs `secrets-store.sh --prod`, with the same actions and guards. It never reads dev's files, and the dev wrapper never reads its own:

| | dev (`secrets-store`) | prod (`secrets-store-prod`) |
|---|---|---|
| settings | `agent_box_secrets_store`, `/var/lib/agent-box/secrets-store.json` | `agent_box_secrets_store_prod`, `/var/lib/agent-box/secrets-store-prod.json` |
| keys, CA file, snapshots | `/etc/agent-keys/dev/` | `/etc/agent-keys/prod/` |
| the store name `address` must equal | `k8s_gitops_source_openbao_store_host` in `/etc/agent-keys/rebuild-dev/inventory/hosts.yml` | the same key in `/var/lib/agent-box/openbao-prod/inventory/hosts.yml`, which `openbao-prod` builds from its `store_host` |
| snapshot mark | `kv/dev/snapshot-mark` | `kv/prod/snapshot-mark` |
| rebuild hold | `/var/lib/agent-box/state/secrets-store.rebuilding` | `/var/lib/agent-box/state/secrets-store-prod.rebuilding` |
| `recovery` | once, into the keys folder | refused: prod gets no recovery shares (D-0038 rule 5, D-0058 rule 10) |

The restore and SOPS helpers take the environment from the keys folder's name, so they name the right mark. With the in-cluster store on, the root chart passes prod's cluster `env` label (`k8s_gitops_cluster_labels.env`) as `openbaoMarkEnv`, so prod's snapshot CronJob reads `kv/prod/snapshot-mark`. A `restore` or `restore-rebuilt` on prod is still the owner's tap (a delete, D-0042 rule 6), and so is putting prod's seal key on its node (a secrets step, D-0058 rule 3). The hourly off-box copy below is for the dev store only.

`openbao-prod` turns the store on in prod's c1 from the box, with no Mac step after the first. It runs as user `keys` on the code of `main`, in its own checkout, one run at a time, and logs each run in `/var/lib/agent-box/openbao-prod/logs/`. Its settings are `agent_box_openbao_prod` in the private inventory, written to `/var/lib/agent-box/openbao-prod.json`: `seal_node` (the prod `k8s_nodes` host that holds the seal key, by its Kubernetes node name), `store_host` (the store's name as the box reaches it) and `box_cidr` (the box's address as a /32, empty until the box's path to the store is set). It reads the box's copy of the prod inventory (`/etc/agent-keys/prod/inventory-hosts.yml`, from the controller's prod-files run) and builds its own copy with the box's node key and plain ssh. It refuses a host that is labelled other than `env: prod`, a `seal_node` that is not a prod node, and a `box_cidr` wider than one address.

1. `openbao-prod key`. It makes `/etc/agent-keys/prod-node-key` once and prints its public half.
   expect: one `ssh-ed25519 ...` line. Putting it into the `authorized_keys` of the inventory's `ansible_user` on each prod node gives the agents a root login there, a new access right, so it waits for the owner's tap (D-0042 rule 6). After the tap, put it there once, from a run that already reaches the nodes.
2. `openbao-prod check`.
   expect: `check <node>: reached` for every node. `answered, the key refused` means step 1's key is not on that node yet. `no answer` means the box's firewall rules to the prod nodes are not applied ([set-up-lab-network-and-firewall.md](set-up-lab-network-and-firewall.md), "prod node 200 SSH"), which is a firewall change and the owner's tap.
3. Check that `seal_node` has room: OpenBao asks for 256Mi of memory (limit 512Mi) and its snapshot job for 32Mi (`apps/openbao/values.yaml`, `apps/openbao-store/templates/snapshot.yaml`). Compare these with the node's allocatable memory less its pods' requests (`c1-read describe nodes`).
4. `openbao-prod seal <tap id>`, after the owner's go (D-0034 rule 9; the tap id is the message ID of his line or of the card he answered). Putting prod's seal key on its node is a secrets step (D-0058 rule 3, D-0042 rule 6). It makes prod's key once, kept only as `/etc/agent-keys/prod/openbao-seal.key.sops.json`, and runs `k8s-openbao-seal.yml`.
   expect: the play's recap with `failed=0`. A node that already holds a different key fails the run rather than being overwritten.
   If an earlier run (the Mac's) already put the seal key on its node, run `openbao-prod seal-copy <tap id>` instead, before step 4 ever runs on the box. Copying the key onto the box is also a secrets step, so it takes the owner's tap too. It reads the node's key file (`/var/lib/central-hub/openbao-seal/seal-1.key`) over ssh into a private folder in memory, keeps it as the same SOPS copy, and reads that copy back before keeping it. It never prints the key. If a SOPS copy is already kept, it only compares the two.
   expect: `PASS: seal-copy: ...`. `FAIL: seal-copy: ... differs` means the box's copy and the node's key are not the same key, and nothing is replaced.
5. `openbao-prod gitops`. It runs `k8s-gitops.yml --tags source` with the in-cluster store on, so Argo CD makes `openbao-store`, `openbao` and the store `openbao`.
   expect: the recap with `failed=0`, then the three apps Synced and Healthy (`c1-read get applications -n argocd`).
6. `openbao-prod handover`, once `box_cidr` is set. It hands the admin login to the IDs in `/etc/agent-keys/prod/` (`k8s-openbao-handover.yml`).
   expect: a `PASS` line, or `SKIP: ... no box address yet` while `box_cidr` is empty.
   If prod's first start stops in self-init (the pod's log says `self-initialization failed: refusing to unseal`), run `openbao-prod reset-failed-start <tap id>` after the fix reaches main, with the owner's tap on a card that names the step and the commit: the run deletes a claim (D-0042 rule 6), and the wrapper refuses without a tap id and logs it. It refuses unless that line is in the pod's log, the pod is not Ready and `bao status` reads as initialized false; then it deletes only pod `openbao-0` and claim `data-openbao-0` in namespace `openbao`, prints both before and after, and the StatefulSet makes them again.
   expect: `the failed start is confirmed`, then the pod and claim listed again. A store that was ever initialized is refused, never touched.
7. `secrets-store-prod status`, once `agent_box_secrets_store_prod.address` and the CA file are set by the box's path to the store.
   expect: `sys/health` with `"sealed":false`.

## The apps' secrets

Plan step 8a (D-0058 rules 5 and 8): every secret c1's apps read at run time moves into OpenBao, with a SOPS copy of each, and what a rebuild or repair needs while c1 is down stays a file on the box. This is the list, read from the code on 2026-11-18. Check it before you trust it, because a later change can add a reader: `git grep -n 'remoteRef\|secretKeyRef\|create secret' -- hosts/`.

**Read through store `c1` today, moving now.** Each is a line `<name>=<value>` in the environment's secret-source file, seeded into namespace `secret-source` by the rebuild's `secrets` stage ([seed-secret-source.md](seed-secret-source.md)). On prod, that file is the controller's, copied to the box (`agent_box` defaults, `prod_files`); on dev it is the box's own, made with random values (`files/rebuild.sh`, `ssfile`).

| Secret | Read by | Where the app names it |
|---|---|---|
| `ntfy-owner-password` | ExternalSecret `alerts/ntfy-auth` | `apps/alerts/values.yaml`, `auth.sources.owner` |
| `ntfy-alertmanager-token` | `alerts/ntfy-auth` and `monitoring/alertmanager-ntfy` | `apps/alerts/values.yaml`, `auth.sources.alertmanager`; `apps/monitoring-extras/values.yaml`, `ntfy.alertmanagerTokenSource` |
| `ntfy-proxmox-token` | `alerts/ntfy-auth` (the Proxmox host's own copy is role `proxmox_notify`'s, from the controller's file) | `apps/alerts/values.yaml`, `auth.sources.proxmox` |
| `healthchecks-ping-url` | `monitoring/alertmanager-heartbeat` | `apps/monitoring-extras/values.yaml`, `heartbeat.pingUrlSource` |
| `share-pod-authkey` | `share-pod/share-pod-authkey`, only where `shareTarget` is set (none on prod: `c1-read get externalsecrets -A` lists no share-pod one, 2026-11-18) | `apps/share-pod/values.yaml`, `authKey.source` |

**Made by Ansible from the controller's files today, into an app's namespace.** These move in a later part of step 8a, which gives each app an ExternalSecret in place of the role's copy:

| Secret | Made by | From |
|---|---|---|
| `monitoring/grafana-sso`, `argocd/argocd-sso`, `media/jellyfin-sso` (each app's client secret) | `k8s_identity`, `tasks/secrets.yml`, "Each app's copy of its client secret" | `identity.env` |
| `identity/realm-lab-secrets` (every client secret, user password and TOTP seed of realm `lab`) | `k8s_identity`, `tasks/secrets.yml`, "The realm's Secret" | `identity.env` |
| `cert-manager/cloudflare-api-token` (DNS-01) | `k8s_certs`, `tasks/issue.yml`, "Token as a Secret in the cert-manager namespace" | `cloudflare-dns01-token.txt` |

**Made inside the cluster, with no copy outside it.** A later part decides, one by one, whether each gets a SOPS copy: `media/jellyfin-admin` (an External Secrets `Password` generator, `CreatedOnce`), `identity/<name>-db` (made on the node by `k8s_identity`), Keycloak's first admin (`<name>-initial-admin`, made by its operator), Grafana's admin (`monitoring/kube-prometheus-stack-grafana`, made by its chart) and Argo CD's `argocd-initial-admin-secret`. `agent-read/agent-read-token` is a service-account token Kubernetes fills in, and the `openbao-tls` and `openbao-ca` certificates come from cert-manager; neither moves.

**Stays outside OpenBao** (rule 5: the jobs that rebuild or repair c1 or the layers under it read files in the box's keys folder; rule 8: what is needed before OpenBao starts): the seal key, the etcd encryption key (`c1-secrets-encryption.key`), the backup's `c1-backup.env`, the store's own admin IDs, and the Proxmox, firewall, tailnet and DNS files the rebuild reads (`files/rebuild-prod.sh`, the `need` list and `MAP`). The secret-source file itself also stays: it is what `put-apps` reads, and dev's rebuild seeds from it.

### Moving them

Off by default: the root value `appSecretsStore` is empty, so every ExternalSecret above reads store `c1` as before. Ansible sets it from `k8s_gitops_source_app_secrets_store` (role `k8s_gitops`). With `openbao`, the apps `alerts`, `monitoring-extras` and `share-pod` read key `c1/<name>`, property `value`, through store `openbao`. Policy `eso-c1` reads `kv/data/c1/*` and nothing else (`apps/openbao-store/policies/eso-c1.hcl`). The root chart and the role both refuse `openbao` while `openbaoInCluster` is off, and the root refuses any value other than empty, `c1` or `openbao`.

Per environment, in this order:

1. The box's path to the store, its hand-over and `sops_copies` are in place: `secrets-store-prod status` answers (prod), or `secrets-store status` (dev).
2. `secrets-store-prod put-apps` (or `secrets-store put-apps`).
   expect: the `put-apps` line above, with one value per line of the file.
3. `secrets-store-prod compare`.
   expect: `PASS: compare: <n> keys equal in SOPS and OpenBao`.
4. Set `k8s_gitops_source_app_secrets_store: openbao` in that environment's inventory and apply the source (prod: `openbao-prod gitops`).
   expect: `c1-read get externalsecrets -A` shows `ntfy-auth`, `alertmanager-ntfy` and `alertmanager-heartbeat` on store `openbao`, each `SecretSynced` and Ready.
5. Leave `secret-source` as it is until the next rebuild proves step 4 from code. Removing its Secrets is a delete (D-0042 rule 6).

On dev, every rebuild makes a fresh store. So the switch stays off there until the rebuild writes the dev values into OpenBao itself before `apps` (`put-apps` needs the hand-over, which waits on the box's path to the store).

## Off-box copy of the snapshots

Pick 237, proposed D-0038 rule 8. **Not installed yet:** it is a box limit, which needs no card (D-0042 rule 4), and it holds a delete (the daily prune) under D-0042 rule 6, so it waits for the owner's tap. It also waits on the blocker in [the bundle's runbook](make-the-box-secrets-bundle.md#before-you-start): no agent or pipeline identity may hold role-assignment rights on the backup vault or container.

Each hour, while the box is up, `secrets-store-offbox.sh`:

1. Skips with `secrets-store-offbox: skipped: no store` and succeeds unless the in-cluster store is on (`/var/lib/agent-box/openbao-in-cluster`) and the dev rebuild's OpenTofu state holds dev VMs. During a rebuild hold it skips with `skipped: store rebuild in progress`, and a hold over 24 hours old fails it. When dev is up with the store on but `sys/health` does not answer 200, the run fails (rule 9).
2. Runs `secrets-store snapshot` and copies the snapshot into `/etc/agent-keys/dev/openbao-snapshots/` (keeps 24).
3. Requires the escrow of pick 222's restic password, as the OPNsense copy does. With no current copy in the vault, nothing is sent.
4. Uses its own repository, `azure:opnsense-backup:/openbao-dev` (`agent_box_secrets_store_offbox.repository`). It refuses the OPNsense repository, a path inside it, or one that holds it, compared the way restic reads an `azure:` path: `azure:c:p`, `azure:c:/p` and `azure:c://p/` are one repository, and `azure:c:/` is the whole container. It makes its repository on the first run, only when restic says it does not exist (exit 10); any other error fails the run.
5. Backs the snapshot up under tag `openbao-dev`, then forgets past 48 hourly, 14 daily and 6 monthly, grouped by host and tags. The first run from 03:00 UTC each day also prunes, which deletes older snapshots from Azure for good.
6. Reads the snapshot back and requires the same bytes. It does not open it: only a store with the seal key can.

expect: `secrets-store-offbox: sent raft-<time>.snap (<n> bytes) off the box; it reads back the same`, and once a day `pruned the repository (once a day)`.

If the box is down, nothing goes off-site; c1's hourly CronJob keeps its own 48 snapshots, and Proxmox's nightly backup holds the node VMs.

**Box lost (break-glass, Activation gate item 7).** The owner alone, with their own Azure sign-in:

1. Grant their own account Key Vault Secrets User on the backup vault and Storage Blob Data Reader on the container.
2. Read the restic password and the box's age identity, and restore the newest secrets bundle as [its runbook](make-the-box-secrets-bundle.md#recover-the-bundle-when-the-box-is-lost-break-glass) says; the bundle holds the seal key's SOPS copy.
3. `restic -r azure:opnsense-backup:/openbao-dev restore --tag openbao-dev latest --target <folder>`.
4. Rebuild the store from code with that seal key, put the snapshot and its `.cluster` file (both are in the restic snapshot) in `/etc/agent-keys/dev/openbao-snapshots/`, and run `secrets-store restore-rebuilt`.
5. Take both roles away.

## If it fails

- `secrets-store-offbox: dev is up with the store on, but sys/health answered ...`: the store is sealed, broken or gone, or the box's path to it is not set yet. Check `secrets-store status`.
- `secrets-store: the settings have no store address yet`, `the dev inventory names no single dev store`, or `secrets-store-ca.crt is missing`: the box's path to the store is not set yet. Nothing was called.
- `secrets-store: the dev inventory gives no single IPv4 k8s_gitops_source_gateway_address`: the dev inventory lacks dev's Gateway address, or names two. Nothing was called.
- `secrets-store: the settings' store address is not the dev c1 store the dev inventory names; refused`: the two private values disagree. Fix the inventory; never point the wrapper at another store.
- `secrets-store: put keeps SOPS copies, which wait for the owner's tap`: `sops_copies` is not true. It waits for the owner's go on an access right (D-0034 rule 9, D-0058 rule 9); never set it by hand.
- `compare`: `FAIL: SOPS and OpenBao differ at the keys above (names only)`: a write reached one side only, or something changed the store outside `put`. Tell the owner before writing either side; a `put` of the right value fixes one key.
- `reseed`: `the store holds kv/<path>, so it is not fresh; nothing written`: use `restore` or `put`, never reseed over data.
- `openbao-handover`: `HANDOVER: login as bootstrap failed: ...`: the store refused role `bootstrap` for another reason than its absence. Nothing was set. Read the store's log; if the text for a deleted role differs from "invalid role name", the stage needs that text.
- `secrets-store-offbox: restic could not open the repository (exit 12) ...`: the password is not the repository's; the job never makes a new one over it. See the OPNsense runbook's password versions.
- `secrets-store: another secrets-store run is going`: the hourly pull met a session's run of the wrapper (its lock is taken with `flock -n`), so that hour's off-box send fails red; the next hour's run sends.
- `restore-rebuilt: 1 snapshot FAIL`: no snapshot of an earlier cluster is in the folder. Nothing was changed. After a recovery from off-box, check that the `.cluster` file came back with the snapshot.
- `restore-rebuilt: 2 empty store FAIL`: the store holds data besides `c1/check`, so it is not a fresh rebuild, and a forced restore would throw that data away. Nothing was changed; tell the owner.
- `restore-rebuilt: 3 restore FAIL: other refusal`: OpenBao refused the plain restore for another reason, or with other words than the pinned text. Nothing was forced. Read the store's log and tell the owner before changing the text.
- `secrets-store-offbox: the store's rebuild hold is over 24 hours old`: a rebuild was left before `restore-rebuilt` passed. Finish it, or, if the empty store is to stay, run `secrets-store clear-hold`, which sets the earlier snapshots aside first.
- `clear-hold`: `setting the earlier snapshots aside failed; the hold stays`: often a file of the same name is already in the kept folder (`exists already`). Nothing was overwritten, and the hold still protects the rest. Tell the owner; removing a kept file is their tap.
- `restore: 1 snapshot FAIL`: no snapshot of this store's own cluster is in the folder. Take one with `secrets-store snapshot`. A snapshot of an earlier store goes back only through `restore-rebuilt`.
- `restore: 3 restore FAIL`: OpenBao refused the plain restore of its own snapshot. Nothing was forced, and nothing ever is on the same store. Read the store's log and tell the owner.
- `restore: 4 mark reads back FAIL`: the restore call was taken, but the snapshot's mark did not come back in the wait. The mark now says `before-restore-<time>`. Read the store's log and tell the owner before running it again.
- `1b shares FAIL` (either restore): the snapshot is older than the recovery shares, and restoring it would leave them useless. Use a later snapshot. When none is left, take one with `secrets-store snapshot`. If the store is gone, there is no way back that keeps the shares: removing or moving `openbao-recovery.json` destroys a secret, so it is a delete under D-0042 rule 6, item 21 on the owner's card, and the wrapper never does it.
- `WARNING: openbao-recovery.made is missing`: the shares came before their time was recorded, so the shares file's own time is used. The run goes on with that time.
- `recovery`: `the shares are made, but the snapshot after them failed`: until a snapshot succeeds, nothing can be restored. Fix what the snapshot line says and run `secrets-store snapshot`.
- After any restore, the token that took the snapshot exists again in the store: it was alive when the snapshot was taken, and its revoke is not in the snapshot. It stops at its TTL, an hour at most (D-0038 rule 6). Its revoke fails with "token not found" ([openbao #522](https://github.com/openbao/openbao/issues/522)), so leave it to expire.
- `secrets-store: AppRole snapshot-box did not sign in`: its IDs are missing from the keys folder, or the store does not hold them yet. Never set `snapshot_box` by hand: it is the install tap's (an access right and a box limit).
- The pod's log shows a self-init error, or `kubectl -n openbao exec openbao-0 -- bao status` shows `Initialized true` while `kv/`, the logins or the policies are missing: the first start failed part way, and later starts skip self-init. Fix the cause in git first. Then the store's data volume must be cleared so the next start is a first start: claim `data-openbao-0` in namespace `openbao` (the chart's `data` claim; `audit-openbao-0` holds only the audit log). Clearing it destroys the store's data, so it is a delete and waits for the owner's tap (D-0042 rule 6), on dev and on prod. A store that ever held secrets needs a snapshot first, if it unseals.
- Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Set up the owner's desktop VM](set-up-the-desktop.md), the wrapper this one copies
