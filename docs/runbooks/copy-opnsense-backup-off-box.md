---
title: Copy the OPNsense configuration backups off the agent box
status: draft
kind: manual
trigger: once, after the box keeps daily OPNsense copies (set-up-the-box-lifeline.md); again if the box is rebuilt or the copy app's certificate expired
runner: an agent lane on the controller, with the Azure CLI signed in as agent-azure, the owner's yes to the Key Vault was given on 2026-11-14 at 03:07 UTC (a decision-card tap on #244)
outcome: every day the box's OPNsense configuration copies go, encrypted, to their own container in the Azure backup account, under their own identity and a restic password made on the box, whose one off-box copy sits in a Key Vault the box can write but not read; the newest copy is read back
needs: the box's daily OPNsense copies (agent_box_opnsense_backup); hosts/terraform/azure/backup applied before (back-up-c1-off-box.md); the Azure CLI on the controller signed in as agent-azure (Owner on the subscription); the box leaves through the home's public address, the only one the storage account and the vault answer
private-values: [c1-backup-azure-storage-account, opnsense-offbox-vault-name, opnsense-offbox-client-id, opnsense-offbox-app-object-id, azure-tenant-id]
files: [hosts/terraform/azure/backup/, hosts/ansible/roles/agent_box/tasks/opnsense_offbox.yml, hosts/ansible/roles/agent_box/files/opnsense-offbox.sh, hosts/ansible/roles/agent_box/files/opnsense-escrow.py, hosts/ansible/roles/k8s_backup/files/c1-backup-azure-cert.py, .github/hosts-check/tests/test_opnsense_offbox.sh, .github/hosts-check/tests/test_opnsense_escrow.sh]
last-tested: "2026-11-14, from real runs reported by the Mac session, and offline tests: step 1, the Azure apply, ran, and its plan showed no changes once opnsense_vault_name was in the private azure tfvars (the variable is needed); the box ran the role, then its first OPNsense backup at 06:11:26 UTC kept config-20261114T061126Z.xml (112,112 bytes, valid XML) with the box-backup key, and the first off-box copy printed all four expect lines in order, read back identical and wrote the vault escrow; both timers are enabled, next at 14:30:12 UTC (backup) and 15:08:14 UTC (off-box copy). The Azure folder, opnsense-offbox.sh and opnsense-escrow.py also passed offline tests. Not yet run: a recovery from the vault, and a replay on a fresh machine"
superseded-by:
---

# Copy the OPNsense configuration backups off the agent box

**Status:** draft. Written 2026-11-14 from the code in this change and tested offline only. Azure side applied 2026-11-14: the owner said yes to the Key Vault (a new billable resource) with a decision-card tap at 03:07 UTC, and the Azure folder's tofu state now lists all seven off-box resources (the `opnsense-backup` container, its app, the Key Vault and its custom role, and their assignments; the apply's own time was not recorded). The box's side then ran on 2026-11-14 (see `last-tested`): the first backup, the first off-box copy and both timers. A recovery from the vault has not been tried.

## Why

The box keeps a daily copy of OPNsense's configuration ([set-up-the-box-lifeline.md](set-up-the-box-lifeline.md)). The box sits on the same Proxmox host as OPNsense, so if that host's disk is lost, both go together.

The owner chose the existing Azure backup account for the copy off the box (the owner's card, 2026-11-14 02:23 UTC, "Azure, own folder and key"; agent pick 222). The copy gets its own container, its own credential and its own restic password. c1's backup identity can't touch these copies, and this one can't touch c1's.

## What is built (pick 222)

| Piece | Where |
|---|---|
| **Container and app.** Container `opnsense-backup` in the same storage account, and app registration `opnsense-backup` with Storage Blob Data Contributor on that container only. c1's apps keep their roles on the `c1-backup` container only | `hosts/terraform/azure/backup` (`main.tf`) |
| **The box's sign-in.** The keys user makes a key and certificate on the box, in `/etc/agent-keys/opnsense-offbox/` (0600), and the key never leaves the box. The role brings back only the public certificate. The controller adds it to the app as agent-azure, the app's owner. After that, the box's daily run rolls it 30 days before it expires, through Graph `addKey`, which needs no permission for an app's own keys | `azure-cert.py` (the c1 nodes' `c1-backup-azure-cert.py`), `tasks/opnsense_offbox.yml` |
| **The restic password, made on the box.** `opnsense-escrow.py` makes it on the first run, as the keys user, in `/etc/agent-keys/opnsense-offbox/restic-password.txt` (0600) | `files/opnsense-escrow.py` |
| **Its one off-box copy, in a Key Vault.** The vault uses RBAC only, has purge protection and 90 days of soft delete, and answers the home's address only. The box writes the password straight into it as a secret version tagged with a salted PBKDF2-SHA256 hash of the password (600,000 rounds), since anyone who can read the vault's metadata can read tags. A custom role lets the OPNsense app only set secrets and read their metadata, so the box can't read the password back or delete a version. c1's apps hold nothing on the vault. Each day the box compares the newest version's tag with its file and writes again if they differ. No repository is made and nothing is copied until the vault holds the current password | `hosts/terraform/azure/backup` (`azurerm_key_vault.opnsense`, `azurerm_role_definition.opnsense_escrow`), `files/opnsense-escrow.py` |
| **Daily timer `opnsense-offbox`.** It runs at 15:00 UTC, after the 14:30 fetch, as the keys user. It rolls the certificate when due, checks the password's copy, then backs up `/var/lib/agent-box/opnsense-backup`. It keeps 30 daily and 12 monthly snapshots and prunes. Last, it reads the newest configuration back and compares it with the file on the box | `files/opnsense-offbox.sh`, `templates/opnsense-offbox.*.j2` |

No secret passes through a transcript, the repository, the controller or OpenTofu state. tofu makes the vault and the role, never the secret. The certificate key and the password are both made on the box, and the password leaves only over HTTPS into the vault.

## Who makes what

| What | Made by | Identity | The owner's part |
|---|---|---|---|
| Container, app registration, its service principal and container role | `tofu apply` of `hosts/terraform/azure/backup`, on the controller | agent-azure (Owner on the subscription, Graph `Application.ReadWrite.OwnedBy`) | the owner's go to apply (given 2026-11-14 at 03:07 UTC) |
| Key Vault, the custom escrow role and its assignment on the vault | the same apply | agent-azure; Owner holds the `Microsoft.Authorization/roleDefinitions/write` and `roleAssignments/write` it needs | **the owner's yes to the vault, a new billable resource** (the owner's standing rule of 2026-11-09 03:33 UTC: nothing billable beyond the storage account without asking; the yes itself was a decision-card tap on 2026-11-14 at 03:07 UTC) |
| The box's first certificate on the app | the box's role, `--tags opnsense_offbox`, from the controller | agent-azure, the app's owner, through `az` | none |
| The password and its vault copy | the box itself, on its first daily run | the OPNsense app, signed in with the box's certificate | none |
| Reading the password for a recovery | the owner, only then | the owner's own account, after giving their own account Key Vault Secrets User on the vault | the owner's step at recovery time |

Nothing here needs the owner's own Azure rights except the recovery read.

## Steps (the owner's yes to the vault was given 2026-11-14 at 03:07 UTC)

1. (Agent, on the controller) Set `opnsense_vault_name` in `azure.tfvars` to a free name (required: on 2026-11-14 the plan showed no changes only once it was set). Then apply the Azure folder as in [back-up-c1-off-box.md, step A1](back-up-c1-off-box.md#azure-blob-without-a-key):

   ```sh
   cd hosts/terraform/azure/backup
   tofu plan -var-file=azure.tfvars -out=backup.tfplan
   tofu apply backup.tfplan
   tofu output
   ```

   why: the container, the app, the vault and their roles are code, so a rebuild makes them the same way. This is management-plane work, which the network rules don't block.
   ※ azurerm 5.11.0: `azurerm_storage_container`, `azurerm_key_vault`, `azurerm_role_definition`, `azurerm_role_assignment`; azuread 3.10.0: `azuread_application`
   expect: the plan adds seven resources and changes nothing else: the container, the app, its service principal, its container role, the vault, the escrow role and its assignment. If it changes or destroys anything of c1's, stop. The outputs add `opnsense_restic_repository`, `opnsense_client_id`, `opnsense_app_object_id` and `opnsense_vault_url`.

2. In the private inventory, set `agent_box_opnsense_offbox` from step 1's outputs, then run the box's role:

   ```yaml
   agent_box_opnsense_offbox:
     account: <storage_account_name>
     client_id: <opnsense_client_id>
     tenant_id: <tenant_id>
     app_object_id: <opnsense_app_object_id>
     vault_url: <opnsense_vault_url>
   ```

   ```sh
   ansible-playbook -i inventories/home/ playbooks/agent-box.yml --tags opnsense_offbox
   ```

   why: the run does the following:
   - installs restic 0.19.1, checked by SHA-256;
   - makes the box's key and certificate;
   - uploads the public certificate as agent-azure, then waits until Entra ID accepts it steadily;
   - records the certificate's key ID and removes any other certificate on the app;
   - turns on the timer.

   No secret is copied to the box.
   ※ [back-up-c1-off-box.md, step A3](back-up-c1-off-box.md#azure-blob-without-a-key)
   expect: `failed=0`; `systemctl list-timers opnsense-offbox.timer` on the box lists the timer.

3. Run one copy now instead of waiting for the day, on the box as its admin user (sessions on the box have no sudo):

   ```sh
   sudo systemctl start opnsense-offbox.service
   journalctl -u opnsense-offbox --since -10min --no-pager
   ```

   expect, in order:
   - `made a new repository password`;
   - `wrote the current password to the vault`;
   - `made the repository`;
   - `copied N configurations off the box; config-<stamp>.xml reads back the same`.

   `systemctl is-failed opnsense-offbox` prints `inactive`. A second start prints `ok: the vault holds the current password` and makes no new version.

## Restore a configuration

- **The box is alive:** on the box, as its admin user (the box already signs in, and the account answers only the home's address):

  ```sh
  sudo -u keys bash -c 'set -a; . /etc/agent-keys/opnsense-offbox/settings.env;
    /usr/local/libexec/agent-box/restic snapshots --tag opnsense;
    /usr/local/libexec/agent-box/restic restore latest --tag opnsense --target /var/lib/agent-box/restore'
  ```

- **The box is gone too:**
  1. The owner gives their own account Key Vault Secrets User on the vault, and Storage Blob Data Reader on the `opnsense-backup` container.
  2. From a machine at home, the owner reads the password from the vault into a 0600 file and runs `restic -r azure:opnsense-backup:/opnsense restore latest --tag opnsense` with `AZURE_ACCOUNT_NAME` set and `az login` as the owner.
  3. If restic can't open the repository with the newest version (exit 12), the owner tries the older versions, newest first, with `az keyvault secret list-versions` and `show --version`. A box that was taken over can only add versions, never delete one, so the right password is still there.
  4. The owner takes both roles away afterwards.

  A rebuilt box made by the role cannot do this: it makes a new password and a new certificate.

Then put the file back in OPNsense: System, Configuration, Backups, Restore, or the API's `core/backup` calls.

## If it fails

| Message | Cause and fix |
|---|---|
| `the vault does not hold the current repository password; nothing copied` | The escrow step failed. The line before it says why: no token (certificate), a 403 (the role assignment hasn't reached the data plane yet, or the box left through another address), or a refused set. Nothing is sent until it passes. |
| `restic could not open the repository (exit 12)` | The password on the box is not the one the repository was made with. Restore the file from the vault's version whose tag matches, as in "The box is gone too". |
| `403` or `This request is not authorized` from restic | The box left through an address the account doesn't allow, or the container role hasn't reached the data plane yet (it can take a few minutes after step 1). |
| A 403 from both the vault and restic, on every run since a given day | The home's public address changed. Both the vault and the account allow only `allowed_ip_addresses`, so the copy fails closed. Put the new address in the tfvars file and run step 1 again with the owner's go. |
| `the certificate renewal failed` | The copy still ran with the current certificate. If it expired, step 2's tag uploads a new one. |
| `the newest copy read back ... differs` | The configuration changed between the fetch and the copy, or the repository is damaged. Run step 3 again; if it repeats, run `restic check` on the box. |

## Limits

- agent-azure holds Owner on the subscription, so it could give itself a data role on either container or on the vault. The separation is between the two backups' own identities, not against the subscription's owner.
- Storage Blob Data Contributor can delete blobs, which restic's prune needs. A box that is taken over could delete these copies; the account's soft delete keeps deleted blobs for 7 days.
- A box that is taken over could write a wrong password as a new version. Earlier versions stay, because the box can't delete or purge them, and each one carries a salted hash of what was written.

## Exit

1. Empty `agent_box_opnsense_offbox` and remove the timer (`systemctl disable --now opnsense-offbox.timer`).
2. Delete the container, the app and its roles by removing their resources from `hosts/terraform/azure/backup` and applying.
3. The vault stays soft-deleted for its retention days after a destroy (purge protection); its name is taken until then.

The restic repository's format is open: `restic restore` gets every file back without this role.
