#!/usr/bin/env bash
# Role proxmox_proxy (Apache httpd in place of nginx on 443 and 80) against a stand-in Proxmox host in a
# container: systemd as PID 1, nginx serving the way it does today, a stand-in pveproxy (proxy/). Each case
# starts from a fresh container. Test values only.
#   0. Install with the move off: apt finishes while nginx holds 80 and 443; apache2 is masked, disabled and
#      not running; nginx still serves and passes the proofs; no policy-rc.d is left behind.
#   1. The move: Apache httpd serves 443 and 80 and passes the proofs; apache2 is enabled, nginx disabled and
#      stopped. A second run changes nothing.
#   2. A failing proof (the front page answers 500): the move rolls back; nginx serves; apache2 is masked.
#   3. The move's unit is stopped during its proofs (TERM): it rolls back the same way.
#   4. The Ansible run dies during the move: the move finishes on its own and Apache httpd serves.
#   5. A graceful reload keeps an open console (a WebSocket through 443) working.
#   6. A host built fresh, with no nginx: the move runs without the nginx steps.
# Usage: .github/hosts-check/tests/test_proxy.sh   (needs docker that can run a privileged systemd container,
# ansible-playbook, ssh-keygen)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
here=$root/.github/hosts-check
t=$(mktemp -d)
# localhost/ marks the image as built here, not pulled from a registry.
image=localhost/central-hub-proxy-test:$$
cleanup() {
  # By label: start() runs in a command substitution, so a list it appended to would be lost.
  docker ps -aq --filter "label=central-hub-proxy-test=$$" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker rmi -f "$image" >/dev/null 2>&1 || true
  rm -rf "$t"
}
trap cleanup EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

docker build -q -t "$image" "$here/proxy" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$t/key"

# start <case>: a fresh container with systemd, sshd and nginx up; prints its name and writes its inventory.
start() {
  local name=central-hub-proxy-$1-$$ ip
  docker run -d --name "$name" --label "central-hub-proxy-test=$$" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock "$image" >/dev/null
  docker exec -i "$name" sh -c 'umask 077; cat > /root/.ssh/authorized_keys' < "$t/key.pub"
  for _ in $(seq 1 60); do
    docker exec "$name" systemctl is-active -q ssh.service nginx.service standin-pveproxy.service 2>/dev/null && break
    sleep 1
  done
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
  cat > "$t/inv-$1.yml" <<INV
proxmox:
  hosts:
    standin:
      ansible_host: $ip
      ansible_user: root
      ansible_ssh_private_key_file: $t/key
      ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      ansible_python_interpreter: /usr/bin/python3
      proxmox_proxy_server_names: [pve.example.test]
INV
  echo "$name"
}
play() {  # play <case> [extra ansible-playbook args...]
  local c=$1; shift
  (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i "$t/inv-$c.yml" playbooks/proxmox-proxy.yml "$@")
}
on443() { docker exec "$1" ss -Hltnp 'sport = :443' | grep -o '"[a-z0-9]*"' | head -1 | tr -d '"'; }
result() { docker exec "$1" sh -c 'cut -d" " -f1 /var/lib/proxmox-proxy/cutover.result 2>/dev/null || true'; }
is() { docker exec "$1" systemctl "$2" apache2.service nginx.service 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }

# 0
c=$(start 0)
if play 0 -e proxmox_proxy_cutover=false > "$t/0.log" 2>&1; then ok "0 install run passes"; else bad "0 install run failed"; tail -30 "$t/0.log"; fi
[ "$(is "$c" is-enabled)" = "masked enabled" ] && ok "0 apache2 masked, nginx enabled" || bad "0 is-enabled: $(is "$c" is-enabled)"
[ "$(is "$c" is-active)" = "inactive active" ] && ok "0 apache2 stopped, nginx running" || bad "0 is-active: $(is "$c" is-active)"
[ "$(on443 "$c")" = nginx ] && ok "0 nginx holds 443" || bad "0 443 held by '$(on443 "$c")'"
docker exec "$c" /usr/local/libexec/proxy-proofs.sh >/dev/null && ok "0 proofs pass through nginx" || bad "0 proofs fail through nginx"
docker exec "$c" test ! -e /usr/sbin/policy-rc.d && ok "0 no policy-rc.d left" || bad "0 policy-rc.d left behind"
docker exec "$c" sh -c 'ls /etc/systemd/system/*.wants/apache2.service' >/dev/null 2>&1 && bad "0 apache2 enable links left" || ok "0 no apache2 enable links"

# 1
c=$(start 1)
if play 1 > "$t/1.log" 2>&1; then ok "1 move run passes"; else bad "1 move run failed"; tail -30 "$t/1.log"; fi
[ "$(result "$c")" = "done" ] && ok "1 result done" || bad "1 result '$(result "$c")'"
[ "$(on443 "$c")" = apache2 ] && ok "1 Apache httpd holds 443" || bad "1 443 held by '$(on443 "$c")'"
[ "$(is "$c" is-enabled)" = "enabled disabled" ] && ok "1 apache2 enabled, nginx disabled" || bad "1 is-enabled: $(is "$c" is-enabled)"
[ "$(is "$c" is-active)" = "active inactive" ] && ok "1 apache2 running, nginx stopped" || bad "1 is-active: $(is "$c" is-active)"
play 1 > "$t/1b.log" 2>&1 && grep -q 'changed=0 ' "$t/1b.log" && ok "1 second run changes nothing" \
  || { bad "1 second run changed something or failed"; grep -E 'changed:|failed=' "$t/1b.log" | tail -10; }

# 5, on case 1's container: an open WebSocket through 443 survives a graceful reload.
cat > "$t/ws.py" <<'PY'
import socket, ssl, subprocess, sys, time
name = sys.argv[1]
ctx = ssl.create_default_context(cafile="/opt/standin/root.pem")
s = ctx.wrap_socket(socket.create_connection(("127.0.0.1", 443)), server_hostname="pve.example.test")
s.sendall(b"GET /ws-echo HTTP/1.1\r\nHost: pve.example.test\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n"
          b"Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
head = b""
while b"\r\n\r\n" not in head:
    head += s.recv(1024)
assert head.startswith(b"HTTP/1.1 101"), head[:40]
s.sendall(b"before"); assert s.recv(16) == b"before"
subprocess.run(["apachectl", "-k", "graceful"], check=True, capture_output=True)
time.sleep(3)
s.sendall(b"after"); assert s.recv(16) == b"after"
print("open")
PY
# Through stdin: systemd mounts a tmpfs on /tmp inside the container, which hides files docker cp puts there.
ws=$(docker exec -i "$c" python3 -I - "$c" < "$t/ws.py" 2>&1 || true)
[ "$ws" = open ] && ok "5 console survives a graceful reload" || { bad "5 console cut by a graceful reload"; echo "$ws" | tail -10; }

# 2
c=$(start 2)
docker exec "$c" sh -c 'echo 500 > /run/standin/front_status'
play 2 > "$t/2.log" 2>&1 && bad "2 run passed with a failing proof" || ok "2 run fails on a failing proof"
[ "$(result "$c")" = rolled-back ] && ok "2 result rolled-back" || bad "2 result '$(result "$c")'"
[ "$(on443 "$c")" = nginx ] && ok "2 nginx holds 443 again" || bad "2 443 held by '$(on443 "$c")'"
[ "$(is "$c" is-enabled)" = "masked enabled" ] && ok "2 apache2 masked, nginx enabled" || bad "2 is-enabled: $(is "$c" is-enabled)"
if play 2 > "$t/2b.log" 2>&1; then bad "2 re-run moved again"
elif grep -q 'did not finish' "$t/2b.log"; then ok "2 re-run stops and says why"
else bad "2 re-run: no reason given"; fi

# 3
c=$(start 3)
docker exec "$c" sh -c 'echo 20 > /run/standin/front_delay'
play 3 > "$t/3.log" 2>&1 &
pid=$!
for _ in $(seq 1 90); do [ "$(on443 "$c")" = apache2 ] && break; sleep 1; done
docker exec "$c" systemctl stop proxmox-proxy-cutover.service
wait "$pid" && bad "3 run passed after its unit was stopped" || ok "3 run fails when its unit is stopped"
[ "$(result "$c")" = rolled-back ] && ok "3 result rolled-back" || bad "3 result '$(result "$c")'"
[ "$(on443 "$c")" = nginx ] && ok "3 nginx holds 443 again" || bad "3 443 held by '$(on443 "$c")'"

# 4
c=$(start 4)
docker exec "$c" sh -c 'echo 8 > /run/standin/front_delay'
play 4 > "$t/4.log" 2>&1 &
pid=$!
for _ in $(seq 1 90); do [ "$(on443 "$c")" = apache2 ] && break; sleep 1; done
# Kill the run on this side (ansible-playbook and its ssh clients, which name the test key) and its SSH
# sessions on the host. The [s] keeps pkill from matching the shell that runs it.
pkill -KILL -f "ansible-playbook -i $t/inv-4.yml" >/dev/null 2>&1 || true
pkill -KILL -f "$t/key" >/dev/null 2>&1 || true
wait "$pid" 2>/dev/null || true
docker exec "$c" sh -c 'pkill -KILL -f "[s]shd-session" || true'
for _ in $(seq 1 60); do [ "$(result "$c")" = "done" ] && break; sleep 1; done
[ "$(result "$c")" = "done" ] && ok "4 move finishes after the run dies" || bad "4 result '$(result "$c")'"
[ "$(on443 "$c")" = apache2 ] && ok "4 Apache httpd holds 443" || bad "4 443 held by '$(on443 "$c")'"

# 6: a host built fresh, with no nginx: the move starts Apache httpd and proves it, with no nginx steps.
c=$(start 6)
docker exec "$c" sh -c 'systemctl stop nginx.service && apt-get purge -qq -y nginx nginx-common >/dev/null 2>&1'
if play 6 > "$t/6.log" 2>&1; then ok "6 move run passes with no nginx"; else bad "6 move run failed with no nginx"; tail -30 "$t/6.log"; fi
[ "$(result "$c")" = "done" ] && ok "6 result done" || bad "6 result '$(result "$c")'"
[ "$(on443 "$c")" = apache2 ] && ok "6 Apache httpd holds 443" || bad "6 443 held by '$(on443 "$c")'"

exit "$fail"
