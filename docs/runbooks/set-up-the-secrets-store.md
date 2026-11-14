---
title: Set up the lab's secrets store (OpenBao) on dev
status: draft
kind: automated
trigger: once per env, after D-0038's picks; again after the store's VM is rebuilt
runner: an agent session on the agent box, through the `secrets-store` wrapper (not on the box yet; see Before you start)
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

- The agent box needs a `secrets-store` wrapper, the same shape as `desktop`: `plan`, `apply`, `configure`, `destroy`, run as user `keys`. Adding a wrapper changes the box's limits, so it waits for the owner's typed go (D-0036). It is a separate PR. Until it exists, nothing in this runbook runs.
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
   The wrapper logs in as `admin` and calls `sys/rotate/recovery/init` with 3 shares and a threshold of 2. On a store that self-initialized with no recovery keys, that call returns the shares at once ([OpenBao's rotate init API](https://openbao.org/docs/api/system/rotate/init/)). The shares go to `/etc/agent-keys/dev/openbao-recovery.json` and are never printed. That is for dev only, where the store holds nothing of value: a prod store's shares go only to the owner's Mac, never to the box (D-0038 rule 5), and the wrapper refuses any store outside the dev IDs.
   expect: `recovery shares written to the keys folder (not printed)`.

6. Register the dev cluster's key.
   why: External Secrets signs in with a token the cluster signed; the store checks it against the key the rebuild wrote.
   The rebuild's `openbao` stage does it, on every rebuild ([rebuild-k8s-layer-with-one-command.md](rebuild-k8s-layer-with-one-command.md)), once `rebuild.env` sets `OPENBAO_ADDR`, `OPENBAO_CACERT` and the AppRole `rebuild`'s two ID files.
   expect: `openbao: PASS: the cluster's signing key and issuer ... are in auth/jwt-c1/config` in the run's log.

7. Restart test.
   `sudo systemctl restart openbao` on the VM, through the wrapper's `configure`.
   expect: health shows `"sealed":false` again with no person.

7. Snapshot off the VM.
   `secrets-store snapshot`
   expect: `snapshot raft-<time>.snap, <n> bytes` with n above 0; the file is in `/etc/agent-keys/dev/openbao-snapshots/`, which keeps 24.

8. Restore drill.
   why: a backup counts only once it has been restored.
   Write a test key, take a snapshot, delete the key, then `secrets-store restore`. This quick drill restores over the live dev store; it is not D-0038 Confirmation 4, which restores into a throwaway server.
   expect: `restored raft-<time>.snap`, and the test key reads back. The full drill is D-0038 Confirmation 5: `destroy`, `plan`, `apply`, `configure`, then `restore`, with no person.

## Remove it

Take a last snapshot with `secrets-store snapshot`, which copies it to the box's keys folder, then `secrets-store destroy`. The seal key in the box's keys folder is what reads that snapshot again: after `apply` and `configure`, `secrets-store restore` puts the newest one back.

## If it fails

- The health check never turns 200: read `journalctl -u openbao`. A seal error means the key file is missing or not 32 bytes.
- The first start failed half way: self-initialization does not run again on storage that holds data. Destroy the VM and start over; nothing is in it yet.
- Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Set up the owner's desktop VM](set-up-the-desktop.md), the wrapper this one copies
