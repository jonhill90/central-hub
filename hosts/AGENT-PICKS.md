# Agent picks in this draft, for the owner to review

Every choice here was made by an agent, not by the owner. Any of them can change; nothing below is decided. The owner's own decisions are listed at the end with their times.

| # | Pick | Where | Why it was picked | Alternatives (sources) |
|---|---|---|---|---|
| 1 | Place folder named `home` | `terraform/home/`, `ansible/inventories/home/` | Matches the IP plan's "Home = 10.1.0.0/16" | `home-lab`, `proxmox/`, or no place level (RB-0083 §2) |
| 2 | ~~Workload folder names `network`, `opnsense`, `ts-connector`~~ **The owner said yes to `network`, `firewall`, `remote-access` on 2026-10-26 at 06:03 UTC. Done.** | `terraform/home/*` | Named by what each makes | `sdn`, `firewall`, `remote-access` (by job, as in layout B) |
| 3 | Values between folders as plain input variables (`remote-access` `var.mgmt_vnet = "mgmt"`, `firewall` `var.trunk_bridge = "vmbr1"`) | `*/variables.tf` | Lowest coupling; no state sharing | data source lookup, remote state, a config store, Terragrunt/Terramate (RB-0083 §3) |
| 4 | Order between folders written in READMEs only (network first) | `hosts/README.md`, `terraform/README.md` | Nothing automates it yet | a pipeline, an orchestrator (RB-0083 §3e) |
| 5 | File names `main.tf` + `versions.tf` | every run folder | Common in Google/AWS guides | `terraform.tf` (HashiCorp, AVM); per-topic names like `sdn.tf` (RB-0083 §4) |
| 6 | `outputs.tf` added in every folder | every run folder | So the producer's value is visible next to the consumer's variable | none needed while values are typed |
| 7 | ~~The `lab_vnets` map variable kept (no locals)~~ Replaced: the owner said yes to one shared VLAN file on 2026-10-26 at 06:08 UTC (pick 15) | `network/variables.tf` | — | — |
| 8 | One state file per folder named `home-<workload>.tfstate` | every `backend.tf` comment | Matches the folder path | any name; one path per folder is what matters (RB-0083 §6) |
| 9 | Ansible playbooks moved into `playbooks/`, inventory into `inventories/<place>/` | `ansible/` | Mirrors `terraform/<place>/` (RB-0084 L4) | playbooks at the top level (Ansible sample layout) |
| 10 | No handoff files yet (no cloud-init template, no `ansible.tf`, no `ansible_pull` role) | `terraform/home/*`, `ansible/roles/` | None of today's three workloads needs them: CT 900 and OPNsense can't use cloud-init or pull; they appear with the first VM workload (for example k8s nodes) | add them now as switched-off examples (RB-0084 visuals README) |
| 11 | ~~Each role has `meta/main.yml` with `galaxy_info`~~ **The owner said yes to dropping `meta/` on 2026-10-26 at 00:18 UTC. Done: both `meta/` folders deleted.** | `ansible/roles/*/meta/` | Habit from the `ansible-galaxy init` skeleton; `dependencies: []` is the only part Ansible uses here | Delete `meta/`: the docs say `galaxy_info` is needed only for a Galaxy upload (playbooks_reuse_roles.rst L33) |
| 12 | Derived values and the rule list in `vars/main.yml` (kept as is; the owner's yes of 2026-10-26 at 00:35 UTC left it unchanged), separate from `defaults/` | `ansible/roles/opnsense_lab/vars/` | `vars/` beats the inventory, so these can't be overridden by accident | Put everything in `defaults/` (overridable), or compute the values inside the tasks |
| 13 | `terraform/.gitignore` also ignores `.terraform/` (provider downloads from `tofu init`) | `terraform/.gitignore` | `tofu init` creates it in every run folder | leave it out; add it at the repository root instead |
| 14 | Kept a non-empty check beside argument_specs: `lab_vlans` not empty, and every VLAN has an `opnsense_lab_vlan_settings` entry | `opnsense_lab/tasks/main.yml` | argument_specs doesn't reject `[]` (inferred) or a missing per-VLAN entry | drop it |
| 15 | The one shared VLAN file sits at `ansible/inventories/home/group_vars/all/vlans.yml`, with its list named `lab_vlans` | Ansible inventory + `terraform/home/network` | Ansible loads it by itself for every home host; Terraform reads it by path | a neutral `hosts/data/home/vlans.yml` both read by path (Ansible would then need `vars_files`) |
| 16 | `opnsense_lab_vlans` is now built in role `vars/` from `lab_vlans` plus a new per-VLAN `opnsense_lab_vlan_settings` (ifname, dhcp, bootstrap) set in the inventory; the role's prefix input is gone (the per-VLAN base comes from each cidr) | `opnsense_lab/vars`, `defaults`, `meta/argument_specs.yml`, tasks | Keeps the OPNsense-only fields out of the shared file | put ifname, dhcp, bootstrap in the shared file |
| 17 | The filled-in inventory now goes in `inventories/home/hosts.yml` (git-ignored), run with `-i inventories/home/` | `ansible.cfg`, `ansible/README.md`, `hosts.example.yml` | Ansible loads `group_vars/` only from next to the inventory or the playbook (Ansible docs, intro_inventory.rst L503, L530) | keep the copy outside the repo and pass the VLAN file with `-e @…/vlans.yml` |
| 18 | Role `IacOps` privilege list (18 privileges) and its ACL paths, as in `terraform/home/bootstrap/iac-access.sh` | Proxmox host | The bpg 0.116.0 docs example, cut to what these folders manage | the bpg example's full list; `PVEVMAdmin` + `PVESDNAdmin` built-in roles |
| 19 | Token `iac@pve!apply`, privilege-separated, expires after 90 days (2027-01-24); secret in `~/.config/central-hub/iac-apply-token.json` (0600) | Mac | Relayed brief; 90 days so it gets rotated | a longer expiry; a password manager entry |
| 20 | State files in `~/.local/state/central-hub/home-<workload>.tfstate`; real tfvars in each folder's git-ignored `home.tfvars` (0600) | Mac | Outside the repo, per the owner's yes to local state | another folder |
| 21 | Removed `snat = false` (subnets) and `pool_id` (container), because bpg 0.116.0 replaces imported objects for them; CT 900's pool membership stays with the bootstrap script | `terraform/home/network`, `remote-access` | Measured: the first plans would have destroyed 4 subnets and CT 900 | keep them and accept the replacement (greenfield) |
| 22 | VM IDs: 100-199 network and appliances, 200-299 Kubernetes nodes, 9000+ templates (template 9000, nodes 200 and 201) | `terraform/home/k8s` | No research; a simple rule | IDs by VLAN (10x for prod) |
| 23 | Node size 2 vCPU, 4 GB, 40 GB disk each; fixed addresses on VNet prod, below the DHCP pool (real ones only in the git-ignored tfvars) | `terraform/home/k8s/home.tfvars` | Brief: runbook minimums; the static range sits below the DHCP pool (.100-.199) | bigger nodes; DHCP reservations |
| 24 | Nodes cloned from template 9000, made from the AlmaLinux 10 GenericCloud "latest" image; admin user `almalinux` with a new key `~/.ssh/central-hub-k8s` | `terraform/home/k8s` | Brief asked for a template | import the image straight into each node; a pinned image URL |
| 25 | `ansible.posix` 2.1.0 pinned for firewalld, sysctl and SELinux (release date not checked against the two-weeks rule) | `ansible/requirements.yml` | The node roles need it | shell commands only |
| 26 | Ansible reaches the nodes through the Proxmox host (ProxyJump), not Tailscale | `inventories/home/hosts.example.yml` | The Mac can't reach VNet prod directly | Tailscale on each node, as in the VPS runbook |

## The owner's decisions so far

- 2026-10-25 18:30 UTC: split by app or workload; Tailscale kept out of the OPNsense code; backend in `backend.tf`.
- 2026-10-25 18:33 UTC: rename the folder `home-lab`.
- 2026-10-25 20:57 UTC: a lean to layout A, `hosts/terraform/<place>/<workload>/`.
- 2026-10-25 23:52 UTC: yes to handoff option 1 (P4: run Ansible after `tofu apply`, by hand now and a pipeline later), as long as it is written down; the other handoffs stay open.
- 2026-10-26 00:18 UTC: yes to layout B for `hosts/ansible/` (`inventories/<place>/`, `playbooks/`, shared `roles/`), which the draft already had; yes to dropping `meta/` from the roles.
- 2026-10-26 00:35 UTC: yes to the Red Hat CoP rule (roles README L424-436): addresses and VLAN numbers get no default, so each place must set them or the run stops.
- 2026-10-26 02:49 UTC: yes to fixes 1 to 3: no default for the VNet list, a `.gitignore` for filled inventories and real tfvars, and `meta/argument_specs.yml` for `opnsense_lab`.
- 2026-10-26 05:54 to 06:06 UTC: yes to one Proxmox pool per workload; names by job, not product, with folders using the same words (`network`, `firewall`, `remote-access`); STD-0001 covers containers and appliances, with new codes OS `op` (OPNsense) and role `nw` (network). Machine names are required variables; the real ones live only in git-ignored tfvars.
- 2026-10-26 06:08 UTC: yes to one shared VLAN data file that Terraform and Ansible both read (picks 15-17).
- 2026-10-26 06:28 to 06:48 UTC: go for agents to run and measure the lab code (greenfield), including applying the tofu plans.
- 2026-10-26 07:33 UTC: yes to STD-0002 staying the VLAN rule, with `inventories/home/group_vars/all/vlans.yml` as its copy in code and a docs check that fails when they differ; yes to pool names by job in STD-0001.
- 2026-10-26 07:35 UTC: yes to layout A, `hosts/terraform/<place>/<workload>/`, as decided (D-0011 rule 8); yes to STD-0003 covering `hosts/` code and cluster manifests.
- Earlier: Ansible for OPNsense with `oxlorg.opnsense`; `bpg/proxmox`; local state now; Terraform modules in their own repository (D-0011, being fixed in place to local modules first).
