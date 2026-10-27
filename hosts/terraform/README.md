# hosts/terraform

Run folders laid out as `<place>/<workload>/` (layout A from RB-0083; decided in D-0011 rule 8, the owner's yes of 2026-10-26 at 07:35 UTC). Each run folder is one root module with its own state and its own `backend.tf`.

| Run folder | What it makes | Needs first |
|---|---|---|
| [home/network/](home/network/) | SDN zone `lab` on vmbr1, VNets `prod` (10), `qa` (20), `dev` (30), `mgmt` (50), one `10.1.<tag>.0/24` subnet each, and the SDN applier | vmbr1 with a fixed MAC (Ansible, `proxmox-host.yml --tags vmbr1`) |
| [home/firewall/](home/firewall/) | VM 100, the OPNsense firewall (net0 trunk on vmbr1, net1 WAN on vmbr0) | home/network |
| [home/remote-access/](home/remote-access/) | CT 900, the tailnet connector (eth0 on vmbr0, eth1 on VNet mgmt) | home/network |
| [home/k8s/](home/k8s/) | Cluster c1's node VMs: template 9000 from a pinned AlmaLinux 10 cloud image, and nodes 200 (control plane) and 201 (worker) cloned from it onto VNet prod | home/network |
| [home/certificates/](home/certificates/) | The Cloudflare API token cert-manager uses for its Let's Encrypt DNS-01 challenge (one zone, Zone / DNS / Edit and Zone / Zone / Read, 90-day expiry), written to the 0600 file the Ansible inventory names. Not Proxmox: it talks to Cloudflare only | the c1 cluster and Secrets at rest (runbook steps 8 and 8a); run it before `playbooks/k8s-certs.yml --tags issue` |

[home/bootstrap/](home/bootstrap/) is not a run folder: `iac-access.sh` makes the limited Proxmox account and token that Terraform uses, once, on the host.

Every run folder has the same files: `main.tf` (the resources), `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`, `backend.tf` and its own `.terraform.lock.hcl`. `home/network`, `home/firewall` and `home/remote-access` also have `imports.tf`, which adopts the objects the lab had before this code; `home/k8s` and `home/certificates` made new objects, so they have none.

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

## home/certificates: the cert-manager token

cert-manager proves to Let's Encrypt that it controls the zone by writing a TXT record through the Cloudflare API (role `k8s_certs`, runbook step 10b). This folder makes the Cloudflare API token it uses, so no one makes it by hand in the dashboard:

- The zone is looked up by name (`var.zone_name`, no default, the same value as the inventory's `k8s_certs_zone`), and the two permission groups by name and scope (`DNS Write` and `Zone Read`, the API names of the dashboard's Zone / DNS / Edit and Zone / Zone / Read, cert-manager's Cloudflare page). No ID is written in the code. The token's only resource is that one zone, not all zones as cert-manager's page shows.
- `cloudflare_api_token` makes a user-owned token, like the dashboard's My Profile > API Tokens. `expires_on` is 90 days after the token is made (`var.token_lifetime_days`, the same lifetime as the Proxmox token `iac@pve!apply`).
- `local_sensitive_file` writes the token to `var.token_file` with mode 0600 (folder 0700). Use the same path as `k8s_certs_cloudflare_token_file` in the inventory. If the file is changed or deleted, the next apply writes it again.
- Optional: `var.request_ip_in` limits where the token may be used from (Cloudflare's client IP condition). It is off by default: the cluster reaches Cloudflare from the home's public address, which can change and would then break renewals without warning, and the address would be a private value.

### The bootstrap token

Cloudflare has no API call that makes the first token, so one credential is made by hand, once, in the same way as the Proxmox bootstrap ([home/bootstrap/](home/bootstrap/) makes `iac@pve` and its token):

1. In the Cloudflare dashboard: My Profile > API Tokens > Create Token, template **Create additional tokens**. It holds one permission, **User > API Tokens > Edit**, and nothing else. Leave it with no other permission. Give it an expiry (for example 1 year) and, if the Mac has a stable public address, a client IP filter.
2. Save it on the Mac, never in the repository: `(umask 077; pbpaste > ~/.config/central-hub/cloudflare-bootstrap-token.txt)`, then `chmod 600` that file and clear the clipboard.

This token can make tokens with any permission the owner's user has, so it is as strong as the owner's Cloudflare login for every zone. Keep it out of the cluster and out of every other tool. The token it makes has only the two zone permissions.

The Cloudflare provider would also make an account-owned token (`cloudflare_account_token`). That needs the account ID as one more private variable and a bootstrap token with Account > Account API Tokens > Edit. This folder uses a user-owned token, which is what cert-manager's page describes and what the role's earlier text told the owner to make.

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
