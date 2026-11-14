---
title: Make the agent box's encrypted bundle of its private files, and send it off the box
status: draft
kind: manual
trigger: once to set up; again if the box is rebuilt; the break-glass recovery only when the box is lost
runner: an agent lane on the controller, running the agent_box role (a box-limit change, and the off-box send is a secrets step, so the owner's decision-card tap under D-0042 rule 6 comes first); the break-glass recovery is the owner's alone
outcome: every day the box writes one SOPS-encrypted bundle of /etc/agent-keys/prod and /dev, proved to read back, and sends the newest one into the OPNsense off-box restic repository, where it reads back the same and opens with the box's age identity; that identity's one off-box copy is in the backup Key Vault, which only the owner can read
needs: the agent_box role applied once from the controller; the OPNsense off-box copy set up and its repository made (copy-opnsense-backup-off-box.md); no agent or pipeline identity holding role-assignment rights on the backup vault or container (see Before you start); optionally the Mac's age public recipient (age1...) in the private inventory as agent_box_secrets_bundle.mac_recipient
private-values: [mac-age-recipient, c1-backup-azure-storage-account, opnsense-offbox-vault-name]
files: [hosts/ansible/roles/agent_box/tasks/secrets_bundle.yml, hosts/ansible/roles/agent_box/files/secrets-bundle.sh, hosts/ansible/roles/agent_box/files/secrets-bundle-offbox.sh, hosts/ansible/roles/agent_box/files/opnsense-escrow.py, hosts/ansible/roles/agent_box/templates/secrets-bundle-settings.env.j2, hosts/ansible/roles/agent_box/templates/secrets-bundle.service.j2, hosts/ansible/roles/agent_box/templates/secrets-bundle.timer.j2, hosts/ansible/roles/agent_box/templates/secrets-bundle-offbox.service.j2, hosts/ansible/roles/agent_box/templates/secrets-bundle-offbox.timer.j2, .github/hosts-check/tests/test_secrets_bundle_offbox.sh, .github/hosts-check/tests/test_opnsense_escrow.sh]
last-tested: "not run on the box; written 2026-11-14 from the code in this change, which passed ShellCheck, ansible-lint and the offline tests test_secrets_bundle_offbox.sh (a local restic repository with the real restic, SOPS and age) and test_opnsense_escrow.sh"
superseded-by:
---

# Make the agent box's encrypted bundle of its private files, and send it off the box

**Status:** draft, not run. Built on D-0038 rule 10, which is proposed and not yet accepted. The off-box send (pick 236) is not installed until the blocker under [Before you start](#before-you-start) is cleared.

## Why

The lab's private files live in the agent box's keys folder, and on the owner's Mac where it has them. Losing the box must not lose them. D-0038 rule 10 (proposed) has SOPS with age encrypt every copy that leaves a machine. The box builds a daily encrypted bundle (pick 228) and sends it, with restic, into the same Azure repository as the [OPNsense off-box copy](copy-opnsense-backup-off-box.md) (pick 236). The bundle opens with the box's age identity, whose one off-box copy the box writes into the backup Key Vault and can never read back. A second recipient, the Mac's, is optional: the off-box copy can be opened without the box and without the Mac.

## What is built

**The bundle (pick 228).**

- SOPS 3.13.3 (MPL-2.0) and age 1.3.2 (BSD-3-Clause) in `/usr/local/libexec/agent-box/`, each checked against its SHA-256. SOPS's comes from the release's checksums file. For age, no checksums file was found, so its value is the tarball's hash as downloaded on 2026-11-14. What was checked on 2026-11-14: age's release workflow at tag v1.3.2 ([build.yml](https://github.com/FiloSottile/age/blob/v1.3.2/.github/workflows/build.yml)) uploads only the `age-*` archives, with a [build provenance attestation](https://github.com/actions/attest-build-provenance); `SHA256SUMS`, `SHA256SUMS.txt` and `checksums.txt` under the release's downloads return 404; a search of age's issues and code found no checksums file; the release page's asset list could not be read from the session (403). A later change can check that attestation instead.
- The box's age identity, `/etc/agent-keys/secrets-bundle/age-identity.txt`, made once by the keys user and never printed or replaced. A new identity could not read older bundles.
- `secrets-bundle.timer`, daily at 15:30 UTC, runs `secrets-bundle.sh` as the keys user. It tars `prod` and `dev` from the keys folder, never its own folder. SOPS encrypts the tar as one binary file to the box's recipient, and to the Mac's when `mac_recipient` is set. The new bundle must decrypt with the box's identity to the same bytes, or it is deleted and the run fails. The newest 14 bundles stay in `/etc/agent-keys/secrets-bundle/bundles/`.

**The off-box send (pick 236).** It reuses everything the OPNsense off-box copy built: its settings file, its Azure sign-in, the `opnsense-backup` container, the restic repository and its password, and the Key Vault. No Azure resource, role or assignment is added, and nothing is applied to Azure.

- `secrets-bundle-offbox.timer`, daily at 16:15 UTC (`agent_box_secrets_bundle_offbox_daily`), after the bundle's, runs `secrets-bundle-offbox.sh` as the keys user. It is installed only when `agent_box_opnsense_offbox` is set. In order, it:
  1. picks the newest bundle, and refuses it unless its `sops.age` lists the box's recipient, and the Mac's when one is set;
  2. runs the escrow (`opnsense-escrow.py ensure`) for both the restic password and the box's age identity, the identity as secret `BUNDLE_VAULT_SECRET` (default `secrets-bundle-age-identity`). If the vault does not hold the current value of both, nothing is sent;
  3. requires the repository to exist already (the OPNsense copy makes it; this job never does);
  4. runs `restic backup --host agent-box --tag secrets-bundle`, then `restic forget --tag secrets-bundle --group-by host,tags --keep-daily 14 --keep-monthly 6 --prune`. Each bundle has its own file name, and restic groups by path unless told otherwise, so without `--group-by host,tags` nothing would ever be forgotten. Every restic call waits up to 30 minutes for a lock (`--retry-lock 30m`), because the OPNsense copy prunes the same repository; it waits the same way;
  5. reads the bundle back with `restic dump latest`, requires the same bytes, decrypts that copy with the box's identity straight into `tar -t` (the clear tar is never written to a file), and requires `prod/` or `dev/` in it;
  6. prints one line with the bundle's name and size. No value is ever printed.
- **Retention:** 14 daily and 6 monthly off-box bundles (`offbox_keep_daily`, `offbox_keep_monthly`). While fewer days than that hold bundles, restic also keeps the oldest one. `--prune` deletes older ones from Azure for good; the account's 7-day soft delete is the only way back. That daily delete is why the install is a delete under D-0042 rule 6, and the owner's card names it.
- **The escrowed identity:** the box's custom vault role can set a secret and read its metadata, never a value, and cannot delete or purge (hosts/terraform/azure/backup/main.tf). Each version carries a salted hash of what was written, so the box can tell the vault holds the current identity without reading it.

## Before you start

- **Blocker, the install waits for it:** no agent or pipeline identity may hold role-assignment rights on the backup vault or the `opnsense-backup` container; that includes the D-0041 pipeline identity (D-0038 rule 10). Today agent-azure holds Owner on the subscription ([back up c1 off box](back-up-c1-off-box.md), step A2), and Owner can write role assignments, so it could grant itself read on both and open every bundle. Clearing that is an access-rights change, which takes the owner's tap (D-0042 rule 6). Until then the send is not installed: this change is not applied to the box.
- The OPNsense off-box copy must already run, and its first run must have made the repository ([copy the OPNsense backups off the box](copy-opnsense-backup-off-box.md)).
- **Optional, the Mac:** if the owner makes an age identity on the Mac, its public recipient (one line starting `age1`) goes in the private inventory as `agent_box_secrets_bundle.mac_recipient`. A recipient is a public key, not a secret. Making the Mac's identity is a change to the Mac's keys script, which is the owner's. With no Mac recipient, the Mac holds no copy: recovery is the Azure vault plus the backup container, and losing that Azure account and the box together loses the bundle.
- This changes the box's limits (new script, units and settings), and the send puts a key (the age identity) into the vault, so the owner's decision-card tap naming the step and the commit comes first (D-0042 rule 6).

## Steps

1. Apply the role from the controller.
   `ansible-playbook -i <private inventory> playbooks/agent-box.yml --tags secrets_bundle`
   expect: `The box's age identity` changed on the first run only, and `The bundle's timer runs` and `The off-box send's timer runs` ok.

2. Make the first bundle now.
   The box's own user has no sudo for this, so the controller that ran step 1 starts it: `ansible <the box> -i <private inventory> -b -m ansible.builtin.systemd_service -a "name=secrets-bundle.service state=started"`, then reads the result with `ansible <the box> -i <private inventory> -b -m ansible.builtin.command -a "journalctl -u secrets-bundle.service -n 5"`.
   expect: `secrets-bundle: bundle-<time>.sops.json: prod dev, <n> bytes before encryption; reads back the same`.

3. Send it off the box now.
   The same way: start `secrets-bundle-offbox.service`, then read `journalctl -u secrets-bundle-offbox.service -n 5`.
   expect, in order: `ok: the vault holds the current password` (or `wrote the current password to the vault`), the same line for the `age identity`, then `secrets-bundle-offbox: sent bundle-<time>.sops.json (<n> bytes) off the box; it reads back the same and opens with the box's identity`.

4. Only if a Mac recipient is set: check that the Mac can decrypt it.
   On the Mac, with its age identity: `SOPS_AGE_KEY_FILE=<Mac identity> sops decrypt --input-type json --output-type binary <bundle> | tar -t`
   expect: the `prod/` and `dev/` file names.

## Recover the bundle when the box is lost (break-glass)

**This is break-glass (Activation gate item 7).** It is the owner's alone, with their own Azure sign-in; no agent and no pipeline runs it. It grants the owner's account read on both the vault and the container, which together open every private file of the lab.

1. The owner gives their own account Key Vault Secrets User on the backup vault, and Storage Blob Data Reader on the `opnsense-backup` container.
2. From a machine at home (the vault and the account answer only the home's address), the owner reads two secrets into 0600 files: the restic password (`OFFBOX_VAULT_SECRET` in the OPNsense settings) and the age identity (`secrets-bundle-age-identity`).
3. With `az login` as the owner and `AZURE_ACCOUNT_NAME` set: `restic -r azure:opnsense-backup:/opnsense restore latest --tag secrets-bundle --target <folder>`. If restic can't open the repository with the newest password version (exit 12), try the older versions as the OPNsense runbook says.
4. `SOPS_AGE_KEY_FILE=<identity file> sops decrypt --input-type json --output-type binary <bundle> > bundle.tar`, then `tar -xf bundle.tar`. If the newest identity version does not open it, the bundle is older than a rotation: try the identity's older versions (`az keyvault secret list-versions`, then `show --version`), newest first.
5. The owner takes both roles away afterwards, and deletes the identity, password and clear files from that machine.

## Rotating the identity

Don't, unless it leaked. A new identity can't open older bundles, so the old identity's vault versions must stay for as long as any off-box bundle encrypted to it is kept: with keep-monthly 6, about six months. They are never purged in that time. The vault's purge protection and the box's role (it cannot delete) already keep them; no person may purge them early either.

## If it fails

| Message | Cause and fix |
|---|---|
| `BUNDLE_MAC_RECIPIENT is not an age recipient` | The inventory value is mistyped. Leave it empty if there is no Mac identity. |
| `does not decrypt with the box's identity` | The identity file changed. Do not make a new one; older bundles need the old one. Tell the owner. |
| `is not encrypted to the box's own recipient; not sent` | The newest bundle was not made by this box's `secrets-bundle.sh`. Find where it came from before anything else; tell the owner. |
| `is not encrypted to the Mac's recipient that the settings name; not sent` | The Mac recipient was added after the newest bundle was made. The next bundle carries it; run step 2, then step 3. |
| `the vault does not hold the current repository password and age identity; nothing sent` | The escrow failed. The line before it says why, as in the OPNsense runbook's table: no token, a 403, or a refused set. |
| `restic could not open the repository (exit 10)` | The OPNsense off-box copy has not made the repository yet. Run it first. |
| `restic could not open the repository (exit 12)` | The password on the box is not the repository's. See the OPNsense runbook. |
| `unable to create lock` from restic | Another restic run held the repository's lock for over 30 minutes. Check that no OPNsense copy or earlier send is stuck (`systemctl status opnsense-offbox secrets-bundle-offbox`), then run step 3 again. |
| `differs from` or `does not decrypt` after the read-back | The repository copy is damaged. Run `restic check` on the box; tell the owner. |

Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Copy the OPNsense backups off the box](copy-opnsense-backup-off-box.md)
- [Set up the agent box](set-up-the-agent-box.md)
