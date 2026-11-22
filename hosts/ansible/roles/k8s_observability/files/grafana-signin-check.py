#!/usr/bin/env python3
"""Sign-in proof for Grafana through Keycloak: a person signing in reaches an authenticated Grafana session.

Run on the agent box against prod: `grafana-signin-check.py <file>`, where <file> is a JSON file the box holds (mode 0600 or
0400, owned by the user running it) with: base (https://<keycloak host>), grafana_base (https://<the Grafana name>, no path:
the host Keycloak's client `grafana` allows), realm, user, password, seed (base32 TOTP seed), digits and period (the realm's
OTP policy), expect_admin (true when the user is in the group that maps to the realm role admin), and optionally address (a
Gateway IP, to reach both hosts whatever DNS says) and verify (false only for a throwaway CA). It refuses to run, with exit 2
and a line saying so, when the file is missing, is readable by anyone else, or lacks a field. The user is a test account an
access-rights step makes (never the owner's account); this script makes nothing.

It does by API what the browser does (Grafana's /login/generic_oauth, Keycloak's form, the callback, then the session cookie),
so no browser is needed. Each step is printed as "<number> <name>: HTTP <code> <ok or FAIL: reason>" and nothing else:
  1 login start      GET /login/generic_oauth on Grafana; it must redirect to Keycloak's authorization endpoint for client grafana.
  2 login page       GET that URL; the login form must come back (200).
  3 password only    POST user name and password; Keycloak must answer with the one-time-code form, never a redirect.
  4 password + code  POST a code computed from the seed; Keycloak must redirect back to Grafana's /login/generic_oauth with a
                     code and a state.
  5 grafana callback GET that redirect with the cookies from step 1; Grafana exchanges the code and must redirect on, setting
                     its session cookie grafana_session.
  6 who am i         GET /api/user; it must answer 200 with a login.
  7 role             GET /api/user/orgs; the first organisation's role is Admin when admin is expected, else Viewer (Grafana's
                     role_attribute_path maps the realm role admin to Admin and anything else to Viewer).
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


def wait_next_window(cfg):
    """Sleep until the next one-time-code window starts (retry_wait, in seconds, replaces that; a test sets it).
    Keycloak refuses a code it has already accepted, so a check that finds its code used, because another check of this run
    signed in with the same seed in the same window, tries again with the next window's own code."""
    period = int(cfg.get("period", 30))
    time.sleep(float(cfg["retry_wait"]) if "retry_wait" in cfg else period - time.time() % period + 1)


def totp(seed, offset=0, digits=6, period=30):
    key = base64.b32decode(seed.replace(" ", "").upper() + "=" * (-len(seed.replace(" ", "")) % 8))
    counter = int(time.time() // period) + offset
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** digits).zfill(digits)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None




NEEDED = ("base", "grafana_base", "realm", "user", "password", "seed")


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
    graf = cfg["grafana_base"].rstrip("/")
    if cfg.get("address"):
        hosts = {urllib.parse.urlsplit(base).hostname, urllib.parse.urlsplit(graf).hostname}
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
    callback_prefix = graf + "/login/generic_oauth"

    try:
        code, headers, _ = call(graf + "/login/generic_oauth")
    except Exception as e:  # network or TLS: the class name only
        line(1, "login start", "none", False, type(e).__name__)
        return 1
    loc = headers.get("Location", "") if headers else ""
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(loc).query)
    if not line(1, "login start", code, code in (301, 302, 303, 307) and loc.startswith(auth_prefix) and query.get("client_id") == ["grafana"],
                "no redirect to keycloak's authorization endpoint for client grafana"):
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
    for attempt in range(3):  # a rejected code is tried again in the next window, with that window's own code
        offset = 0
        if attempt:
            wait_next_window(cfg)
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
                "no redirect back to grafana with a code and a state"):
        return 1

    code, _, _ = call(loc)
    has_session = any(c.name == "grafana_session" for c in jar)
    if not line(5, "grafana callback", code, code in (301, 302, 303, 307) and has_session,
                "no session cookie (grafana could not exchange the code or refused the user)"):
        return 1

    code, _, body = call(graf + "/api/user", headers={"Accept": "application/json"})
    try:
        info = json.loads(body)
    except ValueError:
        info = {}
    if not line(6, "who am i", code, code == 200 and isinstance(info, dict) and bool(info.get("login")),
                "not logged in" if code != 200 else "no login in the answer"):
        return 1

    code, _, body = call(graf + "/api/user/orgs", headers={"Accept": "application/json"})
    try:
        orgs = json.loads(body)
    except ValueError:
        orgs = []
    role = orgs[0].get("role") if isinstance(orgs, list) and orgs and isinstance(orgs[0], dict) else None
    want = "Admin" if cfg.get("expect_admin", False) else "Viewer"
    return 0 if line(7, "role", code, code == 200 and role == want,
                     "the first organisation's role is %s, expected %s" % (role, want) if code == 200 else "not 200") else 1


sys.exit(main())
