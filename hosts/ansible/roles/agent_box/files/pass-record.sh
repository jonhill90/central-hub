#!/bin/bash
# /usr/local/libexec/agent-box/pass-record.sh: the pass ledger the merge sweep reads (D-0042 rule 2, rule 8).
# Runs as user `keys` through sudo. Installed by the agent_box role; root owns it.
#   pass-record add ROLE OWNER/REPO PR HEAD RELAY_REF RELAY_TIME RECORDER   append one pass for this exact head
#                                                                            (RECORDER: orchestrator, builder or reviewer; the reviewer records the role reviewer only)
#   pass-record show OWNER/REPO HEAD                                         print that head's ledger
#   pass-record digest-pass FROM TO DIGEST RELAY_REF RELAY_TIME reviewer     the reviewer's pass of one agent-box limit change
#                                                                            (box-apply reads it in place of an approval PR; the owner's order of 2026-11-22)
#   pass-record halt RELAY_REF RECORDER | resume RELAY_REF RECORDER        set or clear the stop flag the sweep reads first
#                                                                            (resume: recorder orchestrator only)
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
    jonhill90/central-hub | jonhill90/inpara | jonhill90/agent-notebook | jonhill90/obsidian-graph-3d | jonhill90/wizards | jonhill90/central-hub-app) ;;
    *) die "$1 is not one of the project's repositories" ;;
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
    case $recorder in orchestrator | builder | reviewer) ;; *) die "RECORDER must be orchestrator, builder or reviewer" ;; esac
    # The reviewer lane records its own pass, so a merge does not wait for the orchestrator (an agent pick, relayed by the
    # orchestrator on 2026-11-18). It records the role reviewer only: never a council line (earlier ledgers keep theirs) and never an owner-tap.
    [[ $recorder != reviewer || $role == reviewer ]] || die "the reviewer records only the role reviewer"
    # An owner-tap line is the orchestrator's word for a card tap the box cannot see; any session can call add, so
    # no other recorder may write one.
    [[ $role != owner-tap || $recorder == orchestrator ]] || die "owner-tap is recorded by the orchestrator only"
    if [[ $recorder == builder ]]; then
      # The builder never records a pass for a PR the builder wrote. The PR body is data, so this is a speed bump.
      lane=$("$libexec/pr-merge.sh" lane "$full" "$pr") || die "the PR's author lane could not be read; a builder record is refused"
      # "builder" as a word anywhere in the label, in any case, so "agent box builder" and "Builder lane" both count as the builder.
      [[ ! ${lane,,} =~ (^|[^a-z0-9])builder([^a-z0-9]|$) ]] || die "the builder does not record a pass for a PR the builder wrote"
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
  digest-pass)
    [[ $# == 7 ]] || die "usage: pass-record digest-pass FROM TO DIGEST RELAY_REF RELAY_TIME orchestrator|reviewer"
    from=$2 to=$3 digest=$4 ref=$5 rtime=$6 recorder=$7
    [[ $from =~ ^[0-9a-f]{40}$ && $to =~ ^[0-9a-f]{40}$ ]] || die "FROM and TO must be full 40-character commits"
    [[ $from != "$to" ]] || die "FROM and TO are the same commit"
    [[ $digest =~ ^[0-9a-f]{64}$ ]] || die "DIGEST must be the 64-character digest box-apply plan prints"
    ref_ok "$ref" || die "RELAY_REF must be a cmsg_ message id"
    [[ $rtime =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "RELAY_TIME must be an ISO time like 2026-11-14T13:00:00Z"
    # The reviewer lane never touches the box; like `add`, the orchestrator records its pass (relay_ref is the reviewer's own digest-pass
    # post), or the reviewer itself. box-apply counts both and no other recorder. Any session can name itself either: a name, not proof.
    [[ $recorder == orchestrator || $recorder == reviewer ]] || die "a digest pass is recorded by the orchestrator or the reviewer only"
    install -d -m 0700 "$passes"
    python3 -I -c '
import json, sys
frm, to, digest, ref, rtime, rec, box = sys.argv[1:8]
print(json.dumps({"from": frm, "to": to, "digest": digest, "relay_ref": ref, "relay_time": rtime,
                  "recorder": rec, "box_time": box}, sort_keys=True))
' "$from" "$to" "$digest" "$ref" "$rtime" "$recorder" "$(now)" >> "$passes/limits.jsonl"
    journal "digest-pass from=${from:0:7} to=${to:0:7} digest=${digest:0:12} ref=$ref recorder=$recorder"
    echo "pass-record: digest pass recorded for ${from:0:8} to ${to:0:8}"
    ;;
  halt | resume)
    [[ $# == 3 ]] || die "usage: pass-record $1 RELAY_REF RECORDER"
    ref_ok "$2" || die "RELAY_REF must be a cmsg_ message id"
    # Any lane that reviews may stop the sweep (a council or the reviewer must be able to stop a merge); only the orchestrator lifts it.
    case $3 in orchestrator | builder | reviewer | council-a | council-b | council-c) ;; *) die "RECORDER must be orchestrator, builder, reviewer or council-a, council-b or council-c" ;; esac
    # Only the orchestrator lifts a halt, so a halt it relays from the owner is not undone by another lane's call.
    # Any session can name itself the orchestrator; this is a name, not proof.
    [[ $1 == halt || $3 == orchestrator ]] || die "resume is recorded by the orchestrator only"
    install -d -m 0700 "$passes"
    if [[ $1 == halt ]]; then printf '%s %s %s\n' "$(now)" "$2" "$3" > "$passes/HALT"; else rm -f "$passes/HALT"; fi
    printf '%s %s %s %s\n' "$(now)" "$1" "$2" "$3" >> "$passes/halt.log"
    journal "$1 ref=$2 recorder=$3"
    echo "pass-record: sweep $1 recorded"
    ;;
  *) die "usage: pass-record add|show|digest-pass|halt|resume ..." ;;
esac
