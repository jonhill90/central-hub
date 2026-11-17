#!/usr/bin/env bash
# The key-file reader in opnsense-backup.sh: OPNsense's key=/secret= format and the controller's two bare
# lines (key, then secret), with CR, spaces, quotes and a missing final newline; anything else is refused.
# Fake values only. The parser is cut out of the script, so the test runs the real code.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
script=$root/hosts/ansible/roles/agent_box/files/opnsense-backup.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sed -n "/^parsed=\$(python3 -I -c '\$/,/^' \"\\\$apikey\")/p" "$script" | sed '1d;$d' > "$tmp/parse.py"
[[ -s $tmp/parse.py ]] || { echo "FAIL: could not cut the parser out of the script"; exit 1; }
K=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
S=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
fail=0
want() { # name, expected (ok|bad), file content via printf format
  printf "$3" > "$tmp/f"
  if out=$(python3 -I "$tmp/parse.py" "$tmp/f" 2>/dev/null); then got=ok; else got=bad; fi
  if [[ $got == "$2" && ( $2 == bad || $out == "$K"$'\n'"$S" ) ]]; then echo "ok: $1"; else echo "FAIL: $1 (got $got)"; fail=1; fi
}
want "OPNsense download format"        ok  "key=$K\nsecret=$S\n"
want "key= format, CRLF"               ok  "key=$K\r\nsecret=$S\r\n"
want "key= format, spaces and quotes"  ok  "key = \"$K\"\nsecret = '$S'\n"
want "secret line first in key= form"  ok  "secret=$S\nkey=$K\n"
want "two bare lines"                  ok  "$K\n$S\n"
want "two bare lines, no final newline" ok "$K\n$S"
want "two bare lines, CRLF"            ok  "$K\r\n$S\r\n"
want "two bare lines, blank line between" ok "$K\n\n$S\n"
want "one line"                        bad "$K\n"
want "three lines"                     bad "$K\n$S\nx\n"
want "key= only"                       bad "key=$K\n"
want "bad characters"                  bad "$K\n$S;rm\n"
want "empty file"                      bad ""
exit $fail
