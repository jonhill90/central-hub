---
title: Set up the lab's secrets store (OpenBao) on dev
status: draft
kind: automated
trigger: once per env, after D-0058; again after a rebuild of the cluster
runner: "the dev rebuild on the agent box (`rebuild up`), and an agent session through the `secrets-store` wrapper once rework PR 3b points it at the in-cluster store"
outcome: OpenBao 2.7.2 runs in namespace openbao in dev's cluster, starts and unseals with no person from its seal key on one node, initializes itself with audit, KV v2, AppRole and Kubernetes logins, takes an hourly Raft snapshot, and serves External Secrets through its Kubernetes login
needs: the agent box with the agent_box role applied; the dev cluster; the private inventory values listed below
private-values: [seal-node, box-cidr, seal-key, admin-role-id, admin-secret-id]
files: [hosts/kubernetes/home/c1/apps/openbao/, hosts/kubernetes/home/c1/apps/openbao-store/, hosts/kubernetes/home/c1/apps/openbao-measure/, hosts/ansible/playbooks/k8s-openbao-measure.yml, hosts/kubernetes/home/c1/apps/secret-store/, hosts/kubernetes/home/c1/root/, hosts/ansible/roles/k8s_gitops/, hosts/ansible/roles/agent_box/files/secrets-store.sh, hosts/ansible/roles/agent_box/files/secrets-store-offbox.sh, hosts/ansible/roles/agent_box/files/secrets-store-restore.sh, .github/hosts-check/tests/test_secrets_store_restore.sh, hosts/ansible/roles/agent_box/files/secrets-store-snapshots.sh, .github/hosts-check/tests/test_secrets_store_snapshots.sh, hosts/ansible/roles/agent_box/tasks/secrets_store_offbox.yml, .github/hosts-check/tests/test_secrets_store_offbox.sh, hosts/ansible/playbooks/k8s-openbao-auth.yml]
last-tested: not yet run
superseded-by:
---

# Set up the lab's secrets store (OpenBao) on dev

**Status:** draft, not run. Written from the code and the OpenBao 2.7.2 docs; every "expect" below is what the docs say, not yet seen on the lab. The records are [D-0038](../decisions/README.md) and [D-0058](../decisions/README.md), which moves the store into the cluster.

**Inside the cluster ([D-0058](../decisions/README.md)).** OpenBao runs inside the cluster from its own Helm chart, dev's cluster first, not on a VM of its own. No store VM was ever built, and its code is gone. [Inside the cluster](#inside-the-cluster-d-0058-dev-first) below is code only, not yet run. The box's calls to the store that stay are listed after it; rework PR 3b points them at the in-cluster store.

## Inside the cluster (D-0058), dev first

Argo CD installs it when the root Application passes `openbaoInCluster` true, which Ansible sets from `k8s_gitops_source_openbao_in_cluster` (role `k8s_gitops`). c1 keeps false and renders exactly as before (the root chart's `enabledBy`). Three apps take part:

| App | What it makes | Wave |
|---|---|---|
| `openbao-store` (chart in this repository) | Namespace `openbao` (restricted Pod Security); the seal key's local PersistentVolume and claim `openbao-seal`; a self-signed CA and server certificate `openbao-tls` from cert-manager; ConfigMap `openbao-policies` (`admin`, `eso-c1`, `snapshot`, `bootstrap`); service account `openbao-bootstrap`, which no pod runs as; the hourly snapshot CronJob `openbao-snapshot` and its claim `openbao-snapshots` | -1 |
| `openbao` (openbao-helm 0.30.6, OpenBao v2.7.2; the chart file checked in CI against its pinned SHA-256 from the repository's index, though Argo CD's own pull at sync is not checked; the image pinned by digest) | StatefulSet `openbao`, one replica, HA mode with Raft on `local-path`; the static seal read from `/openbao/seal/<id>.key`; TLS on 8200; a NetworkPolicy that lets only namespace `external-secrets` and its own namespace reach it | 0 |
| `secret-store` | With `openbao.inCluster` true: ClusterSecretStore `openbao` at `https://openbao.openbao.svc:8200`, checking TLS against `ca.crt` in Secret `openbao/openbao-tls`, signing in with OpenBao's Kubernetes login, role `eso`, as service account `store-openbao`; ExternalSecret `openbao-check` | -1 |

Private values, set in the dev inventory and never in git (CLAUDE.md rule 4):

- `k8s_gitops_source_openbao_seal_node`: the node that holds the seal key's folder, by its `kubernetes.io/hostname` label. It must be a node with the data disk (label `central-hub/data-disk`), because the data and audit claims use `local-path` and follow the pod. Unset, no PersistentVolume is made, the claim stays Pending and OpenBao does not start.
- `k8s_gitops_source_openbao_box_cidr`: the agent box's address as a /32, the admin AppRole's only source. Unset, the app's default `127.0.0.1/32` applies. That is not a lock: a `kubectl port-forward` connection also arrives from 127.0.0.1, because the container runtime dials localhost inside the pod's network namespace, so anyone who may port-forward in namespace `openbao` and holds the admin IDs passes the binding. The box's hand-over refuses while it is unset.

The hourly snapshot (D-0058 rule 6): CronJob `openbao/openbao-snapshot` runs at minute 17 as service account `openbao-snapshot`, signs in at the Kubernetes login's role `snapshot`, and reads `kv/data/dev/snapshot-mark`. While that mark is missing, the store has only self-initialized, so the job prints `openbao-snapshot: no mark at ... yet, skipped` and exits 0. Any other read failure fails the job. Otherwise it saves `raft-<UTC time>.snap` on claim `openbao-snapshots` (2 GiB, `local-path`), keeps the newest 48, and revokes its token. The box's hourly off-site pull is separate (pick 237).

expect, once a mark exists: `kubectl -n openbao logs job/<newest openbao-snapshot job>` ends with `openbao-snapshot: saved raft-<time>.snap, kept <n>`.

Before the first start, the node folder `/var/lib/central-hub/openbao-seal` must hold the 32-byte seal key as `seal-1.key`, owned by uid 100, group 1000, mode 0400 (OpenBao's pod user), and nothing else. The folder is outside what c1's nightly backup copies (role `k8s_backup` copies only `/var/lib/c1-data/local-path`, which holds OpenBao's data volume, and `/var/lib/central-hub/identity-postgres`), so c1's nightly backup never holds the key with the data. Proxmox's nightly backup of the node VMs does hold both, as it held the store VM's (D-0058, Consequences). On dev the box puts it there (below).

The seal key on dev, from the box (D-0058 rule 3; dev's key needs no tap):

1. The box's install sets `agent_box_openbao_in_cluster: true` in the private inventory, so the `agent_box` role writes `/var/lib/agent-box/openbao-in-cluster`. The role refuses it unless `agent_box_secrets_bundle` is set too, because the rebuild wrapper keeps the seal key as a SOPS copy encrypted to the box's age identity, which the bundle's tasks make ([make-the-box-secrets-bundle.md](make-the-box-secrets-bundle.md)). It is a change to the box's limits, so its install is the owner's tap (D-0042 rule 6).
2. `rebuild up` (or `rebuild rebuild`) then:
   - keeps the key as its SOPS copy, `/etc/agent-keys/dev/openbao-seal.key.sops.json` (user `keys`, 0600), encrypted to the box's age identity (D-0058 rules 3 and 9). It makes that copy once, if it is missing, from the VM wrapper's `openbao-seal.key` when one exists or else from `openssl rand 32`, checks that it decrypts to the same bytes, and never replaces it. It refuses if the identity is missing. A plain `openbao-seal.key` from the VM wrapper (`secrets-store.sh`), if one exists, stays until it is removed, which is a delete and the owner's tap (D-0042 rule 6);
   - decrypts the copy for each run into a folder in memory (`/dev/shm`, only user `keys` can read it) and checks that it is 32 bytes; the folder is removed when the run ends. This run writes no plain copy to the box's disk, and none goes into git;
   - the keys folder is in the box's daily bundle, so the copy leaves the box only once the bundle's off-box send is installed (`agent_box_secrets_bundle` and `agent_box_opnsense_offbox` set; see [make-the-box-secrets-bundle.md](make-the-box-secrets-bundle.md)). Until then the dev key is only on the box and the node;
   - sets `k8s_gitops_source_openbao_in_cluster: true` and `k8s_gitops_source_openbao_seal_node` to the first `k8s_workers` host in its copy of the dev inventory (an inventory value from the Mac for these is dropped), and leaves `k8s_gitops_source_openbao_box_cidr` unset;
   - runs stage `openbao-seal` after `storage` and before `gitops`: `playbooks/k8s-openbao-seal.yml` checks that the key is 32 bytes, that the node at that host's address has the same Kubernetes name and that it carries the label `central-hub/data-disk=true`, makes the folder (uid 100, group 1000, 0500) and copies the key in (0400). A different key already on the node fails the stage and is never replaced; neither key nor checksum is printed.
   - It refuses if the store VM's wiring (the AppRole `rebuild` IDs) is also set.

   expect: `rebuild log` shows `openbao-seal end rc=0`; a second run reports `changed=0` for the play.

What the first start does (self-init, <https://openbao.org/docs/configuration/self-init/>): the file audit device at `/openbao/audit/audit.log`; KV v2 at `kv/`; AppRole and Kubernetes logins; policies `admin`, `eso-c1`, `snapshot` and `bootstrap` from the ConfigMap; the Kubernetes login's config (`kubernetes_host` `https://kubernetes.default.svc`, checked with OpenBao's own service account, which the chart binds to `system:auth-delegator`) and its roles `eso` (service account `store-openbao` in `external-secrets`, policy `eso-c1`, 15-minute tokens), `snapshot` (service account `openbao-snapshot` in `openbao`, policy `snapshot`, for the hourly job) and `bootstrap`; and the admin AppRole bound to the box's /32, with a random role ID and no secret ID. Then it revokes the root token it used. Later starts skip it.

Handing the admin login to the box, once per new store (the box's node play, in a later pull request): it mints a 10-minute token for service account `openbao/openbao-bootstrap` with `kubectl create token`, signs in at the Kubernetes login's role `bootstrap` (5-minute tokens, 4 uses), writes the admin's role ID and a custom secret ID from its keys folder, deletes role `bootstrap` with the same token, and checks that the role is gone. The admin AppRole's IDs never leave the box's keys folder (D-0038 rule 6). Until that step, anyone with cluster-admin could set the admin's IDs the same way, but they can already read the seal key and the data.

expect, after the box's run: `kubectl -n openbao get pod openbao-0` Ready; `kubectl -n openbao exec openbao-0 -- bao status` shows `Sealed false`; ExternalSecret `external-secrets/openbao-check` Ready once `kv/c1/check` is written.

### Measuring the box's path through the Gateway (dev only)

The admin AppRole accepts only the box's /32. Through c1's Gateway, OpenBao may see the Gateway's own address instead of the box's, so the path the box will use is chosen only after this is measured on dev: which address OpenBao sees on two paths, whether the Gateway adds `X-Forwarded-For`, and whether c1 enforces the store's NetworkPolicy. Nothing signs in: every probe is a login with a made-up role ID, which OpenBao refuses and writes to its audit log.

It turns on by itself on dev. When `ENV_NAME` is `dev` and `OPENBAO_SEAL_KEY_FILE` is set (the in-cluster store is on), `hosts/rebuild-k8s.sh` adds `-e k8s_gitops_source_openbao_measure=true` to every `k8s-gitops.yml` call (stage `gitops`, both branches, and stage `dev-ca`), so the root Application passes `openbaoMeasure` true, and it runs stage `openbao-measure` after `dev-ca`, which makes the https listener the probes go through. Prod never gets it: the `-e` needs `ENV_NAME=dev` too, the stage refuses any other env, and CI checks that the root renders the same with the value unset as with it false (`.github/hosts-check/run.sh manifests`, `test_rebuild_dev_stages.sh`).

What the value turns on:

| App | While `openbaoMeasure` is true |
|---|---|
| `gateway` | Gateway `apps` accepts listeners from namespace `openbao` only (`allowedListeners`, selector on the namespace's name) |
| `openbao-store` | The store's certificate `openbao-tls` also names `openbao-pass.<zone>`, the passthrough host |
| `openbao` | Self-init block `measure`: the audit log records the `X-Forwarded-For` and `X-Measure-Nonce` request headers in plain text. Self-init runs only on a store's first start, so this setting stays in that dev store until it is rebuilt. Neither header carries a secret |
| `openbao-measure` (new, `prune: true`, made only with `openbaoInCluster`) | Namespace `openbao-measure` (restricted Pod Security), for the policy check's test Job. Path a, re-encrypt: HTTPRoute `openbao-measure` on listener `https-short`, host `openbao-measure.<zone>`, to Service `openbao` port 8200, and a BackendTLSPolicy that checks OpenBao's certificate against the store's CA by the name `openbao.openbao.svc`. Path b, passthrough: ListenerSet `openbao-measure` with one TLS Passthrough listener on 443, host `openbao-pass.<zone>`, and a TLSRoute to the same Service |

The BackendTLSPolicy reads the CA from ConfigMap `openbao-measure-ca`, because Cilium 1.20.4 accepts only a ConfigMap there (a code read at tag v1.20.4: `operator/pkg/model/ingestion/gateway.go`, lines 643-649, "Cilium only supports ConfigMap currently"). cert-manager writes the CA only to a Secret, so the stage copies the public `ca.crt` into that ConfigMap in namespace `openbao` on every run, owned by Namespace `openbao-measure`, so that the ConfigMap goes when the namespace goes (a namespaced object may name a cluster-scoped owner: <https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/>).

Stage `openbao-measure` (`playbooks/k8s-openbao-measure.yml`, on the first control-plane node, the probes from the box):

1. Checks that all four of the Gateway's listeners are `Programmed`, reads the ListenerSet's conditions, and reads the namespace `openbao-measure`'s uid (it fails if the namespace is missing).
2. Copies `ca.crt` alone from Secret `openbao/openbao-tls` into the ConfigMap; it reads only that field and prints nothing.
3. The policy check: two Jobs run `bao status` against `https://openbao.openbao.svc:8200`, the control from namespace `openbao` (allowed) and the test from namespace `openbao-measure` (not allowed). The control answers and the test times out: `enforced`. Both answer: `not enforced`. Anything else: `not measured`, with the reason.
4. Three probes from the box, each with its own random nonce header: path a, path a with a made-up `X-Forwarded-For: 192.0.2.1`, and path b. It reads the issuer of the certificate path b presents, so a TLS answer from the Gateway's wildcard certificate is not taken for OpenBao's.
5. Finds the three nonces in OpenBao's audit log and records, for each probe, the address OpenBao saw and the `X-Forwarded-For` it received. It also reads Cilium's Gateway addresses (`ciliumnodes`, `spec.ingress.ipv4`). It fails if a probe that got an answer left no audit line, or if path a carries no `X-Forwarded-For`.

expect: `rebuild log` shows `openbao-measure end rc=0`, and the stage's last line is `PASS: openbao-measure: gateway=ok listenerset=... policy=<enforced, not enforced or not measured>; a=<HTTP code> remote=<address> xff=<header>; axff=...; b=...; b_cert=<issuer>; ingress=<addresses>`. A refused login answers 400. A probe with no answer shows curl's error in place of the code.

While the value is on, OpenBao's API can be reached from the dev network through the dev Gateway, on both hosts, if c1 does not enforce the NetworkPolicy for Gateway traffic. OpenBao still checks every login: the admin AppRole's /32 binding is unchanged and no forwarded header is trusted, so a login through the Gateway is refused by address, and on dev the admin AppRole has no secret ID until the hand-over. The dev store holds nothing of value (D-0038 rule 5).

Turning it off is a change to `hosts/rebuild-k8s.sh` (the pull request that writes the chosen path removes the `-e` and the stage), with no install. The `openbao-measure` app then renders nothing and Argo CD prunes its objects; the ConfigMap goes with its namespace; the store's certificate drops `openbao-pass.<zone>` and Gateway `apps` drops `allowedListeners`. On the next dev run, check those two fields are gone:

```sh
kubectl -n openbao get certificate openbao-tls -o jsonpath='{.spec.dnsNames}'
kubectl -n gateway get gateway apps -o jsonpath='{.spec.allowedListeners}'
```

expect: no `openbao-pass` name, and an empty `allowedListeners`. The audited-headers setting stays in that dev store until it is rebuilt. Two more ways the objects go: a run limited with `--only` to a stage that renders the root, without `OPENBAO_SEAL_KEY_FILE`, renders the value off, so they are pruned until the next full run; and if `openbaoInCluster` goes off while the value is on, the `openbao-measure` Application leaves the root and its objects stay (the root has no resources finalizer), until a dev teardown removes them.

Not in this part yet: the agent box's path to OpenBao through the Gateway (after the source address is measured above, so the admin AppRole's /32 binding still holds), then the rest of the box's wrapper changes, which need that path (the admin hand-over, SOPS copies, reseed, compare, and the hold during a rebuild).

## The box's calls to the store (kept for rework PR 3b)

The store VM's code is gone: its OpenTofu folder, the `openbao` Ansible role and play, and the wrapper's `plan`, `apply`, `destroy` and `configure` (D-0058: no store VM was ever built, so nothing in the lab changed). The agent box's `secrets-store` wrapper keeps its calls to the store's API, which the in-cluster store will use: `status`, `recovery`, `snapshot`, `restore`, `restore-rebuilt [raft-<time>.snap]` and `clear-hold`, run as user `keys`, plus the hourly off-box copy.

**Not runnable on the in-cluster store yet.** These calls still read the store's address from `agent_box_secrets_store` and its CA from `/etc/agent-keys/dev/secrets-store-ca.crt`, which only the VM's `configure` wrote, and they refuse a store outside the dev VM IDs 550 to 599. Rework PR 3b points them at the dev c1 store, guards recovery shares by its address (D-0058 rule 10), and has `hosts/rebuild-k8s.sh` write the rebuild hold that `destroy` used to write. Until then every call stops at once with `secrets-store: ... secrets-store.json is missing`, because `agent_box_secrets_store` is not set on the box, and the off-box copy finds no OpenTofu state and skips. The box's sudo rule still lists the four removed words (`agent_box_wrappers` in the role's defaults, whose change needs the owner's tap under D-0056 rule 4); the wrapper answers each with its usage line and does nothing. The rules below are what those calls do; they stay true after PR 3b.

The wrapper makes the admin AppRole's role ID and secret ID once in `/etc/agent-keys/dev/` (user `keys`, 0600, `openssl rand -hex 24` each, no trailing newline) and never prints them. It no longer makes a seal key: the rebuild wrapper keeps the dev seal key as a SOPS copy ([above](#inside-the-cluster-d-0058-dev-first)).

- `status`: `sys/health`, which holds no secret.
- `snapshot`: writes `kv/dev/snapshot-mark` (the snapshot's own time, no secret), then copies a Raft snapshot into `/etc/agent-keys/dev/openbao-snapshots/` (keeps 24), with `raft-<time>.snap.cluster` beside it holding the store's cluster ID. It signs in as AppRole `snapshot-box` once the settings say `snapshot_box: true`, which only the owner's install tap sets (agent pick 240, an access right and a box limit), and with the admin AppRole until then. It refuses while a rebuild hold exists.
- `restore` (D-0038 Confirmations 4 and 7, pick 239). **The owner's tap first:** a restore of the secrets store is a delete under D-0042 rule 6, on dev too. It runs `secrets-store-restore.sh same`: the newest snapshot of the store's own cluster, the mark set to `before-restore-<time>`, a plain restore, never forced, and a fresh login that must read the snapshot's own time back in the mark.
  expect: `PASS: restore: raft-<time>.snap restored (plain) onto the same store; its mark reads back`, and a line `measured: old token: refused` or `still works`.
- `recovery`: on dev only (D-0038 rule 5), once, 3 shares with a threshold of 2 from `sys/rotate/recovery/init` ([OpenBao's rotate init API](https://openbao.org/docs/api/system/rotate/init/)) into `/etc/agent-keys/dev/openbao-recovery.json`, never printed. It records their time in `openbao-recovery.made`, then takes a snapshot a second later, because `restore` and `restore-rebuilt` refuse any snapshot not strictly later than the shares: a restore brings back the recovery keys of the snapshot's time (source: [Performing restore from snapshot invalidates existing auto-unseal recovery keys](https://discuss.hashicorp.com/t/performing-restore-from-snapshot-invalidates-existing-auto-unseal-recovery-keys/55326), about Vault). It refuses while a rebuild hold exists.
- `restore-rebuilt` (D-0038 Confirmation 5, pick 238), after a rebuild of the store, on the owner's tap (a delete). A teardown of dev's c1, which wipes the dev store inside it, is not a store `destroy` and needs no tap; a `restore` keeps the tap on dev and prod, and a `destroy` of the production store, which a teardown of prod's c1 counts as, keeps it (D-0042 rule 6). It runs `secrets-store-restore.sh rebuilt` under the wrapper's lock:
  1. picks the newest snapshot whose `.cluster` names another cluster than the store's current one, later than the recovery shares once they exist, or the one named exactly;
  2. refuses unless `kv/` holds nothing but `c1/check`;
  3. tries the plain restore, and the forced one only if OpenBao refuses it with "possibly the snapshot is using a different set of unseal keys" (a Vault user's report, not OpenBao's own text: [Raft: how to restore from 3-node HA cluster to 1-node DR instance](https://discuss.hashicorp.com/t/raft-how-to-restore-from-3-node-ha-cluster-to-1-node-dr-instance/20572)); any other refusal stops as `other refusal`;
  4. waits for `sys/health` 200 and for its own earlier token to be refused;
  5. reads `kv/dev/snapshot-mark`, which must hold the picked snapshot's time;
  6. removes the hold.

  expect: seven `ok` step lines, then `PASS: restore-rebuilt: raft-<time>.snap restored (<how>) onto the rebuilt store; its mark reads back; hold removed`.
- `clear-hold`: when the rebuilt store is to stay as it is, with no restore (the owner's tap, on the same card line as `restore-rebuilt`). It needs `sys/health` 200, moves every snapshot not of the current cluster, with its `.cluster` file, into `/etc/agent-keys/dev/openbao-snapshots-kept/`, never overwriting a file there, then removes the hold. Rotation never reads the kept folder, and the kept snapshots are not sent off the box. **Removing anything from the kept folder is a delete under D-0042 rule 6, so it needs the owner's tap**, and no wrapper does it.

The admin policy can call the forced restore (`sys/storage/raft/snapshot-force`) only for `restore-rebuilt`. `secrets-store restore` stays plain and never forces.

## Off-box copy of the snapshots

Pick 237, proposed D-0038 rule 8. **Not installed yet:** it is a box limit, and a delete (the daily prune) under D-0042 rule 6, so it waits for the owner's tap. It also waits on the blocker in [the bundle's runbook](make-the-box-secrets-bundle.md#before-you-start): no agent or pipeline identity may hold role-assignment rights on the backup vault or container.

Each hour, while the box is up, `secrets-store-offbox.sh`:

1. Skips with `secrets-store-offbox: skipped: no store` and succeeds when the wrapper's OpenTofu state holds no store VM. With the VM code gone, nothing writes that state, so it skips every hour until rework PR 3b points it at the in-cluster store. When a store is listed but `sys/health` does not answer 200, the run fails (rule 9).
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

- `secrets-store-offbox: the store's VM is in the wrapper's state, but sys/health answered ...`: the store is sealed, broken or gone. Check `secrets-store status`.
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
- Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Set up the owner's desktop VM](set-up-the-desktop.md), the wrapper this one copies
