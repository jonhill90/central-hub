#!/bin/sh
# desktop-trust-check.sh CHAIN BUNDLE [NAME...]: run on the desktop VM by role desktop (task "The desktop
# trusts the lab's certificates"), before the admin user's key is removed, so the configure run fails while
# an agent can still look. Two checks, one line each:
#   1. The system trust store verifies the lab chain: openssl verifies CHAIN's first certificate (the lab
#      intermediate) with CHAIN's other certificates as untrusted helpers and BUNDLE (the extracted system
#      store) as the only anchors, so it passes only if the lab root is in BUNDLE.
#   2. For each NAME, curl opens https://NAME/ with no --cacert and no -k, so it uses the system store as
#      Firefox's system trust does; any HTTP status passes, any TLS error or no answer fails.
# Exit 0 only if every check passed. No secret is read or printed.
set -u
[ $# -ge 2 ] || { echo "usage: desktop-trust-check.sh CHAIN BUNDLE [NAME...]" >&2; exit 2; }
chain=$1 bundle=$2
shift 2
fail=0
err=$(mktemp)
trap 'rm -f "$err"' EXIT

subject=$(openssl x509 -in "$chain" -noout -subject 2>/dev/null | sed 's/^subject= *//')
if openssl verify -CAfile "$bundle" -untrusted "$chain" "$chain" >/dev/null 2>"$err"; then
  echo "desktop trust: the system store verifies the lab chain ($subject)"
else
  echo "desktop trust: the system store does not verify the lab chain ($subject): $(tr '\n' ' ' <"$err")"
  fail=1
fi

for name in "$@"; do
  code=$(curl -sS -o /dev/null --max-time 15 -w '%{http_code}' "https://$name/" 2>"$err")
  rc=$?
  case $rc in
    0) echo "desktop trust: $name: $code, certificate verified" ;;
    35 | 51 | 53 | 54 | 58 | 59 | 60 | 66 | 77 | 80 | 82 | 83 | 90 | 91)
      echo "desktop trust: $name: TLS failed (curl exit $rc): $(tr '\n' ' ' <"$err")"; fail=1 ;;
    *) echo "desktop trust: $name: not reached (curl exit $rc): $(tr '\n' ' ' <"$err")"; fail=1 ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "desktop trust: every check passed"
else
  echo "desktop trust: a check failed"
fi
exit "$fail"
