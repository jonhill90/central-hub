# hosts/terraform

Run folders laid out as `<place>/<workload>/` (layout A from RB-0083; decided in D-0011 rule 8, the owner's yes of 2026-10-26 at 07:35 UTC). Each run folder is one root module with its own state and its own `backend.tf`.

| Run folder | What it makes | Needs first |
|---|---|---|
| [home/network/](home/network/) | SDN zone `lab` on vmbr1, VNets `prod` (10), `qa` (20), `dev` (30), `mgmt` (50), one `10.1.<tag>.0/24` subnet each, and the SDN applier | vmbr1 with a fixed MAC (Ansible, `proxmox-host.yml --tags vmbr1`) |
| [home/firewall/](home/firewall/) | VM 100, the OPNsense firewall (net0 trunk on vmbr1, net1 WAN on vmbr0) | home/network |
| [home/remote-access/](home/remote-access/) | CT 900, the tailnet connector (eth0 on vmbr0, eth1 on VNet mgmt) | home/network |
| [home/k8s/](home/k8s/) | Cluster c1's node VMs: template 9000 from a pinned AlmaLinux 10 cloud image, and nodes 200 (control plane) and 201 (worker) cloned from it onto VNet prod. A rehearsal cluster beside c1 uses the same folder with its own state file and tfvars and `create_template = false`, so it clones template 9000 without owning it | home/network |
| [home/k8s-talos/](home/k8s-talos/) | A Talos Linux cluster's node VMs for the R4 rehearsal beside c1: the pinned Talos ISO from Image Factory (with the QEMU guest agent) and nodes that boot it, with VirtIO SCSI and UEFI as Talos's Proxmox guide asks. talosctl configures them; nothing here does | home/network |
| [home/certificates/](home/certificates/) | The Cloudflare API token cert-manager uses for its Let's Encrypt DNS-01 challenge (one zone, Zone / DNS / Edit and Zone / Zone / Read, 90-day expiry), written to the 0600 file the Ansible inventory names. Not Proxmox: it talks to Cloudflare only | the c1 cluster and Secrets at rest (runbook steps 8 and 8a); run it before `playbooks/k8s-certs.yml --tags issue` |
| [home/dns-token/](home/dns-token/) | The Cloudflare API token OpenTofu uses for the public zone's records (one zone, DNS Write and Zone Read, 90-day expiry), written to a 0600 file. Same shape as home/certificates, its own token | the bootstrap token |
| [home/dns/](home/dns/) | Every DNS record of the public zone at Cloudflare, from the git-ignored `home.records.tfvars.json`; `export-records.sh` writes that file from the live zone once, and `imports.tf` adopts the records ([runbook](../../docs/runbooks/manage-public-dns-records.md)) | home/dns-token |

| [home/tailnet/](home/tailnet/) | Tailnet settings, not Proxmox: CT 900's subnet routes for every lab VLAN turned on, and split DNS that sends the lab names to OPNsense Unbound on the mgmt gateway, so the owner's Mac resolves them ([runbook](../../docs/runbooks/set-up-lab-dns.md)). Logs in with a tailnet OAuth client from the git-ignored `hosts/.env` | `playbooks/tailnet-connector.yml`, which makes CT 900 advertise the same routes |
| [home/tailnet-policy/](home/tailnet-policy/) | The tailnet policy file (tag owners, grants, SSH rules and tests), rendered from `policy.hujson.tftpl` with the Proxmox host's address filled in at apply time. Not applied yet: adopt the live policy first ([below](#hometailnet-policy-the-tailnet-policy-file)). Logs in with its own OAuth client, scope `policy_file` | home/tailnet's routes, which the policy auto-approves |
| [azure/backup/](azure/backup/) | Azure, not Proxmox: resource group, storage account and private container for c1's restic backups. No shared key, no anonymous access, data endpoint open only to the home's public address ([runbook](../../docs/runbooks/back-up-c1-off-box.md)). Signs in as the agents' service principal `agent-azure` | `agent-azure` ([runbook](../../docs/runbooks/give-agents-access-to-azure.md)) |

[home/bootstrap/](home/bootstrap/) is not a run folder: `iac-access.sh` makes the limited Proxmox account and token that Terraform uses, once, on the host.

Every run folder has the same files: `main.tf` (the resources), `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`, `backend.tf` and its own `.terraform.lock.hcl`. `home/network`, `home/firewall` and `home/remote-access` had an `imports.tf` that adopted the objects the lab had before this code. The adoption was applied, so those files were removed on 2026-11-08 (STD-0004 rule 1 allows the file only while a folder adopts objects): import blocks for objects that don't exist stop `tofu plan` on an empty host, and a rebuild from bare metal has to plan clean. To adopt running objects again after state is lost, see [Adopt a running lab after state is lost](#adopt-a-running-lab-after-state-is-lost).

Run folders don't read each other's state. A value one folder needs from another, such as the VNet name `mgmt`, is an input variable with the same value as the producer's output (`home/network` output `vnet_ids`). That choice, the place name `home` and the rest are listed in [../AGENT-PICKS.md](../AGENT-PICKS.md) for the owner's review.

## Run one folder

```sh
cd home/network
tofu init -backend-config="path=<folder outside the repo>/home-network.tfstate"
tofu plan -var vlans_file=../../../ansible/inventories/home/group_vars/all/vlans.yml
```

`home/network` reads its VLANs from the one shared VLAN file, `ansible/inventories/<place>/group_vars/all/vlans.yml`, which Ansible also loads, so the VLAN list is written once. `var.vlans_file` has no default. Real `*.tfvars` files are git-ignored.

`home/firewall` and `home/remote-access` have no default for the machine's name (`firewall_vm_name`, `connector_hostname`), and `home/k8s` none for its node names and addresses (`nodes`). Their `home.tfvars.example` files hold made-up STD-0001-shaped names; the real names go only in the git-ignored `home.tfvars`.

Private values (node name, MACs, the connector's mgmt address) come from the secret store as `TF_VAR_<name>`, and the provider reads `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN`. The four Proxmox run folders, `home/network`, `home/firewall`, `home/remote-access` and `home/k8s`, have been planned and applied against the home lab from the operator's Mac, with local state. `home/certificates` has not been planned or applied yet.

## Adopt a running lab after state is lost

If a state file is lost while the lab still runs, a plain `apply` would try to make every object again, and Proxmox would refuse the IDs it already has. Adopt the objects into a new state with `tofu import` instead, in each folder, after `tofu init` with the usual backend path. The IDs are the ones the removed `imports.tf` files used (in git history before 2026-11-08):

```sh
# home/network (VLAN names and ranges from the shared VLAN file; one vnet and one subnet per VLAN)
tofu import -var vlans_file=<VLAN file> proxmox_sdn_zone_vlan.lab lab
tofu import -var vlans_file=<VLAN file> 'proxmox_sdn_vnet.lab["prod"]' prod
tofu import -var vlans_file=<VLAN file> 'proxmox_sdn_subnet.lab["prod"]' prod/lab-10.1.10.0-24
# home/firewall
tofu import -var-file=home.tfvars proxmox_virtual_environment_vm.opnsense <node name>/100
# home/remote-access
tofu import -var-file=home.tfvars proxmox_virtual_environment_container.ts_connector <node name>/900
# home/k8s, one line per node, plus the template
tofu import -var-file=home.tfvars 'proxmox_virtual_environment_vm.node["<node hostname>"]' <node name>/200
tofu import -var-file=home.tfvars 'proxmox_virtual_environment_vm.template[0]' <node name>/9000
```

Then `tofu plan` must show no changes, or only changes you expect, before any apply. `home/k8s`'s downloaded image (`proxmox_download_file.almalinux10[0]`) and the network folder's `proxmox_sdn_applier` were never imported before; read what the plan does to them, and stop if it would replace the template or a node. `home/certificates` holds only a Cloudflare token, which is simpler to make again: delete the old token in the dashboard and apply.

## home/certificates: the cert-manager token

cert-manager proves to Let's Encrypt that it controls the zone by writing a TXT record through the Cloudflare API (role `k8s_certs`, runbook step 10b). This folder makes the Cloudflare API token it uses, so no one makes it by hand in the dashboard:

- The zone is looked up by name (`var.zone_name`, no default, the same value as the inventory's `k8s_certs_zone`), and the two permission groups by name and scope (`DNS Write` and `Zone Read`, the API names of the dashboard's Zone / DNS / Edit and Zone / Zone / Read, cert-manager's Cloudflare page). No ID is written in the code. The token's only resource is that one zone, not all zones as cert-manager's page shows.
- `cloudflare_api_token` makes a user-owned token, like the dashboard's My Profile > API Tokens. `expires_on` is 90 days after the token is made (`var.token_lifetime_days`, the same lifetime as the Proxmox token `iac@pve!apply`).
- `local_sensitive_file` writes the token to `var.token_file` with mode 0600 (folder 0700). Use the same path as `k8s_certs_cloudflare_token_file` in the inventory. If the file is changed or deleted, the next apply writes it again.
- Optional: `var.request_ip_in` limits where the token may be used from (Cloudflare's client IP condition). It is off by default: the cluster reaches Cloudflare from the home's public address, which can change and would then break renewals without warning, and the address would be a private value.

### The bootstrap token

Cloudflare has no API call that makes the first token, so one credential is made by hand, once, in the same way as the Proxmox bootstrap ([home/bootstrap/](home/bootstrap/) makes `iac@pve` and its token):

1. In the Cloudflare dashboard's account API tokens page: Create Token, template **Create Account Tokens** (one permission, **Account API Tokens Write**, on the account). Add one more policy: **Zone Read**, scoped to the one zone, so the code finds the zone and its account by name and no ID is copied by hand. Name it so it is recognisable (for example `central-hub-terraform-bootstrap`), give it an expiry (90 days, like the Proxmox token), and leave the client IP filter empty unless the Mac has a stable public address.
2. Save it on the Mac, never in the repository, in a 0600 file (for example `~/.config/central-hub/cloudflare-bootstrap-token.txt`), and clear the clipboard.

This token can make account tokens with any permission the account has, so it is as strong as an account admin for every zone. Keep it out of the cluster and out of every other tool. The token it makes has only the two zone permissions.

The token this folder makes is account-owned (`cloudflare_account_token`), so it keeps working if a user leaves the account. A user-owned token (`cloudflare_api_token`, bootstrap template **Create additional tokens**, User > API Tokens > Edit) works the same way and is the kind cert-manager's page describes.

### Run it on the Mac

```sh
cd hosts/terraform/home/certificates
cp home.tfvars.example home.tfvars      # git-ignored; put the real zone and the token file path in it
chmod 600 home.tfvars
tofu init -backend-config="path=$HOME/.local/state/central-hub/home-certificates.tfstate"
export CLOUDFLARE_API_TOKEN="$(cat ~/.config/central-hub/cloudflare-bootstrap-token.txt)"
tofu plan -var-file=home.tfvars -out=certificates.tfplan
tofu apply certificates.tfplan
unset CLOUDFLARE_API_TOKEN
cd ../../../ansible
ansible-playbook -i inventories/home/ playbooks/k8s-certs.yml --tags issue
```

`tofu apply` and then the `issue` run are the whole flow. The role reads the file, checks that it is 0600, and puts the token in the cluster only when it differs from the Secret there.

### Rotation

A `time_rotating` resource starts a clock when the token is made. It runs out 76 days later (`token_lifetime_days` minus `token_renew_days`, 90 - 14). An apply before then changes nothing. The first apply after then makes a new clock, and `replace_triggered_by` makes a new token with a new 90-day expiry. The new token is made before the old one is deleted (`create_before_destroy`), and the new value is written to the token file. Then run the `issue` tag again to put it in the cluster. Between the apply and that run, the cluster still holds the deleted token, so a challenge in those minutes fails and cert-manager tries again later. Output `token_replace_after` shows when the next apply will rotate.

Nothing runs the apply on a schedule yet. If no one applies within the 14 days, the token expires and cert-manager can't renew. The certificate is still valid for weeks after that, because cert-manager renews at two thirds of its lifetime. To rotate now: `tofu apply -var-file=home.tfvars -replace=time_rotating.token`.

### Where the token value is

- In the token file (0600), which the `issue` run reads.
- **In this folder's state file, in plain text.** The provider keeps the value in state, because Cloudflare shows a token's value only when it is made. State encryption (OpenTofu's `encryption` block) is not set up yet; that is deferred, as for the other folders. Until then, keep the state file 0600 under `~/.local/state/central-hub/` and never copy it anywhere.
- In the cluster, as Secret `cloudflare-api-token` in namespace `cert-manager`, encrypted at rest (runbook step 8a).

### Later, not in this folder

A CAA record on the zone that allows only `letsencrypt.org` would stop other certificate authorities from issuing for the zone. It is left out: it changes the whole public zone, not only the lab's names, and it is the owner's decision.

## home/tailnet-policy: the tailnet policy file

The policy says who on the tailnet may reach what. It was edited by hand in the admin console until now, and this folder has never been applied, so the live policy may differ from the file. `overwrite_existing_content` is false, so the first apply would stop with an error rather than replace it. Adopt it, then read the difference:

```sh
cd home/tailnet-policy
tofu init -backend-config="path=<folder outside the repo>/home-tailnet-policy.tfstate"
tofu import -var-file=home.tfvars tailscale_acl.policy acl
tofu plan -var-file=home.tfvars
```

The plan shows every line the file would change in the live policy. Apply only after the owner reads it: a grant the file drops cuts off whatever used it. The tailnet runs the policy's `tests` on save and refuses a policy that fails them. To undo, apply the previous version of `policy.hujson.tftpl` from git, or paste the old policy in the admin console.
