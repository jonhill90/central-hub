#!/usr/bin/env bash
# identity/check_realm.py's sign_in_with_code against a model of what Keycloak does to a TOTP sign-in, on a virtual clock
# (no Keycloak, no docker). The model refuses a code it already took, refuses any code while the user is locked out
# (two failures within a second lock a user for 60 seconds, Keycloak's brute-force defaults, which realm lab turns on),
# and forgets the failures when the check clears them. The cases are the identity job's failure of 2026-11-18 14:01 UTC:
#   1. A fresh run signs in on the first try.
#   2. Two runs in the same time step: the second waits for the next step, and no used code is sent.
#   3. A user locked out by the check's own refusal signs in, because the failures are cleared first.
#   4. A run that starts in the last seconds of a step waits for the next one.
#   5. A Keycloak that refuses every code ends in False after three tries, one per time step.
# Usage: .github/hosts-check/tests/test_check_realm_otp.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
OTP_STEP_FILE=$t/step name=model python3 -I - "$root/.github/hosts-check/identity" <<'PY'
import importlib.util, os, sys, types
spec = importlib.util.spec_from_file_location("cr", sys.argv[1] + "/check_realm.py")
cr = importlib.util.module_from_spec(spec); spec.loader.exec_module(cr)
SEED = "JBSWY3DPEHPK3PXP"
fails = []
def ok(c, m):
    print(("ok   " if c else "FAIL ") + m)
    if not c: fails.append(m)
class World:
    def __init__(self, start, always_refuse=False):
        self.now = start; self.used = set(); self.fail_at = []; self.locked_until = 0
        self.sent = []; self.cleared = 0; self.always_refuse = always_refuse
        cr.time = types.SimpleNamespace(time=lambda: self.now, sleep=lambda s: setattr(self, "now", self.now + s))
        cr.kcadm = self.kcadm; cr.sign_in = self.sign_in
        cr.get = lambda path, *q: [{"id": "u-1"}]
        try: os.remove(os.environ["OTP_STEP_FILE"])
        except OSError: pass
    def kcadm(self, *a, **k):
        if a[0] == "delete" and "attack-detection" in a[1]:
            self.fail_at = []; self.locked_until = 0; self.cleared += 1
        return 0, "", ""
    def fail(self):
        self.fail_at.append(self.now)
        if len(self.fail_at) >= 2 and self.fail_at[-1] - self.fail_at[-2] <= 1: self.locked_until = self.now + 60
        return False
    def sign_in(self, name, password, code=None):
        if self.now < self.locked_until: return False
        if code is None: return self.fail()
        step = int(self.now) // 30
        self.sent.append(step)
        if self.always_refuse or step in self.used or code != cr.totp(SEED): return self.fail()
        self.used.add(step); return True
w = World(1000.0 * 30 + 5)
ok(cr.sign_in_with_code("owner", "pw", SEED) and len(w.sent) == 1, "1. a fresh run signs in on the first try")
r2 = cr.sign_in_with_code("owner", "pw", SEED)
ok(r2 and w.sent[0] != w.sent[1] and len(set(w.sent)) == len(w.sent), "2. a second run in the same step waits and sends no used code")
w = World(2000.0 * 30 + 5); w.sign_in("owner", "pw"); w.sign_in("owner", "pw", "000000")
ok(w.locked_until > w.now, "3a. the model locks the user after two quick failures")
ok(cr.sign_in_with_code("owner", "pw", SEED) and w.cleared >= 1, "3b. the check clears the failures and signs in")
w = World(3000.0 * 30 + 29)
cr.sign_in_with_code("owner", "pw", SEED)
ok(w.sent == [3001], "4. a run at the end of a step waits for the next one: sent steps %s" % w.sent)
w = World(4000.0 * 30 + 5, always_refuse=True)
ok(not cr.sign_in_with_code("owner", "pw", SEED) and w.sent == [4000, 4001, 4002], "5. a Keycloak that refuses every code ends in False after three steps: %s" % w.sent)
sys.exit(1 if fails else 0)
PY
echo "check_realm otp: all checks passed"
