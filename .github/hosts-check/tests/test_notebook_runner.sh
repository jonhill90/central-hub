#!/usr/bin/env bash
# The notebook runner pod on c1 (docs/runbooks/run-the-notebook-runner-on-c1.md), offline: its pin is VM 300's pin,
# the weekly bump can move it, it is made on prod only, and its start script checks the release before running it.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
chart=$root/hosts/kubernetes/home/c1/apps/notebook-runner
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
python3 -I - "$root" <<'PY' || fail=1
import re, sys, yaml
root = sys.argv[1]
role = yaml.safe_load(open(root + "/hosts/ansible/roles/ci_runner/defaults/main.yml"))
vals = yaml.safe_load(open(root + "/hosts/kubernetes/home/c1/apps/notebook-runner/values.yaml"))
text = open(root + "/hosts/kubernetes/home/c1/apps/notebook-runner/values.yaml").read()
rv = yaml.safe_load(open(root + "/hosts/kubernetes/home/c1/root/values.yaml"))
bump = open(root + "/hosts/ansible/roles/agent_box/files/ci-runner.sh").read()
fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    fails += 0 if cond else 1
check("the pod's runner version is VM 300's pin", str(vals["runnerVersion"]) == str(role["ci_runner_version"]))
check("the pod's SHA-256 is VM 300's pin", vals["runnerSha256"] == role["ci_runner_sha256"])
check("the pod takes jobs for the notebook's label", vals["labels"] == ",".join(role["ci_runner_labels"]))
check("the pod serves the same repository", vals["repoURL"] == role["ci_runner_repo_url"])
check("the image is pinned by digest", re.search(r"@sha256:[0-9a-f]{64}$", vals["image"]) is not None)
# The weekly bump's patterns for the chart, read from ci-runner.sh, each match exactly one line.
pats = re.findall(r'\(r"(\^[^"]+)",', bump[bump.index("chart = \"hosts/kubernetes"):])
check("the bump has three patterns for the chart", len(pats) == 3)
for p in pats:
    check("the bump's pattern %s matches one line" % p, len(re.findall(p, text, flags=re.M)) == 1)
app = rv["apps"].get("notebook-runner") if isinstance(rv.get("apps"), dict) else None
check("the root chart lists the app", app is not None)
check("the app is made only when notebookRunner is true", app is not None and app.get("enabledBy") == "notebookRunner")
check("notebookRunner is false in git", rv.get("notebookRunner") is False)
sys.exit(1 if fails else 0)
PY
# openbao-prod sets it in its own inventory copy; rebuild-prod and c1-ansible get it from prod-root-vars.py, which both exec.
grep -q 'v\["k8s_gitops_source_notebook_runner"\] = True' "$root/hosts/ansible/roles/agent_box/files/openbao-prod.sh" \
  && ok "openbao-prod sets the switch for prod" || bad "openbao-prod does not set the switch"
grep -q 'v\["k8s_gitops_source_notebook_runner"\] = True' "$root/hosts/ansible/roles/agent_box/files/prod-root-vars.py" \
  && ok "prod-root-vars.py sets the switch for prod" || bad "prod-root-vars.py does not set the switch"
for w in rebuild-prod c1-ansible; do
  grep -q 'prod-root-vars.py' "$root/hosts/ansible/roles/agent_box/files/$w.sh" \
    && ok "$w gets the switch from prod-root-vars.py" || bad "$w does not use prod-root-vars.py"
done
if grep -q 'notebook_runner' "$root/hosts/ansible/roles/agent_box/files/rebuild.sh" "$root/hosts/rebuild-k8s.sh"; then bad "the dev rebuild names the switch"; else ok "the dev rebuild never sets the switch"; fi
grep -q '{% if k8s_gitops_source_notebook_runner | bool %}' "$root/hosts/ansible/roles/k8s_gitops/templates/source-argocd.yaml.j2" \
  && ok "the root Application passes notebookRunner only when the switch is on" || bad "notebookRunner parameter"
s=$chart/files/start.sh
grep -q 'sha256sum -c -' "$s" && ok "the start script checks the release's SHA-256 before unpacking" || bad "no SHA-256 check"
grep -q -- '--disableupdate' "$s" && ok "self-update stays off" || bad "self-update not off"
bash -n "$s" && ok "the start script parses" || bad "start script syntax"
# A pod made before its registration token exists must wait, not exit: an exit is a restart loop that pages ntfy (C1PodCrashLooping).
fn=$(mktemp); tokf=$(mktemp -u); trap 'rm -f "$fn" "$tokf"' EXIT
sed -n '/^# wait_for_token begin$/,/^# wait_for_token end$/p' "$s" > "$fn"
if [ -s "$fn" ]; then
  # No token: the function must still be running after 3 seconds (timeout exits 124), not have exited by itself.
  rc=0; TOKEN_FILE=$tokf TOKEN_WAIT_SECONDS=1 timeout 3 bash -c ". $fn; wait_for_token" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 124 ] && ok "with no token the start script waits and does not exit" || bad "with no token the start script exited (rc $rc)"
  # The token arrives later: it is returned alone on stdout.
  ( sleep 1; printf 'tok123' > "$tokf" ) &
  got=$(TOKEN_FILE=$tokf TOKEN_WAIT_SECONDS=1 timeout 5 bash -c ". $fn; wait_for_token" 2>/dev/null || true); wait
  [ "$got" = tok123 ] && ok "the token written later is picked up" || bad "token not picked up (got '$got')"
else
  bad "start.sh has no wait_for_token function"
fi
if grep -q 'no registration token in the store' "$s"; then bad "start.sh still exits when the token is missing"; else ok "start.sh no longer exits when the token is missing"; fi
if command -v helm > /dev/null; then
  out=$(helm template notebook-runner "$chart" --namespace notebook-runner)
  grep -q 'automountServiceAccountToken: false' <<<"$out" && ok "no ServiceAccount token" || bad "a token is mounted"
  grep -q 'pod-security.kubernetes.io/enforce: restricted' <<<"$out" && ok "restricted pod security" || bad "pod security"
  grep -q 'except: \[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10\]' <<<"$out" && ok "no egress to private or tailnet ranges" || bad "egress"
  grep -q 'ingress: \[\]' <<<"$out" && ok "nothing comes in" || bad "ingress"
fi
[ "$fail" = 0 ] || exit 1
echo "notebook runner: all checks passed"
