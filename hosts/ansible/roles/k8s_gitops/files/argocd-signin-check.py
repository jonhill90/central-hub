#!/usr/bin/env python3
"""Sign-in proof for Argo CD through Keycloak: a person signing in reaches an authenticated Argo CD session.

Run on the agent box against prod: `argocd-signin-check.py <file>`, where <file> is a JSON file the box holds (mode 0600 or
0400, owned by the user running it) with: base (https://<keycloak host>), argocd_base (https://<the Argo CD name in
argocd-cm's url>, no path: the host Keycloak's client allows), realm, user, password, seed (base32 TOTP seed), digits and
period (the realm's OTP policy), expect_admin (true when the user is in the group that maps to role:admin), and optionally
admin_group (default lab-admins), viewer_group (default lab-viewers), address (a Gateway IP, to reach both hosts whatever
DNS says) and verify (false only for a throwaway CA). It refuses to run, with exit 2 and a line saying so, when the file is
missing, is readable by anyone else, or lacks a field. The user is a test account an access-rights step makes (never the
owner's account); this script makes nothing.

It does by API what the browser does (Argo CD's /auth/login, Keycloak's form, /auth/callback, then the session cookie), so
no browser is needed. Each step is printed as "<number> <name>: HTTP <code> <ok or FAIL: reason>" and nothing else:
  1 login start      GET /auth/login on Argo CD; it must redirect to Keycloak's authorization endpoint for client argocd.
  2 login page       GET that URL; the login form must come back (200).
  3 password only    POST user name and password; Keycloak must answer with the one-time-code form, never a redirect.
  4 password + code  POST a code computed from the seed; Keycloak must redirect back to Argo CD's /auth/callback with a code
                     and a state.
  5 argo cd callback GET that redirect with the cookies from step 1; Argo CD exchanges the code (with its PKCE verifier) and
                     must redirect on, setting its session cookie argocd.token.
  6 who am i         GET /api/v1/session/userinfo; loggedIn, the issuer is Keycloak's realm, and the groups claim holds the
                     expected group.
  7 rights           GET /api/v1/account/can-i/sync/applications/*; "yes" exactly when admin is expected.
No password, seed, code, state or token, and no page text, is ever printed.
"""
import base64
import hashlib
import hmac
import html
import http.cookiejar
import json
import os
import re
import socket
import ssl
import stat
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def totp(seed, offset=0, digits=6, period=30):
    key = base64.b32decode(seed.replace(" ", "").upper() + "=" * (-len(seed.replace(" ", "")) % 8))
    counter = int(time.time() // period) + offset
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** digits).zfill(digits)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


NEEDED = ("base", "pve_base", "realm", "user", "password", "seed")


NEEDED = ("base", "argocd_base", "realm", "user", "password", "seed")


def load():
    """The config file named by the one argument; None, after saying why, when the run must not go on."""
    if len(sys.argv) != 2:
        print("refused: give the one argument, the path of the credentials file")
        return None
    try:
        st = os.stat(sys.argv[1])
    except OSError:
        print("refused: the credentials file is missing")
        return None
    if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077 or st.st_uid != os.getuid():
        print("refused: the credentials file must be a regular file, mode 0600 or 0400, owned by the user running this")
        return None
    try:
        with open(sys.argv[1]) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        print("refused: the credentials file is not readable JSON")
        return None
    missing = [k for k in NEEDED if not isinstance(cfg.get(k), str) or not cfg[k]]
    if missing:
        print("refused: the credentials file lacks: " + ", ".join(missing))
        return None
    return cfg


def main():
    cfg = load()
    if cfg is None:
        return 2
    base = cfg["base"].rstrip("/")
    argo = cfg["argocd_base"].rstrip("/")
    if cfg.get("address"):
        hosts = {urllib.parse.urlsplit(base).hostname, urllib.parse.urlsplit(argo).hostname}
        real = socket.getaddrinfo
        socket.getaddrinfo = lambda h, *a, **k: real(cfg["address"] if h in hosts else h, *a, **k)
    ctx = ssl.create_default_context()
    if not cfg.get("verify", True):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),
                                         urllib.request.HTTPCookieProcessor(jar), NoRedirect)

    def call(url, data=None, headers=None):
        body = urllib.parse.urlencode(data).encode() if data else None
        req = urllib.request.Request(url, data=body, headers=headers or {})
        try:
            r = opener.open(req, timeout=20)
            return r.status, r.headers, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")

    def action(body):
        m = re.search(r'<form[^>]*\baction="([^"]+)"', body)
        return urllib.parse.urljoin(base + "/", html.unescape(m.group(1))) if m else None

    def line(n, name, code, ok, why=""):
        print("%d %s: HTTP %s %s" % (n, name, code, "ok" if ok else "FAIL: " + why))
        return ok

    auth_prefix = base + "/realms/" + cfg["realm"] + "/protocol/openid-connect/auth?"
    callback_prefix = argo + "/auth/callback"

    try:
        code, headers, _ = call(argo + "/auth/login?" + urllib.parse.urlencode({"return_url": argo + "/applications"}))
    except Exception as e:  # network or TLS: the class name only
        line(1, "login start", "none", False, type(e).__name__)
        return 1
    loc = headers.get("Location", "") if headers else ""
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(loc).query)
    if not line(1, "login start", code, code in (301, 302, 303, 307) and loc.startswith(auth_prefix) and query.get("client_id") == ["argocd"],
                "no redirect to keycloak's authorization endpoint for client argocd"):
        return 1

    code, _, body = call(loc)
    form = action(body)
    if not line(2, "login page", code, code == 200 and form is not None and 'name="password"' in body, "no login form"):
        return 1

    code, _, body = call(form, {"username": cfg["user"], "password": cfg["password"], "credentialId": ""})
    form = action(body)
    if not line(3, "password only", code, code == 200 and form is not None and 'name="otp"' in body,
                "redirect, the password alone signed in" if code in (301, 302, 303) else "no one-time-code form"):
        return 1

    loc = ""
    got = {}
    for offset in (0, 1):  # the second try is the next window, if the first sat on a boundary
        code, headers, body = call(form, {"otp": totp(cfg["seed"], offset, int(cfg.get("digits", 6)), int(cfg.get("period", 30))),
                                          "credentialId": ""})
        loc = headers.get("Location", "") if headers else ""
        got = urllib.parse.parse_qs(urllib.parse.urlsplit(loc).query)
        if code == 302 and loc.startswith(callback_prefix) and got.get("code") and got.get("state"):
            break
        form = action(body) or form
        if code != 200:
            break
    if not line(4, "password + code", code, code == 302 and loc.startswith(callback_prefix) and bool(got.get("code")) and bool(got.get("state")),
                "no redirect back to argo cd with a code and a state"):
        return 1

    code, _, _ = call(loc)
    has_session = any(c.name == "argocd.token" for c in jar)
    if not line(5, "argo cd callback", code, code in (301, 302, 303, 307) and has_session,
                "no session cookie (argo cd could not exchange the code or refused the user)"):
        return 1

    code, _, body = call(argo + "/api/v1/session/userinfo", headers={"Accept": "application/json"})
    try:
        info = json.loads(body)
    except ValueError:
        info = {}
    want_group = cfg.get("admin_group", "lab-admins") if cfg.get("expect_admin", False) else cfg.get("viewer_group", "lab-viewers")
    iss = info.get("iss") or ""
    ok = (code == 200 and info.get("loggedIn") is True and iss.startswith(base + "/realms/" + cfg["realm"])
          and want_group in (info.get("groups") or []))
    if not line(6, "who am i", code, ok, "not logged in" if info.get("loggedIn") is not True else
                "the issuer is not keycloak's realm" if not iss.startswith(base + "/realms/" + cfg["realm"]) else
                "the groups claim lacks the expected group"):
        return 1

    code, _, body = call(argo + "/api/v1/account/can-i/sync/applications/*", headers={"Accept": "application/json"})
    try:
        answer = json.loads(body)
    except ValueError:
        answer = body.strip().strip('"')
    if isinstance(answer, dict):
        answer = answer.get("value")
    can_sync = answer == "yes"
    want_sync = bool(cfg.get("expect_admin", False))
    return 0 if line(7, "rights", code, code == 200 and can_sync == want_sync,
                     "sync is %s, expected %s" % ("yes" if can_sync else "no", "yes" if want_sync else "no")
                     if code == 200 else "not 200") else 1


sys.exit(main())
