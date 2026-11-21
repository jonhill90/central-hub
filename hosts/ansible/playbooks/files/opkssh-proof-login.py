#!/usr/bin/env python3
"""Dev only, for the opkssh proof (playbooks/files/opkssh-proof.sh): plays the browser for `opkssh login`.

One JSON object on stdin: url (the address opkssh printed), user, password, seed (base32 one-time-code seed, or
empty). It follows redirects from opkssh's local page to Keycloak, signs in with the password and then a code,
and follows Keycloak's redirect back to opkssh's localhost callback, which ends opkssh's login.
Prints only "opkssh: browser <step>: ok" or "...: FAIL: <reason>", never a password, seed, code or page text.
"""
import base64
import hashlib
import hmac
import html
import http.cookiejar
import json
import re
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


def wait_next_window(period=30):
    time.sleep(period - time.time() % period + 1)


def page_kind(body):
    """What page Keycloak answered with, by form id and error marker only, never its text."""
    ids = re.findall(r'<form[^>]*\bid="([A-Za-z0-9_-]+)"', body or "")
    kind = "form " + ",".join(ids) if ids else "no form"
    if 'name="otp"' in (body or ""):
        kind += ", the one-time-code form again"
    if re.search(r'id="input-error[A-Za-z0-9_-]*"|class="[^"]*alert-error', body or ""):
        kind += ", with an error"
    return kind


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def main():
    cfg = json.load(sys.stdin)
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect)

    def call(url, data=None):
        req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode() if data else None)
        try:
            r = opener.open(req, timeout=20)
            return r.status, r.headers, r.read().decode("utf-8", "replace"), url
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace"), url

    def follow(url, data=None, hops=10):
        code, headers, body, at = call(url, data)
        while code in (301, 302, 303, 307) and hops > 0:
            at = urllib.parse.urljoin(at, headers.get("Location", ""))
            code, headers, body, _ = call(at)
            hops -= 1
        return code, body, at

    def form(body, base):
        m = re.search(r'<form[^>]*\baction="([^"]+)"', body)
        return urllib.parse.urljoin(base, html.unescape(m.group(1))) if m else None

    def line(step, ok, why=""):
        print("opkssh: browser %s: %s" % (step, "ok" if ok else "FAIL: " + why))
        return ok

    try:
        code, body, at = follow(cfg["url"])
        action = form(body, at)
        if not line("login page", code == 200 and action is not None and 'name="password"' in body, "HTTP %s, no login form" % code):
            return 1
        code, body, at = follow(action, {"username": cfg["user"], "password": cfg["password"], "credentialId": ""})
        if cfg.get("seed"):
            action = form(body, at)
            if not line("password", code == 200 and action is not None and 'name="otp"' in body, "HTTP %s, no one-time-code form" % code):
                return 1
            # Keycloak refuses a code it has already accepted, and the ssh-ca route signed in with this seed
            # seconds before, so the first code is the next window's own, and a refused one waits for the next.
            for attempt in range(3):
                wait_next_window()
                code, body, at = follow(action, {"otp": totp(cfg["seed"]), "credentialId": ""})
                if urllib.parse.urlsplit(at).hostname == "localhost" or code != 200:
                    break
                action = form(body, at) or action
        back = urllib.parse.urlsplit(at).hostname == "localhost"
        return 0 if line("back to opkssh", back and code == 200,
                         "HTTP %s, ended away from opkssh's callback (%s)" % (code, page_kind(body))) else 1
    except Exception as e:  # network, TLS or parse: the class name only
        line("run", False, type(e).__name__)
        return 1


sys.exit(main())
