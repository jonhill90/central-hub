#!/usr/bin/env python3
"""Proof of the owner's sign-in to the secrets store through Keycloak (agent pick 233), dev only.

Run on the agent box by tasks/owner_signin.yml, which sends one JSON object on stdin:
api (https://<store address>:<port>/v1), cacert (the store's public certificate), mount, role, policy,
prefix (the folder under kv/ the policy allows), redirect (one of the role's allowed redirect URIs),
kc_base (https://<Keycloak's name>), address (the dev Gateway's address, where Keycloak answers), verify
(false for the dev CA), digits and period (the realm's OTP policy), admin {user, password, seed} and
viewer {user, password} and other {user, password, seed}
(a second lab-admins member who is not the owner).

It drives the same calls the store's web page makes: auth_url, Keycloak's login form, then the store's
callback with the code. Each step prints "<number> <name>: HTTP <code> <ok or FAIL: reason>" and nothing
else. No password, seed, code, token or page text is ever printed.

  1 admin auth_url        the store hands out a Keycloak URL for the role (admin = the owner)
  2 admin login page      Keycloak shows its login form
  3 admin password only   Keycloak asks for the one-time code; a redirect would mean the password alone signs in
  4 admin password + code Keycloak redirects to the store's callback with a code
  5 admin callback        the store gives a token with the role's policy
  6 admin writes          the token writes kv/<prefix>/proof, a fixed non-secret word
  7 admin reads           and reads it back
  8 admin refused c1      the token is refused kv/data/c1/check (403)
  9 admin refused policy  and sys/policies/acl/admin (403)
 10 viewer auth_url       the same for a member of another group
 11 viewer login page
 12 viewer password       Keycloak redirects to the store (viewers have no code)
 13 viewer refused        the store refuses the login
 14 other auth_url        the same for a second lab-admins member who is not the owner
 15 other login page
 16 other password only   Keycloak asks for the code
 17 other password + code Keycloak redirects to the store
 18 other refused         the store refuses the login: the role binds the owner's user name
"""
import base64
import hashlib
import hmac
import html
import http.cookiejar
import json
import re
import socket
import ssl
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROOF_VALUE = "owner-signin-proof"


def totp(seed, offset=0, digits=6, period=30):
    clean = seed.replace(" ", "").upper()
    key = base64.b32decode(clean + "=" * (-len(clean) % 8))
    counter = int(time.time() // period) + offset
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** digits).zfill(digits)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def line(n, name, code, ok, why=""):
    print("%d %s: HTTP %s %s" % (n, name, code, "ok" if ok else "FAIL: " + why))
    return ok


def main():
    cfg = json.load(sys.stdin)
    kc_host = urllib.parse.urlsplit(cfg["kc_base"]).hostname
    real = socket.getaddrinfo
    socket.getaddrinfo = lambda h, *a, **k: real(cfg["address"] if h == kc_host else h, *a, **k)

    store_ctx = ssl.create_default_context(cafile=cfg.get("cacert") or None)
    store = urllib.request.build_opener(urllib.request.HTTPSHandler(context=store_ctx), NoRedirect)
    kc_ctx = ssl.create_default_context()
    if not cfg.get("verify", True):
        kc_ctx.check_hostname = False
        kc_ctx.verify_mode = ssl.CERT_NONE

    def call(opener, url, data=None, token=None, form=False, method=None):
        body = None
        headers = {}
        if data is not None:
            if form:
                body = urllib.parse.urlencode(data).encode()
            else:
                body = json.dumps(data).encode()
                headers["Content-Type"] = "application/json"
        if token:
            headers["X-Vault-Token"] = token
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            r = opener.open(req, timeout=20)
            return r.status, r.headers, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")

    def bao(path, data=None, token=None, method=None):
        return call(store, cfg["api"] + "/" + path, data, token, method=method)

    def action(body):
        m = re.search(r'<form[^>]*\baction="([^"]+)"', body)
        return urllib.parse.urljoin(cfg["kc_base"] + "/", html.unescape(m.group(1))) if m else None

    def as_json(body):
        try:
            return json.loads(body)
        except ValueError:
            return {}

    def to_keycloak(n, who):
        """Steps auth_url and login page for one user; returns (Keycloak opener, login form URL) or None."""
        jar = http.cookiejar.CookieJar()
        kc = urllib.request.build_opener(urllib.request.HTTPSHandler(context=kc_ctx),
                                         urllib.request.HTTPCookieProcessor(jar), NoRedirect)
        code, _, body = bao("auth/%s/oidc/auth_url" % cfg["mount"],
                            {"role": cfg["role"], "redirect_uri": cfg["redirect"]})
        url = as_json(body).get("data", {}).get("auth_url", "")
        if not line(n, who + " auth_url", code, code == 200 and url.startswith(cfg["kc_base"] + "/"),
                    "no Keycloak URL"):
            return None
        code, _, body = call(kc, url)
        form = action(body)
        if not line(n + 1, who + " login page", code, code == 200 and form is not None and 'name="password"' in body,
                    "no login form"):
            return None
        return kc, form

    def callback(location):
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(location).query)
        params = urllib.parse.urlencode({"state": q.get("state", [""])[0], "code": q.get("code", [""])[0]})
        return bao("auth/%s/oidc/callback?%s" % (cfg["mount"], params))

    def to_store(location):
        return location.startswith(cfg["redirect"]) and "code=" in location and "state=" in location

    def with_code(n, who, u):
        """Steps n..n+3 for a lab-admins member: auth_url, login page, password alone must ask for the code,
        password + code must redirect to the store. Returns the redirect location, or None."""
        got = to_keycloak(n, who)
        if not got:
            return None
        kc, form = got
        code, headers, body = call(kc, form, {"username": u["user"], "password": u["password"],
                                              "credentialId": ""}, form=True)
        form = action(body)
        if not line(n + 2, who + " password only", code, code == 200 and form is not None and 'name="otp"' in body,
                    "redirect, the password alone signed in" if code in (301, 302, 303) else "no one-time-code form"):
            return None
        location = ""
        for offset in (0, 1):  # the next 30-second window, if the first code sat on a boundary
            code, headers, body = call(kc, form, {"otp": totp(u["seed"], offset, int(cfg.get("digits", 6)),
                                                              int(cfg.get("period", 30))), "credentialId": ""}, form=True)
            location = headers.get("Location", "") if headers else ""
            if code == 302 and to_store(location):
                break
            form = action(body) or form
            if code != 200:
                break
        if not line(n + 3, who + " password + code", code, code == 302 and to_store(location),
                    "no redirect to the store with a code"):
            return None
        return location

    try:
        # The owner: password, then the code, then a token with the role's policy and nothing more.
        location = with_code(1, "admin", cfg["admin"])
        if not location:
            return 1
        code, _, body = callback(location)
        auth = as_json(body).get("auth") or {}
        token = auth.get("client_token", "")
        if not line(5, "admin callback", code, code == 200 and bool(token) and cfg["policy"] in auth.get("policies", []),
                    "no token with policy " + cfg["policy"]):
            return 1
        try:
            proof = "kv/data/%s/proof" % cfg["prefix"]
            code, _, _ = bao(proof, {"data": {"value": PROOF_VALUE}}, token)
            ok = line(6, "admin writes", code, code in (200, 204), "write refused")
            code, _, body = bao(proof, token=token)
            value = as_json(body).get("data", {}).get("data", {}).get("value")
            ok = line(7, "admin reads", code, code == 200 and value == PROOF_VALUE, "value not read back") and ok
            code, _, _ = bao("kv/data/c1/check", token=token)
            ok = line(8, "admin refused c1", code, code == 403, "not refused") and ok
            code, _, _ = bao("sys/policies/acl/admin", token=token)
            ok = line(9, "admin refused policy", code, code == 403, "not refused") and ok
        finally:
            bao("auth/token/revoke-self", {}, token, method="POST")
        if not ok:
            return 1

        # The viewer: Keycloak lets them through (no code is asked: viewers have none), the store refuses.
        got = to_keycloak(10, "viewer")
        if not got:
            return 1
        kc, form = got
        viewer = cfg["viewer"]
        code, headers, _ = call(kc, form, {"username": viewer["user"], "password": viewer["password"],
                                           "credentialId": ""}, form=True)
        location = headers.get("Location", "") if headers else ""
        if not line(12, "viewer password", code, code == 302 and to_store(location), "no redirect to the store"):
            return 1
        code, _, body = callback(location)
        token = (as_json(body).get("auth") or {}).get("client_token", "")
        if token:
            bao("auth/token/revoke-self", {}, token, method="POST")
        if not line(13, "viewer refused", code, code in (400, 403) and not token, "the store signed the viewer in"):
            return 1

        # Another lab-admins member with a good code: Keycloak lets them through, the store refuses (the role binds
        # the owner's user name as well as the group).
        location = with_code(14, "other", cfg["other"])
        if not location:
            return 1
        code, _, body = callback(location)
        token = (as_json(body).get("auth") or {}).get("client_token", "")
        if token:
            bao("auth/token/revoke-self", {}, token, method="POST")
        return 0 if line(18, "other refused", code, code in (400, 403) and not token,
                         "the store signed another admin in") else 1
    except Exception as e:  # network or TLS: the class name only
        line(0, "connection", "none", False, type(e).__name__)
        return 1


sys.exit(main())
