---
title: Make the agent box's encrypted bundle of its private files
status: draft
kind: manual
trigger: once, after the owner's Mac has an age identity; again if the box is rebuilt
runner: an agent lane on the controller, running the agent_box role (a box-limit change, so the owner's typed go under D-0036 comes first)
outcome: every day the box writes one SOPS-encrypted bundle of /etc/agent-keys/prod and /dev that either the box's or the Mac's age identity can decrypt, proved by a read-back on the box
needs: the agent_box role applied once from the controller; the Mac's age public recipient (age1...) in the private inventory as agent_box_secrets_bundle.mac_recipient
private-values: [mac-age-recipient]
files: [hosts/ansible/roles/agent_box/tasks/secrets_bundle.yml, hosts/ansible/roles/agent_box/files/secrets-bundle.sh, hosts/ansible/roles/agent_box/templates/secrets-bundle-settings.env.j2, hosts/ansible/roles/agent_box/templates/secrets-bundle.service.j2, hosts/ansible/roles/agent_box/templates/secrets-bundle.timer.j2]
last-tested: "not run; written 2026-11-14 from the code in this change, which passed ShellCheck and ansible-lint"
superseded-by:
---

# Make the agent box's encrypted bundle of its private files

**Status:** draft, not run. Built on D-0038 rule 10, which is proposed and not yet accepted.

## Why

The lab's private files live in two places: the owner's Mac and the agent box's keys folder. Losing both loses them. D-0038 rule 10 (proposed) has SOPS with age encrypt every copy that leaves a machine, to two recipients, so either machine alone can decrypt it. This runbook sets up the first half: a daily encrypted bundle on the box, proved to read back. Sending it off the box is a later change, through restic like the [OPNsense off-box copy](copy-opnsense-backup-off-box.md).

## What is built (pick 228)

- SOPS 3.13.3 (MPL-2.0) and age 1.3.2 (BSD-3-Clause) in `/usr/local/libexec/agent-box/`, each checked against its SHA-256. SOPS's comes from the release's checksums file. For age, no checksums file was found, so its value is the tarball's hash as downloaded on 2026-11-14. What was checked on 2026-11-14: age's release workflow at tag v1.3.2 ([build.yml](https://github.com/FiloSottile/age/blob/v1.3.2/.github/workflows/build.yml)) uploads only the `age-*` archives, with a [build provenance attestation](https://github.com/actions/attest-build-provenance); `SHA256SUMS`, `SHA256SUMS.txt` and `checksums.txt` under the release's downloads return 404; a search of age's issues and code found no checksums file; the release page's asset list could not be read from the session (403). A later change can check that attestation instead.
- The box's age identity, `/etc/agent-keys/secrets-bundle/age-identity.txt`, made once by the keys user and never printed or replaced. A new identity could not read older bundles.
- `secrets-bundle.timer`, daily at 15:30 UTC, runs `secrets-bundle.sh` as the keys user. It tars `prod` and `dev` from the keys folder, never its own folder. SOPS encrypts the tar as one binary file to the box's recipient and the Mac's. The new bundle must decrypt with the box's identity to the same bytes, or it is deleted and the run fails. The newest 14 bundles stay in `/etc/agent-keys/secrets-bundle/bundles/`.

## Before you start

- The Mac needs an age identity, and its public recipient (one line starting `age1`) goes in the private inventory as `agent_box_secrets_bundle.mac_recipient`. A recipient is a public key, not a secret. Making the Mac's identity is a change to the Mac's keys script, which is the owner's.
- This changes the box's limits (new script, units and keys folder), so the owner's typed go names the PR and its head (D-0036) before the controller applies it.

## Steps

1. Apply the role from the controller.
   `ansible-playbook -i <private inventory> playbooks/agent-box.yml --tags secrets_bundle`
   expect: `The box's age identity` changed on the first run only, and `The bundle's timer runs` ok.

2. Make the first bundle now.
   The box's own user has no sudo for this, so the controller that ran step 1 starts it: `ansible <the box> -i <private inventory> -b -m ansible.builtin.systemd_service -a "name=secrets-bundle.service state=started"`, then reads the result with `ansible <the box> -i <private inventory> -b -m ansible.builtin.command -a "journalctl -u secrets-bundle.service -n 5"`.
   expect: `secrets-bundle: bundle-<time>.sops.json: prod dev, <n> bytes before encryption; reads back the same`.

3. Check that the Mac can decrypt it.
   why: a bundle only the box can read does not survive losing the box.
   On the Mac, with its age identity: `SOPS_AGE_KEY_FILE=<Mac identity> sops decrypt --input-type json --output-type binary <bundle> | tar -t`
   expect: the `prod/` and `dev/` file names.

## If it fails

- `BUNDLE_MAC_RECIPIENT is not an age recipient`: the inventory value is missing or mistyped.
- `does not decrypt with the box's identity`: the identity file changed. Do not make a new one; older bundles need the old one. Tell the owner.
- Tell the owner before trying anything not written here.

## Related

- [D-0038 and its evidence](../decisions/README.md)
- [Set up the agent box](set-up-the-agent-box.md)
