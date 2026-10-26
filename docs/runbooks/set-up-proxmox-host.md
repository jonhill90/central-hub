---
title: Set up a Proxmox VE host by hand, from fresh install to a patched, locked-down, backed-up host
status: draft
kind: manual
trigger: on request; after a fresh Proxmox VE 9 install
runner: the owner
outcome: a Proxmox VE 9 host on the no-subscription repositories, fully upgraded, with a tested break-glass login, key-only SSH, a least-privilege agent account and API token, backups and notifications
needs: console or LAN access to the host as root@pam; a password manager with an offline copy; a TOTP app
private-values: [host-name, host-address, root-pam-password, root-pam-recovery-keys, pve-iac-token]
files: []
last-tested:
superseded-by:
---

# Set up a Proxmox VE host by hand

**Status:** draft, not yet run end to end on the host. Steps 0 and 2 were run on the host on 2026-10-22. Whether step 1 was run as written is not recorded; step 2's upgrade worked, so the host's repositories were usable. Built from research batch RB-0061; its independent check held for 118 of 120 sampled source rows, and the 2 weaker rows were fixed.

## Before you start

### The story

Proxmox VE 9 is freshly installed on a home PC. Right now it is a fresh box on the home network: root logs in with a password, it pulls updates from a repository with no subscription, it has no backups, and nothing outside the house can reach it. That last part is good, and this runbook keeps it that way.

The runbook walks the box through three parts, each one depending on the one before:

```text
 Part 1  Make it a clean, updated host        (at the keyboard or a LAN browser)
    │      rename → repos → updates + microcode → time → break-glass login + 2FA → SSH keys
    ▼
 Part 2  Let the agent in, with least privilege
    │      Linux user `agent` → Terraform account `iac@pve`, its pools and a token only you can read
    ▼
 Part 3  Give it a safety net
           backups (+ "repeat missed": the PC is often off) → notifications
```

Why this order: updates first, because Proxmox published guest-reachable qemu-server advisories on the day of the install, so no VM goes on the box before a full upgrade [S2 summary; S1-83]. The agent comes in only after your own login is locked down, so the agent never has more than you deliberately gave it.

### Not in this runbook

The networking steps come after the IP address plan: remote access through a connector container and the tailnet policy, the Proxmox firewall (it needs the management address range), GPU passthrough, and the Kubernetes node VMs on the lab network. They join this runbook, or a runbook of their own, once the plan exists.

### How to read this runbook

- Each step has the commands, then a `why:` line of one or two sentences, then an `expect:` line where there is something to see. A longer story, where there is one, comes before the commands.
- `[S1-12]` and similar labels are rows in the ledger of research batch RB-0061, kept in the owner's private research archive. `[pick]` marks the agent's lean; the owner decides. `[inferred]` is reasoning, and `[model]` is not checked against a source.
- `<host name>` follows [STD-0001](../standards/0001-names.md). `<host address>` is the host's LAN address. Neither is written here.

Reminders used below:

- **※F (prove a way in before you close one):** open a second session that already works before you change SSH or the firewall. Proxmox's own firewall docs say this [S1-42].
- **※U (full-upgrade, never upgrade):** `apt upgrade` can leave Proxmox half-upgraded; always `apt full-upgrade` [S1-14].
- **※S (no private names in public places):** hostnames, tailnet names and addresses stay out of this public repository (CLAUDE.md rule 4). `tailscale cert` and Let's Encrypt publish names to public certificate logs, so neither is used here [S2-36 row; S1-53].
- **※R (root@pam is break-glass):** root@pam can never be deleted [S1-23]. Its password lives in the password manager plus an offline copy, and you use it only when your normal login is broken.

## Steps

### Part 1. Make it a clean, updated host

#### 0. Rename the host (before anything else)

The host takes its name from [STD-0001](../standards/0001-names.md) (env `p` for prod, OS `de` for Debian, role `hv` hypervisor).

```bash
# 0a. check the node is empty: both lists must be empty. Delete any test VM first.
qm list; pct list

# 0b. replace the installer's name with the new one in the three files that hold it [wiki: Change Hostname]
#     (on 9.2 the name sits in these three files; /etc/mailname doesn't exist)
sed -i 's/\b<old name>\b/<host name>/g' /etc/hostname /etc/hosts /etc/postfix/main.cf
cat /etc/hostname /etc/hosts

# 0c. reboot
reboot

# 0d. after reboot: remove the old node folder and its graph data [wiki: Cleanup]
ls /etc/pve/nodes/                                  # shows the old and the new name
ls -R /etc/pve/nodes/<old name>                     # on an empty node: only certs and empty qemu-server/ lxc/ folders
#    if qemu-server/ or lxc/ hold any .conf file, stop and ask: a VM still exists
rm -r /etc/pve/nodes/<old name>                     # the new folder already has its own files; certs are redone in 0e
# the wiki copies the old usage graphs across; on a box a few days old they aren't worth keeping [inferred]
rm -rf /var/lib/rrdcached/db/pve2-node/<old name> /var/lib/rrdcached/db/pve2-storage/<old name>

# 0e. new web certificate for the new name, then check
pvecm updatecerts --force                           # prints "generate new node certificate"
systemctl restart pveproxy
hostname -f
```

why: The installer gave the host a default name, and Proxmox uses the hostname as the node name; the rename "must be done on a empty node" (source: <https://pve.proxmox.com/wiki/Renaming_a_PVE_node>) and is impossible once the node is in a cluster. So do it now, while there are no VMs and no cluster.

expect: `/etc/hostname` holds the new name; `hostname -f` prints it with the local domain; the web UI at `https://<host address>:8006` shows the node under its new name. Storage you added (for example a Directory on a second disk) lives in `/etc/pve/storage.cfg`, which is not per-node, so it stays [inferred]. Check each storage's "Nodes" setting still includes the new name.

status: run on the host on 2026-10-22.

#### 1. Point apt at repositories you can actually use

In the web UI (node → Updates → Repositories) you can disable `pve-enterprise` and the Ceph `enterprise` entry and add `No-Subscription` with buttons [S1-12]. Or in the node Shell:

```bash
# 1a. look first
ls /etc/apt/sources.list.d/
cat /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources

# 1b. add "Enabled: no" to each enterprise stanza (the docs' own method) [S1-07, S1-11]
#     open each file and add the line under the stanza:   Enabled: no
nano /etc/apt/sources.list.d/pve-enterprise.sources
nano /etc/apt/sources.list.d/ceph.sources

# 1c. add the no-subscription repository [S1-08, S1-89]
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# 1d. check
apt update
apt policy | grep -i proxmox
```

why: A fresh 9.x install has the enterprise repositories switched on. Without a subscription key, `apt update` fails on them, so you would get no updates at all [S1-06, S1-07, S1-10].

※ This is what makes the upgrade in [step 2](#2-update-everything-add-cpu-microcode-reboot) possible.

expect: `apt update` shows no errors, and Proxmox packages come from download.proxmox.com.

Proxmox calls the no-subscription repository "for testing and non-production use" [S1-08]. That fits a homelab; forum regulars treat it as a step closer to beta than enterprise [S2 table, repos row].

Keep the Debian base repositories (`debian.sources`) untouched; Proxmox always needs them [S1-09]. Check their `Components:` line contains `non-free-firmware`, because the docs contradict each other on whether it is on by default and step 2 needs it [S1-90].

**The "No valid subscription" pop-up:** options [S2 table, nag row]:

| Option | What happens | Source |
|---|---|---|
| Click OK each login | Nothing changes | — |
| Buy a Community subscription | Pop-up gone, enterprise repo usable | S2-10..S2-13 |
| Patch it out (community script / sed) | Edits a packaged JS file, re-patched on each update; staff call it "not supported" | S2-10..S2-14 |

[pick] click OK for now: no packaged file is modified, so nothing can break on update.

**Don't run the community post-pve-install script.** It does steps 1-2 and the nag patch only, nothing for users, SSH, firewall, 2FA or backups, and it pulls more unpinned code as root from `community-scripts/core@main` at run time [S2-02, S2-03, S2 summary 1-2]. Doing it by hand teaches the same thing and runs only what you read.

#### 2. Update everything, add CPU microcode, reboot

```bash
apt update
apt full-upgrade          # ※U
apt install intel-microcode   # or amd64-microcode on an AMD CPU; lscpu shows which
grep -m1 "linux /boot/vmlinuz" /boot/grub/grub.cfg   # before rebooting: GRUB's default entry is the new kernel
reboot
# after reboot
grep microcode /proc/cpuinfo | uniq
dmesg | grep microcode
uname -r                  # note the kernel
lscpu | grep "Model name"
free -h                   # RAM decides worker VM size later
```

why: Patches go in before any guest exists ※U. Microcode fixes CPU bugs that the BIOS may not have [S1-17, S1-18].

※ The repositories from [step 1](#1-point-apt-at-repositories-you-can-actually-use) are where these come from.

expect: a newer kernel after the reboot, and the microcode revision loaded early in `dmesg`. On the host on 2026-10-22, the microcode package was already installed by the ISO; the upgrade brought kernel 7.0.14-25-pve and a newer microcode revision.

**If a new kernel misbehaves** (it will happen at some point with a GPU box): pick the older kernel in the boot menu, then pin it until a fix lands, and unpin as soon as possible so security fixes apply [source: <https://pve.proxmox.com/pve-docs/pve-admin-guide.html>, "Override the Kernel-Version for next Boot"]:

```bash
proxmox-boot-tool kernel list
proxmox-boot-tool kernel pin <older-version>     # later: proxmox-boot-tool kernel unpin
```

**Which bootloader you have** decides where kernel options go if one is ever needed (GRUB: `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` then `update-grub`; systemd-boot: `/etc/kernel/cmdline` then `proxmox-boot-tool refresh`) [same page, "Editing the Kernel Commandline"]:

```bash
efibootmgr -v | grep -iE 'proxmox|systemd'     # grubx64/shimx64 = GRUB, systemd-bootx64 = systemd-boot
proxmox-boot-tool status
```

On an ext4/LVM install `proxmox-boot-tool status` prints `E: /etc/kernel/proxmox-boot-uuids does not exist`; that is expected, because GRUB boots via shimx64.efi and proxmox-boot-tool only manages ZFS-root installs [model].

**Ongoing updates:** options [S2 table, unattended-upgrades row]:

| Option | For | Against | Source |
|---|---|---|---|
| A. You run `apt update && apt full-upgrade` weekly and watch Proxmox security advisories | You see every change; matches doing every step by hand | Needs a habit | S1-14, S1-83, NIST SP 800-123 §4.1 (S2-21) |
| B. `unattended-upgrades` with the Proxmox origin added and a reboot window | Patches land without you | Proxmox staff warn the default (Debian-only) setup "might cause problems"; NIST 800-123 says test before auto-install | S2-19..S2-22 |

[pick] A for now. Proxmox already emails root@pam every day when updates are available [S1-13], so [step 7](#7-notifications) turns that into a reminder.

status: run on the host on 2026-10-22.

#### 3. Check the clock

```bash
chronyc tracking          # "Leap status: Normal" and a small offset
timedatectl               # time zone; set with: timedatectl set-timezone <Region/City>
```

why: 2FA codes ([step 4](#4-break-glass-login-and-the-admins-group)) are time-based, and TLS checks need the right time [S1-21].

expect: Chrony is the default and already points at public servers; nothing to configure [S1-20].

#### 4. Break-glass login and the admins group

On 2026-10-22 the owner asked for an industry-standard break-glass account, with daily logins later through Authentik or Keycloak, and on 2026-10-23 said yes to the shape below.

- **Break-glass = `root@pam`.** It "can always log in via the Linux PAM realm" and "cannot be deleted" [source: <https://pve.proxmox.com/wiki/User_Management>, "System administrator"]. No separate personal account now.
- **Daily login = Authentik or Keycloak, later**, through an OpenID Connect realm; setting `groups-claim` maps IdP groups to Proxmox groups [source: same page, "OpenID Connect", "Groups mapping"]. The admins group made here is where that mapping lands.

```bash
pveum group add admins -comment "Human administrators (IdP group maps here later)"
pveum acl modify / -group admins -role Administrator
pveum group list; pveum acl list            # check
```

Then, by hand in the web UI as root@pam (only the owner does this):

- **Password:** long and random, in the password manager plus an offline copy [pick].
- **2FA:** Datacenter → Permissions → Two Factor → Add → TOTP in your authenticator app [S1-28].
- **Recovery keys:** same place, Add → Recovery Keys; print them and keep them with the offline password copy. One set per user, each key works once [S1-32].
- WebAuthn needs a trusted certificate, which this host doesn't have ※S, so skip it for now [S1-31].
- **Test it** every 90 days: log in as root@pam with TOTP [source: Microsoft page below, "Validate accounts regularly"].

why: Everyday logins will go through an identity provider (IdP), and a local emergency ("break-glass") account that does not depend on it is the usual pattern, tested regularly [source: <https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access>]. If the IdP runs on the cluster that lives on this box, an outage would otherwise lock you out of the machine that fixes it [inferred].

expect: a root@pam login asks for the TOTP code; `pveum acl list` shows `admins` with `Administrator` on `/`.

Lockout facts so they don't surprise you: 8 wrong TOTP codes disable TOTP until a recovery key or `pveum user tfa unlock root@pam` from the shell [S1-30]. SSH by key ([step 5](#5-ssh-for-you-keys-not-passwords)) is the second way in.

Later, when the IdP exists (sketch, values from the IdP): `pveum realm add <idp> --type openid --issuer-url <url> --client-id <id> --client-key <secret> --username-claim username --autocreate 1 --groups-claim groups` [source: <https://pve.proxmox.com/wiki/User_Management>, "OpenID Connect"; groups flags inferred from "Groups mapping"]. Secrets go in through the secrets layer, never in a repo.

#### 5. SSH for you: keys, not passwords

※F Keep the web UI Shell open while you do this; it is your second way in.

```bash
# on your workstation: copy your public key to the host (LAN)
ssh-copy-id root@<host address>
ssh root@<host address> 'echo key login works'      # prove it before changing anything

# on the host: a drop-in that sorts first (sshd keeps the FIRST value it reads)
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t && systemctl reload ssh
sshd -T | grep -Ei 'passwordauthentication|permitrootlogin|kbdinteractive'   # check effective values, not the file
```

why: Proxmox ships with "sshd configured to allow logging in as root with a password" [S1-77], and on a single node nothing in Proxmox needs it. Keys only also keeps the way open to a cluster later, which the admin guide says works with `PasswordAuthentication no` [S1-78, S1-80].

※ The TOTP lockout in [step 4](#4-break-glass-login-and-the-admins-group) is why a key login is worth having as the second way in.

expect: `sshd -T` shows `passwordauthentication no`, `kbdinteractiveauthentication no` and `permitrootlogin without-password`. Then from the workstation, in a NEW terminal: `ssh root@<host address>` must still work with the key ※F.

`PermitRootLogin`, as options [S2 table, SSH row]:

| Value | Who uses it | Note |
|---|---|---|
| `prohibit-password` | ProxmoxR, Vormox guides | Root by key only; Proxmox's root `authorized_keys` link keeps working [S1-77] |
| `no` | Brandon Lee guide, CIS Debian 5.1.20 | Needs a separate sudo user for every shell task first |

[pick] `prohibit-password` now; revisit `no` once your sudo user exists.

Also add Proxmox's guard to the top of `/root/.bashrc`, because Proxmox runs root SSH sessions non-interactively [S1-79]:

```bash
sed -i '1i case $- in *i*) ;; *) return;; esac' /root/.bashrc
```

### Part 2. Let the agent in, with least privilege

How the agent reaches the host over the network comes with the networking steps (see [Not in this runbook](#not-in-this-runbook)). These two steps make the accounts it will use.

#### 6. The Linux user `agent`, and the Terraform account and its API token

The owner asked for secrets that the agent can use but not read.

**6a. The Linux user.** Put its public key in `/home/agent/.ssh/authorized_keys` [inferred].

```bash
apt install sudo          # may already be installed; not verified on PVE 9 [S4-68]
adduser --disabled-password --gecos "agent (automation)" agent
```

**sudo:** start with none. Each command the agent needs as root gets its own fixed script in `/usr/local/sbin/`, and sudoers allows exactly that script with no wildcards. The sudoers manual itself says deny-lists on `ALL` are "advisory at best" and wildcards match across words [S4-61]. Never give `agent` sudo for `pvesh`: it runs as root and skips Proxmox permission checks, which is the same as giving root [S4-45].

**6b. The Terraform account and its API token.** Terraform (OpenTofu) builds the lab's VMs and networks (D-0011 rule 6), so it gets its own Proxmox account, a role with only the privileges it uses, and a token that expires. The script [`hosts/terraform/home/bootstrap/iac-access.sh`](../../hosts/terraform/home/bootstrap/iac-access.sh) makes all of it except the token, and it is safe to run again. Read it before you run it.

| Piece | Name | What it is |
|---|---|---|
| user | `iac@pve` | Proxmox's built-in `pve` realm: no Linux login |
| group | `iac` | the user is its only member; ACLs go on the group |
| role | `IacOps` | the script's own least-privilege list, not a built-in role |
| token | `iac@pve!apply` | privilege-separated, expires after 90 days |
| pools | `firewall`, `remote-access`, `k8s` | one per workload, named by job (STD-0001); the ACLs give the role on each pool, so the token reaches only those guests |

```bash
# 1. copy the script to the host, then on the host, as root: the group, role, user, pools and the group's ACLs
sh iac-access.sh

# 2. the token. Run it from your own machine over SSH, so the secret goes straight into a file
#    there that only you can read, and is never printed or seen by an agent session.
( umask 077
  ssh root@<host address> "pveum user token add iac@pve apply --privsep 1 --expire $(date -d '+90 days' +%s) --output-format json" \
    | python3 -c 'import json,sys; print("iac@pve!apply=" + json.load(sys.stdin)["value"])' \
    > <token file> )

# 3. on the host again: now that the token exists, the script gives it the same ACLs as the group
#    (a privilege-separated token gets at most what its user has, and needs its own ACLs)
sh iac-access.sh
pveum user token permissions iac@pve apply      # check what it can really do
```

At apply time `PROXMOX_VE_API_TOKEN` is filled from `<token file>` (see `hosts/terraform/README.md`).

why: Terraform needs its own account, so a bad run is capped at what that account may do (NIST IR 7966: least privilege for automated access [S2 summary 10]). root@pam stays break-glass only ※R. The role is the script's own list, not `PVEVMAdmin`, which includes `VM.Console` and the `VM.GuestAgent.FileRead/FileWrite/Unrestricted` privileges this step forbids below (measured on 9.2.21, 2026-10-23).

※ The admins group from [step 4](#4-break-glass-login-and-the-admins-group) is for people; this step makes a separate group for automation.

expect: `pveum user token permissions iac@pve apply` lists only the pools, the SDN and storage paths and the node in the script's `acl` lines; `ls -l <token file>` shows `-rw-------` and your user.

What this buys:

| Threat | Result |
|---|---|
| Agent session prints its environment | Nothing: the secret is only in `<token file>` and, during a run, in the apply's own environment [inferred] |
| Token leaks anyway | Only the three pools, the lab SDN zone, two storages and a read of the node; expires in 90 days; one command revokes it: `pveum user token remove iac@pve apply` [S1-37, S1-38] |
| Token tries the VM console | Tokens can't use console endpoints [S1-36] |

Proxmox 9.2 can rotate a token's secret in place without losing its ACLs [S1-38].

Roles the token must NOT get: Administrator, anything with `Permissions.Modify`, `Sys.Modify`, `Sys.Console`, or the `VM.GuestAgent.FileRead/FileWrite/Unrestricted` privileges (those read files inside VMs) [S1-34, S4-41]. Proxmox 9 renamed some privileges, so custom roles must use the 9.x names [S1-86].

Other "use but not read" options, for later (not picked; the secrets backend is an open decision) [S4 options table]:

| Mechanism | Agent sees the value? | Fits this host? |
|---|---|---|
| Root-only file on the host + fixed sudo script | No | Yes, if an agent on the host needs a secret |
| systemd `LoadCredential=` for a service | No (kernel-enforced per service) [S4-60] | Yes, when a service needs it |
| Cloud environment network secret | No | Only for internet-reachable APIs, not this host [S4-03] |
| Cloud environment variable | **Yes** | No [S4-01] |
| A password manager's CLI that runs a child process with the secret | **Yes**, the child process gets it [S4 summary 7] | No |
| Desktop SSH agent in a password manager | Protects your keys on your workstation; never reaches a cloud session [S4-46, S4-10] | For your own SSH only |

### Part 3. Give it a safety net

#### 7. Notifications

Datacenter → Notifications: the root@pam email given to the installer is the default target [S1-02]. Mail from a home IP often needs Postfix pointed at a relay (smart host), or use an SMTP target directly, or a webhook to ntfy or Discord [S1-68].

why: Updates, failed backups and disk warnings only help if you see them [S1-13, S1-67, S1-70].

※ This is where the daily update mail from [step 2](#2-update-everything-add-cpu-microcode-reboot) lands.

expect: a test notification arrives.

#### 8. Backups

Targets, as options [S1-60, S1-65, S1-66]:

| Target | Note |
|---|---|
| `local` (same disk) | Fast restores after a bad change; lost with the disk |
| A USB disk added as a Directory storage | Off the main disk; cheap |
| Proxmox Backup Server on another machine | What the docs recommend; dedupe, encryption; needs a second box |
| NFS share | The docs' "good alternative" |

[pick] `local` now for change-rollback, plus a USB or Proxmox Backup Server target before any VM holds data you care about.

Datacenter → Backup → Add: schedule, mode `snapshot`, retention on the storage (`keep-last=3,keep-daily=7` for example; `maxfiles` is gone in 9.x) [S1-61, S1-63], and tick **Repeat missed**: the PC is often off at backup time [S1-62].

The host's own config (`/etc/pve`, `/etc/network/interfaces`, `/etc/ssh/sshd_config.d`) is not in guest backups; a small tar of those to the USB target covers it [S1 gaps; S2 table, backups row].

why: Proxmox backs up whole guests (config + disks) [S1-60]. A backup on the same disk as the VMs is not a backup, but it may be the only target available at first [inferred].

※ A failed backup reaches you through [step 7](#7-notifications).

expect: the job shows under Datacenter → Backup, and a first run (Run now) finishes with status OK.

## If it fails

Stop at the step that fails. If SSH or a login breaks, use the session ※F kept open, or the physical console as root@pam ※R. Undo a change in step 5 by removing `/etc/ssh/sshd_config.d/00-hardening.conf` and reloading `ssh`. Undo step 6 with `pveum user token remove iac@pve apply`, then `pveum user delete iac@pve; pveum role delete IacOps; pveum group delete iac` (the script's exit path), and `deluser agent`. Tell the owner before changing a command, and fix the runbook text in the same change.

## Afterwards

Record a replay in the PR that changes this runbook: set `last-tested` with the date, who ran it and on what, and only then set `status: tested` (D-0012).

## Exit paths (REQ-0011)

| Piece | How it comes out |
|---|---|
| Terraform access | `pveum user token remove iac@pve apply`; `pveum user delete iac@pve; pveum role delete IacOps; pveum group delete iac` |
| Agent access | `deluser agent` |
| The token file | Moves behind whatever secrets backend is picked later |
| Proxmox itself | Back up guests, then reinstall the PC as a bare-metal AlmaLinux worker or Talos |

## Not in this version

- The networking steps (see [Not in this runbook](#not-in-this-runbook)).
- An automated version: Terraform for the Proxmox VMs and networks, and Ansible for the host (D-0011), with the `bpg/proxmox` Terraform provider (D-0011 rule 6). Batch RB-0061 compared the bpg Terraform/OpenTofu provider, the community.proxmox Ansible collection and Packer. It comes after this runbook has been done by hand (D-0012, "Manual first").
- A trusted TLS certificate for the web UI ※S.
- A separate management VLAN (NIST SP 800-125A asks for one; later) [S2 table].
- CIS Debian benchmark items that conflict with a hypervisor (at least seven) [S2 summary 8].
- Root password reset on 9.x: Proxmox's documented method says "works until 8.1"; untested on 9 [S4-47]. Break-glass = password manager copy ※R + physical console.

## Related

- [D-0012](../decisions/0012-sort-docs-by-kind-of-document.md): runbook format, manual first.
- [STD-0001](../standards/0001-names.md): the host name.
- Research batch RB-0061 (strands S1 to S4, the ledger and the independent check) is kept in the owner's private research archive.
