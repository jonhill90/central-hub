#!/bin/bash
# Managed by Ansible (role proxmox_proxy). Moves 443 and 80 from nginx to Apache httpd, once, and rolls back
# by itself. The role starts it with systemd-run as its own unit, so a dropped SSH connection or a killed
# Ansible run does not stop it half-way. Until the proofs pass, nginx stays enabled and apache2 is never
# enabled, so a reboot part-way brings nginx back. On a failed proof, or a stop of the unit (TERM), the trap
# stops and masks apache2 and starts nginx again. The result is written to $state.
# A host built fresh has no nginx: the move then only starts Apache httpd and proves it.
set -Eeuo pipefail
state=/var/lib/proxmox-proxy/cutover.result
mkdir -p "$(dirname "$state")"
nginx=no
[ "$(systemctl show -P LoadState nginx.service)" = loaded ] && nginx=yes
rollback() {
  systemctl stop apache2.service || true
  systemctl mask apache2.service || true
  [ "$nginx" = no ] || systemctl start nginx.service || true
  echo "rolled-back $(date -u +%FT%TZ)" > "$state"
}
on_exit() {
  local rc=$?
  [ "$rc" -eq 0 ] || rollback
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 143' HUP INT TERM
echo "started $(date -u +%FT%TZ)" > "$state"
systemctl unmask apache2.service
[ "$nginx" = no ] || systemctl stop nginx.service
systemctl start apache2.service
/usr/local/libexec/proxy-proofs.sh
systemctl enable apache2.service
[ "$nginx" = no ] || systemctl disable nginx.service
echo "done $(date -u +%FT%TZ)" > "$state"
