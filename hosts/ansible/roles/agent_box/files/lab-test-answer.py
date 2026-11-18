#!/usr/bin/env python3
"""The answer file the lab-test wrapper bakes into the Proxmox VE installer ISO (docs/runbooks/build-the-lab-test-copy.md).

  lab-test-answer.py answer <settings.json> <vlans.yml> <root key .pub> <root.hash> <out answer.toml>
      The automated installer's answer (Proxmox VE wiki, Automated Installation, "Answer File Format"):
      root by key, with the hash of a random password kept only on the box; dev's static address, gateway and DNS;
      ext4 on the one disk.

  lab-test-answer.py inventory <settings.json> <vlans.yml> <ssh key> <known_hosts> <out hosts.yml>
      The copy's Ansible inventory, in the shape of hosts/ansible/inventories/home/hosts.example.yml: group proxmox
      with one host, the copy, reached as root with the wrapper's key, and the copy's own network values.

  lab-test-answer.py layers <settings.json> <vlans.yml> <OPNsense image> <container template> <out dir>
      The copy's own values for the network, firewall and remote-access run folders, one <folder>.tfvars.json each:
      the copy's node name, made-up MACs and names for its VM 100 and CT 900, and WAN link-down.

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
        # Hash of a random password kept only on the box. SSH is by key; the password is for the copy's own API, where
        # only root@pam may make CT 900 (lab-test.sh, lab).
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


# The copy's VM 100 and CT 900, locally administered MACs from their IDs. VM 100's two NICs stay inside the copy:
# net0 on the copy's vmbr1, which has no ports, and net1 link-down. CT 900's eth0 is on the copy's vmbr0, so on dev.
COPY_OPNSENSE_LAN_MAC = "02:00:00:00:01:00"
COPY_OPNSENSE_WAN_MAC = "02:00:00:00:01:01"
COPY_CONNECTOR_ETH0_MAC = "02:00:00:00:09:00"


def layers(settings, vlans, image, template, outdir):
    s, net, gw, addr = load(settings, vlans)
    lab = yaml.safe_load(open(vlans))["lab_vlans"]
    mgmt = ipaddress.ip_network([v for v in lab if v["name"] == "mgmt"][0]["cidr"])
    # STD-0001: <env><os><role><what><nn>. The copy's VM 100 and CT 900 keep its env, what and nn, with OPNsense
    # (op) or Debian (de) as the OS and network (nw) as the role.
    n = s["name"]
    env, what, nn = n[0], n[5:-2], n[-2:]
    if env not in "dqspn" or not 3 <= len(what) <= 8 or not nn.isdigit():
        sys.exit("lab-test: the name is not <env><os><role><what><nn> (STD-0001)")
    for f in (image, template):
        if not re.fullmatch(r"[A-Za-z0-9._-]+", f):
            sys.exit("lab-test: an image name is not a plain file name")
    node = {"proxmox_node_name": n}
    out = {
        "network": {**node, "vlans_file": vlans},
        "firewall": {**node, "firewall_vm_name": f"{env}opnw{what}{nn}",
                     "opnsense_lan_mac": COPY_OPNSENSE_LAN_MAC, "opnsense_wan_mac": COPY_OPNSENSE_WAN_MAC,
                     # WAN stays link-down until the WAN safety check passes, as on a fresh real host.
                     "opnsense_wan_connected": False,
                     "opnsense_image_file_id": f"local:import/{image}"},
        "remote-access": {**node, "connector_hostname": f"{env}denw{what}{nn}",
                          "connector_eth0_mac": COPY_CONNECTOR_ETH0_MAC,
                          # mgmt's .2 is the copy's own address there (inventory); the connector takes .3.
                          "connector_mgmt_address": f"{mgmt.network_address + 3}/{mgmt.prefixlen}",
                          "connector_template_file_id": f"local:vztmpl/{template}"},
    }
    for folder, values in out.items():
        with open(f"{outdir}/{folder}.tfvars.json", "w") as f:
            json.dump(values, f, indent=2)
            f.write("\n")


if __name__ == "__main__":
    fn = {"answer": answer, "inventory": inventory, "layers": layers}
    if len(sys.argv) != 7 or sys.argv[1] not in fn:
        sys.exit(__doc__)
    fn[sys.argv[1]](*sys.argv[2:])
