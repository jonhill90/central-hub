#!/usr/bin/env python3
"""Proof of the secrets store's OIDC login, with the test user: the browser flow driven over HTTPS.

Run by secrets-store-owner.sh check-test with: store API address (https://<store>/v1), CA file, identity.env,
issuer, redirect URI, user name. The password and one-time-code seed come from identity.env (PASSWORD_<USER> and
TOTP_<USER>) and are never printed.

Steps, each printed as "<n> <name>: <ok or FAIL: reason>" and nothing else (no token, code, page text):
  1 auth url        the store gives Keycloak's sign-in URL for role login-test
  2 password        Keycloak takes the password and asks for the one-time code
  3 code            Keycloak redirects back with a code
  4 token           the store trades the code for a token (a token is not printed)
  5 own path        the token writes and reads kv/login-test/probe
  6 other paths     the token is refused on kv/owner/probe and kv/c1/check and cannot list policies
"""
import base64
import hashlib
import hmac
import html
import http.cookiejar
import json
import os
import re
import ssl
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def totp(seed, offset=0):
    s = seed.replace(" ", "").upper()
    key = base64.b32decode(s + "=" * (-len(s) % 8))
    mac = hmac.new(key, struct.pack(">Q", int(time.time() // 30) + offset), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** 6).zfill(6)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def main(addr, cafile, envfile, issuer, redirect, user):
    vals = {}
    for l in open(envfile, encoding="utf-8"):
        k, _, v = l.rstrip("\n").partition("=")
        vals[k] = v.strip().strip("\"'")
    suffix = re.sub(r"[^A-Z0-9]", "_", user.upper())
    password, seed = vals.get("PASSWORD_" + suffix), vals.get("TOTP_" + suffix)
    if not password or not seed:
        print("1 auth url: FAIL: identity.env has no password or seed for the test user")
        return 1
    # The store is reached at the admin address the wrapper resolves its name to (SECRETS_STORE_RESOLVE=<name>:443:<ip>).
    res = os.environ.get("SECRETS_STORE_RESOLVE", "").split(":")
    if len(res) == 3:
        import socket
        real = socket.getaddrinfo
        socket.getaddrinfo = lambda h, *a, **k: real(res[2] if h == res[0] else h, *a, **k)
    ctx = ssl.create_default_context(cafile=cafile)
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),
                                         urllib.request.HTTPCookieProcessor(jar), NoRedirect)

    def call(url, data=None, body=None, token=None, method=None):
        if body is not None:
            data = json.dumps(body).encode()
        elif data is not None:
            data = urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(url, data=data, method=method)
        if body is not None:
            req.add_header("Content-Type", "application/json")
        if token:
            req.add_header("X-Vault-Token", token)
        try:
            r = opener.open(req, timeout=20)
            return r.status, r.headers, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")

    def line(n, name, ok, why=""):
        print("%d %s: %s" % (n, name, "ok" if ok else "FAIL: " + why))
        return ok

    def form(body):
        m = re.search(r'<form[^>]*\baction="([^"]+)"', body)
        return html.unescape(m.group(1)) if m else None

    try:
        code, _, body = call(addr + "/auth/oidc/oidc/auth_url", body={"role": "login-test", "redirect_uri": redirect})
        auth_url = json.loads(body)["data"]["auth_url"] if code == 200 else None
        if not line(1, "auth url", bool(auth_url), "HTTP %s" % code):
            return 1
        nonce = urllib.parse.parse_qs(urllib.parse.urlsplit(auth_url).query).get("nonce", [""])[0]
        code, _, body = call(auth_url)
        action = form(body)
        if code != 200 or not action:
            line(2, "password", False, "no login form (HTTP %s)" % code)
            return 1
        code, _, body = call(action, {"username": user, "password": password, "credentialId": ""})
        action = form(body)
        if not line(2, "password", code == 200 and action is not None and 'name="otp"' in body,
                    "the password alone signed in" if code in (301, 302, 303) else "no one-time-code form"):
            return 1
        loc = ""
        for offset in (0, 1):
            code, headers, body = call(action, {"otp": totp(seed, offset), "credentialId": ""})
            loc = headers.get("Location", "") if headers else ""
            if code == 302 and loc.startswith(redirect) and "code=" in loc:
                break
            action = form(body) or action
        if not line(3, "code", code == 302 and loc.startswith(redirect) and "code=" in loc, "no redirect with a code"):
            return 1
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(loc).query)
        cb = addr + "/auth/oidc/oidc/callback?" + urllib.parse.urlencode(
            {"state": q["state"][0], "code": q["code"][0], "nonce": nonce})
        code, _, body = call(cb)
        token = json.loads(body).get("auth", {}).get("client_token") if code == 200 else None
        if not line(4, "token", bool(token), "HTTP %s" % code):
            return 1
        c1, _, _ = call(addr + "/kv/data/login-test/probe", body={"data": {"k": "v"}}, token=token)
        c2, _, b2 = call(addr + "/kv/data/login-test/probe", token=token)
        own = c1 in (200, 204) and c2 == 200 and json.loads(b2)["data"]["data"].get("k") == "v"
        if not line(5, "own path", own, "write HTTP %s, read HTTP %s" % (c1, c2)):
            return 1
        denied = []
        for method, path, body_ in (("POST", "/kv/data/owner/probe", {"data": {"k": "v"}}), ("GET", "/kv/data/c1/check", None),
                                    ("GET", "/sys/policies/acl?list=true", None)):
            c, _, _ = call(addr + path, body=body_, token=token, method=method)
            denied.append(c)
        return 0 if line(6, "other paths", all(c == 403 for c in denied), "HTTP %s, wanted 403 each" % denied) else 1
    except Exception as e:  # network, TLS or parse: the class name only
        print("0 run: FAIL: %s" % type(e).__name__)
        return 1


sys.exit(main(*sys.argv[1:7]))
