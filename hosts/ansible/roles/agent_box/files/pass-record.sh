#!/bin/bash
# /usr/local/libexec/agent-box/pass-record.sh: the pass ledger the merge sweep reads (D-0042 rule 2, rule 8).
# Runs as user `keys` through sudo. Installed by the agent_box role; root owns it.
#   pass-record add ROLE OWNER/REPO PR HEAD RELAY_REF RELAY_TIME RECORDER   append one pass for this exact head
#   pass-record show OWNER/REPO HEAD                                         print that head's ledger
#   pass-record halt RELAY_REF | resume RELAY_REF                           set or clear the stop flag the sweep reads first
# The ledger is a file per repository and head, so a new head starts empty and no pass carries over. One identity
# records all four checkers, so a line proves the recorder's word and the relay id it gave, not four separate
# judgements; the sweep's PR comment lists every line. Everything is checked here and a bad argument writes nothing.
set -euo pipefail
umask 077

work=/var/lib/agent-box
passes=$work/passes
libexec=/usr/local/libexec/agent-box
die() { echo "pass-record: $*" >&2; exit 2; }
ref_ok() { [[ $1 =~ ^cmsg_[A-Za-z0-9]{10,64}$ ]]; }
repo_ok() {
  case $1 in
    jonhill90/central-hub | jonhill90/inpara | jonhill90/agent-notebook | jonhill90/obsidian-graph-3d) ;;
    *) die "$1 is not one of the project's four repositories" ;;
  esac
}
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
journal() { logger -t pass-record -- "$*" 2>/dev/null || true; }

case ${1:-} in
  add)
    [[ $# == 8 ]] || die "usage: pass-record add ROLE OWNER/REPO PR HEAD RELAY_REF RELAY_TIME RECORDER"
    role=$2 full=$3 pr=$4 head=$5 ref=$6 rtime=$7 recorder=$8
    case $role in reviewer | council-a | council-b | council-c | owner-tap) ;; *) die "unknown role '$role'" ;; esac
    repo_ok "$full"
    [[ $pr =~ ^[0-9]{1,6}$ ]] || die "PR must be a number"
    [[ $head =~ ^[0-9a-f]{40}$ ]] || die "HEAD must be the full 40-character head"
    ref_ok "$ref" || die "RELAY_REF must be a cmsg_ message id"
    [[ $rtime =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "RELAY_TIME must be an ISO time like 2026-11-14T13:00:00Z"
    case $recorder in orchestrator | builder) ;; *) die "RECORDER must be orchestrator or builder" ;; esac
    # An owner-tap line is the orchestrator's word for a card tap the box cannot see; any session can call add, so
    # no other recorder may write one.
    [[ $role != owner-tap || $recorder == orchestrator ]] || die "owner-tap is recorded by the orchestrator only"
    if [[ $recorder == builder ]]; then
      # The builder never records a pass for a PR the builder wrote. The PR body is data, so this is a speed bump.
      lane=$("$libexec/pr-merge.sh" lane "$full" "$pr") || die "the PR's author lane could not be read; a builder record is refused"
      [[ $lane != builder ]] || die "the builder does not record a pass for a PR the builder wrote"
    fi
    dir=$passes/${full#*/}
    install -d -m 0700 "$passes" "$dir"
    python3 -I -c '
import json, sys
role, full, pr, head, ref, rtime, rec, box = sys.argv[1:9]
print(json.dumps({"role": role, "repo": full, "pr": int(pr), "head": head, "relay_ref": ref,
                  "relay_time": rtime, "recorder": rec, "box_time": box}, sort_keys=True))
' "$role" "$full" "$pr" "$head" "$ref" "$rtime" "$recorder" "$(now)" >> "$dir/$head.jsonl"
    journal "add role=$role repo=$full pr=$pr head=${head:0:7} ref=$ref recorder=$recorder"
    echo "pass-record: $role recorded for $full#$pr ${head:0:7}"
    ;;
  show)
    [[ $# == 3 ]] || die "usage: pass-record show OWNER/REPO HEAD"
    repo_ok "$2"
    [[ $3 =~ ^[0-9a-f]{40}$ ]] || die "HEAD must be the full 40-character head"
    f=$passes/${2#*/}/$3.jsonl
    [[ -f $f ]] && cat "$f" || echo "pass-record: no ledger for ${3:0:7}"
    ;;
  halt | resume)
    [[ $# == 2 ]] || die "usage: pass-record $1 RELAY_REF"
    ref_ok "$2" || die "RELAY_REF must be a cmsg_ message id"
    install -d -m 0700 "$passes"
    if [[ $1 == halt ]]; then printf '%s %s\n' "$(now)" "$2" > "$passes/HALT"; else rm -f "$passes/HALT"; fi
    printf '%s %s %s\n' "$(now)" "$1" "$2" >> "$passes/halt.log"
    journal "$1 ref=$2"
    echo "pass-record: sweep $1 recorded"
    ;;
  *) die "usage: pass-record add|show|halt|resume ..." ;;
esac
