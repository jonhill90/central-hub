---
title: Set up the lab's secrets store (OpenBao) on dev
status: draft
kind: automated
trigger: once per env, after D-0038's picks; again after the store's VM is rebuilt
runner: "an agent session on the agent box, through the `secrets-store` wrapper (in the agent_box role since #276; on the box once that role is applied, see Before you start)"
outcome: one AlmaLinux 10 VM on VNet dev runs OpenBao 2.7.2, starts and unseals with no person, initialized by itself with audit, KV v2 and two AppRoles, takes an hourly Raft snapshot, and holds c1's External Secrets login and the rebuild's AppRole
needs: the agent box; the agents' Proxmox token with rights on pool `dev`; template 9001; a free dev address; the private inventory values listed below
private-values: [store-name, store-address, box-address, seal-key, admin-role-id, admin-secret-id, rebuild-role-id, rebuild-secret-id, store-ssh-key]
files: [hosts/kubernetes/home/c1/apps/openbao/, hosts/kubernetes/home/c1/apps/openbao-store/, hosts/kubernetes/home/c1/apps/secret-store/, hosts/kubernetes/home/c1/root/, hosts/ansible/roles/k8s_gitops/, hosts/terraform/home/secrets-store/, hosts/ansible/roles/openbao/, hosts/ansible/roles/agent_box/files/secrets-store-offbox.sh, hosts/ansible/roles/agent_box/files/secrets-store-restore.sh, .github/hosts-check/tests/test_secrets_store_restore.sh, hosts/ansible/roles/agent_box/files/secrets-store-snapshots.sh, .github/hosts-check/tests/test_secrets_store_snapshots.sh, hosts/ansible/roles/agent_box/tasks/secrets_store_offbox.yml, .github/hosts-check/tests/test_secrets_store_offbox.sh, hosts/ansible/playbooks/openbao.yml, hosts/ansible/playbooks/k8s-openbao-auth.yml]
last-tested: not yet run
superseded-by:
---

# Set up the lab's secrets store (OpenBao) on dev

**Status:** draft, not run. Written on 2026-11-14 from the code in this PR and the OpenBao 2.7.2 docs and package files. Every "expect" below is what the docs say, not yet seen on the lab. The record is [D-0038](../decisions/README.md) (proposed).

**Moving into the cluster ([D-0058](../decisions/README.md)).** OpenBao leaves its VM and runs inside the cluster from its own Helm chart, dev's cluster first. [Inside the cluster](#inside-the-cluster-d-0058-dev-first) below is that part; it is code only, not yet run. The VM sections after it stay until the VM's code is removed in its own pull request. Step 8 now needs the in-cluster store, since the secret-store app's `openbao` store points there.

## Inside the cluster (D-0058), dev first

Argo CD installs it when the root Application passes `openbaoInCluster` true, which Ansible sets from `k8s_gitops_source_openbao_in_cluster` (role `k8s_gitops`). c1 keeps false and renders exactly as before (the root chart's `enabledBy`). Three apps take part:

| App | What it makes | Wave |
|---|---|---|
| `openbao-store` (chart in this repository) | Namespace `openbao` (restricted Pod Security); the seal key's local PersistentVolume and claim `openbao-seal`; a self-signed CA and server certificate `openbao-tls` from cert-manager; ConfigMap `openbao-policies` (`admin`, `eso-c1`, `snapshot`) | -2 |
| `openbao` (openbao-helm 0.30.6, OpenBao v2.7.2) | StatefulSet `openbao`, one replica, HA mode with Raft on `local-path`; the static seal read from `/openbao/seal/<id>.key`; TLS on 8200; a NetworkPolicy that lets only namespace `external-secrets` and its own namespace reach it | -1 |
| `secret-store` | With `openbao.inCluster` true: ClusterSecretStore `openbao` at `https://openbao.openbao.svc:8200`, checking TLS against `ca.crt` in Secret `openbao/openbao-tls`, signing in with OpenBao's Kubernetes login, role `eso`, as service account `store-openbao`; ExternalSecret `openbao-check` | -1 |

Private values, set in the dev inventory and never in git (CLAUDE.md rule 4):

- `k8s_gitops_source_openbao_seal_node`: the node that holds the seal key's folder, by its `kubernetes.io/hostname` label. It must be a node with the data disk (label `central-hub/data-disk`), because the data and audit claims use `local-path` and follow the pod. Unset, no PersistentVolume is made, the claim stays Pending and OpenBao does not start.
- `k8s_gitops_source_openbao_box_cidr`: the agent box's address as a /32, the admin AppRole's only source. Unset, the chart's default `127.0.0.1/32` lets no one outside the pod sign in as admin.

Before the first start, the node folder `/var/lib/central-hub/openbao-seal` must hold, owned by uid 100, group 1000, mode 0400 (OpenBao's pod user): the 32-byte seal key as `seal-1.key`, and, for that first start only, the admin AppRole's two IDs as `admin-role-id` and `admin-secret-id` (no trailing newline). The folder is outside what c1's nightly backup copies (role `k8s_backup` copies only `/var/lib/c1-data/local-path`, which holds OpenBao's data volume, and `/var/lib/central-hub/identity-postgres`), so c1's nightly backup never holds the key with the data. Proxmox's nightly backup of the node VMs does hold both, as it held the store VM's (D-0058, Consequences). Once `sys/init` reports initialized, the node play removes both ID files and checks they are gone, so the IDs then live only in the box's keys folder (D-0038 rule 6). The box's node play comes in a later pull request; until then nothing here runs on the lab.

What the first start does (self-init, <https://openbao.org/docs/configuration/self-init/>): the file audit device at `/openbao/audit/audit.log`; KV v2 at `kv/`; AppRole and Kubernetes logins; policies `admin`, `eso-c1` and `snapshot` from the ConfigMap; the Kubernetes login's config (`kubernetes_host` `https://kubernetes.default.svc`, checked with OpenBao's own service account, which the chart binds to `system:auth-delegator`) and its roles `eso` (service account `store-openbao` in `external-secrets`, policy `eso-c1`, 15-minute tokens) and `snapshot` (service account `openbao-snapshot` in `openbao`, policy `snapshot`, for the hourly job that comes later); the admin AppRole bound to the box's /32 with the IDs from the node folder. Then it revokes the root token it used. Later starts skip it.

expect, once the node play exists: `kubectl -n openbao get pod openbao-0` Ready; `kubectl -n openbao exec openbao-0 -- bao status` shows `Sealed false`; ExternalSecret `external-secrets/openbao-check` Ready once `kv/c1/check` is written.

Not in this part yet: the agent box's path to OpenBao through the Gateway (after the source address is measured, so the admin AppRole's /32 binding still holds), the hourly snapshot job, and the box's wrapper changes (the seal key and IDs on the node, SOPS copies, reseed).

## What it builds

- A VM from `hosts/terraform/home/secrets-store`: VM ID 550 on dev, in pool `dev`, cloned from template 9001.
- The `openbao` role on it:
  - OpenBao from the release RPM, checked against its SHA-256.
  - The static seal, its key at `/etc/openbao/seal/<id>.key`, readable only by user `openbao`.
  - A listener on 443 with TLS. On dev the role makes a self-signed certificate for the name, the address and 127.0.0.1, and copies its public half back to the box.
  - Raft storage in `/opt/openbao/data`.
  - On the first start only, an `initialize` block: the file audit device, KV v2 at `kv/`, AppRole, policies `admin` and `snapshot`, and their two roles. The role restarts OpenBao only before that start, never during it. Once the store is healthy it takes one snapshot through the `snapshot` AppRole, whose secret ID is the block's last request, to prove the block finished. Only then does it rewrite the configuration without the block and delete the ID files it read.
  - Timer `openbao-snapshot.timer`: an hourly Raft snapshot in `/var/lib/openbao-snapshots`, keeping 48.
- On the box, when both this wrapper and the [OPNsense off-box copy](copy-opnsense-backup-off-box.md) are set up (pick 237): timer `secrets-store-offbox.timer` runs `secrets-store-offbox.sh` hourly as user `keys`. It is not installed until the owner's tap (see [Off-box copy](#off-box-copy-of-the-snapshots)).
  - The store's first clients, set from the box through the admin AppRole on every `configure` (`tasks/clients.yml`). Each is written only when the store holds something else, so a second run changes nothing:
    - Login `auth/jwt-c1` (type jwt) for c1's External Secrets Operator. Its role `eso` takes only a token whose subject is `system:serviceaccount:external-secrets:store-openbao` and whose audience is `openbao`, and gives policy `eso-c1`, which reads `kv/data/c1/*` and nothing else. The login holds no key until a rebuild's `openbao` stage writes one.
    - AppRole `rebuild`, from the box's address only, with policy `rebuild-jwt-c1`: it can write `auth/jwt-c1/config` and nothing else. Its two IDs are made once in `/etc/agent-keys/dev/` (`openbao-rebuild-role-id`, `openbao-rebuild-secret-id`, no trailing newline) and never printed. The run proves them with one sign-in and revokes that token and its own admin token.
    - AppRole `snapshot-box` (agent pick 240, `tasks/snapshot_box.yml`), made only once the wrapper's settings say `snapshot_box: true` (`agent_box_secrets_store` in the inventory), which only the owner's install tap sets. Until then `configure` skips it and `snapshot` signs in with the admin AppRole, as before. It is from the box's address only, 5-minute tokens (10 at most), with policy `snapshot-box` plus the `default` policy: `read` on `sys/storage/raft/snapshot` and `create` and `update` on `kv/data/dev/snapshot-mark`, nothing else. The wrapper's `snapshot`, and so the hourly off-box send, signs in with it instead of the admin (D-0038 rules 8 and 12). Its two IDs are made once in `/etc/agent-keys/dev/` (`openbao-snapshot-box-role-id`, `openbao-snapshot-box-secret-id`) and never printed. `configure` proves it without writing anything: the token's policies are exactly `default` and `snapshot-box`, and `sys/capabilities-self` gives exactly `[read]` on the snapshot path and `[create, update]` on the mark, so neither a restore nor a read of the mark is allowed; the forced restore, `kv/data/c1/check`, `kv/metadata/`, the admin policy and its own role hold nothing but `deny`. It is a new credential for agents, so on the install card it is named as an access right as well as a box limit (D-0042 rule 6), one tap. That tap sets `snapshot_box: true`, runs the `agent_box` role to install the wrapper, and then runs `configure`.

## Before you start

- The agent box needs the `secrets-store` wrapper (`plan`, `apply`, `configure`, `recovery`, `status`, `snapshot`, `restore`, `restore-rebuilt [raft-<time>.snap]`, `clear-hold`, `destroy`, run as user `keys`), which the agent_box role installs (#276). A new wrapper changes the box's limits, so the box's self-apply stops on it and a controller apply puts it there (D-0036). Until it is on the box, nothing in this runbook runs.
- The wrapper makes, once, in `/etc/agent-keys/dev/` (user `keys`, 0600): the 32-byte seal key (`openssl rand -out <file> 32`), the admin AppRole's role ID and secret ID (`openssl rand -hex 24` each, with no trailing newline, because the first start reads each file whole), and the VM's SSH key. None is ever printed.
- The private inventory group `secrets_store` holds the VM's name, VM ID, address, cores, memory and disk, and the box's own address.

## Steps

1. Plan the VM.
   `secrets-store plan`
   expect: one VM to add, ID 550, pool `dev`, on VNet `dev`.

2. Make it.
   `secrets-store apply`
   expect: `Apply complete! Resources: 1 added`.

3. Configure it.
   `secrets-store configure`
   expect: the play ends with `OpenBao is up, initialized and unsealed` ok, then the configuration rewritten without its first-start block, and a second run reports `changed=0`.

4. Check it from the box.

   ```sh
   curl -sS --cacert <the fetched certificate> https://<store address>/v1/sys/health
   ```

   expect: `"initialized":true,"sealed":false`.

   The first measurement after the install tap's `configure` (pick 240): `configure` prints `PASS: AppRole snapshot-box holds default and snapshot-box only; capabilities-self: ...`, and then the first `secrets-store snapshot` must print `snapshot raft-<time>.snap`. That run is what shows `create` and `update` on the `data/` path alone let `snapshot-box` write the mark, which the sources state but nothing here had run.

5. Restore with no recovery shares (D-0038 Confirmation 7, pick 239).
   why: prod runs with no recovery shares (D-0038 rule 5), so dev proves first that a store with none takes a snapshot and restores it.
   **The owner's tap first:** `restore` of the secrets store is a delete under D-0042 rule 6, on dev too; it runs only after the owner taps the card that names it and its commit.
   Only on a store with no recovery shares yet: once `/etc/agent-keys/dev/openbao-recovery.json` exists, Confirmation 7 needs a fresh store, made with `destroy`, `apply` and `configure`.
   1. `secrets-store snapshot`
   2. `secrets-store restore`. It runs `secrets-store-restore.sh same` under the wrapper's lock. It picks the newest snapshot of the store's own cluster, sets `kv/dev/snapshot-mark` to `before-restore-<time>`, restores the snapshot plainly, never forced, and waits until a fresh login reads the snapshot's own time back in the mark. It then prints whether the token from before the restore is refused now. That is a measurement, not a check.
      expect: `1b shares ok: no recovery shares yet`, then `PASS: restore: raft-<time>.snap restored (plain) onto the same store; its mark reads back`, and a line `measured: old token: refused` or `still works`.
   3. `secrets-store status`
      expect: `"initialized":true,"sealed":false`.

6. Make the recovery keys.
   why: self-initialization makes none, and the docs warn to make them before they are needed.
   The wrapper logs in as `admin` and calls `sys/rotate/recovery/init` with 3 shares and a threshold of 2. On a store that self-initialized with no recovery keys, that call returns the shares at once ([OpenBao's rotate init API](https://openbao.org/docs/api/system/rotate/init/)). The shares go to `/etc/agent-keys/dev/openbao-recovery.json` and are never printed. That is for dev only, where the store holds nothing of value: a prod store makes none (D-0038 rule 5), and the wrapper refuses any store outside the dev IDs.
   It refuses while a rebuild hold exists. It records the shares' time in `openbao-recovery.made`, taken before it asks for them. After the shares it waits a second and takes a snapshot itself, because from then on `restore` and `restore-rebuilt` refuse any snapshot that is not strictly later than the shares. A restore brings back the recovery keys of the snapshot's time, so an older snapshot would leave the box's shares useless (source: [Performing restore from snapshot invalidates existing auto-unseal recovery keys](https://discuss.hashicorp.com/t/performing-restore-from-snapshot-invalidates-existing-auto-unseal-recovery-keys/55326), about Vault).
   expect: `recovery shares written to the keys folder (not printed)`, then `snapshot raft-<time>.snap, <n> bytes`.

7. Register the dev cluster's key.
   why: External Secrets signs in with a token the cluster signed; the store checks it against the key the rebuild wrote.
   The rebuild's `openbao` stage does it, on every rebuild ([rebuild-k8s-layer-with-one-command.md](rebuild-k8s-layer-with-one-command.md)), once `rebuild.env` sets `OPENBAO_ADDR`, `OPENBAO_CACERT` and the AppRole `rebuild`'s two ID files.
   expect: `openbao: PASS: the cluster's signing key and issuer ... are in auth/jwt-c1/config` in the run's log.

8. Prove External Secrets reads from the store (D-0038 Confirmation 2).
   why: one non-secret value through the whole path (the cluster's token, the store's login, policy `eso-c1`) before any real secret moves.
   With `k8s_gitops_source_openbao_in_cluster` true in the dev inventory, the root Application turns on the secret-store app's `openbao` store, which adds ClusterSecretStore `openbao`, service account `store-openbao` and ExternalSecret `openbao-check` in namespace `external-secrets`, pointed at OpenBao inside the cluster ([Inside the cluster](#inside-the-cluster-d-0058-dev-first)), not at this VM. `configure` wrote the value it reads, `kv/c1/check`. Every other ExternalSecret keeps naming store `c1`. On c1, where it is false, the app renders as before.
   expect: the dev rebuild's `apps` stage passes, since it waits for every ExternalSecret to be Ready, this one too.

9. Restart test.
   `sudo systemctl restart openbao` on the VM, through the wrapper's `configure`.
   expect: health shows `"sealed":false` again with no person.

10. Snapshot off the VM.
   `secrets-store snapshot`
   expect: `snapshot raft-<time>.snap, <n> bytes` with n above 0; the file is in `/etc/agent-keys/dev/openbao-snapshots/`, which keeps 24. Beside it, `raft-<time>.snap.cluster` holds the store's cluster ID from `sys/health` (not a secret).
   It signs in as AppRole `snapshot-box`, not the admin, once the install tap has set `snapshot_box: true`; until then it signs in with the admin AppRole. Every snapshot writes one key into the store first: `kv/dev/snapshot-mark`, which holds the snapshot's own time and no secret, so a restore can prove which snapshot came back. It is the only key the wrapper writes on each run. KV keeps 10 versions of it and deletes older ones, since the mount sets no `max_versions` ([OpenBao KV v2 API](https://openbao.org/docs/api/secret/kv/kv-v2/)).

11. Restore drill.
   why: a backup counts only once it has been restored.
   `secrets-store snapshot`, then `secrets-store restore` (the owner's tap first, as in step 5). This quick drill restores over the live dev store; it is not D-0038 Confirmation 4, which restores into a throwaway server.
   expect: the same `PASS: restore:` line as step 5, with `1b shares ok: snapshot is later than the shares`. The full drill is D-0038 Confirmation 5, in [Rebuild and restore](#rebuild-and-restore-d-0038-confirmation-5).

    The weekly drill, D-0038 Confirmation 4, needs nothing typed. `configure` installs `openbao-drill.timer` on the VM and runs the drill once (tag `drill`). Unit `openbao-drill.service` runs `/usr/local/libexec/openbao-drill.sh`:
    - it has only a loopback device, so the throwaway can't reach the live store;
    - its storage and the restored audit log sit in temporary file systems that go with the unit;
    - it starts a throwaway server from `/etc/openbao/drill.hcl` on `127.0.0.1:8300`, initializes it with no recovery shares, and force-restores the newest snapshot into it;
    - it checks that the throwaway's own token is refused, then signs in with the store's snapshot AppRole and reads that login's policy back;
    - it stops the throwaway and deletes its storage.

    Around it, `configure` reads the live store's Raft peers, leader and term through the admin AppRole, before and after. That check runs only when `configure` runs the drill. The weekly timer has no admin token, so on its own runs the live store is kept apart by `PrivateNetwork=yes` alone.
    expect: 10 `ok` step lines, `PASS: restore drill: raft-<time>.snap restored into a throwaway server; the snapshot login and its policy read back; copy deleted`, then `PASS: live store unchanged by the drill`. The step lines name steps and the snapshot's file name only.

12. The owner's sign-in to the web page (agent pick 233).
    why: the owner enters keys, such as the VPS provider key at `kv/vps/provider-key`, in the store's web page with the lab account they already have, with no paste in chat, no command and no Mac step.
    On dev the inputs come from the dev rebuild, so nothing is typed: once the store exists, `rebuild up` (stage `identity-keycloak`) adds client `openbao` for the store's address, a `lab-viewers` user `dev-viewer` and a second `lab-admins` user `dev-admin2`, then writes `openbao-oidc.json` in its env folder (Keycloak's issuer, the dev Gateway's address, the dev CA's root). The next `secrets-store configure` reads that file and the rebuild's `identity.env`, and passes `openbao_oidc` (`discovery_url`, `values_file`, `ui_names`, `owner_user` set to `dev-admin`, `ca_pem_file`, `pin_address`, because on dev the lab's names resolve to prod's Gateway) and `openbao_oidc_proof`. **Not runnable yet:** the box's `rebuild` wrapper passes the store's address only since #302, and `secrets-store` reads the file only since agent pick 233. Both wrappers are box limits (D-0036 rule 3), so both wait for the box's limits to be applied. Then `secrets-store configure`, tag `owner_signin`:
    - login `auth/oidc` (type jwt) with Keycloak's realm as its discovery URL and client `openbao`;
    - role `owner`: only the owner, by two `bound_claims` that must both match: group `lab-admins` and `preferred_username` equal to `owner_user`. Anyone the inventory adds to `lab-admins` later is still refused. `max_age` 300, a 15-minute token with policy `vps-intake` and nothing else;
    - policy `vps-intake`: create, update and read `kv/data/vps/*`, list and read its metadata, list `kv/metadata/`. No delete, no `sys/`, no `auth/`.

    On prod, `owner_user` is the owner's user name from the private inventory.
    On dev, `openbao_oidc_proof` (`admin_user`, `viewer_user`, `other_admin_user`, `gateway_address`, `verify`) runs `files/oidc-check.py`, which makes the web page's calls and prints step names and HTTP codes only.
    expect: `PASS: owner sign-in: the owner with the code gets vps-intake only; a viewer and another admin are refused`, after 18 `ok` steps: the password alone stops at the code form, the code gives a token with `vps-intake`, that token writes and reads `kv/vps/proof` and gets 403 on `kv/data/c1/check` and `sys/policies/acl/admin`, a `lab-viewers` user gets through Keycloak but not the store, and so does `dev-admin2`, a `lab-admins` member with a good code who is not the owner.

    **Limits:**
    - The one-time code is checked by Keycloak only. OpenBao's own login MFA fails in the web page with OIDC ([openbao#3281](https://github.com/openbao/openbao/issues/3281)), and the `amr` claim is unreliable ([keycloak#54497](https://github.com/keycloak/keycloak/issues/54497)).
    - The realm seeds each admin's password and code seed from the values file. Anyone holding that file can make the owner's password and code, so a sign-in proves the owner only as far as that file stays with them. Every sign-in is in the store's audit log with the user name.
    - Safari's sign-in window fails on OpenBao 2.7.x for some users ([openbao#4308](https://github.com/openbao/openbao/issues/4308)). Use another browser.
    - The web page itself is first used by the owner; the dev proof drives its calls, not a browser.
    - Prod: the login is a new access right, so it is set only after the owner's tap (D-0042 rule 6).

## Rebuild and restore (D-0038 Confirmation 5)

Pick 238. **The owner's tap first:** a `destroy` or `restore` of the secrets store is a delete under D-0042 rule 6, on dev too, so this sequence runs only after the owner taps the card that names it and its commit. No other person takes any step.

1. `secrets-store snapshot`. It writes `kv/dev/snapshot-mark` with its time, then saves the snapshot and its `.cluster` file.
2. `secrets-store destroy`. Before it removes the VM, it writes the hold `/var/lib/agent-box/state/secrets-store.rebuilding`.
3. `secrets-store plan`, `apply` and `configure`. The rebuilt store initializes itself, with a new cluster ID. While the hold exists, `secrets-store snapshot` refuses, and, once the VM is back, the hourly off-box send prints `skipped: store rebuild in progress` and takes no snapshot.
4. `secrets-store restore-rebuilt`. It runs `secrets-store-restore.sh rebuilt` under the wrapper's lock:
   1. picks the newest snapshot whose `.cluster` names another cluster than the store's current one; one of the rebuilt store, or one with no `.cluster` file, is never picked; once recovery shares exist, the snapshot must be later than them (step 6);
   2. refuses unless `kv/` holds nothing but `c1/check`, the fixed word `configure` writes; a listing that answers anything but 200 or 404 refuses too;
   3. tries the plain restore. Only if OpenBao refuses it with "possibly the snapshot is using a different set of unseal keys" does it use the forced one. That text is a Vault user's report, not OpenBao's own (source: [Raft: how to restore from 3-node HA cluster to 1-node DR instance](https://discuss.hashicorp.com/t/raft-how-to-restore-from-3-node-ha-cluster-to-1-node-dr-instance/20572)). If OpenBao words it otherwise, the run stops as `other refusal`, and the text in the script is changed once measured;
   4. waits for `sys/health` 200 and for its own token from before the restore to be refused;
   5. signs in again and reads `kv/dev/snapshot-mark`, which must hold the picked snapshot's time;
   6. removes the hold.

   expect: seven `ok` step lines (1, 1b and 2 to 6), step 3 saying `plain` or `forced`, then `PASS: restore-rebuilt: raft-<time>.snap restored (<how>) onto the rebuilt store; its mark reads back; hold removed`. The first run's `plain` or `forced` answers the open question whether the same static seal key passes the plain restore.
5. `secrets-store configure` again. expect `changed=0`.

If the rebuilt store is to stay as it is, with no restore, run `secrets-store clear-hold`. It gives up the restore, so it runs only on the owner's tap, on the same card line as `destroy` and `restore-rebuilt` (item 21). It needs `sys/health` to answer 200. While the hold exists, no snapshot runs, so rotation cannot remove the earlier store's snapshots, and those box copies may be the only ones. So `clear-hold` first moves every snapshot not of the current cluster, with its `.cluster` file, into `/etc/agent-keys/dev/openbao-snapshots-kept/`, never overwriting a file there. Rotation never reads that folder. Then it removes the hold, so snapshots and the hourly send run again. Nothing is deleted.

The kept snapshots are not sent off the box. **Removing anything from the kept folder is a delete under D-0042 rule 6, so it needs the owner's tap**, and no wrapper does it. To restore a kept snapshot later, run `secrets-store destroy` first (the owner's tap), so its hold stops every snapshot and rotation cannot remove the file once it is back. Then run `plan`, `apply` and `configure`, move the snapshot and its `.cluster` file back into `openbao-snapshots/`, and run `secrets-store restore-rebuilt raft-<time>.snap` with that file's exact name. Without the name it would take the newest snapshot of any earlier store, which after more than one rebuild is not the kept one. With the name it restores that file only, refuses it if it is missing, has no `.cluster` file or is of the current store, and names it on the `PASS` line. Its empty-store guard refuses any store but a fresh rebuild.

The admin policy can call the forced restore (`sys/storage/raft/snapshot-force`) only for this. `secrets-store restore` stays plain and never forces.

## Off-box copy of the snapshots

Pick 237, proposed D-0038 rule 8. **Not installed yet:** it is a box limit, and a delete (the daily prune) under D-0042 rule 6, so it waits for the owner's tap. It also waits on the blocker in [the bundle's runbook](make-the-box-secrets-bundle.md#before-you-start): no agent or pipeline identity may hold role-assignment rights on the backup vault or container.

Each hour, while the box is up, `secrets-store-offbox.sh`:

1. Skips with `secrets-store-offbox: skipped: no store` and succeeds when the wrapper's OpenTofu state holds no store VM. Dev is often torn down. When the VM is in the state but `sys/health` does not answer 200, the run fails (rule 9).
2. Runs `secrets-store snapshot`, which signs in with AppRole `snapshot-box` (the admin AppRole until the install tap sets `snapshot_box: true`) and copies a snapshot into `/etc/agent-keys/dev/openbao-snapshots/` (keeps 24).
3. Requires the escrow of pick 222's restic password, as the OPNsense copy does. With no current copy in the vault, nothing is sent.
4. Uses its own repository, `azure:opnsense-backup:/openbao-dev` (`agent_box_secrets_store_offbox.repository`). It refuses the OPNsense repository, a path inside it, or one that holds it, compared the way restic reads an `azure:` path: `azure:c:p`, `azure:c:/p` and `azure:c://p/` are one repository, and `azure:c:/` is the whole container. It makes its repository on the first run, only when restic says it does not exist (exit 10); any other error fails the run.
5. Backs the snapshot up under tag `openbao-dev`, then forgets past 48 hourly, 14 daily and 6 monthly, grouped by host and tags. The first run from 03:00 UTC each day also prunes, which deletes older snapshots from Azure for good.
6. Reads the snapshot back and requires the same bytes. It does not open it: only a store with the seal key can, and the weekly drill proves that on the VM.

expect: `secrets-store-offbox: sent raft-<time>.snap (<n> bytes) off the box; it reads back the same`, and once a day `pruned the repository (once a day)`.

If the box is down, nothing goes off-site; the VM keeps its own 48 hourly snapshots and Proxmox's nightly backup.

**Box lost (break-glass, Activation gate item 7).** The owner alone, with their own Azure sign-in:

1. Grant their own account Key Vault Secrets User on the backup vault and Storage Blob Data Reader on the container.
2. Read the restic password and the box's age identity, and restore the newest secrets bundle as [its runbook](make-the-box-secrets-bundle.md#recover-the-bundle-when-the-box-is-lost-break-glass) says; the bundle holds the seal key.
3. `restic -r azure:opnsense-backup:/openbao-dev restore --tag openbao-dev latest --target <folder>`.
4. Rebuild the store from code with that seal key in the keys folder, put the snapshot and its `.cluster` file (both are in the restic snapshot) in `/etc/agent-keys/dev/openbao-snapshots/`, and run `secrets-store restore-rebuilt`.
5. Take both roles away.

## Remove it

Take a last snapshot with `secrets-store snapshot`, which copies it to the box's keys folder, then `secrets-store destroy` (the owner's tap: a delete under D-0042 rule 6). The seal key in the box's keys folder is what reads that snapshot again: after `apply` and `configure`, `secrets-store restore-rebuilt` puts it back, as in [Rebuild and restore](#rebuild-and-restore-d-0038-confirmation-5). While no store VM exists, the hourly off-box send skips.

## If it fails

- The health check never turns 200: read `journalctl -u openbao`. A seal error means the key file is missing or not 32 bytes.
- The first start failed half way: self-initialization does not run again on storage that holds data. Destroy the VM and start over; nothing is in it yet.
- The restore drill fails: read `journalctl -u openbao-drill`. The step line names the step that failed, and the throwaway's own log is gone with its temporary file system. To run it again, use `systemctl start openbao-drill.service` on the VM. It never touches the live store's data.
- Step 8 (`known login`) fails, but steps 5 to 7 passed: the snapshot AppRole's IDs on the VM may differ from the ones in the newest snapshot, for example when that snapshot is older than a rebuild of the VM, which makes the IDs again. The restored data then holds the old IDs, so the login is refused although the restore worked. That is a false fail: check that `openbao-snapshot.service` succeeds, and once a snapshot is taken with the current IDs, run the drill again.
- The drill passed but `configure` says the live store's Raft state changed: stop the timer (`systemctl disable --now openbao-drill.timer`) and tell the owner. The throwaway should never be able to reach the live store.
- `secrets-store-offbox: the store's VM is in the wrapper's state, but sys/health answered ...`: the store is sealed, broken or gone without `destroy`. Check `secrets-store status`. If the VM was removed outside the wrapper, its state still lists it; fix that before anything else.
- `secrets-store-offbox: restic could not open the repository (exit 12) ...`: the password is not the repository's; the job never makes a new one over it. See the OPNsense runbook's password versions.
- `secrets-store: another secrets-store run is going`: the hourly pull met a session's run of the wrapper (its lock is taken with `flock -n`), so that hour's off-box send fails red; the next hour's run sends. During Rebuild and restore this can happen in steps 1 to 3, before the VM is back with the hold in place.
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
- `secrets-store: AppRole snapshot-box did not sign in`: its IDs are missing from the keys folder, or the store does not hold them yet. With `snapshot_box: true` in the settings, run `configure`, which makes and sets them, then `snapshot` again. Never set `snapshot_box` by hand: it is the install tap's (an access right and a box limit).
- `configure` fails at `The rights are exactly the two paths'`: the store's `snapshot-box` login holds more or less than its two paths. The message lists every path's rights (no secrets). Nothing uses the login until it passes; tell the owner.
- Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Set up the owner's desktop VM](set-up-the-desktop.md), the wrapper this one copies
