#!/usr/bin/env bash
# The lifeline filter's per-user entry (templates/lifeline.nft.j2, `uid` in agent_box_lifeline_allow; Library
# plans/r1-host-job/DESIGN.md v3.1): the role's own template, rendered with test values and loaded by nft in a
# container, lets only that user's sockets out to the entry's port, and leaves the other entries for every user.
#   1. The rendered file loads, and nft lists the entry with its skuid.
#   2. hostops gets out to port 22 (the SYN leaves: no answer, so the attempt times out).
#   3. Another user is rejected on port 22 at once (connection refused).
#   4. Another user still gets out to 8006, which has no uid.
# Usage: .github/hosts-check/tests/test_lifeline_uid.sh   (needs docker that can give a container NET_ADMIN, and
# python3 with jinja2)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
image=localhost/central-hub-lifeline-test:$$
cleanup() { docker rmi -f "$image" >/dev/null 2>&1 || true; rm -rf "$t"; }
trap cleanup EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# The same pinned base as the proxy stand-in (proxy/Dockerfile), with nftables and two users.
base=$(sed -n 's/^FROM //p' "$root/.github/hosts-check/proxy/Dockerfile" | head -n 1)
printf 'FROM %s\nRUN apt-get update && apt-get install -y --no-install-recommends nftables iproute2 && useradd -r -s /usr/sbin/nologin hostops && useradd -r -s /usr/sbin/nologin other\n' "$base" > "$t/Dockerfile"
docker build -q -t "$image" "$t" >/dev/null
python3 - "$root/hosts/ansible/roles/agent_box/templates" > "$t/lifeline.nft" <<'PY'
import sys, jinja2
env = jinja2.Environment(loader=jinja2.FileSystemLoader(sys.argv[1]))
print(env.get_template("lifeline.nft.j2").render(agent_box_lifeline_interface="eth0", agent_box_lifeline_allow=[
    {"address": "DST", "ports": [8006]}, {"address": "DST", "ports": [22], "uid": "hostops"}]))
PY
cat > "$t/run.sh" <<'SH'
set -e
dst=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d. -f1-3).250   # nothing answers there
sed "s/DST/$dst/g" /t/lifeline.nft > /tmp/l.nft
nft -f /tmp/l.nft
nft list table inet lifeline | grep 'dport 22'
try() { su -s /bin/bash "$1" -c "timeout 3 bash -c 'echo > /dev/tcp/$dst/$2'" 2>&1 | tail -n 1; echo "rc=${PIPESTATUS[0]}"; }
echo "hostops-22 $(try hostops 22 | tr '\n' ' ')"
echo "other-22 $(try other 22 | tr '\n' ' ')"
echo "other-8006 $(try other 8006 | tr '\n' ' ')"
SH
out=$(docker run --rm --cap-add NET_ADMIN -v "$t:/t:ro" "$image" bash /t/run.sh 2>&1) || { bad "1 the filter did not load"; echo "$out"; exit 1; }
grep -q 'tcp dport 22 meta skuid [0-9a-z"]* accept' <<< "$out" && ok "1 the file loads; nft lists the entry with its skuid" || bad "1 $out"
grep -q '^hostops-22 rc=124' <<< "$out" && ok "2 hostops gets out to 22" || bad "2 $(grep hostops-22 <<< "$out")"
grep -q '^other-22 .*Connection refused' <<< "$out" && ok "3 another user is rejected on 22" || bad "3 $(grep other-22 <<< "$out")"
grep -q '^other-8006 rc=124' <<< "$out" && ok "4 another user still gets out to 8006" || bad "4 $(grep other-8006 <<< "$out")"
exit "$fail"
