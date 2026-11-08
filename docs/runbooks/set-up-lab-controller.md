---
title: Set up the lab controller (the machine that runs OpenTofu and Ansible)
status: draft
kind: manual
trigger: on request; before a lab rebuild; on a new controller machine
runner: the owner
outcome: the controller has the pinned tools, a clone of central-hub, the private folder at mode 0700 and a filled-in inventory, so every other lab runbook can run from it
needs: a macOS controller with Python 3 and Homebrew; SSH access to GitHub or HTTPS; the private values for the inventory
private-values: [ansible-inventory, terraform-tfvars, node-ssh-key]
files: [hosts/ansible/requirements.txt, hosts/ansible/requirements.yml, hosts/ansible/inventories/home/hosts.example.yml, hosts/terraform/home/*/home.tfvars.example]
last-tested:
superseded-by:
---

# Set up the lab controller

**Status:** draft, written from the code on 2026-11-08, not yet run as a whole. The controller today is the owner's Mac.

The controller is the one machine that runs OpenTofu, Ansible and SSH into the lab. Every private value lives on it and nowhere else ([Rebuild the home lab, The private files](rebuild-home-lab-from-scratch.md#the-private-files-on-the-controller)).

## Before you start

- Check whether the controller already holds `~/.config/central-hub/` and a filled-in `hosts/ansible/inventories/home/hosts.yml`. If it does, keep them: this runbook never overwrites a private file.

## Steps

1. Clone the repository and stay on `main`.

   ```sh
   git clone https://github.com/jonhill90/central-hub.git ~/source/central-hub
   cd ~/source/central-hub
   ```

   why: every runbook's paths are relative to this clone. Agent pick: `~/source/central-hub` as the place; any folder works.
   expect: `git status` shows a clean `main`.

2. Install OpenTofu 1.10 or later.

   ```sh
   brew install opentofu
   tofu version
   ```

   why: every run folder sets `required_version = ">= 1.10.0"` (`hosts/terraform/home/*/versions.tf`); the providers are pinned in each folder's `.terraform.lock.hcl`.
   expect: a version of 1.10.0 or later.

3. Install Ansible and its collections, pinned, in a virtual environment.

   ```sh
   cd hosts/ansible
   python3 -m venv .venv && . .venv/bin/activate
   pip install -r requirements.txt
   ansible-galaxy collection install -r requirements.yml -p ./collections
   ```

   why: `requirements.txt` pins ansible-core and httpx (the OPNsense modules call the API with httpx); `requirements.yml` pins `oxlorg.opnsense`, `community.general` and `ansible.posix`. `collections/` is git-ignored. Agent pick: the virtual environment; the README installs with plain `pip`.
   expect: `ansible --version` shows the pinned ansible-core; `ansible-galaxy collection list -p ./collections` lists the three collections.

4. Make the private folder.

   ```sh
   mkdir -p ~/.config/central-hub && chmod 700 ~/.config/central-hub
   mkdir -p ~/.local/state/central-hub && chmod 700 ~/.local/state/central-hub
   ```

   why: every key and token file the runbooks make goes in `~/.config/central-hub/`, and every OpenTofu state file in `~/.local/state/central-hub/` ([hosts/terraform/README.md](../../hosts/terraform/README.md#run-it-on-the-mac)). Both stay out of the repository and out of any synced folder.
   expect: `ls -ld` shows `drwx------` for both.

5. Make the SSH key the c1 nodes will trust, if there isn't one.

   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/central-hub-c1 -C central-hub-c1
   ```

   why: `hosts/terraform/home/k8s` puts the public half on each node (`node_ssh_public_key`), and the inventory names the private half (`ansible_ssh_private_key_file`). Agent pick: the file name.
   expect: two files, the private one `-rw-------`.

6. Fill in the inventory and each run folder's `home.tfvars`.

   ```sh
   cp hosts/ansible/inventories/home/hosts.example.yml hosts/ansible/inventories/home/hosts.yml
   for d in hosts/terraform/home/*/; do [ -f "$d/home.tfvars.example" ] && cp -n "$d/home.tfvars.example" "$d/home.tfvars"; done
   chmod 600 hosts/ansible/inventories/home/hosts.yml hosts/terraform/home/*/home.tfvars
   ```

   Then fill every blank by hand. Each blank is named in the template's comment, and [hosts/ansible/README.md](../../hosts/ansible/README.md) and [hosts/terraform/README.md](../../hosts/terraform/README.md) say what each one is.
   why: the roles and run folders give private values no default, so a blank stops the run. `hosts.yml` and `*.tfvars` are git-ignored (`hosts/ansible/.gitignore`, `hosts/terraform/.gitignore`).
   expect: `git status` shows none of these files.

## If it fails

Nothing here touches the lab. Delete what this runbook made and run it again; never delete a file in `~/.config/central-hub/` that another runbook made, because some of them can't be made again (see the rebuild runbook's table).

## Afterwards

Set `last-tested` with the date, who ran it and on which machine.

## Related

- [Rebuild the home lab from bare metal](rebuild-home-lab-from-scratch.md).
- [hosts/ansible/README.md](../../hosts/ansible/README.md), "Run it" and "Private values".
