#!/usr/bin/env bash
# Test of role k8s_backup's Azure SAS tasks (tasks/azure_sas.yml) on this machine, with a stand-in
# for the Azure CLI, so no Azure account is needed:
#   1. The tasks call `az storage container generate-sas` with the role's arguments, a start about
#      15 minutes ago, and an expiry az accepts (more than 6 and less than 7 days from now).
#   2. The node env lines name the account, quote the SAS, and give its expiry from the SAS's se=.
#   3. Those lines, sourced by bash as c1-backup-lib.sh does, give back the SAS unchanged.
#   4. An az that returns no user delegation SAS stops the run.
# Usage: .github/hosts-check/tests/test_backup_azure_sas.sh   (needs ansible-core, python3)
set -euo pipefail
# Not UTC on purpose: the controller is a Mac in US Eastern time, and a time zone bug in the
# expiry was found there (2026-11-09). CI runners use UTC, which would hide it.
export TZ=America/New_York
cd "$(dirname "$0")/../../.."
root=$PWD
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The stand-in az: checks its arguments, then prints a SAS shaped like az's (Microsoft Learn,
# "Create a user delegation SAS for a container or blob with the Azure CLI"), or a bad one.
cat > "$work/az" <<'AZ'
#!/usr/bin/env python3
import sys, datetime, urllib.parse
args = sys.argv[1:]
log = open(sys.argv[0] + ".log", "w")
log.write(" ".join(args) + "\n")
want = ["storage", "container", "generate-sas"]
assert args[:3] == want, args
opt = {args[i]: args[i + 1] for i in range(3, len(args) - 1) if args[i].startswith("--") and not args[i + 1].startswith("--")}
for flag in ("--https-only", "--as-user"):
    assert flag in args, flag
assert opt["--auth-mode"] == "login" and opt["--permissions"] == "racwdl", opt
assert opt["--account-name"] == "exampleaccount" and opt["--name"] == "c1-backup", opt
expiry = datetime.datetime.strptime(opt["--expiry"], "%Y-%m-%dT%H:%MZ").replace(tzinfo=datetime.timezone.utc)
left = expiry - datetime.datetime.now(datetime.timezone.utc)
if not datetime.timedelta(days=6) < left < datetime.timedelta(days=7):
    sys.exit(f"--expiry should be within 7 days from now (got {left})")
start = datetime.datetime.strptime(opt["--start"], "%Y-%m-%dT%H:%MZ").replace(tzinfo=datetime.timezone.utc)
back = datetime.datetime.now(datetime.timezone.utc) - start
if not datetime.timedelta(minutes=10) < back < datetime.timedelta(minutes=20):
    sys.exit(f"--start should be about 15 minutes ago (got {back} ago)")
if open(sys.argv[0] + ".mode").read().strip() == "bad":
    print("not a sas")
else:
    se = urllib.parse.quote(opt["--expiry"], safe="")
    print(f"se={se}&sp=racwdl&sv=2022-11-02&sr=c&skoid=0000&sktid=1111&skt=x&ske=y&sks=b&skv=2022-11-02&sig=ab%2Bc%3D")
AZ
chmod +x "$work/az"

cat > "$work/play.yml" <<'PLAY'
- name: Azure SAS tasks of k8s_backup
  hosts: localhost
  gather_facts: false
  vars:
    k8s_backup_azure_account: exampleaccount
    k8s_backup_azure_container: c1-backup
    k8s_backup_azure_sas_days: 7
  tasks:
    - name: The role's Azure SAS tasks
      ansible.builtin.include_role:
        name: k8s_backup
        tasks_from: azure_sas.yml
    - name: Write the env lines for the test to read
      ansible.builtin.copy:
        content: "{{ k8s_backup_azure_env_lines }}"
        dest: "{{ out }}"
        mode: "0600"
PLAY

run() {
  ANSIBLE_ROLES_PATH="$root/hosts/ansible/roles" ansible-playbook -i localhost, -c local "$work/play.yml" \
    -e "k8s_backup_az=$work/az" -e "out=$work/env"
}

echo good > "$work/az.mode"
run >"$work/run.log" 2>&1 || { cat "$work/run.log"; echo "FAIL: the SAS tasks failed with a good az" >&2; exit 1; }
echo "ok   1. az called with the role's arguments and an expiry az accepts"

grep -qx 'AZURE_ACCOUNT_NAME=exampleaccount' "$work/env" || { cat "$work/env"; echo "FAIL: account line" >&2; exit 1; }
grep -qE "^AZURE_ACCOUNT_SAS_EXPIRES=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$" "$work/env" || { cat "$work/env"; echo "FAIL: expiry line" >&2; exit 1; }
echo "ok   2. env lines: account, quoted SAS, expiry from se="

sas=$(set -a; . "$work/env"; printf '%s' "$AZURE_ACCOUNT_SAS")
case $sas in
  se=*'&sig=ab%2Bc%3D') echo "ok   3. the SAS comes back unchanged when bash sources the lines" ;;
  *) echo "FAIL: sourced SAS is '$sas'" >&2; exit 1 ;;
esac

echo bad > "$work/az.mode"
if run >"$work/run.log" 2>&1; then
  echo "FAIL: a run with no user delegation SAS passed" >&2
  exit 1
fi
grep -q "az did not return a user delegation SAS" "$work/run.log" || { cat "$work/run.log"; echo "FAIL: wrong failure" >&2; exit 1; }
echo "ok   4. no user delegation SAS stops the run"
echo "backup azure sas: 4 checks passed"
