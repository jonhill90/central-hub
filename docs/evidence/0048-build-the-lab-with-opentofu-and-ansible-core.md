---
record: D-0048
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: OpenTofu, Terraform and ansible-core licence files read from their repositories; OpenTofu's manifesto and Red Hat's Ansible comparison page opened; the controller's requirements file read; on 2026-11-14 at about 11:00 UTC, every provider's and collection's licence file and AWX's licence read, the Red Hat page's list of enterprise capabilities read for the paywall weighing, and the reach re-counted at main 6f777df
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0048: OpenTofu and ansible-core

This file summarises the research behind D-0048. It adds nothing the research and the pages listed below did not find.

## Question

Are OpenTofu and Ansible free with nothing held back behind a paywall, and which parts does the lab install?

## Findings

1. **OpenTofu** is MPL-2.0 [1] (measured). It is a Linux Foundation project that says it will stay "Truly open source" and "not at the whim of any one company" [2] (sourced).
2. **Providers.** `bpg/proxmox`, `hashicorp/azurerm`, `hashicorp/azuread`, `hashicorp/local` and `hashicorp/time` are MPL-2.0, and `tailscale/tailscale` is MIT [7] (measured). `cloudflare/cloudflare` is Apache-2.0 (evidence 0045).
3. **Terraform** is under the Business Source License for version 1.6.0 and later [3] (measured).
4. **ansible-core** is GPL-3.0 [4] (measured). The collections `community.general`, `ansible.posix` and `oxlorg.opnsense` are GPL-3.0 [8] (measured).
5. **Red Hat Ansible Automation Platform.**
   - The comparison page calls it a platform that "combines 20+ community projects" sold "through an enterprise subscription". It calls the free alternative "a set of upstream projects", needing "manual integration of open-source GUI and API components".
   - Its list of enterprise capabilities includes:
     - the automation controller (web UI and API), event-driven automation, role-based access and audit, and a private automation hub;
     - support and life-cycle support;
     - "Red Hat Ansible Certified Content";
     - generative AI assistants.

   [5] (sourced)
6. **AWX**, the controller's upstream, is Apache-2.0 [9] (measured).
7. **What the lab installs.** The controller installs `ansible-core==2.21.5` and `httpx==0.28.1` [6] (measured), and the collections `oxlorg.opnsense`, `community.general` and `ansible.posix` from Galaxy, pinned [6] (measured).
8. **Reach.** At main 6f777df there are 90 `.tf` files in 15 run folders and 303 files under `hosts/ansible/`. 24 runbooks name OpenTofu and 51 name Ansible; 5 records name OpenTofu and 14 name Ansible [6] (measured, 2026-11-14).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1, 2, 4 and 7 set rules 1 and 2. Finding 3 rules out option 2. Findings 5 and 6 are option 3 and the paywall weighing. Finding 8 is the context.

## Limits

- The tools were not compared on fit; the record keeps what runs.
- Whether certified content and the AI assistants are sold only with the subscription was read from Red Hat's page, not from a price list or a test.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. OpenTofu LICENSE. <https://raw.githubusercontent.com/opentofu/opentofu/main/LICENSE>
2. OpenTofu, "Manifesto". <https://opentofu.org/manifesto>
3. Terraform LICENSE. <https://raw.githubusercontent.com/hashicorp/terraform/main/LICENSE>
4. ansible-core COPYING. <https://raw.githubusercontent.com/ansible/ansible/devel/COPYING>
5. Red Hat, "Ansible vs. Red Hat Ansible Automation Platform". <https://www.redhat.com/en/technologies/management/ansible/ansible-vs-red-hat-ansible-automation-platform>
6. central-hub at 6f777df (this repository): `hosts/ansible/requirements.txt`, `hosts/ansible/requirements.yml`, and a repository search.
7. Provider licence files: <https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/LICENSE>, <https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/LICENSE>, <https://raw.githubusercontent.com/hashicorp/terraform-provider-azuread/main/LICENSE>, <https://raw.githubusercontent.com/hashicorp/terraform-provider-local/main/LICENSE>, <https://raw.githubusercontent.com/hashicorp/terraform-provider-time/main/LICENSE>, <https://raw.githubusercontent.com/tailscale/terraform-provider-tailscale/main/LICENSE>
8. Collection licence files: <https://raw.githubusercontent.com/ansible-collections/community.general/main/COPYING>, <https://raw.githubusercontent.com/ansible-collections/ansible.posix/main/COPYING>, <https://raw.githubusercontent.com/O-X-L/ansible-opnsense/latest/LICENSE.txt>
9. AWX LICENSE. <https://raw.githubusercontent.com/ansible/awx/devel/LICENSE.md>

The batch is RB-0208; its working files are private.
