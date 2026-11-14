---
title: Set up the lab's secrets store (OpenBao) on dev
status: draft
kind: automated
trigger: once per env, after D-0038's picks; again after the store's VM is rebuilt
runner: an agent session on the agent box, through the `secrets-store` wrapper (in the agent_box role since #276; on the box once that role is applied, see Before you start)
outcome: one AlmaLinux 10 VM on VNet dev runs OpenBao 2.7.2, starts and unseals with no person, initialized by itself with audit, KV v2 and two AppRoles, takes an hourly Raft snapshot, and holds c1's External Secrets login and the rebuild's AppRole
needs: the agent box; the agents' Proxmox token with rights on pool `dev`; template 9001; a free dev address; the private inventory values listed below
private-values: [store-name, store-address, box-address, seal-key, admin-role-id, admin-secret-id, rebuild-role-id, rebuild-secret-id, store-ssh-key]
files: [hosts/terraform/home/secrets-store/, hosts/ansible/roles/openbao/, hosts/ansible/playbooks/openbao.yml, hosts/ansible/playbooks/k8s-openbao-auth.yml]
last-tested: not yet run
superseded-by:
---

# Set up the lab's secrets store (OpenBao) on dev

**Status:** draft, not run. Written on 2026-11-14 from the code in this PR and the OpenBao 2.7.2 docs and package files. Every "expect" below is what the docs say, not yet seen on the lab. The record is [D-0038](../decisions/README.md) (proposed).

## What it builds

- A VM from `hosts/terraform/home/secrets-store`: VM ID 550 on dev, in pool `dev`, cloned from template 9001.
- The `openbao` role on it:
  - OpenBao from the release RPM, checked against its SHA-256.
  - The static seal, its key at `/etc/openbao/seal/<id>.key`, readable only by user `openbao`.
  - A listener on 443 with TLS. On dev the role makes a self-signed certificate for the name, the address and 127.0.0.1, and copies its public half back to the box.
  - Raft storage in `/opt/openbao/data`.
  - On the first start only, an `initialize` block: the file audit device, KV v2 at `kv/`, AppRole, policies `admin` and `snapshot`, and their two roles. The role restarts OpenBao only before that start, never during it. Once the store is healthy it takes one snapshot through the `snapshot` AppRole, whose secret ID is the block's last request, to prove the block finished. Only then does it rewrite the configuration without the block and delete the ID files it read.
  - Timer `openbao-snapshot.timer`: an hourly Raft snapshot in `/var/lib/openbao-snapshots`, keeping 48.
  - The store's first clients, set from the box through the admin AppRole on every `configure` (`tasks/clients.yml`). Each is written only when the store holds something else, so a second run changes nothing:
    - Login `auth/jwt-c1` (type jwt) for c1's External Secrets Operator. Its role `eso` takes only a token whose subject is `system:serviceaccount:external-secrets:store-openbao` and whose audience is `openbao`, and gives policy `eso-c1`, which reads `kv/data/c1/*` and nothing else. The login holds no key until a rebuild's `openbao` stage writes one.
    - AppRole `rebuild`, from the box's address only, with policy `rebuild-jwt-c1`: it can write `auth/jwt-c1/config` and nothing else. Its two IDs are made once in `/etc/agent-keys/dev/` (`openbao-rebuild-role-id`, `openbao-rebuild-secret-id`, no trailing newline) and never printed. The run proves them with one sign-in and revokes that token and its own admin token.

## Before you start

- The agent box needs the `secrets-store` wrapper (`plan`, `apply`, `configure`, `recovery`, `status`, `snapshot`, `restore`, `destroy`, run as user `keys`), which the agent_box role installs (#276). A new wrapper changes the box's limits, so the box's self-apply stops on it and a controller apply puts it there (D-0036). Until it is on the box, nothing in this runbook runs.
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

5. Make the recovery keys.
   why: self-initialization makes none, and the docs warn to make them before they are needed.
   The wrapper logs in as `admin` and calls `sys/rotate/recovery/init` with 3 shares and a threshold of 2. On a store that self-initialized with no recovery keys, that call returns the shares at once ([OpenBao's rotate init API](https://openbao.org/docs/api/system/rotate/init/)). The shares go to `/etc/agent-keys/dev/openbao-recovery.json` and are never printed. That is for dev only, where the store holds nothing of value: a prod store makes none (D-0038 rule 5), and the wrapper refuses any store outside the dev IDs.
   expect: `recovery shares written to the keys folder (not printed)`.

6. Register the dev cluster's key.
   why: External Secrets signs in with a token the cluster signed; the store checks it against the key the rebuild wrote.
   The rebuild's `openbao` stage does it, on every rebuild ([rebuild-k8s-layer-with-one-command.md](rebuild-k8s-layer-with-one-command.md)), once `rebuild.env` sets `OPENBAO_ADDR`, `OPENBAO_CACERT` and the AppRole `rebuild`'s two ID files.
   expect: `openbao: PASS: the cluster's signing key and issuer ... are in auth/jwt-c1/config` in the run's log.

7. Prove External Secrets reads from the store (D-0038 Confirmation 2).
   why: one non-secret value through the whole path (the cluster's token, the store's login, policy `eso-c1`) before any real secret moves.
   With `k8s_gitops_source_openbao_address` and `k8s_gitops_source_openbao_ca_file` set in the dev inventory, the root Application passes them to the secret-store app, which adds ClusterSecretStore `openbao`, service account `store-openbao` and ExternalSecret `openbao-check` in namespace `external-secrets`. `configure` wrote the value it reads, `kv/c1/check`. Every other ExternalSecret keeps naming store `c1`. On c1, where they are unset, the app renders as before.
   expect: the dev rebuild's `apps` stage passes, since it waits for every ExternalSecret to be Ready, this one too.

8. Restart test.
   `sudo systemctl restart openbao` on the VM, through the wrapper's `configure`.
   expect: health shows `"sealed":false` again with no person.

9. Snapshot off the VM.
   `secrets-store snapshot`
   expect: `snapshot raft-<time>.snap, <n> bytes` with n above 0; the file is in `/etc/agent-keys/dev/openbao-snapshots/`, which keeps 24.

10. Restore drill.
   why: a backup counts only once it has been restored.
   Write a test key, take a snapshot, delete the key, then `secrets-store restore`. This quick drill restores over the live dev store; it is not D-0038 Confirmation 4, which restores into a throwaway server.
   expect: `restored raft-<time>.snap`, and the test key reads back. The full drill is D-0038 Confirmation 5: `destroy`, `plan`, `apply`, `configure`, then `restore`, with no person.

    The weekly drill, D-0038 Confirmation 4, needs nothing typed. `configure` installs `openbao-drill.timer` on the VM and runs the drill once (tag `drill`). Unit `openbao-drill.service` runs `/usr/local/libexec/openbao-drill.sh`:
    - it has only a loopback device, so the throwaway can't reach the live store;
    - its storage and the restored audit log sit in temporary file systems that go with the unit;
    - it starts a throwaway server from `/etc/openbao/drill.hcl` on `127.0.0.1:8300`, initializes it with no recovery shares, and force-restores the newest snapshot into it;
    - it checks that the throwaway's own token is refused, then signs in with the store's snapshot AppRole and reads that login's policy back;
    - it stops the throwaway and deletes its storage.

    Around it, `configure` reads the live store's Raft peers, leader and term through the admin AppRole, before and after. That check runs only when `configure` runs the drill. The weekly timer has no admin token, so on its own runs the live store is kept apart by `PrivateNetwork=yes` alone.
    expect: 10 `ok` step lines, `PASS: restore drill: raft-<time>.snap restored into a throwaway server; the snapshot login and its policy read back; copy deleted`, then `PASS: live store unchanged by the drill`. The step lines name steps and the snapshot's file name only.

11. The owner's sign-in to the web page (agent pick 233).
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

## Remove it

Take a last snapshot with `secrets-store snapshot`, which copies it to the box's keys folder, then `secrets-store destroy`. The seal key in the box's keys folder is what reads that snapshot again: after `apply` and `configure`, `secrets-store restore` puts the newest one back.

## If it fails

- The health check never turns 200: read `journalctl -u openbao`. A seal error means the key file is missing or not 32 bytes.
- The first start failed half way: self-initialization does not run again on storage that holds data. Destroy the VM and start over; nothing is in it yet.
- The restore drill fails: read `journalctl -u openbao-drill`. The step line names the step that failed, and the throwaway's own log is gone with its temporary file system. To run it again, use `systemctl start openbao-drill.service` on the VM. It never touches the live store's data.
- Step 8 (`known login`) fails, but steps 5 to 7 passed: the snapshot AppRole's IDs on the VM may differ from the ones in the newest snapshot, for example when that snapshot is older than a rebuild of the VM, which makes the IDs again. The restored data then holds the old IDs, so the login is refused although the restore worked. That is a false fail: check that `openbao-snapshot.service` succeeds, and once a snapshot is taken with the current IDs, run the drill again.
- The drill passed but `configure` says the live store's Raft state changed: stop the timer (`systemctl disable --now openbao-drill.timer`) and tell the owner. The throwaway should never be able to reach the live store.
- Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Set up the owner's desktop VM](set-up-the-desktop.md), the wrapper this one copies
