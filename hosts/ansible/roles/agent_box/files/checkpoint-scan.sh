#!/bin/bash
# /usr/local/libexec/agent-box/checkpoint-scan.sh: the hourly checkpoint as a box script (checkpoint-scan.py, beside it).
# Runs as user `keys` through sudo, and hourly from checkpoint-scan.timer as the same user. Installed by the agent_box
# role; root owns it.
#   checkpoint-scan run    scan once: said-i-would rows left Open, merges with no pass, ledger times, moved heads;
#                          print the findings, and post through checkpoint-note only when the report is new
#   checkpoint-scan show   print the last scan's report
# Exit: 0 no finding, 3 findings (the timer's unit counts 3 as success), 2 usage.
set -euo pipefail
case "${1:-}" in
  run | show) [[ $# == 1 ]] || { echo "usage: checkpoint-scan run | show" >&2; exit 2; } ;;
  *) echo "usage: checkpoint-scan run | show" >&2; exit 2 ;;
esac
export HOME=/var/lib/agent-box PATH=/usr/local/bin:/usr/bin:/bin
exec python3 -I /usr/local/libexec/agent-box/checkpoint-scan.py "$1"
