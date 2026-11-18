#!/bin/bash
# /usr/local/libexec/agent-box/opnsense-cert-check.sh: read the certificate the firewall's web UI serves and say how
# many days it has left (ask 320; docs/runbooks/set-opnsense-gui-certificate.md, "Afterwards"). cert-manager renews the
# Certificate on c1, but nothing copies it to the firewall except a run of that runbook's Path A from the Mac, so the
# copy the firewall serves can end while c1's copy is fresh. This reads the served one. It writes nothing to the firewall
# and holds no key: it makes one TLS connection and reads the certificate off it.
# Runs as user `keys` through sudo and from the box's daily timer. Installed by the agent_box role; root owns it.
#   opnsense-cert-check check    connect, print one line, save it, exit 0 only when the certificate verifies and has at least
#                                25 days left; exit 1 with the line starting WARN otherwise
#   opnsense-cert-check status   print the last saved line and when it was taken (no connection)
# The firewall's name is the host in {work}/opnsense-backup.json, the setting the daily configuration backup already uses
# (agent_box_opnsense_backup), so this needs no setting of its own. The chain is checked against the lab chain, the file the box's
# prod files copy puts in the keys folder, or, if that file is missing, against the box's system store (which holds the lab root
# when the role's agent_box_ca_files names it). A certificate that does not verify either way fails the run.
# What is printed: the days left, the end date and whether the chain verified. Never the firewall's name or address.
# There is no push notification: the box holds no ntfy credential, and making one is a secret. A failing run shows as a failed
# unit (`systemctl --failed`, unit opnsense-cert-check.service) and in the journal under the tag opnsense-cert-check.
set -euo pipefail
umask 077

work=/var/lib/agent-box
settings=$work/opnsense-backup.json
chain=/etc/agent-keys/prod/lab-ca/c1-intermediate-chain.crt
port=443
warn_days=25   # c1 renews 30 days before the end (lab_host_cert_renew_before 720h), so under 25 days a newer certificate is ready to copy
state=$work/opnsense-cert
status=$state/status.txt
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

usage() { echo "usage: opnsense-cert-check check|status" >&2; exit 2; }
[[ $# -eq 1 ]] || usage

case $1 in
  status)
    [[ -s $status ]] || { echo "opnsense-cert-check: no check has been saved yet" >&2; exit 1; }
    cat -- "$status"
    exit 0 ;;
  check) ;;
  *) usage ;;
esac

[[ -f $settings ]] || { echo "opnsense-cert-check: $settings is missing; set agent_box_opnsense_backup in the inventory and run the agent_box role" >&2; exit 1; }
host=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["host"])' "$settings")
[[ $host =~ ^[A-Za-z0-9.-]+$ ]] || { echo "opnsense-cert-check: the host setting is not a name or an address" >&2; exit 1; }

install -d -m 0700 "$state"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

save() { # the line to print and keep, and the exit code
  printf '%s %s\n' "$now" "$1" > "$status"
  logger -t opnsense-cert-check -- "$1" 2>/dev/null || true
  if [[ $2 -ne 0 ]]; then echo "$1" >&2; else echo "$1"; fi
  exit "$2"
}

# s_client verifies the chain against the lab chain when it exists, else against the system store; -verify_return_error makes a
# failed chain end the handshake, so a line with a date is always one that verified.
cafile_args=()
if [[ -r $chain ]]; then cafile_args=(-CAfile "$chain" -no-CApath); fi
out=$(mktemp)
trap 'rm -f "$out"' EXIT
# The host setting is a name or an IPv4 address: a name goes in SNI and is checked as a host name, an address as an IP.
if [[ $host =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then host_args=(-verify_ip "$host"); else host_args=(-servername "$host" -verify_hostname "$host"); fi
if ! timeout 20 openssl s_client -connect "$host:$port" "${host_args[@]}" ${cafile_args[@]+"${cafile_args[@]}"} \
     -verify_return_error </dev/null > "$out" 2>&1; then
  # A refused or failed handshake: tell the two causes apart, because the second one is the finding this check exists for.
  if grep -q 'Verification error\|verify error' "$out"; then
    reason=$(grep -m1 'verify error' "$out" | cut -c1-90 || true)
    save "WARN opnsense-cert-check: the certificate the firewall serves does not verify against the lab chain ($reason)" 1
  fi
  save "WARN opnsense-cert-check: no certificate could be read from the firewall's web UI (connection or handshake failed)" 1
fi
# s_client prints the server's certificate first; x509 reads the first PEM block of the file and skips the text around it.
enddate=$(openssl x509 -noout -enddate -in "$out" 2>/dev/null | sed 's/^notAfter=//' || true)
[[ -n $enddate ]] || save "WARN opnsense-cert-check: the connection worked but no end date could be read from the certificate" 1
end=$(date -u -d "$enddate" +%s)
days=$(( (end - $(date -u +%s)) / 86400 ))
line="notAfter $(date -u -d "$enddate" +%Y-%m-%d), $days days left, verified yes"
if (( days < warn_days )); then
  save "WARN opnsense-cert-check: $line; fewer than $warn_days days, and c1 renews at 30 days left, so a renewed certificate is ready: copy it with Path A of set-opnsense-gui-certificate.md" 1
fi
save "opnsense-cert-check: $line" 0
