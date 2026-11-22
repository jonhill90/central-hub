#!/bin/bash
# /usr/local/libexec/agent-box/signin-check.sh: run the three scripted sign-in checks (Jellyfin, Argo CD, Proxmox) against prod
# with the test user, from the agent box. It runs as user `keys` through sudo, because the test user's password and TOTP seed are
# lines in <keys>/prod/identity.env, which a session cannot read. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/signin-check.sh run|log
# run   builds a private credentials file for each check from <keys>/prod/signin-check.json (the places and the test user's
#       name, no secret) and identity.env (PASSWORD_<USER> and TOTP_<USER>), runs the three scripts from this wrapper's own
#       checkout of main, and prints only their numbered lines. A password, seed, code, state or token is never printed.
#       The exit is 0 only when every check that ran passed.
# log   the newest run's lines.
# The test user is an access right the owner's go creates (docs/runbooks/move-jellyfin-to-argo-cd.md); with no such user in
# signin-check.json the wrapper stops before any request. It makes nothing in Keycloak, Jellyfin, Argo CD or Proxmox.
# signin-check.json (JSON, written by the controller and copied by its prod-files run): base, realm, user, expect_admin; jellyfin_base
# and provider; argocd_base; pve_base and pve_realm (optional: no pve_base, no Proxmox check); address, pve_address, digits, period,
# verify, admin_group, viewer_group (optional, as the scripts take them).
set -euo pipefail
umask 077

keys=/etc/agent-keys
work=/var/lib/agent-box
repo=$work/checkouts/signin-check   # this wrapper's own checkout of central-hub
logs=$work/signin-check/logs
conf=$keys/prod/signin-check.json
values=$keys/prod/identity.env
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

usage() { echo "usage: signin-check run|log" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
action=$1
case $action in run | log) ;; *) usage ;; esac

if [[ $action == log ]]; then
  newest=$(find "$logs" -maxdepth 1 -name 'run-*.log' 2>/dev/null | sort | tail -n 1)
  [[ -n $newest ]] || { echo "signin-check: no run has been logged yet" >&2; exit 1; }
  echo "run: ${newest##*/}"
  cut -c1-200 -- "$newest" | tail -n 60
  exit 0
fi

[[ -s $conf ]] || { echo "signin-check: $conf is missing; the controller's prod-files run copies it (docs/runbooks/move-jellyfin-to-argo-cd.md)" >&2; exit 1; }
[[ -s $values ]] || { echo "signin-check: $values is missing; the controller's prod-files run copies it" >&2; exit 1; }
mkdir -p "$logs" "$work/state"
exec 9>"$work/state/signin-check.lock"
flock -n 9 || { echo "signin-check: another run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse --short HEAD)

tmp=$(mktemp -d "$work/state/signin-check.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
log=$logs/run-$(date -u +%Y%m%dT%H%M%SZ).log
# One private file per check, built in Python so that no value is in an argument or in the output. Prints the names of the checks
# to run, one per line, or a line "refused: ..." and exits non-zero.
checks=$(python3 -I -c "$(cat <<'PY'
import json, os, re, sys
conf, values, tmp = sys.argv[1:4]
def die(m):
    print("refused: " + m); sys.exit(1)
try:
    c = json.load(open(conf))
except (OSError, ValueError):
    die("signin-check.json is not readable JSON")
for k in ("base", "realm", "user", "jellyfin_base", "argocd_base"):
    if not isinstance(c.get(k), str) or not c[k]:
        die("signin-check.json lacks: " + k)
key = re.sub(r"[^A-Z0-9]", "_", c["user"].upper())
env = {}
for ln in open(values):
    ln = ln.rstrip("\n")
    if "=" in ln and not ln.lstrip().startswith("#"):
        k, v = ln.split("=", 1)
        env[k.strip()] = v.strip().strip("'\"")
for k in ("PASSWORD_" + key, "TOTP_" + key):
    if not env.get(k):
        die("identity.env has no %s line (the test user is not made, or its lines were not copied)" % k)
common = {k: c[k] for k in ("base", "realm", "user", "expect_admin", "address", "digits", "period", "verify", "admin_group", "viewer_group") if k in c}
common.update(password=env["PASSWORD_" + key], seed=env["TOTP_" + key])
files = {"jellyfin": dict(common, jellyfin_base=c["jellyfin_base"], provider=c.get("provider", "keycloak")),
         "argocd": dict(common, argocd_base=c["argocd_base"])}
# Grafana: its name is grafana_base, or the Argo CD name with its first label argocd swapped for grafana (both are app names under the
# same zone). With neither the run is refused before any request, so a missing Grafana never reads as a pass.
graf = c.get("grafana_base") or re.sub(r"^(https?://)argocd\.", r"\1grafana.", c["argocd_base"], count=1)
if graf and graf != c["argocd_base"]:
    files["grafana"] = dict(common, grafana_base=graf)
else:
    die("signin-check.json has no grafana_base and argocd_base has no argocd label to swap for grafana")
if c.get("pve_base"):
    files["proxmox"] = dict(common, pve_base=c["pve_base"], pve_realm=c.get("pve_realm", "sso"))
    if c.get("pve_address"):
        files["proxmox"]["pve_address"] = c["pve_address"]
for name, body in files.items():
    fd = os.open(os.path.join(tmp, name + ".json"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(body, f)
    print(name)
PY
)" "$conf" "$values" "$tmp") || { echo "signin-check: $checks" >&2; exit 1; }

declare -A script=([jellyfin]=roles/k8s_identity/files/jellyfin-signin-check.py [argocd]=roles/k8s_gitops/files/argocd-signin-check.py
                   [proxmox]=roles/proxmox_sso/files/proxmox-signin-check.py [grafana]=roles/k8s_observability/files/grafana-signin-check.py)
rc=0
{
  echo "signin-check: commit $commit"
  for name in $checks; do
    s=$repo/hosts/ansible/${script[$name]}
    if [[ ! -f $s ]]; then echo "$name: the script is not in this commit of main"; rc=1; continue; fi
    echo "== $name"
    out=$(python3 -I "$s" "$tmp/$name.json" 2>&1) && sc=0 || sc=$?
    printf '%s\n' "$out" | cut -c1-200
    [[ $sc -eq 0 ]] || { echo "$name: exit $sc"; rc=1; }
  done
} > "$log"
cat "$log"
echo "signin-check: $([[ $rc -eq 0 ]] && echo PASS || echo FAIL)"
exit "$rc"
