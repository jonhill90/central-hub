#!/bin/bash
# /usr/local/libexec/agent-box/pickup-scan.sh: the box pickup scan (pickup-scan.py, beside it).
# Runs as user `keys` through sudo (dry-run and show only), and every 10 minutes from pickup-scan.timer as the same
# user (the mode agent_box_pickup_mode names). Installed by the agent_box role; root owns it.
#   pickup-scan dry-run   scan once: print the ready list of each project and what would be posted; post nothing
#   pickup-scan run       scan once and post what is new (the timer's job once the owner's pick turns it on)
#   pickup-scan show      print the last scan's report
# Exit: 0 nothing new, 3 something new (the timer's unit counts 3 as success), 2 usage.
set -euo pipefail
case "${1:-}" in
  run | dry-run | show) [[ $# == 1 ]] || { echo "usage: pickup-scan dry-run | run | show" >&2; exit 2; } ;;
  *) echo "usage: pickup-scan dry-run | run | show" >&2; exit 2 ;;
esac
export HOME=/var/lib/agent-box PATH=/usr/local/bin:/usr/bin:/bin
exec python3 -I /usr/local/libexec/agent-box/pickup-scan.py "$1"
