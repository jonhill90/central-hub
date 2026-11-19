#!/usr/bin/env bash
# The dev rebuild's node probes (hosts/rebuild-k8s.sh: node_pressure_probe, vm_mem_probe, node_journal_diag), added after
# the dev worker went <unknown> at 71% working set (2026-11-19 07:20 UTC). Runs the three functions against stubs:
#   1. vm_mem_probe logs only this run's VM IDs from the guest list, never another guest.
#   2. node_pressure_probe asks every node (-T 10) for /proc/pressure memory, cpu and io and free, and logs the reply.
#   3. A hanging ansible is cut at the timeout, logs a "no reading" line and does not fail the caller.
#   4. node_journal_diag asks for the lab zone's ports, forward ports and firewalld policies, the kernel warnings and the kubelet and containerd journal with become, prefixes each
#      line `diag:`, scrubs a secret, and survives a hanging ansible.
#   5. The failed-run diag calls node_journal_diag and reads Cilium's host-routing line, and the identity-keycloak sampler calls both probes each minute.
# Usage: .github/hosts-check/tests/test_node_probes.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
repo=$PWD; script=hosts/rebuild-k8s.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/ansible" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$ANSIBLE_ARGS"
case "${ANSIBLE_MODE:-ok}" in
  hang) sleep 30 ;;
  ok) echo 'node1 | CHANGED | rc=0 | (stdout) some avg10=0.00 total=1 some avg10=1.5 total=2 Mem: 6000 4100 200';;
  journal) printf '%s\n' '-- kernel warnings' 'Out of memory: Killed process 1 (java)' 'token=abcDEF1234567890secret' '-- kubelet and containerd' 'kubelet started';;
esac
STUB
chmod +x "$work/bin/ansible"
export PATH="$work/bin:$PATH" ANSIBLE_ARGS="$work/args"
fn=$(sed -n '/^node_pressure_probe() {/,/^# A failed ephemeral-dev run/p' "$script" | sed '$d')
[ -n "$fn" ] || { echo "FAIL could not read the probe functions from $script"; exit 1; }
run() { # mode, function, label ; stdout: the log
  ( log="$work/log"; raw="$work/raw"; : > "$log"; : > "$raw"; export repo INVENTORY=/x ids=$'250\n251'
    export PROBE_TIMEOUT_S=2 JOURNAL_TIMEOUT_S=2 ANSIBLE_MODE=$1
    preflight_guests() { printf '%s\n' 'preflight: guest vmid=250 type=qemu status=running maxmem=3584 MiB mem=2900 MiB name=cp pool=dev' \
      'preflight: guest vmid=2500 type=qemu status=running maxmem=1 MiB mem=1 MiB name=other pool=x' \
      'preflight: guest vmid=300 type=qemu status=running maxmem=2048 MiB mem=1836 MiB name=runner pool=ci'; }
    eval "$fn"; "$2" "$3" >/dev/null 2>&1; echo "rc=$?" >> "$work/rc"; cat "$log" "$raw" )
}
: > "$work/rc"
out=$(run ok vm_mem_probe idk)
{ printf '%s\n' "$out" | grep -q 'vm .* guest vmid=250 ' && ! printf '%s\n' "$out" | grep -Eq 'vmid=(300|2500)'; } &&
  ok "1 vm_mem_probe logs the run's VM only" || bad "1 vm_mem_probe logged the wrong guests: $out"
out=$(run ok node_pressure_probe idk); a=$(cat "$ANSIBLE_ARGS")
{ printf '%s\n' "$out" | grep -q 'idk: node psi .*avg10=1.5' && printf '%s' "$a" | grep -q -- '-T 10' &&
  printf '%s' "$a" | grep -q '/proc/pressure/memory' && printf '%s' "$a" | grep -q '/proc/pressure/cpu' &&
  printf '%s' "$a" | grep -q '/proc/pressure/io' && printf '%s' "$a" | grep -q 'free -m'; } &&
  ok "2 node_pressure_probe asks for memory, cpu and io pressure and free, and logs the reply" || bad "2 the pressure probe is wrong: $a / $out"
start=$(date +%s); out=$(run hang node_pressure_probe idk); took=$(( $(date +%s) - start ))
{ [ "$took" -lt 10 ] && printf '%s\n' "$out" | grep -q 'idk: node psi .*no reading' && ! grep -q 'rc=[1-9]' "$work/rc"; } &&
  ok "3 a hanging ansible is cut at the timeout (${took}s), logged as no reading, caller not failed" || bad "3 hang handling wrong (${took}s): $out"
out=$(run journal node_journal_diag x); a=$(cat "$ANSIBLE_ARGS")
{ printf '%s\n' "$out" | grep -q '^diag: Out of memory: Killed process' && printf '%s' "$a" | grep -q -- '-b' &&
  printf '%s' "$a" | grep -q 'journalctl -k -p warning' && printf '%s' "$a" | grep -q 'firewall-cmd --zone=lab --list-ports' &&
  printf '%s' "$a" | grep -q 'firewall-cmd --zone=lab --list-forward-ports' && printf '%s' "$a" | grep -q 'firewall-cmd --get-policies' && printf '%s' "$a" | grep -q 'journalctl -u kubelet -u containerd' &&
  ! printf '%s\n' "$out" | grep -q 'abcDEF1234567890secret'; } &&
  ok "4 node_journal_diag reads the lab zone's ports, forward ports and policies, kernel and kubelet journals with become, prefixes diag:, scrubs the token" || bad "4 journal diag is wrong: $a / $out"
start=$(date +%s); run hang node_journal_diag x >/dev/null; took=$(( $(date +%s) - start ))
{ [ "$took" -lt 10 ] && ! grep -q 'rc=[1-9]' "$work/rc"; } && ok "4b journal diag survives a hanging ansible (${took}s)" || bad "4b journal diag hung or failed (${took}s)"
if sed -n '/^runner_capture_diag() {/,/^}/p' "$script" | grep -q '^  node_journal_diag || true$' &&
   sed -n '/^runner_capture_diag() {/,/^}/p' "$script" | grep -q "cilium-dbg status 2>&1 | grep -iE 'host routing|masquerading|kubeproxyreplacement'" &&
   sed -n '/^node_top_sampler() {/,/^}/p' "$script" | grep -q '^    node_pressure_probe "\$1"; vm_mem_probe "\$1"$'; then
  ok "5 the failed-run diag calls the node probe and reads Cilium's host routing, and the sampler calls the probes"
else bad "5 a probe is not called from the diag or the sampler"; fi
exit "$fail"
