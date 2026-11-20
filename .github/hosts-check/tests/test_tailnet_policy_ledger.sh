#!/usr/bin/env bash
# The tailnet policy job's box-side apply (hosts/ansible/roles/agent_box/files/tailnet-policy.sh; D-0063 rule 3), with a
# stand-in tofu and a local repository as main:
#   1. The new actions refuse bad arguments; pass and go refuse the wrong recorder and write nothing.
#   2. apply-recorded with no saved plan refuses; after plan, it refuses naming both a missing pass and a missing go.
#   3. With a reviewer pass for the plan's commit and hash and a go for the commit, it applies once; the go is then spent.
#   4. It reads only the two OAuth lines of the guard folder's env file, and never prints them.
# Usage: .github/hosts-check/tests/test_tailnet_policy_ledger.sh   (needs git and python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/keys" "$t/work" "$t/bin"
printf 'TAILSCALE_OAUTH_CLIENT_ID=TESTID123\nTAILSCALE_OAUTH_CLIENT_SECRET="TESTSECRET456"\nOTHER=x\n' > "$t/keys/tailnet-policy.env"
echo 'tailnet = "x"' > "$t/keys/tailnet-policy.tfvars"
git init -q -b main "$t/src" && mkdir -p "$t/src/hosts/terraform/home/tailnet-policy" "$t/src/hosts/ansible/inventories/home/group_vars/all"
echo 'print("acls")' > "$t/src/hosts/terraform/home/tailnet-policy/policy_sections.py"
git -C "$t/src" add -A && git -C "$t/src" -c user.name=t -c user.email=t@t commit -q -m one
git clone -q --bare "$t/src" "$t/main.git"
# The stand-in tofu: plan writes a plan file, show prints set JSON, apply records its call; it records the OAuth env it saw.
cat > "$t/bin/tofu" <<EOF
#!/bin/bash
echo "\$* id=\$TAILSCALE_OAUTH_CLIENT_ID" >> "$t/calls"
for a in "\$@"; do case \$a in -out=*) echo planned > "\${a#-out=}" ;; esac; done
case " \$* " in *" show "*) echo '{"resource_changes": [{"change": {"actions": ["update"]}}]}' ;; esac
exit 0
cat > "$t/bin/tofu" <<EOF
#!/bin/bash
echo "\$* id=\$TAILSCALE_OAUTH_CLIENT_ID" >> "$t/calls"
for a in "\$@"; do case \$a in -out=*) echo "planned \$RANDOM" > "\${a#-out=}" ;; esac; done
case " \$* " in *" show "*) echo '{"resource_changes": [{"change": {"actions": ["update"]}}]}' ;; esac
exit 0
EOF
chmod +x "$t/bin/tofu"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^work=.*|work=$t/work|" -e "s|^repo_url=.*|repo_url=$t/main.git|" \
    -e "s|/usr/local/bin/tofu|$t/bin/tofu|g" \
    "$root/hosts/ansible/roles/agent_box/files/tailnet-policy.sh" > "$t/job.sh"
grep -q "^keys=$t/keys" "$t/job.sh" && grep -q "^repo_url=$t/main.git" "$t/job.sh" || { echo "FAIL: could not point the wrapper at its folders"; exit 1; }
job() { bash "$t/job.sh" "$@"; }
c=$(git -C "$t/main.git" rev-parse main); tm=2026-11-20T00:00:00Z

# 1
for a in "apply-recorded" "apply-recorded 0123456789AB" "ledger x" "pass $c 0123456789ab cmsg_0123456789ab $tm" "go ${c:0:12} cmsg_0123456789ab $tm orchestrator"; do
  # shellcheck disable=SC2086
  job $a >/dev/null 2>&1; rc=$?; [ "$rc" = 2 ] || bad "1 '$a' gave $rc, not 2"
done
job pass "$c" 0123456789ab cmsg_0123456789ab "$tm" builder >/dev/null 2>&1; r1=$?
job go "$c" cmsg_0123456789ab "$tm" reviewer >/dev/null 2>&1; r2=$?
[ $r1 = 2 ] && [ $r2 = 2 ] && [ ! -d "$t/work/ledger" ] && [ ! -e "$t/calls" ] && ok "1 bad arguments and wrong recorders refused, nothing run or written" || bad "1 $r1 $r2"

# 2
job apply-recorded 0123456789ab > "$t/2a.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "no saved plan" "$t/2a.out" && ok "2 no saved plan: refused" || bad "2a rc=$rc $(cat "$t/2a.out")"
job plan > "$t/plan.out" 2>&1 || bad "plan failed: $(cat "$t/plan.out")"
h=$(sed -n 's/^tailnet-policy: plan \([0-9a-f]\{12\}\):.*/\1/p' "$t/plan.out")
job apply-recorded "$h" > "$t/2b.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "no reviewer pass" "$t/2b.out" && grep -q "no go for" "$t/2b.out" && ! grep -q -- ' apply -input' "$t/calls" \
  && ok "2 no pass and no go: refused naming both, tofu apply not run" || bad "2b rc=$rc $(cat "$t/2b.out")"

# 3
job pass "$c" "$h" cmsg_0123456789ab "$tm" reviewer >/dev/null
job go "$c" cmsg_0123456789cd "$tm" orchestrator >/dev/null
job apply-recorded "$h" > "$t/3.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -q "applied plan $h" "$t/3.out" && [ "$(grep -c -- ' apply -input' "$t/calls")" = 1 ] && ok "3 with a pass and a go it applies once" || bad "3 rc=$rc $(cat "$t/3.out")"
h2=$(job plan 2>&1 | sed -n 's/^tailnet-policy: plan \([0-9a-f]\{12\}\):.*/\1/p')
job pass "$c" "$h2" cmsg_0123456789ab "$tm" reviewer >/dev/null
job apply-recorded "$h2" > "$t/3b.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "was used already" "$t/3b.out" && ok "3 the go is spent: a second apply needs a new go" || bad "3b rc=$rc $(cat "$t/3b.out")"

# 4
grep -q "id=TESTID123" "$t/calls" && ok "4 tofu got the client ID from the guard folder's env file" || bad "4 calls: $(head -2 "$t/calls")"
if cat "$t"/*.out | grep -q 'TESTID123\|TESTSECRET456'; then bad "4 a client value was printed"; else ok "4 nothing printed holds the client's values"; fi
exit $fail
