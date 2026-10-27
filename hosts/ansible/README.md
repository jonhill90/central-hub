# hosts/ansible

Ansible code that configures the Proxmox host's network and safety net (host firewall, backups, notifications) and the OPNsense firewall's settings.

## What it builds

| Playbook | Role | What it sets |
|---|---|---|
| `playbooks/proxmox-host.yml` | `proxmox_network` | Tag `vmbr1`: bridge vmbr1 with no ports, VLAN-aware 2-4094, and a fixed MAC. A bridge with no ports otherwise gets an all-zero MAC, and then the SDN's VLAN devices on it can't come up. Tag `mgmt`: the host's address on VNet mgmt, with no gateway. The host's home LAN address on vmbr0 is checked after every reload and never changed. |
| `playbooks/opnsense.yml` | `opnsense_lab` | VLANs 10, 20 and 30 on the trunk port, and their interface slots with the `.1/24` gateway address. DHCP pools `.100` to `.199` on VLANs 10 and 30 only, ending before the `.224/27` load-balancer reserve. Four rules per lab VLAN: block the home LAN, allow ping and DNS to the firewall, allow everything that isn't RFC 1918. An Unbound host override `opnsense.<zone>` pointing at the mgmt gateway, plus the lab names in `opnsense_lab_host_overrides`: the c1 API name, and the wildcard `*.apps.c1.prod.<zone>` (host `*` with `subdomain: apps.c1.prod`) pointing at the c1 Gateway. On WAN: home LAN to the mgmt gateway on tcp 443, tcp/udp 53 and ping, and private sources no longer blocked. |
| `playbooks/k8s-gateway.yml` | `k8s_gateway` | Tag `gateway`: one shared Cilium Gateway `apps` in namespace `gateway` for `*.apps.c1.prod.<zone>`, HTTP on port 80, at the pinned address `k8s_gateway_address` from the load-balancer pool, and tcp 80 in the nodes' `lab` firewalld zone. Tag `smoke`: an echo app and its HTTPRoute, called from the Proxmox host through the Gateway address, a 404 check, a DNS check from the worker, then deleted. Needs `playbooks/k8s.yml` first, which applies the Gateway API CRDs and turns on Cilium's Gateway API controller. With `k8s_gateway_https: true` (BUILD-PATH S12), also an HTTPS listener on 443 with the certificate Secret `apps-tls`, and tcp 443 in the same zone; the run stops if that Secret doesn't exist yet. |
| `playbooks/k8s-certs.yml` | `k8s_certs` | Tag `certmanager`: cert-manager v1.21.3 by Helm, from the chart file checked against its SHA-256, with its CRDs, Gateway API support, and public resolvers for the DNS-01 check. Tag `issue`, only with `k8s_certs_issue: true`: the Cloudflare token as a Secret, ClusterIssuers `letsencrypt-staging` and `letsencrypt-prod` (DNS-01 at Cloudflare for the zone), and Certificate `apps` for `*.apps.c1.prod.<zone>` in namespace `gateway` from `k8s_certs_issuer`; with it false, those are removed. Tag `smoke`: an echo app on the HTTPS listener, called from the Proxmox host, then deleted. See [Certificates on c1](#certificates-on-c1). |
| `playbooks/proxmox-safety.yml` | `proxmox_notify` | Tag `notify`: a notification matcher `central-hub-errors` that sends every notification of severity error (failed backup jobs, HA fencing, other system errors) to one target. Until an endpoint is picked, the target is `central-hub-off`, a sendmail target that is switched off, so nothing new is sent. Proxmox's own default matcher and `mail-to-root` are left alone. |
| `playbooks/proxmox-safety.yml` | `proxmox_backup` | Tag `backup`: the empty HDD becomes directory storage `hdd-backup` (content backup only), through Proxmox's own Disks > Directory API: one GPT partition, ext4, a systemd mount unit at `/mnt/pve/hdd-backup` by UUID. It runs only while the disk has no partition, filesystem or signature. Then backup job `nightly-guests` in `/etc/pve/jobs.cfg`: VMs 100, 200, 201 and CT 900, daily at 03:00, snapshot mode, zstd, keep-last 3 and keep-daily 7, repeat missed. |
| `playbooks/proxmox-safety.yml` | `proxmox_firewall` | Tag `firewall`: Proxmox's own firewall at datacenter and host level only. Inbound DROP; SSH 22 and the GUI/API 8006 only from IPSet `management` (the home LAN range and VNet mgmt); ICMP and ICMPv6 from anywhere; outbound ACCEPT. Guest firewalls stay off. Two runs: the switch off first, then on, with a dead-man timer (see [Host firewall](#host-firewall)). |

The OPNsense role uses the `oxlorg.opnsense` collection, which calls the OPNsense API from the controller. The mgmt VLAN and its LAN slot are made at the console before the API can be reached, so the role leaves them alone.

## Private values

`inventories/home/hosts.example.yml` is the inventory template for the home place (one `inventories/<place>/` per place, matching `terraform/<place>/`). Every blank in it is a private value, filled from the secret store at run time. Save the filled-in copy as `inventories/home/hosts.yml` (git-ignored) and pass `-i inventories/home/`, so Ansible also loads `group_vars/all/vlans.yml`, the one shared VLAN file that `terraform/home/network` reads too. The roles stop with an error if a private value is missing, because the roles give these values no default.

## Run it

```sh
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p ./collections
ansible-playbook -i <filled-in inventory> playbooks/proxmox-host.yml --tags vmbr1 --check --diff
ansible-playbook -i <filled-in inventory> playbooks/opnsense.yml --check --diff
```

Run each playbook with `--check --diff` first: against the running lab it should report no changes. The order with Terraform is in [../README.md](../README.md).

Checked so far: `ansible-playbook --syntax-check` passes for every playbook, and `ansible-lint` passes the production profile. Its only warnings say that the API connection arguments are missing, because they are set once in the playbook, not in each task. It has never run against the lab. `proxmox-safety.yml` was also run end to end against stand-in commands on a test machine (check mode, both firewall runs, a second run with no changes, the disk guard), not against Proxmox.

## Secrets at rest on c1

`playbooks/k8s.yml` (role `k8s_control_plane`, tag `encryption`, runbook step 8a) makes the API server store Secrets in etcd encrypted with secretbox, with plain storage (`identity`) kept only to read Secrets written before. The key is 32 random bytes, base64, in a 0600 file on the controller; the filled-in inventory names the file in `k8s_control_plane_encryption_key_file`. Make it once and keep a copy in the password manager, because a restored etcd backup can't be read without it:

```sh
mkdir -p ~/.config/central-hub && (umask 077; head -c 32 /dev/urandom | base64 > ~/.config/central-hub/c1-secrets-encryption.key)
```

The run stops if the file is missing, empty, not mode 0600 or 0400, or not 44 base64 characters. On the node the key sits in `/etc/kubernetes/enc/encryption-config.yaml` (mode 0600), written with `no_log`. The role adds the flag and its folder to kubeadm's own `ClusterConfiguration` (ConfigMap `kube-system/kubeadm-config`), so `kubeadm upgrade` keeps them, and writes the API server manifest from it with `kubeadm init phase control-plane apiserver`; a new cluster gets both from `kubeadm init`'s config file. Then it writes every Secret again and reads every one straight from etcd: each value must start with `k8s:enc:secretbox:v1:`. It never changes the key: if the node holds a different one, it stops (rotation is a separate job).

On the running c1, run only this part (`--limit` skips the workers play, whose join command comes from a task this tag skips):

```sh
ansible-playbook -i inventories/home/ playbooks/k8s.yml --tags encryption --limit k8s_control_plane --check --diff
ansible-playbook -i inventories/home/ playbooks/k8s.yml --tags encryption --limit k8s_control_plane
```

## Certificates on c1

`playbooks/k8s-certs.yml` (role `k8s_certs`, runbook step 10b) gets one Let's Encrypt certificate for `*.apps.c1.prod.<zone>` and puts it on the shared Gateway's HTTPS listener. Only the label `apps.c1.prod` reaches the public Certificate Transparency logs, never an app's name. It needs [Secrets at rest on c1](#secrets-at-rest-on-c1) first: the `issue` tag stops if the API server has no encryption config, and reads the token back from etcd to check it is stored encrypted.

Values in the filled-in inventory (the template has them):

| Variable | What it is |
|---|---|
| `k8s_certs_zone` | The public zone at Cloudflare; the template sets it to `k8s_gateway_zone`. |
| `k8s_certs_acme_email` | The ACME account's contact address. |
| `k8s_certs_cloudflare_token_file` | A 0600 file on the controller holding a Cloudflare API token for this zone only, with Zone / DNS / Edit and Zone / Zone / Read (cert-manager's Cloudflare page). Make the token in the Cloudflare dashboard (My Profile > API Tokens > Create Token > Custom token); it is shown once. The run stops if the file is missing, empty or not 0600. |
| `k8s_certs_issue` | `false` until you want Let's Encrypt to be asked. With `false` nothing talks to Let's Encrypt, and a run removes the token, the issuers and the Certificate (the issued Secret stays). |
| `k8s_certs_issuer` | `letsencrypt-staging` first, then `letsencrypt-prod`. |
| `k8s_gateway_https` | `true` once the certificate is issued: the Gateway gets its HTTPS listener and the nodes open tcp 443. |

Set the switches in the inventory rather than with `-e`: a later run without them removes what they made.

## Host safety net

`playbooks/proxmox-safety.yml` is its own playbook, apart from `proxmox-host.yml`: Ansible checks a role's inputs with any `--tags`, so the safety net's required values would otherwise block a network-only run. It needs two more private values in the filled-in inventory, under the Proxmox host:

| Variable | What it is |
|---|---|
| `proxmox_firewall_home_lan_cidr` | The home router's LAN range, as `a.b.c.d/nn`: the owner's way to the host, and CT 900's eth0. |
| `proxmox_backup_disk` | The empty HDD as `/dev/disk/by-id/<id>`, the whole disk. The id holds the serial number. On the host: `ls -l /dev/disk/by-id/ \| grep -v -- -part`, then `lsblk -f <path>` must show no partition and no filesystem. |

Every other value has a default in the role's `defaults/main.yml` and is listed in its `meta/argument_specs.yml`. The picks behind those defaults are in [../AGENT-PICKS.md](../AGENT-PICKS.md), rows 36 to 47.

### Notifications

No endpoint has been picked, so `proxmox_notify_endpoint` has no default. While it is unset, the matcher sends errors to `central-hub-off`, a switched-off placeholder: nothing fails and nothing new is sent. To turn alerts on, set it in the filled-in inventory with the API's own fields for that type, for example (made-up values):

```yaml
proxmox_notify_endpoint:
  type: gotify            # smtp, gotify, webhook or sendmail
  options:
    server: https://push.example.invalid
    token: "<from the secret store>"
```

The role then makes target `central-hub-gotify`, points the matcher at it and leaves the placeholder switched off. Secret fields (`password`, `token`, `secret`, `header`) are sent with `no_log` and never compared, so a changed secret needs the endpoint deleted, or one run with the value changed by hand. Test it on the host: `pvesh create /cluster/notifications/targets/central-hub-gotify/test`.

### Backups

The disk step runs only when `lsblk` and `wipefs` see nothing on the disk: no partition, no filesystem, no partition table. A disk that already holds one ext4 partition with storage `hdd-backup` present is left as it is, whether this role formatted it or it was set up earlier by hand and is mounted by an `fstab` line (the home lab's disk: `defaults,nofail`, from an earlier build session). The role doesn't reformat it or replace its mount. Anything else stops the run before anything is written. Proxmox's Disks > Directory API checks again that the disk is unused before it partitions it. The mount unit is wanted by `multi-user.target`, not required, so a dead HDD doesn't stop the host from booting.

After the run, prove one backup and one restore source by hand on the host: `vzdump 900 --storage hdd-backup --mode snapshot --compress zstd`, then `pvesm list hdd-backup`.

### Host firewall

Proxmox's own firewall (pve-firewall), at datacenter (`/etc/pve/firewall/cluster.fw`) and host (`/etc/pve/local/host.fw`) level only. No VM or CT gets its own firewall, and the role stops if one has it switched on. The rules:

| Direction | Rule | Why |
|---|---|---|
| in | policy DROP | Default for the host |
| in | tcp 22 and 8006 from IPSet `management` | `management` holds `proxmox_firewall_home_lan_cidr` and VNet mgmt (`10.1.50.0/24`). Proxmox adds the host's own LAN (`local_network`) to it and opens 22, 8006, 3128 (SPICE), 5900-5999 (VNC) and 60000-60050 (migration) from it by itself |
| in | ICMP and ICMPv6 from anywhere; neighbour discovery (`ndp: 1`) | Ping, unreachable and time-exceeded messages; IPv6 neighbour discovery |
| out | policy ACCEPT | The host's own updates, DNS, NTP and the routes to the lab |
| forward | `nf_conntrack_allow_invalid: 1` | Once on, pve-firewall sends every bridged guest packet through its FORWARD chain and drops conntrack-INVALID ones there. Skipping that drop keeps guest traffic (OPNsense routing, CT 900) as it is today |

The role is safe to run in check mode: `--check --diff` shows the two files as they would be written, and runs no command that changes anything.

Rollout, from `hosts/ansible/` on the controller, with a second session open (the web UI Shell or the console):

1. `ansible-playbook -i inventories/home/ playbooks/proxmox-safety.yml --tags firewall --check --diff`: read the two files.
2. `ansible-playbook -i inventories/home/ playbooks/proxmox-safety.yml --tags firewall`: writes both files with `enable: 0`. Nothing is filtered yet. `pve-firewall compile` prints nothing while the switch is off, so the role also runs `files/pve-firewall-preview.pl`, which compiles the same files with the switch on in memory only, and prints the ruleset. Check that the `management` IPSet holds the two ranges, and that `PVEFW-HOST-IN` accepts tcp 22 and 8006 from it.
3. `ansible-playbook -i inventories/home/ playbooks/proxmox-safety.yml --tags firewall -e '{"proxmox_firewall_enable": true}'`: the role records what works now (CT 900's tailnet client, CT 900 to OPNsense on VNet mgmt, the host to each c1 node on port 22), arms a 10-minute dead-man timer on the host (`systemd-run`, which runs `pvesh set /cluster/firewall/options --enable 0`), switches the firewall on, waits until `pve-firewall compile` says "no changes", then checks: `pve-firewall status` says enabled/running, a new SSH connection works, the API on 8006 answers the controller, vmbr0 keeps its address, and everything that worked before still works. Only then is the timer cancelled.
4. Set `proxmox_firewall_enable: true` in the filled-in inventory. A later run without it would switch the firewall off again.

Rollback, at the console or a session that still works:

- `pve-firewall stop`: removes every Proxmox rule now. The service starts again at the next boot with the switch still on.
- `pvesh set /cluster/firewall/options --enable 0`, or `enable: 0` in `/etc/pve/firewall/cluster.fw`: switches it off for good; the daemon removes the rules within about 10 seconds. Then set `proxmox_firewall_enable: false` in the inventory.
- If the run was cut off after step 3 armed the timer, wait: the host switches the firewall off by itself after 10 minutes.

## Still open

- No release of `oxlorg.opnsense` for OPNsense 26.7 has been seen yet. The pinned 26.1.11 is tested on 26.1.
- The import of the running lab's objects is untested. The VLANs made at the console are named `vtnet0_vlan<tag>`, while the collection names new ones `vlan0.<tag>`. Its DHCP ranges, VLANs and rules are matched by description, and the console-made ones may not carry these descriptions.
- The vmbr1 MAC field is unchecked: whether `hwaddress` in the vmbr1 stanza, written through `interfaces_file`, keeps the MAC fixed across `ifreload` and Proxmox network edits.
- The collection has no module for interface assignment. The role calls the `interfaces/assignment` API through the collection's `raw` module instead. That API is in the current OPNsense API docs, but its presence in 26.7 and the shape of its replies are unverified. The WAN `blockpriv` change uses the same API.
- The `dnsmasq_general` module sets every general dnsmasq setting at once; the ones the role doesn't name go to the collection's defaults.
- Whether OPNsense's default "allow LAN to any" rules are rules this API manages on 26.7 is unchecked.
- The safety net has not run on Proxmox. Unchecked there: that Ansible's `template` writes into `/etc/pve` (pmxcfs) with `unsafe_writes` as the fallback; that the API accepts each option as the roles pass it; that `pvesh create .../disks/directory` accepts a `/dev/disk/by-id/` path (pve-storage resolves it with `abs_path`, read in the source, not run).
- Fencing alerts are matched by severity `error`, not by type. Whether every fencing message uses that severity is not checked.
- Backing up VM 100 in snapshot mode asks the QEMU guest agent inside OPNsense to freeze its filesystems. The agent hung on large payloads during the build; if a freeze hangs, the lab router stalls during the backup. Run the first backup by hand and watch it.
- CT 900 is assumed to masquerade (Tailscale's default for subnet routes), so the host sees tailnet clients as CT 900's own addresses, which `management` covers. Without masquerading, tailnet sources would need their own rule.
- Not covered yet: the GUI's alternate hostname, which its DNS-rebind check needs for `opnsense.<zone>`, and everything inside the connector container.
