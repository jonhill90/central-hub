#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-kv.sh ACTION ADDR CACERT KEYS LIBEXEC [PATH KEY]: run only by the
# `secrets-store` wrapper, under its lock, for D-0058 rule 8 (SOPS holds a copy of every secret written into
# OpenBao). No value, token or AppRole ID is printed or passed as an argument: values come in on stdin, tokens go to
# curl on stdin, and the SOPS write takes its value on stdin (`sops set --value-stdin`, SOPS 3.13.3). Only key names
# are ever printed.
#
# The SOPS file is KEYS/openbao-kv.sops.json: {"<kv path>": {"<key>": "<value>"}}, encrypted to the box's own age
# identity (the secrets bundle's, KEYS/../secrets-bundle/age-identity.txt), so it is in the box's daily encrypted
# bundle and never in git. Paths are under c1/, the paths External Secrets reads (policy eso-c1).
#
# put PATH KEY   the value on stdin. SOPS first, one key only (never decrypt and re-encrypt the whole file), then
#                OpenBao: read kv/data/PATH, merge the one key, write it back with check-and-set on the version read
#                (0 when the path is new), so a write in between is refused, not overwritten. Fails if either write
#                fails, naming which.
# compare        every key of the SOPS file against OpenBao: equal SHA-256 of the value, or the key is named. Keys in
#                OpenBao at a path the SOPS file holds, but not in the file, are named too. Exit 1 on any difference.
# reseed         a fresh store, empty but for configure's old word c1/check (the restore helper's empty-store guard,
#                check 2) and kv/<env>/snapshot-mark (a time, no secret, which any snapshot writes, so the hourly off-box
#                send leaves one within the hour), gets every path of the SOPS file, each only if still absent (cas 0).
set -euo pipefail
# secrets-store.sh sets SECRETS_STORE_RESOLVE (<store name>:443:<the store's admin address>, D-0062) on dev, and on
# prod once prod has an admin address; every curl here goes there. Unset (prod with no admin address yet, or a helper
# run on its own, as in its test): curl as it is.
curl() { if [[ -n ${SECRETS_STORE_RESOLVE:-} ]]; then command curl --resolve "$SECRETS_STORE_RESOLVE" "$@"; else command curl "$@"; fi; }
umask 077
action=$1 addr=$2/v1 cacert=$3 keys=$4 libexec=$5
kvfile=$keys/openbao-kv.sops.json
# The environment is the keys folder's own name, dev or prod (the wrapper passes <keys>/<env>): it names the mark.
env=$(basename -- "$keys")
identity=$keys/../secrets-bundle/age-identity.txt
export SOPS_AGE_KEY_FILE=$identity

die() { echo "secrets-store $action: $*" >&2; exit 1; }
[[ -s $identity ]] || die "the box's age identity ($identity) is missing; set agent_box_secrets_bundle and run the agent_box role"

# A private folder in memory for the decrypted SOPS file and request bodies; gone when the run ends.
find /dev/shm -maxdepth 1 -name 'secrets-store-kv.*' -user "$(id -u)" -exec rm -rf -- {} +
tmp=$(mktemp -d /dev/shm/secrets-store-kv.XXXXXX)
token=''
cleanup() {
  [[ -z $token ]] || call POST auth/token/revoke-self -o /dev/null >/dev/null 2>&1 || true
  rm -rf -- "$tmp"
}
trap cleanup EXIT

# call METHOD PATH [curl args...]: the token goes in on stdin as a header, never in the argument list.
call() {
  local method=$1 path=$2
  shift 2
  curl -s --cacert "$cacert" -X "$method" -H @- "$@" "$addr/$path" <<<"X-Vault-Token: $token"
}
# login: prints the admin token. On a failure it prints nothing and leaves the reason in $tmp/login.why, for why():
# with no HTTP answer, curl's exit code and its name (https://curl.se/libcurl/c/libcurl-errors.html); with one, the
# HTTP code and OpenBao's error text. That text can quote the secret ID ("invalid secret_id %q") and the source
# address ("source address %q unauthorized through CIDR restrictions on the secret ID"; OpenBao v2.7.2,
# internal/builtin/credential/approle/path_login.go lines 269 and 291), so both IDs become <id>; an IPv4 or IPv6
# address becomes <the box's /32> or <another address than the box's /32> by SECRETS_STORE_BOX_CIDR (or <an address;
# the box's /32 is not set> while it is empty), never itself; and a tailnet name (*.ts.net) becomes <tailnet name>. The
# connect timeout ends a path that drops packets in 10 s, where the kernel's own retries took over two minutes.
login() {
  local rc=0
  python3 -I -c 'import json, sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
    "$keys/openbao-admin-role-id" "$keys/openbao-admin-secret-id" |
    curl -s --connect-timeout 10 --max-time 30 --cacert "$cacert" -X POST --data @- -o "$tmp/login.json" -w '%{http_code}' \
      "$addr/auth/approle/login" > "$tmp/login.code" || rc=$?
  python3 -I -c '
import ipaddress, json, os, re, sys
out, code_file, rc, rid_file, sid_file, why = sys.argv[1:7]
def read(p):
    try: return open(p).read()
    except OSError: return ""
def put(s): open(why, "w").write(s)
code, body = read(code_file).strip(), read(out)
if code == "200":
    try: print(json.loads(body)["auth"]["client_token"]); sys.exit()
    except Exception: put("the store answered HTTP 200 with no token"); sys.exit()
if code in ("", "000"):
    names = {"6": "the name did not resolve", "7": "the connection was refused or had no route", "28": "timed out",
             "35": "the TLS handshake failed", "52": "the store sent nothing", "55": "sending failed",
             "56": "receiving failed", "60": "the store'"'"'s certificate did not verify against the CA file"}
    put("no HTTP answer: curl exit %s (%s)" % (rc, names.get(rc, "see curl'"'"'s exit codes")))
    sys.exit()
try: errs = json.loads(body).get("errors") or []
except Exception: errs = []
text = "; ".join(str(e) for e in errs) or "no error text"
for f in (rid_file, sid_file):
    v = read(f).strip()
    if v: text = text.replace(v, "<id>")
text = re.sub(r"[0-9a-fA-F-]{24,}", "<id>", text)
box = os.environ.get("SECRETS_STORE_BOX_CIDR", "")
try: net = ipaddress.ip_network(box, strict=False) if box else None
except ValueError: net = None
def addr(m):
    try: a = ipaddress.ip_address(m.group(0))
    except ValueError: return "<address>"
    if net is None: return "<an address; the box'"'"'s /32 is not set>"
    return "<the box'"'"'s /32>" if a.version == net.version and a in net else "<another address than the box'"'"'s /32>"
text = re.sub(r"(?<![\w:])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f.]*(?![\w:])", addr, text)
text = re.sub(r"\b\d{1,3}(?:\.\d{1,3}){3}\b", addr, text)
text = re.sub(r"[\w.-]+\.ts\.net\b", "<tailnet name>", text)
put("the store answered HTTP %s: %s" % (code, text[:300]))' \
    "$tmp/login.json" "$tmp/login.code" "$rc" "$keys/openbao-admin-role-id" "$keys/openbao-admin-secret-id" "$tmp/login.why"
}
# why: the last failed login's reason, for the message that names it.
why() { cat -- "$tmp/login.why" 2>/dev/null || echo "no reason recorded"; }
# The SOPS file, decrypted into the private folder.
plain() {
  "$libexec/sops" decrypt --input-type json --output-type json --output "$tmp/plain.json" "$kvfile" ||
    die "the SOPS file does not decrypt with the box's identity"
}
valid_path() { [[ $1 =~ ^c1(/[a-z0-9][a-z0-9_-]*)+$ ]]; }

case $action in
  put | put-new)
    path=${6:-} key=${7:-}
    valid_path "$path" || die "the path must be c1/<name>[/<name>...], lowercase letters, digits, - and _"
    [[ $key =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || die "the key must be letters, digits, _, . and -"
    cat > "$tmp/value"
    [[ -s $tmp/value ]] || die "no value on stdin; nothing written"
    # The SOPS file, made once as an empty document for the box's identity.
    if [[ ! -e $kvfile ]]; then
      recipient=$("$libexec/age-keygen" -y "$identity")
      [[ $recipient =~ ^age1[0-9a-z]{58}$ ]] || die "the box's identity gives no age recipient"
      printf '{}' > "$tmp/empty.json"
      "$libexec/sops" encrypt --input-type json --output-type json --age "$recipient" --output "$kvfile.part" "$tmp/empty.json" ||
        { rm -f -- "$kvfile.part"; die "sops could not make $kvfile; nothing written"; }
      mv -- "$kvfile.part" "$kvfile"
    fi
    # put-new writes nothing when OpenBao already holds the key: a value kept there is never replaced by one adopted later.
    if [[ $action == put-new ]]; then
      token=$(login) && [[ -n $token ]] || die "the admin AppRole did not sign in ($(why)); nothing written"
      rc=$(call GET "kv/data/$path" -o "$tmp/current.json" -w '%{http_code}') || true
      [[ $rc == 200 || $rc == 404 ]] || die "reading kv/$path answered HTTP ${rc:-nothing}; nothing written"
      if [[ $rc == 200 ]] && python3 -I -c 'import json, sys; sys.exit(0 if sys.argv[2] in ((json.load(open(sys.argv[1]))["data"].get("data")) or {}) else 1)' "$tmp/current.json" "$key"; then
        echo "secrets-store put-new: kv/$path key $key is in OpenBao already; kept, nothing written"
        exit 0
      fi
    fi
    # 1. SOPS: the value as a JSON string on stdin, into the one key.
    index=$(python3 -I -c 'import json, sys; print("[%s][%s]" % (json.dumps(sys.argv[1]), json.dumps(sys.argv[2])))' "$path" "$key")
    python3 -I -c 'import json, sys; sys.stdout.write(json.dumps(open(sys.argv[1]).read()))' "$tmp/value" |
      "$libexec/sops" set --value-stdin "$kvfile" "$index" ||
      die "the SOPS write failed; OpenBao was not written"
    # 2. OpenBao: read, merge the one key, write back with check-and-set.
    [[ -n $token ]] || token=$(login) && [[ -n $token ]] || die "SOPS is written, but the admin AppRole did not sign in ($(why)), so OpenBao is not; run put again"
    rc=$(call GET "kv/data/$path" -o "$tmp/current.json" -w '%{http_code}') || true
    [[ $rc == 200 || $rc == 404 ]] || die "SOPS is written, but reading kv/$path answered HTTP ${rc:-nothing}, so OpenBao is not; run put again"
    python3 -I -c '
import json, sys
cur, val, key, out, found = sys.argv[1:6]
data, version = {}, 0
if found == "200":
    d = json.load(open(cur))["data"]
    data, version = d.get("data") or {}, d["metadata"]["version"]
data[key] = open(val).read()
json.dump({"options": {"cas": version}, "data": data}, open(out, "w"))' "$tmp/current.json" "$tmp/value" "$key" "$tmp/body.json" "$rc"
    rc=$(call POST "kv/data/$path" --data-binary "@$tmp/body.json" -o /dev/null -w '%{http_code}') || true
    [[ $rc == 200 || $rc == 204 ]] || die "SOPS is written, but OpenBao refused the write (HTTP ${rc:-nothing}); run put again, then compare"
    echo "secrets-store $action: kv/$path key $key written to SOPS, then OpenBao"
    ;;
  compare)
    [[ -e $kvfile ]] || die "no SOPS file ($kvfile): nothing has been written through put"
    plain
    token=$(login) && [[ -n $token ]] || die "the admin AppRole did not sign in ($(why))"
    python3 -I -c 'import json, sys; print("\n".join(k for k in json.load(open(sys.argv[1])) if k != "sops"))' "$tmp/plain.json" > "$tmp/paths"
    differ=0 count=0
    while read -r path; do
      valid_path "$path" || { echo "DIFF: $path is not a c1/ path in the SOPS file"; differ=1; continue; }
      rc=$(call GET "kv/data/$path" -o "$tmp/current.json" -w '%{http_code}') || true
      [[ $rc == 200 || $rc == 404 ]] || die "reading kv/$path answered HTTP ${rc:-nothing}"
      out=$(python3 -I -c '
import hashlib, json, sys
plain, cur, path, found = sys.argv[1:5]
want = json.load(open(plain))[path]
have = (json.load(open(cur))["data"].get("data") or {}) if found == "200" else {}
h = lambda v: hashlib.sha256(json.dumps(v).encode()).hexdigest()
for k in sorted(set(want) | set(have)):
    if k not in have: print("DIFF: %s %s is in SOPS, not in OpenBao" % (path, k))
    elif k not in want: print("DIFF: %s %s is in OpenBao, not in SOPS" % (path, k))
    elif h(want[k]) != h(have[k]): print("DIFF: %s %s differs" % (path, k))
    else: print("SAME")' "$tmp/plain.json" "$tmp/current.json" "$path" "$rc")
      while read -r line; do
        if [[ $line == SAME ]]; then count=$((count + 1)); else echo "$line"; differ=1; fi
      done <<<"$out"
    done < "$tmp/paths"
    (( differ == 0 )) || die "FAIL: SOPS and OpenBao differ at the keys above (names only)"
    echo "PASS: compare: $count keys equal in SOPS and OpenBao"
    ;;
  reseed)
    [[ -e $kvfile ]] || die "no SOPS file ($kvfile): nothing to reseed from"
    plain
    token=$(login) && [[ -n $token ]] || die "the admin AppRole did not sign in ($(why))"
    # The empty-store guard, as secrets-store-restore.sh check 2: only 200 and 404 are answers; any key but
    # c1/check and the snapshot mark <env>/snapshot-mark means the store is not fresh, and nothing is written.
    found=() queue=("")
    while (( ${#queue[@]} )); do
      p=${queue[0]}
      queue=("${queue[@]:1}")
      out=$(call LIST "kv/metadata/$p" -w '\n%{http_code}') || true
      rc=${out##*$'\n'}
      [[ $rc == 404 ]] && continue
      [[ $rc == 200 ]] || die "listing kv/$p answered HTTP ${rc:-nothing}; nothing written"
      listed=$(python3 -I -c 'import json, sys; print("\n".join(json.load(sys.stdin)["data"]["keys"]))' <<<"${out%$'\n'*}") ||
        die "listing kv/$p gave no key list; nothing written"
      while read -r k; do
        [[ -n $k ]] || continue
        if [[ $k == */ ]]; then queue+=("$p$k"); else found+=("$p$k"); fi
      done <<<"$listed"
    done
    for k in "${found[@]}"; do
      [[ $k == c1/check || $k == "$env/snapshot-mark" ]] || die "the store holds kv/$k, so it is not fresh; nothing written"
    done
    python3 -I -c 'import json, sys; print("\n".join(k for k in json.load(open(sys.argv[1])) if k != "sops"))' "$tmp/plain.json" > "$tmp/paths"
    n=0
    while read -r path; do
      valid_path "$path" || die "the SOPS file holds $path, not a c1/ path; stopped after $n paths"
      python3 -I -c '
import json, sys
json.dump({"options": {"cas": 0}, "data": json.load(open(sys.argv[1]))[sys.argv[2]]}, open(sys.argv[3], "w"))' "$tmp/plain.json" "$path" "$tmp/body.json"
      rc=$(call POST "kv/data/$path" --data-binary "@$tmp/body.json" -o /dev/null -w '%{http_code}') || true
      [[ $rc == 200 || $rc == 204 ]] || die "writing kv/$path answered HTTP ${rc:-nothing}; stopped after $n paths"
      n=$((n + 1))
    done < "$tmp/paths"
    echo "PASS: reseed: $n paths written from SOPS into the fresh store"
    ;;
  *) die "action must be put, compare or reseed" ;;
esac
