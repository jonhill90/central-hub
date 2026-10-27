---
id: STD-0004
title: Code under hosts/
status: active
scope: how Terraform run folders and Ansible roles, playbooks and inventories under `hosts/` are written; where they sit is D-0011
owner-system: 8 Platform
why: the owner said yes on 2026-10-26 at 04:34 UTC to the proposed step of one standard for how `hosts/` code is laid out and written, written after the first real `tofu apply` and Ansible run, and on 2026-10-26 at 01:55 UTC to writing it as a standard with a skill that points at it; each rule below names its own origin
follows: [Ansible role argument validation (meta/argument_specs.yml), Red Hat Communities of Practice "Ansible Good Practices" (roles README), HashiCorp Terraform style guide, OpenTofu backend configuration]
check: none yet; a reviewing agent checks each PR that changes `hosts/` against the rules by hand. A check script is planned (the owner's yes of 2026-10-26 at 04:34 UTC)
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-27T02:55:47Z
  approved-commit: 0622e3b6cb3db944c2d7b27933a95df09064196b
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNBXECP3JHRcrWjcJeRvhwop
  approval-names: "PR #47 and head 0622e3b, in the message itself"
  check: the Gaming PC thread read the message in the records thread on 2026-10-27; it names PR jonhill90/central-hub#47 and head 0622e3b itself. An independent check by a reviewing agent is still to do.
  merged: PR #47 merged at 2026-10-27T02:56:35Z as b52d931
---

# STD-0004: Code under hosts/

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

This standard is a draft written by an agent from what the first real `tofu apply` and Ansible runs taught (2026-10-26). The owner has not yet given feedback on the code itself; each rule says where it came from, and any rule can change after that review. Where the code sits (tool first, `hosts/terraform/<place>/<workload>/`, `hosts/ansible/inventories/<place>/`, `playbooks/`, `roles/`) is D-0011, not this standard.

## Both tools

1. **No private values in the repository.** Machine names, single addresses, MAC addresses, the DNS zone, tokens and keys MUST be inputs with no default, filled at run time from git-ignored files or the secret store (CLAUDE.md rule 4, D-0011 rule 5, D-0013 rule 2). The repository keeps `*.example` templates with made-up values shaped by STD-0001.
2. **No default for addresses and VLAN numbers.** An input that holds an address, a prefix or a VLAN number MUST have no default, so each place sets it or the run stops. Inputs with a safe value everywhere keep a default (the owner's yes of 2026-10-26 at 00:35 UTC to the Red Hat Communities of Practice rule).
3. **One VLAN file per place.** A place's VLAN list is written once, in `hosts/ansible/inventories/<place>/group_vars/all/vlans.yml`, and both tools read it. For the home place it is STD-0002's copy in code, and the docs check fails when they differ (the owner's yes of 2026-10-26 at 06:08 and 07:33 UTC).
4. **Names follow STD-0001**, pools and VM IDs included.
5. **Versions follow STD-0003**, pinned in `versions.tf`, `requirements.yml` or the role's defaults.
6. **Every agent choice is listed** in `hosts/AGENT-PICKS.md` with what it chose, why and the alternatives, until the owner says yes to it or changes it (the first spec's acceptance criteria).

## Terraform run folders

1. **Files.** Each run folder MUST have `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf` and `backend.tf`, and MAY have `imports.tf` while it adopts objects that already exist (`backend.tf`: the owner's answer of 2026-10-25 at 18:30 UTC; the other names: agent picks the owner said to keep as built, v0.1, on 2026-10-26 at 07:37 UTC).
2. **No `locals` blocks** (the owner's statement of 2026-10-25 at 07:03 UTC). Values a folder derives come from input variables or from the shared VLAN file.
3. **No state sharing between folders.** A value one folder needs from another is a plain input variable with the same value as the producer's output; the run order is written in the READMEs (agent picks the owner said to keep as built on 2026-10-26 at 07:37 UTC).
4. **State outside the repository**, one state file per run folder, named `<place>-<workload>.tfstate` (the owner's yes of 2026-10-25 at 17:47 UTC to local state for now; the name is an agent pick kept as built).
5. **Real variable files are git-ignored.** `*.tfvars` and `*.tfvars.json` stay out; `<place>.tfvars.example` is tracked.

## Ansible roles and playbooks

1. **Inputs declared.** Each role MUST have `meta/argument_specs.yml` declaring every input, so a missing one stops the run (the owner's yes of 2026-10-26 at 02:49 UTC, first for the firewall role; carried to the other roles as an agent pick).
2. **No other `meta/` files.** Roles MUST NOT carry `meta/main.yml` with Galaxy information; it is needed only to upload a role to Galaxy (the owner's yes of 2026-10-26 at 00:18 UTC).
3. **`defaults/` for what a place may change, `vars/` only for fixed rules** that the inventory must not override (the owner's yes of 2026-10-26 at 00:35 UTC left `vars/` as it is).
4. **Filled inventories are git-ignored.** `inventories/<place>/hosts.yml` stays out; `hosts.example.yml` is tracked, and runs use `-i inventories/<place>/` so `group_vars/` loads (agent pick, kept as built).
5. **One job per playbook** where a job can run on its own, with role tags for parts of it, for example `proxmox-safety.yml` with tags `notify`, `backup` and `firewall` (agent pick).
6. **A second run changes nothing.** Every playbook and run folder MUST report no change on a second run against the same lab (the first spec's acceptance criteria).

Example that passes: `hosts/terraform/home/network/` has the seven files of Terraform rule 1, no `locals`, and reads its VLANs from the shared VLAN file through `var.vlans_file`, which has no default; its second `tofu plan` after the first apply reported "No changes".

Known gap: the `proxmox_network` role has no `meta/argument_specs.yml` yet, so it does not meet Ansible rule 1.

## Not covered here

- Whether Ansible runs by push or by pull (D-0011 "Not decided here").
- The order of Ansible after `tofu apply`. The owner said on 2026-10-26 at 01:35 UTC that this is not a rule yet.
- Remote state and state encryption.
- Kubernetes manifests and Helm values: they are not machine code (D-0011 rule 1).
