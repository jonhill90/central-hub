---
title: Copy the OPNsense configuration backups off the agent box
status: draft
kind: manual
trigger: once, after the box keeps daily OPNsense copies (set-up-the-box-lifeline.md); again if the box is rebuilt or the copy app's certificate expired
runner: an agent lane on the controller, with the Azure CLI signed in as agent-azure, after the owner's go to apply
outcome: every day the box's OPNsense configuration copies go, encrypted, to their own container in the Azure backup account, under their own identity and their own restic password, and the newest one is read back
needs: the box's daily OPNsense copies (agent_box_opnsense_backup); hosts/terraform/azure/backup applied before (back-up-c1-off-box.md); the Azure CLI on the controller signed in as agent-azure; the box leaves through the home's public address, the only one the storage account answers
private-values: [c1-backup-azure-storage-account, opnsense-offbox-restic-password, opnsense-offbox-client-id, opnsense-offbox-app-object-id, azure-tenant-id]
files: [hosts/terraform/azure/backup/, hosts/ansible/roles/agent_box/tasks/opnsense_offbox.yml, hosts/ansible/roles/agent_box/files/opnsense-offbox.sh, hosts/ansible/roles/k8s_backup/files/c1-backup-azure-cert.py, .github/hosts-check/tests/test_opnsense_offbox.sh]
last-tested: 2026-11-14, an agent, the Azure folder's offline tests (mocked provider) and opnsense-offbox.sh against a local restic repository (test_opnsense_offbox.sh); nothing applied
superseded-by:
---

# Copy the OPNsense configuration backups off the agent box

**Status:** draft. Written 2026-11-14 from the code in this change, tested offline only. Nothing is applied.

## Why

The box keeps a daily copy of OPNsense's configuration ([set-up-the-box-lifeline.md](set-up-the-box-lifeline.md)), but the box sits on the same Proxmox host as OPNsense. If that host's disk is lost, both go together. The owner chose the existing Azure backup account for the copy off the box, in its own container with its own credential and its own restic password, so c1's backup identity can't touch these copies and this one can't touch c1's (the owner's card, 2026-11-14 02:23 UTC, "Azure, own folder and key"; agent pick 222).

## What is built (pick 222)

| Piece | Where |
|---|---|
| Container `opnsense-backup` in the same storage account, and app registration `opnsense-backup` with Storage Blob Data Contributor on that container only. c1's apps keep their roles on the `c1-backup` container only | `hosts/terraform/azure/backup` (`main.tf`, outputs `opnsense_restic_repository`, `opnsense_client_id`, `opnsense_app_object_id`) |
| The box's sign-in: a key and certificate made on the box by the keys user, in `/etc/agent-keys/opnsense-offbox/` (0600). The key never leaves the box. The role brings back only the public certificate, and the controller adds it to the app as agent-azure, the app's owner. After that the box's daily run rolls it 30 days before it expires, through Graph `addKey`, which needs no permission for an app's own keys | `azure-cert.py` (the c1 nodes' script, `c1-backup-azure-cert.py`), `tasks/opnsense_offbox.yml` |
| The restic password: made once on the controller in `~/.config/central-hub/opnsense-offbox-restic.txt` (0600) and copied to `/etc/agent-keys/prod/` by the prod files copy, with nothing printed. The controller keeps its copy, so the backups can be read without the box | `agent_box_prod_files`, `tasks/prod_files.yml` |
| Daily timer `opnsense-offbox` (15:00 UTC, after the 14:30 fetch), as the keys user: rolls the certificate when due, backs up `/var/lib/agent-box/opnsense-backup`, keeps 30 daily and 12 monthly snapshots, prunes, then reads the newest configuration back and compares it with the file on the box | `files/opnsense-offbox.sh`, `templates/opnsense-offbox.*.j2` |

No secret passes through a transcript, the repository or OpenTofu state: tofu makes no key, the certificate key is made on the box, and the password goes from one 0600 file to another.

## Steps (after the owner's go)

1. (Agent, on the controller) Apply the Azure folder, as in [back-up-c1-off-box.md, step A1](back-up-c1-off-box.md#azure-blob-without-a-key):

   ```sh
   cd hosts/terraform/azure/backup
   tofu plan -var-file=azure.tfvars -out=backup.tfplan
   tofu apply backup.tfplan
   tofu output
   ```

   why: the container, the app and its role are code, so a rebuild makes them the same way. It is management-plane work, which the account's network rule doesn't block.
   ※ azurerm 5.11.0 `azurerm_storage_container` and `azurerm_role_assignment`; azuread 3.10.0 `azuread_application`
   expect: the plan only adds four resources (`azurerm_storage_container.opnsense`, `azuread_application.opnsense`, `azuread_service_principal.opnsense`, `azurerm_role_assignment.opnsense`) and changes nothing else. If it changes or destroys anything of c1's, stop. The outputs add `opnsense_restic_repository` (`azure:opnsense-backup:/opnsense`), `opnsense_client_id` and `opnsense_app_object_id`.

2. (Agent, on the controller) Make the restic password once, printing nothing:

   ```sh
   (umask 077; [ -s ~/.config/central-hub/opnsense-offbox-restic.txt ] || head -c 32 /dev/urandom | base64 > ~/.config/central-hub/opnsense-offbox-restic.txt)
   ```

   why: restic encrypts every snapshot with a key from this password; without it the copies can't be read. It is not c1's password, so neither repository opens the other.
   ※ restic's docs, "Design"; CLAUDE.md rule 4
   expect: `ls -l ~/.config/central-hub/opnsense-offbox-restic.txt` shows `-rw-------`. Do not run the line again on a controller that lost the file while the box still holds one: copy the box's back first.

3. In the private inventory set `agent_box_opnsense_offbox` from step 1's outputs, then run the box's role once with the prod files copy turned on for that run:

   ```yaml
   agent_box_opnsense_offbox:
     account: <storage_account_name>
     client_id: <opnsense_client_id>
     tenant_id: <tenant_id>
     app_object_id: <opnsense_app_object_id>
   ```

   ```sh
   ansible-playbook -i inventories/home/ playbooks/agent-box.yml --tags prod_files,opnsense_offbox -e agent_box_copy_prod_files=true
   ```

   why: the prod files copy puts the password on the box; the `opnsense_offbox` tag installs restic 0.19.1 (checked by SHA-256), makes the box's key and certificate, uploads the public certificate as agent-azure, waits until Entra ID accepts it steadily, records its key ID, removes any other certificate on the app, and turns on the timer.
   ※ [set-up-the-agent-box.md, "Copy the controller's private files to the box"](set-up-the-agent-box.md); [back-up-c1-off-box.md, step A3](back-up-c1-off-box.md#azure-blob-without-a-key)
   expect: `failed=0`; the debug line names `opnsense-offbox-restic.txt` under `copied`; `systemctl list-timers opnsense-offbox.timer` on the box lists the timer.

4. Run one copy now instead of waiting for the day, on the box as its admin user (sessions on the box have no sudo):

   ```sh
   sudo systemctl start opnsense-offbox.service
   journalctl -u opnsense-offbox --since -10min --no-pager
   ```

   expect: `made the repository` on the first run, then `copied N configurations off the box; config-<stamp>.xml reads back the same`. `systemctl is-failed opnsense-offbox` prints `inactive`.

## Restore a configuration from Azure

On the box, as its admin user, because the box already signs in and the account answers only the home's address. (agent-azure holds no data role on this container; a restore from elsewhere needs one given for the restore and taken away after.)

```sh
sudo -u keys bash -c 'set -a; . /etc/agent-keys/opnsense-offbox/settings.env;
  /usr/local/libexec/agent-box/restic snapshots --tag opnsense;
  /usr/local/libexec/agent-box/restic restore latest --tag opnsense --target /var/lib/agent-box/restore'
```

With the box gone too, a new box made by the role signs in again after step 3, with the same password from the controller. Then put the file back in OPNsense: System, Configuration, Backups, Restore, or the API's `core/backup` calls.

## If it fails

- `the repository password file is missing`: step 3 ran without `agent_box_copy_prod_files=true`, or step 2's file is missing on the controller.
- `restic could not open the repository (exit 12)`: the password on the box is not the one the repository was made with.
- `403` or `This request is not authorized` from restic: the box left through an address the account doesn't allow, or the role assignment hasn't reached the data plane yet (it can take a few minutes after step 1).
- `the certificate renewal failed`: the copy still ran with the current certificate. If it expired, step 3's tag uploads a new one.
- `the newest copy read back ... differs`: the configuration changed between the fetch and the copy, or the repository is damaged. Run step 4 again; if it repeats, run `restic check` on the box.

## Limits

- agent-azure holds Owner on the subscription (back-up-c1-off-box.md, step A2), so it could give itself a data role on either container. The separation is between the two backups' own identities, not against the subscription's owner.
- Storage Blob Data Contributor can delete blobs, which restic's prune needs. A box that is taken over could delete these copies; the account's soft delete keeps deleted blobs for 7 days.

## Exit

Empty `agent_box_opnsense_offbox` and remove the timer (`systemctl disable --now opnsense-offbox.timer`); delete the container and the app by removing their four resources from `hosts/terraform/azure/backup` and applying. The restic repository's format is open: `restic restore` gets every file back without this role.
