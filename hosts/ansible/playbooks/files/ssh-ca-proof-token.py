#!/usr/bin/env python3
"""Dev only, for the SSH certificate proof (playbooks/k8s-ssh-ca-proof.yml): each named user signs in to
Keycloak through the browser flow of client grafana, the code is traded for an ID token, and the token is
written to a file for the proof's throwaway OpenBao. Also writes realm lab's signing key as PEM, so that
OpenBao can check the tokens with no network path to Keycloak.

One JSON object on stdin: base (https://<keycloak host>), realm, client, redirect (one of the client's
redirect URIs), secret (the client's secret), address (this cluster's Gateway address), verify (false for
dev's own CA), pem_out (path), and users: a list of {user, password, seed (empty for a user with no one-time
code), out (path for the ID token)}.

Prints only lines "ssh-ca: token <user> <step>: ok" or "...: FAIL: <reason>", never a password, seed, code or
token. Exit 0 when every user got a token and the key was written.
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
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def totp(seed, offset=0, digits=6, period=30):
    s = seed.replace(" ", "").upper()
    key = base64.b32decode(s + "=" * (-len(s) % 8))
    mac = hmac.new(key, struct.pack(">Q", int(time.time() // period) + offset), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** digits).zfill(digits)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def der_len(n):
    if n < 128:
        return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(b)]) + b


def der(tag, body):
    return bytes([tag]) + der_len(len(body)) + body


def der_int(b):
    b = b.lstrip(b"\x00") or b"\x00"
    if b[0] & 0x80:
        b = b"\x00" + b
    return der(0x02, b)


def rsa_pem(jwk):
    """SubjectPublicKeyInfo PEM from an RSA JWK (n, e), with no library beyond the standard one."""
    unb = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    rsakey = der(0x30, der_int(unb(jwk["n"])) + der_int(unb(jwk["e"])))
    algo = der(0x30, der(0x06, bytes.fromhex("2a864886f70d010101")) + b"\x05\x00")
    spki = der(0x30, algo + der(0x03, b"\x00" + rsakey))
    b64 = base64.b64encode(spki).decode()
    return "-----BEGIN PUBLIC KEY-----\n" + "\n".join(b64[i:i + 64] for i in range(0, len(b64), 64)) + "\n-----END PUBLIC KEY-----\n"


def main():
    cfg = json.load(sys.stdin)
    host = urllib.parse.urlsplit(cfg["base"]).hostname
    real = socket.getaddrinfo
    socket.getaddrinfo = lambda h, *a, **k: real(cfg["address"] if h == host else h, *a, **k)
    ctx = ssl.create_default_context()
    if not cfg.get("verify", True):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    realm_url = cfg["base"] + "/realms/" + cfg["realm"]
    ok_all = True

    def line(user, step, ok, why=""):
        print("ssh-ca: token %s %s: %s" % (user, step, "ok" if ok else "FAIL: " + why))
        return ok

    # Realm lab's signing key (RS256), as PEM.
    try:
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
        keys = json.load(opener.open(realm_url + "/protocol/openid-connect/certs", timeout=20))["keys"]
        rsa = [k for k in keys if k.get("kty") == "RSA" and k.get("use", "sig") == "sig" and k.get("alg", "RS256") == "RS256"]
        if not rsa:
            line("realm", "signing key", False, "no RS256 key in the realm's key set")
            return 1
        with open(cfg["pem_out"], "w", encoding="utf-8") as f:
            f.write("".join(rsa_pem(k) for k in rsa))
        line("realm", "signing key", True)
    except Exception as e:  # network, TLS or parse: the class name only
        line("realm", "signing key", False, type(e).__name__)
        return 1

    for u in cfg["users"]:
        user = u["user"]
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

        def redirected(code, headers):
            loc = headers.get("Location", "") if headers else ""
            return loc if code == 302 and loc.startswith(cfg["redirect"]) and "code=" in loc else ""

        try:
            verifier = secrets.token_urlsafe(48)
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
            auth = realm_url + "/protocol/openid-connect/auth?" + urllib.parse.urlencode({
                "client_id": cfg["client"], "response_type": "code", "scope": "openid", "redirect_uri": cfg["redirect"],
                "state": secrets.token_hex(8), "code_challenge": challenge, "code_challenge_method": "S256"})
            code, _, body = call(auth)
            form = action(body)
            if not line(user, "login page", code == 200 and form is not None, "HTTP %s, no login form" % code):
                ok_all = False
                continue
            code, headers, body = call(form, {"username": user, "password": u["password"], "credentialId": ""})
            loc = redirected(code, headers)
            if u.get("seed"):
                form = action(body)
                if not line(user, "password", code == 200 and form is not None and 'name="otp"' in body,
                            "HTTP %s, no one-time-code form" % code):
                    ok_all = False
                    continue
                for offset in (0, 1):
                    code, headers, body = call(form, {"otp": totp(u["seed"], offset), "credentialId": ""})
                    loc = redirected(code, headers)
                    if loc:
                        break
                    form = action(body) or form
            if not line(user, "code", bool(loc), "HTTP %s, no redirect with a code" % code):
                ok_all = False
                continue
            grant = urllib.parse.parse_qs(urllib.parse.urlsplit(loc).query)["code"][0]
            code, _, body = call(realm_url + "/protocol/openid-connect/token", {
                "grant_type": "authorization_code", "code": grant, "redirect_uri": cfg["redirect"],
                "client_id": cfg["client"], "client_secret": cfg["secret"], "code_verifier": verifier})
            idt = json.loads(body).get("id_token") if code == 200 else None
            if not line(user, "id token", bool(idt), "HTTP %s" % code):
                ok_all = False
                continue
            fd = os.open(u["out"], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(idt)
        except Exception as e:  # network, TLS or parse: the class name only
            line(user, "run", False, type(e).__name__)
            ok_all = False
    return 0 if ok_all else 1


sys.exit(main())
