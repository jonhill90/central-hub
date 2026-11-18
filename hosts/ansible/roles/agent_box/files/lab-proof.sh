#!/bin/bash
# /usr/local/bin/lab-proof: read-only proof that each app's names on c1 resolve through the lab DNS and that the
# Gateway answers on 443 with a certificate the box trusts (the lab root is in its trust store). It holds no key:
# it reads the HTTPRoutes and the Gateway address through c1-read, asks the box's own resolver (the tailnet's, which
# hands lab names to Unbound) with a short Python query (no dig: BIND's tools are not installed), and opens a TLS connection with openssl. Installed by the agent_box role; root
# owns it.
#   lab-proof
# It prints one line per route name and name number (the short name first, as the route lists them): the app's
# label, the DNS result (ok when the name answers with the Gateway's address) and the TLS result (the verify code
# openssl names). It prints no host name, address or zone, so its output can go in a public record. It does not run
# the opnsense_lab dns_proof tag, which needs the OPNsense settings; it asks the same question of the names c1 serves.
# OPNsense's own name is not a c1 route and is not covered.
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

[[ $# -eq 0 ]] || { echo "usage: lab-proof" >&2; exit 2; }
for t in c1-read python3 openssl; do command -v "$t" > /dev/null || { echo "lab-proof: $t is not installed" >&2; exit 1; }; done

server=$(awk '$1 == "nameserver" {print $2; exit}' /etc/resolv.conf)
[[ -n $server ]] || { echo "lab-proof: no nameserver in /etc/resolv.conf" >&2; exit 1; }
gw=$(c1-read get gateway.gateway.networking.k8s.io -A -o 'jsonpath={.items[*].status.addresses[*].value}' 2> /dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
[[ -n $gw ]] || { echo "lab-proof: c1 shows no Gateway IPv4 address" >&2; exit 1; }
routes=$(c1-read get httproutes.gateway.networking.k8s.io -A -o 'jsonpath={range .items[*]}{.metadata.name}={.spec.hostnames[*]}{"\n"}{end}' 2> /dev/null)
[[ -n $routes ]] || { echo "lab-proof: c1 shows no HTTPRoutes" >&2; exit 1; }

# dns_a <name>: the A records the resolver gives for a name, one per line (a plain UDP query, stdlib only).
dns_a() {
  python3 -I -c '
import random, socket, struct, sys
name, server = sys.argv[1], sys.argv[2]
q = struct.pack(">HHHHHH", random.randrange(65536), 0x0100, 1, 0, 0, 0)
q += b"".join(bytes([len(x)]) + x.encode() for x in name.strip(".").split(".")) + b"\x00" + struct.pack(">HH", 1, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
try:
    s.sendto(q, (server, 53))
    r = s.recv(4096)
except OSError:
    sys.exit(0)
if r[:2] != q[:2] or r[3] & 15:
    sys.exit(0)
an, i = struct.unpack(">H", r[6:8])[0], len(q)
for _ in range(an):
    while r[i] != 0 and r[i] < 192:
        i += r[i] + 1
    i += 2 if r[i] >= 192 else 1
    t, _c, _ttl, n = struct.unpack(">HHIH", r[i:i + 10])
    if t == 1 and n == 4:
        print(".".join(str(b) for b in r[i + 10:i + 14]))
    i += 10 + n
' "$1" "$server"
}

fail=0 checked=0
while IFS='=' read -r name hosts; do
  [[ -n $name && -n $hosts && $name != *-redirect ]] || continue
  n=0
  for host in $hosts; do
    n=$((n + 1))
    [[ $host =~ ^[A-Za-z0-9.-]+$ ]] || { echo "$name #$n: DNS skipped (not a host name)"; fail=1; continue; }
    answer=$(dns_a "$host")
    if grep -qxF "$gw" <<< "$answer"; then dns=ok; else dns=FAIL; fail=1; fi
    # shellcheck disable=SC2312
    tls=$(timeout 20 openssl s_client -connect "$gw:443" -servername "$host" -verify_hostname "$host" -verify_return_error \
      < /dev/null 2>&1 | sed -n 's/^Verification: *//p; s/^Verify return code: *//p' | head -n1)
    [[ $tls == OK* || $tls == "0 (ok)"* ]] || fail=1
    echo "$name #$n: dns=$dns tls=${tls:-no answer}"
    checked=$((checked + 1))
  done
done <<< "$routes"

[[ $checked -gt 0 ]] || { echo "lab-proof: no name was checked" >&2; exit 1; }
if [[ $fail -eq 0 ]]; then echo "PASS: lab-proof: $checked names, dns ok and tls verified"; else echo "FAIL: lab-proof: see the lines above"; exit 1; fi
