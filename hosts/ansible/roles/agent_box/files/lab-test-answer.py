#!/usr/bin/env python3
"""The answer file the lab-test wrapper bakes into the Proxmox VE installer ISO (docs/runbooks/build-the-lab-test-copy.md).

  lab-test-answer.py answer <settings.json> <vlans.yml> <root key .pub> <root.hash> <out answer.toml>
      The automated installer's answer (Proxmox VE wiki, Automated Installation, "Answer File Format"):
      root by key, with a hashed password no one keeps; dev's static address, gateway and DNS; ext4 on the one disk.

  lab-test-answer.py inventory <settings.json> <vlans.yml> <ssh key> <known_hosts> <out hosts.yml>
      The copy's Ansible inventory, in the shape of hosts/ansible/inventories/home/hosts.example.yml: group proxmox
      with one host, the copy, reached as root with the wrapper's key, and the copy's own network values.

Exits non-zero with a reason when the settings are not what the copy needs. Needs PyYAML for the shared VLAN file.
"""
import ipaddress
import json
import re
import sys

import yaml


def load(settings, vlans):
    s = json.load(open(settings))
    dev = [v for v in yaml.safe_load(open(vlans))["lab_vlans"] if v["name"] == "dev"][0]
    net = ipaddress.ip_network(dev["cidr"])
    gw = net.network_address + 1
    addr = ipaddress.ip_address(s["address"])
    if addr not in net or addr in (net.network_address, net.broadcast_address, gw):
        sys.exit(f"lab-test: address {addr} is not a host address in dev's {net}, other than its gateway")
    if not re.fullmatch(r"[a-z][a-z0-9]{10,14}", s["name"]):
        sys.exit("lab-test: the name is not a STD-0001 hostname")
    # One or more DNS labels; the installer takes the part after the first dot as the search domain.
    if not re.fullmatch(r"([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?", s["domain"]):
        sys.exit("lab-test: the domain is not a DNS name")
    return s, net, gw, addr


def toml_str(v):
    # A TOML basic string. JSON's escapes are a subset of TOML's, and the values here are plain ASCII.
    if not v.isascii():
        sys.exit("lab-test: a value in the answer is not ASCII")
    return json.dumps(v)


def answer(settings, vlans, pubkey, roothash, out):
    s, net, gw, addr = load(settings, vlans)
    key = open(pubkey).read().strip()
    if not re.fullmatch(r"ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._:+-]+)*", key):
        sys.exit("lab-test: the root key is not one ed25519 public key")
    h = open(roothash).read().strip()
    # SHA-512 crypt, as `openssl passwd -6` writes it; the installer writes it to /etc/shadow verbatim.
    if not re.fullmatch(r"\$6\$[./A-Za-z0-9]{1,16}\$[./A-Za-z0-9]{86}", h):
        sys.exit("lab-test: the root hash is not one SHA-512 crypt hash")
    fqdn = f"{s['name']}.{s['domain']}"
    lines = [
        "[global]",
        'keyboard = "en-us"',
        'country = "us"',
        f"fqdn = {toml_str(fqdn)}",
        f"mailto = {toml_str('root@' + fqdn)}",
        'timezone = "UTC"',
        # Hash of a random password no one keeps: root signs in by key only.
        f"root-password-hashed = {toml_str(h)}",
        f"root-ssh-keys = [{toml_str(key)}]",
        # Stop on an error instead of looping through the installer; the wrapper's check then times out.
        "reboot-on-error = false",
        "",
        "[network]",
        'source = "from-answer"',
        f"cidr = {toml_str(f'{addr}/{net.prefixlen}')}",
        f"gateway = {toml_str(str(gw))}",
        f"dns = {toml_str(str(gw))}",
        # The VM has one NIC; every NIC with a MAC has this property, and only the first match is used.
        'filter.ID_NET_NAME_MAC = "*"',
        "",
        "[disk-setup]",
        'filesystem = "ext4"',
        # virtio-scsi-single puts scsi0, the only disk, at sda.
        'disk-list = ["sda"]',
        # On 32 GB the defaults (swap hdsize/8 = 4, root at least hdsize/2 = 16 under 48 GiB, minfree
        # hdsize/8 = 4; pve-docs, "Advanced LVM Configuration Options") leave 8 GB of data, too small for the
        # copy's own OPNsense disk (16 GB). datasize = hdsize - root - swap - minfree = 32 - 12 - 1 - 1 = 18.
        "lvm.swapsize = 1",
        "lvm.maxroot = 12",
        "lvm.minfree = 1",
        "",
    ]
    with open(out, "w") as f:
        f.write("\n".join(lines))


# The copy's own values, which are not private: its vmbr1 has no ports, so its MAC is seen only inside the copy
# (a locally administered address from the VM ID), and its mgmt address is mgmt's .2, inside the copy only.
COPY_VMBR1_MAC = "02:00:00:00:02:56"


def inventory(settings, vlans, key, known_hosts, out):
    s, net, gw, addr = load(settings, vlans)
    lab = yaml.safe_load(open(vlans))["lab_vlans"]
    mgmt = ipaddress.ip_network([v for v in lab if v["name"] == "mgmt"][0]["cidr"])
    supernet = ipaddress.ip_network(f"{mgmt.network_address}/16", strict=False)
    host = {
        "ansible_host": str(addr),
        "ansible_user": "root",
        "ansible_ssh_private_key_file": key,
        "ansible_ssh_common_args": f"-o UserKnownHostsFile={known_hosts} -o StrictHostKeyChecking=accept-new",
        "proxmox_vmbr1_mac": COPY_VMBR1_MAC,
        "proxmox_host_mgmt_address": str(mgmt.network_address + 2),
        "proxmox_network_lab_supernet": str(supernet),
    }
    doc = {"all": {"children": {"proxmox": {"hosts": {"proxmox_host": host}}}}}
    with open(out, "w") as f:
        f.write("---\n# Written by lab-test host for the lab test copy, VM 256; not the real host.\n")
        yaml.safe_dump(doc, f, default_flow_style=False, sort_keys=False)


if __name__ == "__main__":
    fn = {"answer": answer, "inventory": inventory}
    if len(sys.argv) != 7 or sys.argv[1] not in fn:
        sys.exit(__doc__)
    fn[sys.argv[1]](*sys.argv[2:])
