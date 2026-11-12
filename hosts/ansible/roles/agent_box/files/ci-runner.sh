#!/bin/bash
# /usr/local/libexec/agent-box/ci-runner.sh: build and set up the notebook's self-hosted CI runner
# (docs/runbooks/set-up-the-ci-runner.md). It runs as user `keys` through sudo, so the session that
# asks for it never sees the Proxmox token, the runner's SSH key or the GitHub App key. Installed
# by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/ci-runner.sh plan|apply|configure|destroy|bump
#   (weekly is for the timer, which runs it as `keys` without sudo)
# plan, apply, destroy: OpenTofu on hosts/terraform/home/ci-runner with the agents' Proxmox token.
# configure: the ci_runner playbook over SSH, with a one-hour registration token minted from the
# GitHub App, narrowed to the one repository and the one permission it needs.
# bump: if actions/runner has a release newer than the pin on main and at least two weeks old
# (STD-0003), checks its SHA-256 against a download and opens a central-hub PR that moves the pin,
# as the App. Changes nothing when the pin is current or that PR is open already.
# weekly: configure, then bump. The agent box's timer runs it (role agent_box); the runner's
# self-update is off, so this is how a merged pin reaches the runner.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | configure | destroy | bump | weekly) action=$1 ;;
  *) echo "usage: ci-runner plan|apply|configure|destroy|bump|weekly" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
repo=$work/central-hub
folder=$repo/hosts/terraform/home/ci-runner
settings=$work/ci-runner.json   # private values the agent_box role writes from the inventory
state=$work/state/ci-runner.tfstate
plan=$work/state/ci-runner.tfplan
vars=$work/state/ci-runner.tfvars.json
sshkey=$keys/ci-runner-ssh
# Ansible comes from the box's own virtual environment (role agent_box), as in the rebuild wrapper.
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/ci-runner TF_IN_AUTOMATION=1 ANSIBLE_HOME=$work/ansible-home

[[ -f $settings ]] || { echo "ci-runner: $settings is missing; set agent_box_ci_runner in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit.
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "ci-runner: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The runner's own SSH key, made here the first time. Only its public half leaves this folder.
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box ci-runner" -f "$sshkey"

tofu_run() {
  python3 -I - "$settings" "$sshkey.pub" "$repo" "$vars" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
json.dump({
    "proxmox_node_name": s["proxmox_node_name"],
    "vnet": s["vnet"],
    "vlans_file": sys.argv[3] + "/hosts/ansible/inventories/home/group_vars/all/vlans.yml",
    "template_vm_id": s["template_vm_id"],
    "ssh_public_key": open(sys.argv[2]).read().strip(),
    "runner": {k: s[k] for k in ("name", "vm_id", "address", "cores", "memory_mb", "disk_gb")},
}, open(sys.argv[4], "w"))
PY
  # PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN (agent@pve!dev).
  set -a
  # shellcheck source=/dev/null
  . "$keys/proxmox-dev.env"
  set +a
  tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
  tofu init -input=false -backend-config="path=$state" >/dev/null
  case $action in
    plan) tofu plan -input=false -var-file="$vars" -out="$plan" ;;
    apply)
      [[ -f $plan ]] || { echo "ci-runner: no saved plan; run ci-runner plan first" >&2; exit 1; }
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
    destroy)
      tofu plan -destroy -input=false -var-file="$vars" -out="$plan"
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
  esac
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# An installation token from the GitHub App "Central Hub Agents", cut down to one repository and
# the permissions asked for (a JSON object), so it can do only the one job it is minted for.
app_token() {
  local owner=$1 name=$2 perms=$3 app_id now jwt inst
  app_id=$(setting github_app_id)
  now=$(date +%s)
  jwt="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)"
  jwt="$jwt.$(printf '%s' "$jwt" | openssl dgst -sha256 -sign "$keys/github-app.pem" | b64url)"
  inst=$(BEARER=$jwt api "https://api.github.com/repos/$owner/$name/installation" | field id) ||
    {
      # GET /app works with any valid JWT, so it tells a wrong ID or key from a missing install.
      if BEARER=$jwt api "https://api.github.com/app" >/dev/null; then
        echo "ci-runner: the App's ID and key work, but the App is not installed on $owner/$name" >&2
      else
        echo "ci-runner: GitHub refused the App's ID or key" >&2
      fi
      return 1
    }
  BEARER=$jwt api -X POST \
    -d "{\"repositories\":[\"$name\"],\"permissions\":$perms}" \
    "https://api.github.com/app/installations/$inst/access_tokens" | field token ||
    { echo "ci-runner: no installation token for $owner/$name with $perms (has the installation accepted it?)" >&2; return 1; }
}

# A registration token for the one repository. The App needs the repository permission
# Administration (write), which GitHub requires for this call.
registration_token() {
  local owner name tok
  owner=$(setting repo_owner)
  name=$(setting repo_name)
  tok=$(app_token "$owner" "$name" '{"administration":"write"}') || return 1
  BEARER=$tok api -X POST "https://api.github.com/repos/$owner/$name/actions/runners/registration-token" |
    field token
}

# One GitHub API call, with the bearer token in BEARER. The token goes to curl as a config line on
# stdin, never as an argument, because any local user can read arguments from /proc/<pid>/cmdline.
# On an error it prints the status and GitHub's message (never a token) and fails.
api() {
  local out code
  out=$(printf 'header = "Authorization: Bearer %s"\n' "$BEARER" |
    curl -sS -K - -w '\n%{http_code}' -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@") || return 1
  code=${out##*$'\n'}
  out=${out%$'\n'*}
  if [[ $code != 2* ]]; then
    printf 'ci-runner: GitHub returned %s for %s: %s\n' "$code" "${*: -1}" \
      "$(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("message", ""))' 2>/dev/null)" >&2
    return 1
  fi
  printf '%s' "$out"
}

# Quiet on bad input: api() has already said what went wrong.
field() { python3 -I -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1" 2>/dev/null; }

configure() {
  local extra inventory
  extra=$(mktemp --suffix=.json "$work/state/ci-runner-extra.XXXXXX")
  # The .json suffix makes Ansible read the inventory as YAML (JSON), not INI.
  inventory=$(mktemp --suffix=.json "$work/state/ci-runner-inventory.XXXXXX")
  # Expanded now: the trap runs after configure returns, when its locals are gone.
  # shellcheck disable=SC2064
  trap "rm -f '$extra' '$inventory'" EXIT
  python3 -I - "$settings" "$inventory" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
json.dump({"ci_runner": {"hosts": {"ci_runner_vm": {
    "ansible_host": s["address"], "ansible_user": "admin", "ci_runner_hostname": s["name"]}}}},
    open(sys.argv[2], "w"))
PY
  # A runner that is registered already needs no token, so a failed mint only warns; the role
  # stops if the runner isn't registered and has no token.
  local token
  token=$(registration_token) || { echo "ci-runner: no registration token (does the App have Administration: write?)" >&2; token=""; }
  printf '{"ci_runner_registration_token": "%s"}\n' "$token" > "$extra"
  mkdir -p "$work/.ssh"
  cd "$repo/hosts/ansible"
  # A rebuilt runner has a new host key, and the run stops on it: remove its line from
  # $work/.ssh/known_hosts after checking (docs/runbooks/set-up-the-ci-runner.md).
  ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/.ssh/known_hosts" \
    ansible-playbook -i "$inventory" --private-key "$sshkey" -e "@$extra" playbooks/ci-runner.yml
}

# Open a central-hub PR that moves the runner pin to the newest release at least two weeks old.
# The pin is read from origin/main, the release list and tarball come from GitHub, and the PR is
# made through the API as the App (Contents and Pull requests, write), so no git credentials are
# stored and nothing runs from a branch.
bump() {
  local defaults=hosts/ansible/roles/ci_runner/defaults/main.yml tok
  tok=$(app_token jonhill90 central-hub '{"contents":"write","pull_requests":"write"}') || return 1
  BEARER=$tok python3 -I - "$repo/$defaults" "$defaults" "$work/state" <<'PY'
import base64, datetime, hashlib, json, os, re, sys, urllib.request

local_file, path, scratch = sys.argv[1:4]
api = "https://api.github.com"
target = "jonhill90/central-hub"


def call(method, url, body=None, raw=False):
    req = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Authorization", "Bearer " + os.environ["BEARER"])
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return data if raw else json.loads(data or b"null")


def vtuple(v):
    return tuple(int(x) for x in v.split("."))


text = open(local_file).read()
pinned = re.search(r"^ci_runner_version: (\S+)$", text, re.M).group(1)

# Releases two weeks old or more (STD-0003), newest version first.
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=14)
releases = []
for r in call("GET", api + "/repos/actions/runner/releases?per_page=30"):
    if r["draft"] or r["prerelease"] or not re.fullmatch(r"v\d+\.\d+\.\d+", r["tag_name"]):
        continue
    published = datetime.datetime.fromisoformat(r["published_at"].replace("Z", "+00:00"))
    if published <= cutoff:
        releases.append((vtuple(r["tag_name"][1:]), r, published))
if not releases:
    sys.exit("ci-runner bump: no release at least two weeks old was found")
releases.sort(key=lambda x: x[0], reverse=True)
_, rel, published = releases[0]
version = rel["tag_name"][1:]
if vtuple(version) <= vtuple(pinned):
    print(f"ci-runner bump: the pin {pinned} is current (newest release two weeks old: {version})")
    sys.exit(0)

branch = "chore/bump-ci-runner-" + version.replace(".", "-")
for pr in call("GET", f"{api}/repos/{target}/pulls?state=open&per_page=100"):
    if pr["head"]["ref"] == branch:
        print(f"ci-runner bump: PR #{pr['number']} already moves the pin to {version}")
        sys.exit(0)

# The SHA-256 must match twice: the release notes' line for the linux-x64 tarball, and a download.
asset = f"actions-runner-linux-x64-{version}.tar.gz"
body = rel.get("body") or ""
m = (re.search(r"<!-- BEGIN SHA linux-x64 -->([0-9a-f]{64})<!-- END SHA linux-x64 -->", body)
     or re.search(re.escape(asset) + r"\W+([0-9a-f]{64})", body))
if not m:
    sys.exit(f"ci-runner bump: the notes of {rel['tag_name']} give no SHA-256 for {asset}; pin it by hand")
noted = m.group(1)
url = next((a["browser_download_url"] for a in rel["assets"] if a["name"] == asset), None)
if not url:
    sys.exit(f"ci-runner bump: {rel['tag_name']} has no {asset}")
digest = hashlib.sha256()
with urllib.request.urlopen(url, timeout=600) as r:
    for chunk in iter(lambda: r.read(1 << 20), b""):
        digest.update(chunk)
if digest.hexdigest() != noted:
    sys.exit(f"ci-runner bump: the download of {asset} doesn't match its release notes; nothing opened")

today = datetime.date.today().isoformat()
new = text
for pattern, repl in [
    (r"v\d+\.\d+\.\d+, published \d{4}-\d{2}-\d{2}\.", f"v{version}, published {published.date().isoformat()}."),
    (r"actions-runner-linux-x64-\d+\.\d+\.\d+\.tar\.gz", asset),
    (r"download on \d{4}-\d{2}-\d{2}\.", f"download on {today}."),
    (r"^ci_runner_version: \S+$", f"ci_runner_version: {version}"),
    (r"^ci_runner_sha256: \S+$", f"ci_runner_sha256: {noted}"),
]:
    new, n = re.subn(pattern, repl, new, flags=re.M)
    if n != 1:
        sys.exit(f"ci-runner bump: {path} no longer has exactly one line matching {pattern!r}; nothing opened")

main_sha = call("GET", f"{api}/repos/{target}/git/ref/heads/main")["object"]["sha"]
on_main = call("GET", f"{api}/repos/{target}/contents/{path}?ref={main_sha}")
call("POST", f"{api}/repos/{target}/git/refs", {"ref": "refs/heads/" + branch, "sha": main_sha})
call("PUT", f"{api}/repos/{target}/contents/{path}", {
    "message": f"chore: bump the CI runner to {version}",
    "content": base64.b64encode(new.encode()).decode(),
    "sha": on_main["sha"],
    "branch": branch,
})
pr = call("POST", f"{api}/repos/{target}/pulls", {
    "title": f"chore: bump the CI runner to {version}",
    "head": branch,
    "base": "main",
    "body": "\n".join([
        "## Summary", "",
        f"- Moves the notebook's CI runner pin from {pinned} to {version}, the newest actions/runner release at least two weeks old (STD-0003), published {published.date().isoformat()}.",
        f"- SHA-256 `{noted}`, from the release notes and matched against a download on {today}.",
        "", "## Issue", "", "- Closes: none.",
        "", "## Deploy impact", "",
        "- What the GitOps tool will change when this merges (Foundation: none): none. The agent box's next weekly `ci-runner configure` installs the new runner.",
        "", "## Validation Evidence", "", "- Opened by the agent box's weekly `ci-runner bump` (hosts/ansible/roles/agent_box/files/ci-runner.sh).",
        "", "## Test plan", "", "- [ ] CI checks pass",
        "", "## Notes", "",
        "- The runner's self-update is off, and GitHub stops queuing jobs on a runner more than 30 days behind a new release, so merge this within about two weeks.",
        "", "Author-Lane: runner-bump timer",
    ]),
})
print(f"ci-runner bump: opened PR #{pr['number']} moving the pin from {pinned} to {version}")
PY
}

case $action in
  plan | apply | destroy) tofu_run ;;
  configure) configure ;;
  bump) bump ;;
  weekly)
    # Each half runs even if the other fails, and the run fails if either did.
    rc=0
    ( configure ) || rc=1
    ( bump ) || rc=1
    exit $rc
    ;;
esac
