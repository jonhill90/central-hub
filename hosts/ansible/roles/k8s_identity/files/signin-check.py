#!/usr/bin/env python3
"""Sign-in proof for realm lab: the browser flow of one client, driven over HTTPS, no token endpoint.

Run on a control-plane node by tasks/signin.yml, which sends one JSON object on stdin:
base (https://<keycloak host>), realm, client, redirect (one of the client's redirect URIs), user,
password, seed (base32 TOTP seed), digits and period (the realm's OTP policy), address (the Gateway's IP, so the proof reaches THIS cluster's
Gateway whatever the lab DNS says), verify (false only for the staging certificate).

Steps, each printed as "<number> <name>: HTTP <code> <ok or FAIL: reason>" and nothing else:
  1 login page      GET the authorization URL; the login form must come back (200).
  2 password only   POST user name and password; Keycloak must answer with the one-time-code form,
                    never with a redirect (a redirect would mean the password alone signs in).
  3 password + code POST a code computed from the seed; Keycloak must redirect to the client's
                    redirect URI with a code.
No password, seed or code, and no page text, is ever printed.
"""
import base64
import hashlib
import hmac
import html
import http.cookiejar
import json
import re
import secrets
import socket
import ssl
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


def main():
    cfg = json.load(sys.stdin)
    host = urllib.parse.urlsplit(cfg["base"]).hostname
    real = socket.getaddrinfo
    socket.getaddrinfo = lambda h, *a, **k: real(cfg["address"] if h == host else h, *a, **k)
    ctx = ssl.create_default_context()
    if not cfg.get("verify", True):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),
                                         urllib.request.HTTPCookieProcessor(jar), NoRedirect)

    def call(url, data=None):
        req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode() if data else None)
        try:
            r = opener.open(req, timeout=20)
            return r.status, r.headers, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")

    def action(body):
        m = re.search(r'<form[^>]*\baction="([^"]+)"', body)
        return urllib.parse.urljoin(cfg["base"] + "/", html.unescape(m.group(1))) if m else None

    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    auth = cfg["base"] + "/realms/" + cfg["realm"] + "/protocol/openid-connect/auth?" + urllib.parse.urlencode({
        "client_id": cfg["client"], "response_type": "code", "scope": "openid", "redirect_uri": cfg["redirect"],
        "state": secrets.token_hex(8), "code_challenge": challenge, "code_challenge_method": "S256"})

    def line(n, name, code, ok, why=""):
        print("%d %s: HTTP %s %s" % (n, name, code, "ok" if ok else "FAIL: " + why))
        return ok

    try:
        code, _, body = call(auth)
    except Exception as e:  # network or TLS: the class name only
        line(1, "login page", "none", False, type(e).__name__)
        return 1
    form = action(body)
    if not line(1, "login page", code, code == 200 and form is not None and 'name="password"' in body,
                "no login form"):
        return 1
    code, _, body = call(form, {"username": cfg["user"], "password": cfg["password"], "credentialId": ""})
    form = action(body)
    if not line(2, "password only", code, code == 200 and form is not None and 'name="otp"' in body,
                "redirect, the password alone signed in" if code in (301, 302, 303) else "no one-time-code form"):
        return 1
    for offset in (0, 1):  # the second try is the next 30-second window, if the first sat on a boundary
        code, headers, body = call(form, {"otp": totp(cfg["seed"], offset, int(cfg.get("digits", 6)), int(cfg.get("period", 30))), "credentialId": ""})
        loc = headers.get("Location", "") if headers else ""
        ok = code == 302 and loc.startswith(cfg["redirect"]) and "code=" in loc
        if ok:
            return 0 if line(3, "password + code", code, True) else 1
        form = action(body) or form
        if code != 200:
            break
    line(3, "password + code", code, False, "no redirect with a code")
    return 1


sys.exit(main())
