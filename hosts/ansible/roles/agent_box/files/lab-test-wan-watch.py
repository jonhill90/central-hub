#!/usr/bin/env python3
"""The WAN safety check's capture, inside the lab test copy (docs/runbooks/build-the-lab-test-copy.md, wancheck).

  lab-test-wan-watch.py <bridge> <WAN MAC> <seconds> [<port>]

Run as root on the copy, it watches the bridge VM 100's WAN sits on for the packets set-up-lab-network-and-firewall.md
step 7 counts: from the WAN's MAC, UDP from port 67 (a DHCPv4 server's offer or ack), UDP from port 547 (a DHCPv6
server's reply) and ICMPv6 type 134 (a router advertisement). The copy's WAN bridge has no ports and no other guest,
so nothing would ask a server there; every 5 seconds the watch asks itself, from a made-up MAC, with a DHCPv4
discover, a DHCPv6 solicit and a router solicitation. It exits 0 only when it saw frames from the WAN's MAC (the WAN
is up and alive) and none of server type. It reads the frames where they enter the bridge, on its ports (VM 100's
tap), before the bridge's own netfilter hooks could drop them, so a reboot's new tap is read too. Standard library
only; Linux AF_PACKET.

With <port> (VM 100's WAN tap, for the watch over a reboot), frames from the WAN count as a sign of life only once
that port is a new device: the port must be on the bridge at the start, and it counts as back when the same name has
a new interface index, which only a new QEMU process gives it. Frames sent before the reboot prove nothing about the
WAN after it, so they are not counted. Server-type frames count at any time. It exits 5 when the port never came
back as a new device in the time given, and 4 when it came back but sent nothing.
"""
import os
import re
import socket
import struct
import sys
import time

ETH_P_ALL = 0x0003
PACKET_OUTGOING = 4
PROBE_MAC = bytes.fromhex("020000000998")   # made up, locally administered, seen only on the copy's WAN bridge


def mac_bytes(text):
    if not re.fullmatch(r"[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}", text):
        sys.exit(f"wan-watch: {text} is not a MAC")
    return bytes.fromhex(text.replace(":", ""))


def csum(data):
    if len(data) % 2:
        data += b"\0"
    s = sum(struct.unpack(f"!{len(data) // 2}H", data))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return ~s & 0xFFFF


def link_local(mac):
    eui = bytes([mac[0] ^ 2]) + mac[1:3] + b"\xff\xfe" + mac[3:]
    return b"\xfe\x80" + b"\0" * 6 + eui


def ipv6(src, dst, nh, payload):
    # The upper-layer checksum covers the pseudo-header (RFC 8200 section 8.1); the caller leaves its field zero.
    pseudo = src + dst + struct.pack("!I3xB", len(payload), nh)
    off = {17: 6, 58: 2}[nh]
    c = csum(pseudo + payload)
    payload = payload[:off] + struct.pack("!H", c or 0xFFFF) + payload[off + 2:]
    return struct.pack("!IHBB", 6 << 28, len(payload), nh, 255) + src + dst + payload


def probes():
    """The three client frames, each a whole Ethernet frame from PROBE_MAC."""
    xid = 0x4C54   # "LT"
    bootp = struct.pack("!BBBBIHH4s4s4s4s16s64s128s", 1, 1, 6, 0, xid, 0, 0x8000, b"\0" * 4, b"\0" * 4, b"\0" * 4,
                        b"\0" * 4, PROBE_MAC + b"\0" * 10, b"", b"")
    bootp += b"\x63\x82\x53\x63" + bytes([53, 1, 1, 55, 3, 1, 3, 6, 255])
    udp4 = struct.pack("!HHHH", 68, 67, 8 + len(bootp), 0) + bootp   # UDP checksum 0: none, allowed for IPv4
    ip4 = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp4), 0, 0, 64, 17, 0, b"\0" * 4, b"\xff" * 4)
    ip4 = ip4[:10] + struct.pack("!H", csum(ip4)) + ip4[12:]
    dhcp4 = b"\xff" * 6 + PROBE_MAC + b"\x08\x00" + ip4 + udp4

    src = link_local(PROBE_MAC)
    rs = ipv6(src, socket.inet_pton(socket.AF_INET6, "ff02::2"), 58, struct.pack("!BBHI", 133, 0, 0, 0))
    rs = b"\x33\x33\x00\x00\x00\x02" + PROBE_MAC + b"\x86\xdd" + rs

    duid = struct.pack("!HH", 3, 1) + PROBE_MAC                       # DUID-LL (RFC 8415 section 11.4)
    msg = struct.pack("!I", (1 << 24) | xid)                          # SOLICIT, transaction id
    msg += struct.pack("!HH", 1, len(duid)) + duid                    # Client Identifier
    msg += struct.pack("!HHH", 8, 2, 0)                               # Elapsed Time
    msg += struct.pack("!HHIII", 3, 12, 1, 0, 0)                      # IA_NA, IAID 1
    udp6 = struct.pack("!HHHH", 546, 547, 8 + len(msg), 0) + msg
    sol = ipv6(src, socket.inet_pton(socket.AF_INET6, "ff02::1:2"), 17, udp6)
    sol = b"\x33\x33\x00\x01\x00\x02" + PROBE_MAC + b"\x86\xdd" + sol
    return [dhcp4, rs, sol]


def classify(frame, wan):
    """None when the frame is not from the WAN's MAC; else 'dhcp4-server', 'dhcp6-server', 'ra' or 'other'."""
    if len(frame) < 14 or frame[6:12] != wan:
        return None
    etype, p = struct.unpack("!H", frame[12:14])[0], 14
    if etype == 0x8100 and len(frame) >= 18:   # one 802.1Q tag
        etype, p = struct.unpack("!H", frame[16:18])[0], 18
    if etype == 0x0800 and len(frame) >= p + 20:
        ihl = (frame[p] & 0x0F) * 4
        if frame[p + 9] == 17 and len(frame) >= p + ihl + 2 and struct.unpack("!H", frame[p + ihl:p + ihl + 2])[0] == 67:
            return "dhcp4-server"
    elif etype == 0x86DD and len(frame) >= p + 40:
        nh, q = frame[p + 6], p + 40
        if nh == 17 and len(frame) >= q + 2 and struct.unpack("!H", frame[q:q + 2])[0] == 547:
            return "dhcp6-server"
        if nh == 58 and len(frame) > q and frame[q] == 134:
            return "ra"
    return "other"


def port_index(brif, port):
    """The port's interface index while it is on the bridge, else None."""
    try:
        with open(os.path.join(brif, port, "..", "ifindex")) as f:   # brif/<port> links to the port's brport folder
            return int(f.read())
    except (OSError, ValueError):
        return None


def came_back(brif, port, start_index):
    """True once the port is on the bridge with an index other than the one it had at the start."""
    i = port_index(brif, port)
    if i is None or i == start_index:
        return False
    print(f"wan-watch: {port} is back as a new device (index {start_index} -> {i})", flush=True)
    return True


def main():
    if len(sys.argv) not in (4, 5) or not re.fullmatch(r"vmbr[0-9]+", sys.argv[1]) or not sys.argv[3].isdigit() \
            or (len(sys.argv) == 5 and not re.fullmatch(r"[a-z][a-z0-9]{1,14}", sys.argv[4])):
        sys.exit(__doc__)
    bridge, wan, seconds = sys.argv[1], mac_bytes(sys.argv[2]), int(sys.argv[3])
    port = sys.argv[4] if len(sys.argv) == 5 else None
    brif = f"/sys/class/net/{bridge}/brif"
    if not os.path.isdir(brif):
        sys.exit(f"wan-watch: {bridge} is not a bridge here")
    start_index = port_index(brif, port) if port else None
    if port and start_index is None:
        sys.exit(f"wan-watch: {port} is not on {bridge} at the start, so a reboot can't be told apart")
    back = port is None
    # Not bound: frames are taken from the bridge's ports, read again each second as VM 100's tap comes and goes.
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    s.settimeout(0.5)
    seen, before, bad, end, next_probe, next_ports, ports = 0, 0, {}, time.monotonic() + seconds, 0.0, 0.0, set()
    frames = probes()
    while time.monotonic() < end:
        now = time.monotonic()
        if now >= next_ports:
            ports, next_ports = set(os.listdir(brif)), now + 1
            back = back or came_back(brif, port, start_index)
        if now >= next_probe:
            for f in frames:
                s.sendto(f, (bridge, 0))
            next_probe = now + 5
        try:
            frame, where = s.recvfrom(65535)
        except socket.timeout:
            continue
        if where[0] not in ports or where[2] == PACKET_OUTGOING:
            continue
        kind = classify(frame, wan)
        if kind is None:
            continue
        if not back and where[0] == port:   # read the index again at once, so the new tap's first frame counts
            back = came_back(brif, port, start_index)
        # A frame from a port that is gone has no name (Python reads the name from the index at receive time), so a
        # frame the old tap sent is never taken for one from the new tap.
        if back:
            seen += 1
        else:
            before += 1
        if kind != "other":
            bad[kind] = bad.get(kind, 0) + 1
    print(f"wan-watch: {seconds}s on {bridge}: {seen} frames from the WAN"
          + (f" after {port} came back ({before} before, not counted)" if port else "") + ", server-type: "
          + (", ".join(f"{k} {v}" for k, v in sorted(bad.items())) or "0"), flush=True)
    if bad:
        sys.exit(3)
    if not back:
        print(f"wan-watch: {port} never came back as a new device, so the reboot was not seen", flush=True)
        sys.exit(5)
    if not seen:
        print("wan-watch: nothing from the WAN's MAC; the WAN is not up, so this proves nothing", flush=True)
        sys.exit(4)


if __name__ == "__main__":
    main()
