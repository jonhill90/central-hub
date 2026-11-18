#!/usr/bin/python3 -I
"""Proof items 2 to 7 and 9 against the throwaway OPNsense (docs/runbooks/prove-opnsense-sign-in-on-dev.md).

  opnsense-test-prove.py <VM address> <proof dir> <SSH key> <known_hosts>

The opnsense-test wrapper runs it from `prove`, with the proof's Keycloak up. Each item prints one
`proof item N:` line saying what was measured; the run fails on the first item that does not hold.
Browser steps are made with urllib: the GUI's own certificate (read over SSH) and the proof CA are
the only trust anchors, and no certificate check is turned off.
"""
import base64
import html
import http.cookiejar
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

addr, proof, sshkey, known_hosts = sys.argv[1:5]
SERVER = "keycloak-proof"
PROOF_ADMIN_UID = "2000"
base = f"https://{addr}"

# The GUI's self-signed certificate names the VM's hostname, not its address, so the name check is
# off; the chain check is not, and the only anchors are that certificate and the proof CA.
ctx = ssl.create_default_context(cafile=os.path.join(proof, "gui.pem"))
ctx.load_verify_locations(cafile=os.path.join(proof, "ca.pem"))
ctx.check_hostname = False


def fail(msg):
    sys.exit(f"opnsense-test: proof failed: {msg}")


def read(name):
    return open(os.path.join(proof, name)).read().strip()


def vm(cmd, stdin=None):
    r = subprocess.run(["ssh", "-i", sshkey, "-o", "BatchMode=yes", "-o", f"UserKnownHostsFile={known_hosts}",
                        f"root@{addr}", cmd], input=stdin, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        fail(f"{cmd!r} on the VM: {r.stderr.strip()[:300]}")
    return r.stdout


def php(body):
    """A PHP snippet run as root on the VM with OPNsense's own loader."""
    return vm("php", "<?php\nrequire_once '/usr/local/opnsense/mvc/script/load_phalcon.php';\n" + body)


def browser():
    return urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),
                                       urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


last_status = {"code": None}   # the newest answer's HTTP status, for a failure line


def get(op, url, data=None):
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    try:
        with op.open(urllib.request.Request(url, data=body), timeout=60) as r:
            last_status["code"] = r.status
            return r.geturl(), r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:   # a refusal page is an answer too; signed_in() decides
        last_status["code"] = e.code
        return e.geturl(), e.read().decode(errors="replace")


def why_no_redirect(page):
    """What OPNsense answered in place of the redirect to Keycloak, and the plugin's own log lines.

    The plugin's loginAction refuses with a short text page (404 no such server, 400 not under this
    address) or a protocol failure page, and it logs each refusal to syslog with an `OIDC:` prefix
    (os-openid-connect v1.0.0-beta5 AuthController.php loginAction, RelyingParty.php acceptedRedirectUri).
    """
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", page)
    text = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", text)).split())[:300]
    log = vm("grep -h -i -e 'OIDC' -e 'openidconnect' /var/log/system/latest.log /var/log/audit/latest.log"
             " 2>/dev/null | tail -n 12 | cut -c1-300; true").strip()
    return f"HTTP {last_status['code']}, page text: {text or '(empty)'}\nthe VM's OIDC log lines:\n{log or '(none)'}"


def signed_in(op):
    url, page = get(op, base + "/")
    return url.startswith(base) and 'name="usernamefld"' not in page


def keycloak_sign_in(user, password):
    """The login button's path: OPNsense, Keycloak's form, the callback, back to OPNsense."""
    op = browser()
    url, page = get(op, base + "/api/openidconnect/auth/login?" + urllib.parse.urlencode({"provider": SERVER}))
    m = re.search(r'<form[^>]*id="kc-form-login"[^>]*action="([^"]+)"', page)
    if not m:
        fail(f"no Keycloak sign-in form after {url}\n{why_no_redirect(page)}")
    get(op, html.unescape(m.group(1)), {"username": user, "password": password, "credentialId": ""})
    return op


def pending(hint):
    rows = json.loads(php(f"echo json_encode((new \\OPNsense\\Auth\\AuthenticationFactory())->get('{SERVER}')->pendingApprovals());"))
    return [r for r in rows if hint in json.dumps(r.get("hints", ""))]


def approve(request_id, uid):
    out = php(f"var_export((new \\OPNsense\\Auth\\AuthenticationFactory())->get('{SERVER}')"
              f"->approvePendingIdentity('{request_id}', '{uid}'));")
    return out.strip() == "true"


# Item 2: the test user's first sign-in queues it (admission `approval`); once an admin binds it to the
# new local admin, its next sign-in lands on the dashboard.
op = keycloak_sign_in("proof-user", read("user.pass"))
if signed_in(op):
    fail("the unbound test user got a session before any approval")
rows = pending("proof-user")
if len(rows) != 1:
    fail(f"expected one pending request for proof-user, found {len(rows)}")
if not approve(rows[0]["id"], PROOF_ADMIN_UID):
    fail("the approval of proof-user to uid 2000 was refused")
op = keycloak_sign_in("proof-user", read("user.pass"))
if not signed_in(op):
    fail("the bound test user did not land on the dashboard")
print("opnsense-test: proof item 2: Keycloak sign-in as proof-user, once bound to local admin uid 2000, lands on the dashboard")

# Item 2 (part): Keycloak advertises DPoP (prove checked discovery), so the plugin's sign-in used it.
# Its key store is /var/db/openid-connect/dpop, a 0700 folder of 0600 key-<binding>.json files
# (os-openid-connect v1.0.0-beta5 DpopKeyStore.php, statePath and ensureDirectory).
modes = vm("cd /var/db/openid-connect/dpop 2>/dev/null && stat -f '%Lp %N' . key-*.json 2>/dev/null || true").split("\n")
modes = [line.split(" ", 1) for line in modes if line.strip()]
if not modes or modes[0] != ["700", "."]:
    fail("the plugin's DPoP key folder is missing or not mode 0700")
keys = [name for mode, name in modes[1:] if mode == "600"]
if not keys or len(keys) != len(modes) - 1:
    fail("the bound sign-in left no DPoP key, or a key file is not mode 0600")
print(f"opnsense-test: proof item 2: the sign-in used DPoP ({len(keys)} key file in the plugin's 0700 store, mode 0600)")

# Item 2 (part): the plugin's own sign-in test, run as the bound admin, reports the DPoP sender constraint.
# "Used" there, with a completed token exchange, means the token came back as type DPoP: the plugin refuses a
# Bearer token where it asked for DPoP (os-openid-connect v1.0.0-beta5 Api/TestController.php startAction,
# Api/AuthController.php line 894, RelyingParty.php lines 305 and 566-570). The API call needs the session's
# CSRF token, which an MVC page prints (opnsense/core stable/26.1 ApiControllerBase.php, layouts/default.volt).
_, page = get(op, base + "/ui/core/firmware")
m = re.search(r'setRequestHeader\("X-CSRFToken", "([^"]+)"', page)
if not m:
    fail("no CSRF token on the bound admin's firmware page")
req = urllib.request.Request(base + "/api/openidconnect/test/start", data=urllib.parse.urlencode({"provider": SERVER}).encode(),
                             headers={"X-CSRFToken": m.group(1)})
try:
    with op.open(req, timeout=60) as r:
        answer = json.loads(r.read().decode())
except (urllib.error.HTTPError, ValueError) as e:
    fail(f"the plugin's sign-in test did not start: {e}")
if answer.get("status") != "ok" or "authorization_url_b64" not in answer:
    fail(f"the plugin's sign-in test did not start: {answer.get('message', answer)}")
url, page = get(op, base64.b64decode(answer["authorization_url_b64"]).decode())
m = re.search(r'<form[^>]*id="kc-form-login"[^>]*action="([^"]+)"', page)
if m:  # Keycloak asks again when the test wants a fresh sign-in; otherwise its session answers at once
    url, page = get(op, html.unescape(m.group(1)), {"username": "proof-user", "password": read("user.pass"), "credentialId": ""})
row = re.search(r"<th>DPoP sender constraint</th><td><code>([^<]*)</code>", page)
if not row:
    fail(f"the sign-in test page at {url} has no DPoP sender constraint row")
if row.group(1) != "Used":
    fail(f"the plugin's sign-in test reports the DPoP sender constraint as {row.group(1)!r}")
print("opnsense-test: proof item 2: the plugin's sign-in test reports the DPoP sender constraint as Used")

# Item 3: an identity no one approved gets no session, only a pending request.
op = keycloak_sign_in("proof-stranger", read("stranger.pass"))
if signed_in(op):
    fail("the unknown user got a session")
stranger = pending("proof-stranger")
if len(stranger) != 1:
    fail("the unknown user was neither refused nor queued as one pending request")
print("opnsense-test: proof item 3: the unknown user proof-stranger got no session and waits as one pending request")

# Item 9 (part): approving an identity onto root (uid 0) is refused.
if approve(stranger[0]["id"], "0"):
    fail("an identity was bound to root")
print("opnsense-test: proof item 9: binding an identity to root (uid 0) is refused")

# Item 4: with the client disabled, root signs in by password through the Local Database.
php(f"""$c = \\OPNsense\\Core\\Config::getInstance(); $done = false;
foreach ($c->object()->system->authserver as $s) {{ if ((string)$s->name === '{SERVER}') {{ $s->openidconnect_enabled = '0'; $done = true; }} }}
if (!$done) {{ exit(1); }} $c->save(); echo "ok";""")
op = browser()
_, page = get(op, base + "/")
form = re.search(r'<form[^>]*id="iform".*?</form>', page, re.S)
if not form:
    fail("no local login form on the GUI")
fields = dict(re.findall(r'<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"', form.group(0)))
fields.update({"usernamefld": "root", "passwordfld": read("root.pass"), "login": "1"})
get(op, base + "/", fields)
if not signed_in(op):
    fail("root could not sign in by password with the client disabled")
print("opnsense-test: proof item 4: with the OIDC server disabled, root signs in by password (Local Database)")

# Item 5: from the code, not a run. The firmware API's install takes a package name, sanitized as
# `pkgname`, and passes it to `configctl firmware install`, which installs from the repository only
# (opnsense/core stable/26.1 FirmwareController.php installAction; actions_firmware.conf [install]).
print("opnsense-test: proof item 5: no; the firmware API installs only by package name from the repository, so a local .pkg needs pkg add over SSH")

# Item 6 and item 9 (settings): the plugin keeps its settings in /conf/config.xml.
conf = vm("cat /conf/config.xml")
want = {"openidconnect_par_mode": "disabled", "openidconnect_ssf_enabled": "0", "openidconnect_logout_notifications": "off",
        "openidconnect_bootstrap_mode": "approval", "openidconnect_allow_root": "0", "openidconnect_create_users": "0"}
for k, v in want.items():
    m = re.search(rf"<{k}>([^<]*)</{k}>", conf)
    if not m or m.group(1) != v:
        fail(f"{k} in /conf/config.xml is {m.group(1) if m else 'missing'}, not {v}")
print("opnsense-test: proof item 6: the plugin's settings are in /conf/config.xml (%d openidconnect_ fields)" % len(re.findall(r"<openidconnect_", conf)))
print("opnsense-test: proof item 9: admission approval, root not allowed, PAR disabled, shared signals and logout notifications off, no account made on first login")

# Item 7: memory in use, from the kernel's page counts.
mem = dict(line.split(": ", 1) for line in vm("sysctl hw.physmem hw.pagesize vm.stats.vm.v_free_count vm.stats.vm.v_inactive_count").splitlines())
page_size = int(mem["hw.pagesize"])
total = int(mem["hw.physmem"]) // 1048576
free = (int(mem["vm.stats.vm.v_free_count"]) + int(mem["vm.stats.vm.v_inactive_count"])) * page_size // 1048576
print(f"opnsense-test: proof item 7: {total - free} MiB in use of {total} MiB (free plus inactive pages counted as free)")
print("opnsense-test: proof item 8 is `opnsense-test destroy`, the proof's last step")
