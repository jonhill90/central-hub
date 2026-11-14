#!/usr/bin/env bash
# Give the agent box its own read-only OPNsense API key for the daily configuration copy (pick 220): user
# "box-backup" with two privileges, made by opnsense-backup-user.php (its header says why those two).
# Run on the controller, from hosts/ansible, with root SSH to the Proxmox host:
#   bootstrap/opnsense-backup-user.sh [-i <SSH key>] <Proxmox host> [<OPNsense VM ID, default 100>]
# -i names the private key the host accepts for root (the one the controller's Proxmox wrappers use); ssh then
# offers only that key (IdentitiesOnly), because the host refuses other keys and an agent's or the default key
# is tried first otherwise. Without -i, ssh uses its own settings for the host.
# The key and secret are made here, once, in ~/.config/central-hub/opnsense-backup-api.txt (0600, two lines:
# the key, then the secret); a run again keeps them. OPNsense gets only "<key>|<sha512-crypt of the secret>".
# Nothing secret is printed or put in an argument: the secret reaches openssl on stdin, and only base64 of the
# hash line and of the PHP file goes to the firewall, through the host's QEMU guest agent, in pieces of 512
# bytes (larger guest-agent payloads hung OPNsense's agent, set-up-lab-network-and-firewall.md step 6).
# Then the agent_box role's prod_files tasks copy the file to the box (set-up-the-box-lifeline.md).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
usage="usage: $0 [-i <SSH key>] <Proxmox host> [<OPNsense VM ID>]"
ssh_opts=(-n -o BatchMode=yes)
while getopts 'i:' opt; do
  case $opt in
    i) [[ -r $OPTARG ]] || { echo "opnsense-backup-user: cannot read SSH key $OPTARG" >&2; exit 2; }
       ssh_opts+=(-i "$OPTARG" -o IdentitiesOnly=yes) ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
host=${1:?$usage}
vm=${2:-100}
[[ $host =~ ^[A-Za-z0-9.:-]+$ && $vm =~ ^[0-9]+$ ]] || { echo "opnsense-backup-user: bad host or VM ID" >&2; exit 2; }
keyfile=$HOME/.config/central-hub/opnsense-backup-api.txt
umask 077
marks=$(mktemp -d)
written=$marks/written

if [[ ! -s $keyfile ]]; then
  mkdir -p "$(dirname "$keyfile")"
  { openssl rand -base64 60 | tr -d '\n'; echo; openssl rand -base64 60 | tr -d '\n'; echo; } > "$keyfile"
  echo "opnsense-backup-user: made $keyfile"
fi
chmod 0600 "$keyfile"
[[ $(grep -c . "$keyfile") == 2 ]] || { echo "opnsense-backup-user: $keyfile must be two lines, the key then the secret" >&2; exit 1; }
key=$(sed -n 1p "$keyfile")
hash=$(sed -n 2p "$keyfile" | openssl passwd -6 -stdin)
# shellcheck disable=SC2016  # a literal $6$, the sha512-crypt prefix
[[ $hash == '$6$'* ]] || { echo "opnsense-backup-user: openssl passwd -6 failed; it needs OpenSSL 1.1.1 or later" >&2; exit 1; }

# One guest-agent command; fails unless the command's own exit code is 0. Prints what it wrote to stdout.
gx() {
  # shellcheck disable=SC2029  # $vm and $1 are meant to expand here: they make the command the host runs
  ssh "${ssh_opts[@]}" "root@$host" "qm guest exec $vm --timeout 60 -- $1" |
    python3 -I -c 'import json, sys
d = json.load(sys.stdin)
sys.stdout.write(d.get("out-data", "")); sys.stderr.write(d.get("err-data", ""))
sys.exit(0 if d.get("exited") and d.get("exitcode") == 0 else 1)'
}
# Write stdin to a file on the firewall: base64 in 512-byte pieces, then decoded there.
put() {
  local dest=$1 data piece
  data=$(base64 | tr -d '\n')
  gx "/bin/sh -c ': > $dest.b64'"
  : > "$written"   # the firewall now holds a file of ours; a marker file, because put runs in a pipeline's subshell
  while [[ -n $data ]]; do
    piece=${data:0:512}; data=${data:512}
    gx "/bin/sh -c 'printf %s $piece >> $dest.b64'"
  done
  gx "/bin/sh -c 'openssl base64 -d -A -in $dest.b64 -out $dest && chmod 0600 $dest && rm -f $dest.b64'"
}

# The key line and the PHP file must not stay on the firewall whichever way this run ends, so a failed PHP step, a
# dropped connection or Ctrl-C all remove them (and any half-written .b64 pieces) before the script exits. The
# removal is best effort: if the firewall cannot be reached, it says so and names the files to remove by hand.
# It runs only once the first write to the firewall has succeeded: a failure at the first SSH call (the wrong key,
# an unreachable host) wrote nothing, so there is nothing to remove and no hand-removal notice.
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -e $written ]] && ! gx "rm -f /root/box-backup-user.php /root/box-backup-apikey.line /root/box-backup-user.php.b64 /root/box-backup-apikey.line.b64" >/dev/null 2>&1; then
    echo "opnsense-backup-user: could not remove /root/box-backup-apikey.line and /root/box-backup-user.php (and their .b64 pieces) from the firewall; remove them by hand" >&2
    [[ $rc -eq 0 ]] && rc=1
  fi
  rm -rf "$marks"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

printf '%s|%s\n' "$key" "$hash" | put /root/box-backup-apikey.line
put /root/box-backup-user.php < "$here/opnsense-backup-user.php"
gx "php /root/box-backup-user.php"
echo "opnsense-backup-user: done; now copy $keyfile to the box (agent_box role, tags prod_files)"
