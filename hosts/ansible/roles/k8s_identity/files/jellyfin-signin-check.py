#!/usr/bin/env python3
"""Sign-in proof for Jellyfin through Keycloak: a person signing in reaches an authenticated Jellyfin session.

Run on the agent box against prod: `jellyfin-signin-check.py <file>`, where <file> is a JSON file the box holds (mode 0600 or
0400, owned by the user running it) with: base (https://<keycloak host>), jellyfin_base (https://<Jellyfin's app name>), realm,
provider (the SSO plugin's provider name), user, password, seed (base32 TOTP seed), digits and period (the realm's OTP
policy), expect_admin (true when the user's realm roles map to Jellyfin admin), and optionally address (a Gateway IP, to reach
that Gateway whatever DNS says) and verify (false only for a throwaway CA). It refuses to run, with exit 2 and a line saying so,
when the file is missing, is readable by anyone else, or lacks a field. The user is a test account an access-rights step makes
(never the owner's account); this script makes nothing.

The steps follow the plugin's own page script (jellyfin-plugin-sso 5.1.1, SSOController.cs and WebResponse.cs),
so no browser is needed. Each is printed as "<number> <name>: HTTP <code> <ok or FAIL: reason>" and nothing else:
  1 sso start        GET /sso/OID/start/<provider> on Jellyfin's own host; Jellyfin must redirect to Keycloak's
                     authorization endpoint for client jellyfin.
  2 login page       GET that URL; the login form must come back (200), after at most one redirect to Keycloak's
                     login-actions page, which is where a pushed authorization request leads.
  3 password only    POST user name and password; Keycloak must answer with the one-time-code form, never a redirect.
  4 password + code  POST a code computed from the seed; Keycloak must redirect back to Jellyfin's
                     /sso/OID/redirect/<provider> with a code.
  5 jellyfin callback  GET that redirect; Jellyfin exchanges the code at Keycloak and answers the page whose script
                     holds the flow's state.
  6 session          POST /sso/OID/Auth/<provider> with that state, as the page's script does; Jellyfin must answer
                     200 with an access token.
  7 who am i         GET /Users/Me with the token; 200, the user's name, and IsAdministrator as expected.
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
import secrets
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


NEEDED = ("base", "jellyfin_base", "realm", "user", "password", "seed")


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
    jf = cfg["jellyfin_base"].rstrip("/")
    provider = cfg.get("provider", "keycloak")
    hosts = {urllib.parse.urlsplit(base).hostname, urllib.parse.urlsplit(jf).hostname}
    if cfg.get("address"):
        real = socket.getaddrinfo
        socket.getaddrinfo = lambda h, *a, **k: real(cfg["address"] if h in hosts else h, *a, **k)
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

    def line(n, name, code, ok, why=""):
        print("%d %s: HTTP %s %s" % (n, name, code, "ok" if ok else "FAIL: " + why))
        return ok

    auth_prefix = base + "/realms/" + cfg["realm"] + "/protocol/openid-connect/auth"
    callback_prefix = jf + "/sso/OID/redirect/" + provider

    try:
        code, headers, _ = call(jf + "/sso/OID/start/" + provider)
    except Exception as e:  # network or TLS: the class name only
        line(1, "sso start", "none", False, type(e).__name__)
        return 1
    loc = headers.get("Location", "") if headers else ""
    if not line(1, "sso start", code, code in (301, 302, 303) and loc.startswith(auth_prefix) and "client_id=jellyfin" in loc,
                "no redirect to keycloak's authorization endpoint for client jellyfin"):
        return 1

    code, headers, body = call(loc)
    # The plugin starts the flow with a pushed authorization request (the link holds only client_id and request_uri), and Keycloak
    # answers that link with one redirect to its login-actions page, where the form is. Followed once, and only to that path on
    # Keycloak's own host. Measured on prod on 2026-11-19: step 2 ended "HTTP 302 FAIL: no login form" without this.
    redirect = headers.get("Location", "") if headers else ""
    if code in (301, 302, 303) and redirect.startswith(base + "/realms/" + cfg["realm"] + "/login-actions/"):
        loc = redirect
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
    for attempt in range(3):  # a rejected code is tried again in the next window, with that window's own code
        offset = 0
        if attempt:
            wait_next_window(cfg)
        code, headers, body = call(form, {"otp": totp(cfg["seed"], offset, int(cfg.get("digits", 6)), int(cfg.get("period", 30))),
                                          "credentialId": ""})
        loc = headers.get("Location", "") if headers else ""
        if code == 302 and loc.startswith(callback_prefix) and "code=" in loc:
            break
        form = action(body) or form
        if code != 200:
            break
    if not line(4, "password + code", code, code == 302 and loc.startswith(callback_prefix) and "code=" in loc,
                "no redirect back to jellyfin with a code"):
        return 1

    code, _, body = call(loc)
    m = re.search(r"var data = '([^']+)'", body)
    if not line(5, "jellyfin callback", code, code == 200 and m is not None,
                "no state in the page (jellyfin could not exchange the code or refused the user)"):
        return 1
    state = m.group(1)

    device = secrets.token_hex(8)
    code, _, body = call(jf + "/sso/OID/Auth/" + provider, json_body={
        "deviceId": device, "appName": "Jellyfin Web", "appVersion": "10.8.0", "deviceName": "signin-check", "data": state})
    try:
        token = json.loads(body).get("AccessToken") or ""
    except ValueError:
        token = ""
    if not line(6, "session", code, code == 200 and bool(token), "no access token"):
        return 1

    code, _, body = call(jf + "/Users/Me", headers={
        "Authorization": 'MediaBrowser Client="signin-check", Device="signin-check", DeviceId="%s", Version="1", Token="%s"' % (device, token),
        "X-Emby-Token": token})
    try:
        me = json.loads(body)
    except ValueError:
        me = {}
    is_admin = bool((me.get("Policy") or {}).get("IsAdministrator"))
    right_user = me.get("Name") == cfg["user"]
    want_admin = bool(cfg.get("expect_admin", False))
    why = "" if right_user and is_admin == want_admin else (
        "the session is for another user" if not right_user else
        "IsAdministrator is %s, expected %s" % (str(is_admin).lower(), str(want_admin).lower()))
    return 0 if line(7, "who am i", code, code == 200 and right_user and is_admin == want_admin, why or "not 200") else 1


sys.exit(main())
