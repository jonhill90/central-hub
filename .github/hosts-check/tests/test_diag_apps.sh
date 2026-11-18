#!/usr/bin/env bash
# hosts/diag-apps.py: the failed-run reads. `apps` lists each application that is not Synced and Healthy with its message,
# its conditions and its unhealthy resources, and skips the healthy ones; both modes scrub secrets and long token-like strings.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
json='{"items":[{"metadata":{"name":"openbao"},"status":{"sync":{"status":"Synced"},"health":{"status":"Progressing","message":"waiting token=abc123"},"conditions":[{"type":"SyncError","message":"failed password: hunter2 eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9abcdefghijklmnop"}],"resources":[{"kind":"StatefulSet","namespace":"openbao","name":"openbao","status":"Synced","health":{"status":"Progressing","message":"Waiting for 1 pods"}},{"kind":"Service","namespace":"openbao","name":"svc","status":"Synced","health":{"status":"Healthy"}}]}},{"metadata":{"name":"fine"},"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}]}'
out=$(python3 -I hosts/diag-apps.py apps <<< "$json")
if [[ $out == *"openbao: sync=Synced health=Progressing"* && $out == *"StatefulSet openbao/openbao sync=Synced health=Progressing Waiting for 1 pods"* && $out != *fine* && $out != *"Service openbao/svc"* ]]; then
  ok "apps: the unhealthy app and resource are listed, the healthy ones are not"; else bad "apps: $out"; fi
if [[ $out != *abc123* && $out != *hunter2* && $out != *eyJhbG* && $out == *"<redacted>"* ]]; then ok "apps: secrets are scrubbed"; else bad "apps scrub: $out"; fi
out=$(python3 -I hosts/diag-apps.py apps <<< '{"items":[{"metadata":{"name":"a"},"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}]}')
if [[ $out == "every application is Synced and Healthy" ]]; then ok "apps: all healthy says so"; else bad "apps healthy: $out"; fi
out=$(python3 -I hosts/diag-apps.py apps <<< 'not json'); if [[ $out == *"did not read as JSON"* ]]; then ok "apps: bad input is reported, not a crash"; else bad "apps bad input: $out"; fi
out=$(printf 'GET /x Authorization: Bearer abcdef\nsecret: s3cr3t value\nplain line\n%s\n' "$(printf 'B%.0s' {1..60})" | python3 -I hosts/diag-apps.py scrub)
if [[ $out != *abcdef* && $out != *s3cr3t* && $out != *BBBBBBBBBB* && $out == *"plain line"* ]]; then ok "scrub: secrets go, plain lines stay"; else bad "scrub: $out"; fi
shapes=$(cat <<'S'
{"password":"hunter2pass"}
password: "hunter2pass"
token: 'tok12345abc'
{"client_secret": "Zx9qWv3LmN8pRt2YkB7cD4fG6hJ1sA5e"}
"secret_id":"0f8fad5b-d9cb-469f-a165-70867728950e"
login with s.AbCdEfGhIjKlMnOpQrStUvWx now
postgres://keycloak:Sup3rS3cret@db.example:5432/kc
run --password hunter2pass --verbose
S
)
out=$(python3 -I hosts/diag-apps.py scrub <<< "$shapes")
leak=""; for v in hunter2pass tok12345abc Zx9qWv3LmN8pRt2YkB7cD4fG6hJ1sA5e 0f8fad5b-d9cb AbCdEfGhIjKlMnOpQrStUvWx Sup3rS3cret; do [[ $out == *"$v"* ]] && leak+=" $v"; done
if [[ -z $leak && $out == *"keycloak:<redacted>@db.example"* && $out == *"--verbose"* ]]; then ok "scrub: quoted JSON and YAML values, URL userinfo, OpenBao tokens and --flags go"; else bad "scrub shapes leaked:$leak :: $out"; fi
python3 -I hosts/diag-apps.py nothing < /dev/null > /dev/null 2>&1; rc=$?
if [[ $rc -eq 2 ]]; then ok "an unknown mode is refused"; else bad "unknown mode rc=$rc"; fi
exit "$fail"
