---
title: Trust the Proxmox host's CA on the controller
status: draft
kind: automated
trigger: once per controller, after the Proxmox host is installed (step 3 of the bare-metal order); again if the host's own CA changes
runner: the owner, on the owner's Mac, with an agent lane in the session
outcome: the Proxmox host's own CA is in the Mac's System keychain, trusted for TLS server checks only, so OpenTofu's Proxmox provider verifies the host's API certificate with `PROXMOX_VE_INSECURE` unset
needs: a macOS controller (the play runs `security` and `shasum` on it); the controller from set-up-lab-controller.md with Ansible; SSH as the inventory's `ansible_user` to the Proxmox host; the Mac account's password, asked once; the filled-in inventory
private-values: [ansible-inventory, controller_trust_ca_file]
files: [hosts/ansible/playbooks/controller-trust.yml, hosts/ansible/roles/controller_trust/tasks/main.yml, hosts/ansible/roles/controller_trust/defaults/main.yml, hosts/ansible/roles/controller_trust/meta/argument_specs.yml, hosts/ansible/README.md]
last-tested: not yet run as written; no complete run of the playbook is recorded in this repository. Only the keychain write was tried (2026-10-28, the permission error that made the add task run as root). `ansible-playbook --syntax-check` and `ansible-lint` pass on the playbook and role (2026-11-19, with a stand-in inventory, no host reached)
superseded-by:
---

# Trust the Proxmox host's CA on the controller

**Status:** draft. Written on 2026-11-19 from the playbook and role, step by step; each step below says which file and lines do it. Nothing here has been run on a Mac against the host, so every `expect:` is what the code is written to print, not something seen. No CI test runs this play (the repository's test folder has none for `controller_trust`). It is `automated` with no `manual` twin: D-0012 wants a `tested` manual runbook first, and the nearest by-hand page, [Trust the lab root CA on a Mac](trust-lab-root-ca-on-mac.md), is for another CA and is itself `draft`.

OpenTofu's Proxmox provider has no CA setting, and on macOS the provider checks certificates with the system's verifier, so the Mac has to trust the host's CA in its System keychain ([hosts/ansible/README.md, Proxmox CA on the controller](../../hosts/ansible/README.md#proxmox-ca-on-the-controller) gives the reasons and the sources). This is step 3 of [Rebuild the home lab from bare metal](rebuild-home-lab-from-scratch.md). It comes after [Set up a Proxmox VE host by hand](set-up-proxmox-host.md), which makes the host and its CA, and before any OpenTofu run against the host.

## Before you start

- The host answers over SSH as the inventory's `ansible_user`, and the inventory has it in group `proxmox`. The play runs on that group (`playbooks/controller-trust.yml`, `hosts: proxmox`).
- The inventory sets `controller_trust_ca_file` for the host: a path on the Mac, for example under `~/.config/central-hub/`. It is required and has no default (`roles/controller_trust/meta/argument_specs.yml`). The example inventory has a blank for it (`inventories/home/hosts.example.yml`).
- You are on the Mac, not on the agent box or another Linux machine: the play calls `security`, which only macOS has. The agent box trusts the CA that signs the host's API certificate through its own role (the `ca` tag), not through this play ([Set up the agent box's users, keys, wrappers and guard rules](set-up-the-agent-box.md)).
- You know the Mac account's password. It is asked once, in the terminal.

## Steps

1. Look before you change anything.

   ```sh
   cd hosts/ansible
   ansible-playbook -i inventories/home/ playbooks/controller-trust.yml --tags trust --check --diff
   ```

   why: the playbook's own header gives this line first. A `--check` run fetches no file, so on a first run the tasks that read the file are skipped and the run shows only what it would fetch.
   ※ [Set up the lab controller](set-up-lab-controller.md): Ansible and the collections are there.
   expect: the run should end `failed=0`. It writes nothing to the Mac's keychain.

2. Run it.

   ```sh
   ansible-playbook -i inventories/home/ playbooks/controller-trust.yml --tags trust --ask-become-pass
   ```

   why: it copies the host's CA to the path you set, finds the CA's fingerprints, and adds the CA to the System keychain unless the keychain already holds that SHA-256. Only the add task runs as root (writing the System keychain as your own user failed with "SecCertificateAddToKeychain: Write permissions error.", measured 2026-10-28), so `--ask-become-pass` asks for your Mac password once.
   ※ [Where each step comes from](#where-each-step-comes-from) lists the tasks.
   expect: the last task prints one `Proof` message: `CA SHA-256 <64 hex digits> is in /Library/Keychains/System.keychain, trusted for ssl. To remove it: sudo security remove-trusted-cert -d <your CA file>; sudo security delete-certificate -Z <SHA-1> /Library/Keychains/System.keychain`. Copy that line into your notes: it holds the two commands that undo the step. The run ends `failed=0`.

3. Run step 2 again.

   why: the add task skips when the keychain already lists the CA's SHA-256, so a second run adds nothing and asks for no password.
   expect: the `Trust the CA for TLS (as root)` task shows `skipping`, and the `Proof` message is the same. Not seen yet: whether the file-copy task also reports no change on a second run. It should, because Ansible's `fetch` compares checksums, but no run has shown it.

4. Check the keychain yourself.

   ```sh
   security find-certificate -a -Z /Library/Keychains/System.keychain | grep "SHA-256 hash: <the hash from the Proof line>"
   ```

   why: this is the same read the play uses to decide whether to add (`security find-certificate -a -Z`), so it shows what the play saw.
   expect: one line that reads `SHA-256 hash:` and then the same digits, in upper case.

5. Check that OpenTofu verifies the host, with `PROXMOX_VE_INSECURE` unset.

   ```sh
   unset PROXMOX_VE_INSECURE
   cd hosts/terraform/home/<a run folder that uses the Proxmox provider, for example k8s>
   tofu plan
   ```

   why: this is the reason for the whole page. Each run folder's `providers.tf` says `PROXMOX_VE_INSECURE` is "true" only while the host still uses its self-signed certificate. This step is not in the playbook, which stops at the keychain; it is written here from the README's reason for the trust, and it has not run.
   expect: the plan reads the Proxmox API without a certificate error (a certificate error is what this runbook exists to remove). It needs the run folder's other private inputs from [Set up the lab controller](set-up-lab-controller.md).

## If it fails

- `SecCertificateAddToKeychain: Write permissions error.`: the add task did not run as root. Run step 2 with `--ask-become-pass`, as the README says.
- The run fails at the first task, `CA from the Proxmox host to the controller`: the host is not reachable over SSH as the inventory's user, or `/etc/pve/pve-root-ca.pem` is not there (the role's default source, `controller_trust_source`). Check the host first ([Set up a Proxmox VE host by hand](set-up-proxmox-host.md)). Nothing was changed on the Mac.
- The run stops with a message about `controller_trust_ca_file`: the inventory has no value for it. Set it and run again.
- `openssl` or `shasum` or `security` is not found: the controller is not a Mac with its normal tools. Stop and tell the owner.
- To trust the CA by hand when the play can't run: `sudo security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain <the CA file>`. This is the command the task runs (`roles/controller_trust/tasks/main.yml`); run by hand, it is unproven. `-d` makes it an admin trust setting for every user on the Mac, and `-p ssl` trusts it for TLS server checks only.
- To undo: use the two commands the `Proof` message printed. They are the README's removal commands too.
- If the host's CA ever changes (for example after a reinstall of the host), a later run adds the new CA by its new SHA-256. The old one stays until you remove it with the removal commands above (README).
- Tell the owner before trying anything not written here.

## Where each step comes from

All paths are under `hosts/ansible/` and read at central-hub `640ce91d`.

| Step | What the code does | File and lines |
|---|---|---|
| 1, 2 | The two command lines, the host group, no `become` for the play | `hosts/ansible/playbooks/controller-trust.yml` lines 4-5, 7-9 |
| 2 | Copies the host's CA to `controller_trust_ca_file` on the controller, `flat: true` | `hosts/ansible/roles/controller_trust/tasks/main.yml` lines 8-12 |
| 2 | The source is `/etc/pve/pve-root-ca.pem`; the keychain is `/Library/Keychains/System.keychain`; the policy is `ssl` | `hosts/ansible/roles/controller_trust/defaults/main.yml` lines 6, 9, 12 |
| 2 | Looks for the copied file, then reads its SHA-256 and SHA-1 with `openssl` and `shasum` on the controller | `hosts/ansible/roles/controller_trust/tasks/main.yml` lines 14-32 |
| 2, 3, 4 | Lists the keychain with `security find-certificate -a -Z` | `hosts/ansible/roles/controller_trust/tasks/main.yml` lines 34-41 |
| 2, 3 | Adds the CA with `security add-trusted-cert -d -r trustRoot -p ssl -k <keychain> <file>`, as root, only when the keychain's list has no `SHA-256 hash:` line for it | `hosts/ansible/roles/controller_trust/tasks/main.yml` lines 43-62 |
| 2 | Prints the proof and the two removal commands | `hosts/ansible/roles/controller_trust/tasks/main.yml` lines 64-72 |
| Before you start | `controller_trust_ca_file` is required, no default | `hosts/ansible/roles/controller_trust/meta/argument_specs.yml` lines 8-11 |
| 1 | A first `--check` run fetches nothing, so nothing is looked up | `hosts/ansible/roles/controller_trust/tasks/main.yml` line 20 (comment) |
| Intro, 5 | Why the Mac keychain: no CA setting in the provider, Go on macOS ignores `SSL_CERT_FILE` | `hosts/ansible/README.md` lines 199-209 |
| 2 | Only the add needs root, measured 2026-10-28 | `hosts/ansible/README.md` line 207; `hosts/ansible/roles/controller_trust/tasks/main.yml` lines 4-6 |

## Afterwards

- Set `last-tested` here after a run on the owner's Mac, with the date and what the `Proof` line and step 5 showed. Then step 3 of [Rebuild the home lab from bare metal](rebuild-home-lab-from-scratch.md) can say `tested` for it.
- Record the picks behind this in [hosts/AGENT-PICKS.md](../../hosts/AGENT-PICKS.md) (picks 103 to 106 are already there).

## Related

- [Rebuild the home lab from bare metal](rebuild-home-lab-from-scratch.md), step 3: where this sits in the order.
- [Set up a Proxmox VE host by hand](set-up-proxmox-host.md): makes the host and its CA.
- [Trust the lab root CA on a Mac](trust-lab-root-ca-on-mac.md): the same keychain command for the lab's own root.
- [Serve the Proxmox web UI on port 443](serve-proxmox-on-443.md): the host's later certificate from the lab CA (README: "A private CA replaces this later").
