#!/usr/bin/env python3
"""Sign-in proof for the Proxmox web UI through Keycloak: a person signing in reaches an authenticated Proxmox session.

Run on the agent box: `proxmox-signin-check.py <file>`, where <file> is a JSON file the box holds (mode 0600 or 0400, owned by
the user running it) with: base (https://<keycloak host>), pve_base (https://<the web UI's name on 443>, no path and no port:
the redirect Keycloak's client allows), realm (Keycloak's), user, password, seed (base32 TOTP seed), digits and period (the
realm's OTP policy), expect_admin (true when the user is in the group that maps to Administrator), and optionally pve_realm
(Proxmox's realm for the sign-in, default sso), address (an IP to reach Keycloak at, whatever DNS says), pve_address (an IP
to reach the web UI at, default address) and verify (false only for a throwaway CA). It refuses to run, with exit 2 and a
line saying so, when the file is missing, is readable by anyone else, or lacks a field. The user is a test account an
access-rights step makes (never the owner's account); this script makes nothing.

It does by API what the login page does (pve-manager LoginWindow.js: auth-url, the redirect back, then openid/login), so no
browser and no QR code is needed. Each step is printed as "<number> <name>: HTTP <code> <ok or FAIL: reason>" and nothing else:
  1 auth url         POST /api2/json/access/openid/auth-url for the realm; Proxmox must answer a link to Keycloak's
                     authorization endpoint for client proxmox that redirects back to the web UI's name.
  2 login page       GET that link; the login form must come back (200).
  3 password only    POST user name and password; Keycloak must answer with the one-time-code form, never a redirect.
  4 password + code  POST a code computed from the seed; Keycloak must redirect back to the web UI with a code and a state.
  5 proxmox login    POST /api2/json/access/openid/login with that code and state; Proxmox must answer 200 with a ticket
                     for <user>@<pve_realm>.
  6 permissions      GET /api2/json/access/permissions with the ticket; Sys.Modify on / present exactly when admin is expected.
No password, seed, code, state or ticket, and no page text, is ever printed.
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


NEEDED = ("base", "pve_base", "realm", "user", "password", "seed")


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
    pve = cfg["pve_base"].rstrip("/")
    pve_realm = cfg.get("pve_realm") or "sso"
    pins = {}
    if cfg.get("address"):
        pins[urllib.parse.urlsplit(base).hostname] = cfg["address"]
    if cfg.get("pve_address") or cfg.get("address"):
        pins[urllib.parse.urlsplit(pve).hostname] = cfg.get("pve_address") or cfg["address"]
    if pins:
        real = socket.getaddrinfo
        socket.getaddrinfo = lambda h, *a, **k: real(pins.get(h, h), *a, **k)
    ctx = ssl.create_default_context()
    if not cfg.get("verify", True):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),
                                         urllib.request.HTTPCookieProcessor(jar), NoRedirect)

    def call(url, data=None, json_body=None, headers=None):
        if json_body is not None:
            body, hdrs = json.dumps(json_body).encode(), {"Content-Type": "application/json", "Accept": "application/json"}
        else:
            body, hdrs = (urllib.parse.urlencode(data).encode() if data else None), {}
        hdrs.update(headers or {})
        req = urllib.request.Request(url, data=body, headers=hdrs)
        try:
            r = opener.open(req, timeout=20)
            return r.status, r.headers, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")

    def action(body):
        m = re.search(r'<form[^>]*\baction="([^"]+)"', body)
        return urllib.parse.urljoin(base + "/", html.unescape(m.group(1))) if m else None

    def data_of(body):
        try:
            return json.loads(body).get("data")
        except (ValueError, AttributeError):
            return None

    def line(n, name, code, ok, why=""):
        print("%d %s: HTTP %s %s" % (n, name, code, "ok" if ok else "FAIL: " + why))
        return ok

    auth_prefix = base + "/realms/" + cfg["realm"] + "/protocol/openid-connect/auth?"

    try:
        code, _, body = call(pve + "/api2/json/access/openid/auth-url", json_body={"realm": pve_realm, "redirect-url": pve})
    except Exception as e:  # network or TLS: the class name only
        line(1, "auth url", "none", False, type(e).__name__)
        return 1
    link = data_of(body)
    link = link if isinstance(link, str) else ""
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(link).query)
    if not line(1, "auth url", code, code == 200 and link.startswith(auth_prefix) and query.get("client_id") == ["proxmox"]
                and query.get("redirect_uri") == [pve],
                "no link to keycloak's authorization endpoint for client proxmox that redirects to the web UI"):
        return 1

    code, _, body = call(link)
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
        if code == 302 and loc.startswith(pve) and got.get("code") and got.get("state"):
            break
        form = action(body) or form
        if code != 200:
            break
    if not line(4, "password + code", code, code == 302 and loc.startswith(pve) and bool(got.get("code")) and bool(got.get("state")),
                "no redirect back to the web UI with a code and a state"):
        return 1

    code, _, body = call(pve + "/api2/json/access/openid/login", json_body={
        "state": got["state"][0], "code": got["code"][0], "redirect-url": pve})
    d = data_of(body)
    d = d if isinstance(d, dict) else {}
    ticket = d.get("ticket") or ""
    want_name = cfg["user"] + "@" + pve_realm
    if not line(5, "proxmox login", code, code == 200 and bool(ticket) and d.get("username") == want_name,
                "the session is for another user" if ticket and d.get("username") != want_name else "no ticket"):
        return 1

    code, _, body = call(pve + "/api2/json/access/permissions", headers={"Cookie": "PVEAuthCookie=" + urllib.parse.quote(ticket, safe="")})
    perms = data_of(body)
    root = perms.get("/") if isinstance(perms, dict) else None
    root = root if isinstance(root, dict) else {}
    is_admin = bool(root.get("Sys.Modify"))
    want_admin = bool(cfg.get("expect_admin", False))
    return 0 if line(6, "permissions", code, code == 200 and is_admin == want_admin,
                     "Sys.Modify on / is %s, expected %s" % (str(is_admin).lower(), str(want_admin).lower())
                     if code == 200 else "not 200") else 1


sys.exit(main())
