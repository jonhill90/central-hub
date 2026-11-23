#!/usr/bin/env python3
"""signin-browser <config.json> <shots-dir>: sign in to every lab app in headless Chromium, as the test user, and save one screenshot per app.

Run by the signin-check wrapper (as the keys user, through sudo) with Playwright's Python from the box's virtual environment. <config.json> is
the wrapper's private file (mode 0600): base (Keycloak's https address), realm, user, password, seed (base32 TOTP seed), digits, period, verify,
and each app's address: jellyfin_base, grafana_base, argocd_base, pve_base, hub_base, mealie_base, homeassistant_base, openbao_base, ntfy_base, opnsense_base. It makes nothing in
any app: it only signs in as the test user and reads.

Eleven apps (Mealie and Home Assistant added once they had Keycloak clients), each printed as "<n> <app>: <result>" and nothing more (no password, seed, code, state, token or page text):
  passed                    the browser signed in through Keycloak and the app answered as that user (Jellyfin: a stored access token; Grafana
                            /api/user; Argo CD userinfo; Proxmox /access/permissions; Keycloak: the account console's own page).
  failed                    the app should sign in through Keycloak and did not, or its address did not load at all.
  no Keycloak sign-in yet   the app has no Keycloak sign-in today (OpenBao, ntfy; OPNsense with its own login). It is still opened and
                            photographed, and the line says what the address answered (an HTTP 404 is said, not hidden).
The screenshot is <shots-dir>/<n>-<app>.png, taken after the sign-in (or where it stopped; any text typed into a form is cleared first). The exit
is 0 unless an app is "failed". One Keycloak one-time code is used once: the script waits for the next 30-second window between sign-ins.
"""
import base64
import hashlib
import hmac
import json
import os
import stat
import struct
import sys
import time
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

SSO = ("hub", "jellyfin", "grafana", "argocd", "pve", "mealie", "homeassistant", "sso")
NO_SSO = ("openbao", "ntfy", "opnsense")
ORDER = ("hub", "jellyfin", "grafana", "argocd", "pve", "mealie", "homeassistant", "sso", "openbao", "ntfy", "opnsense")
NO_SSO_NOTE = {"opnsense": "its own login page"}
LAST_WINDOW = {"w": None}


def totp(seed, digits, period, offset=0):
    s = seed.replace(" ", "").upper()
    key = base64.b32decode(s + "=" * (-len(s) % 8))
    mac = hmac.new(key, struct.pack(">Q", int(time.time() // period) + offset), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** digits).zfill(digits)


def next_code(cfg):
    """A code for a window no sign-in has used yet: Keycloak refuses a code it has accepted, and the scripted checks that ran before
    this one used the windows up to now."""
    period, digits = int(cfg.get("period", 30)), int(cfg.get("digits", 6))
    w = int(time.time() // period)
    if LAST_WINDOW["w"] is not None and w <= LAST_WINDOW["w"]:
        time.sleep((LAST_WINDOW["w"] + 1) * period - time.time() + 1)
        w = int(time.time() // period)
    LAST_WINDOW["w"] = w
    return totp(cfg["seed"], digits, period)


def clean(page):
    """Clear every text box on the page, so a screenshot never shows what was typed."""
    try:
        page.evaluate("() => document.querySelectorAll('input').forEach(i => { if (i.type !== 'hidden') i.value = ''; })")
    except Exception:
        pass


def shot(page, path):
    clean(page)
    page.screenshot(path=path, full_page=False)


def keycloak_sign_in(page, cfg):
    """From Keycloak's sign-in form to the one-time-code step and out: raises when the form never leaves Keycloak."""
    page.wait_for_selector("#username", timeout=30000)
    page.fill("#username", cfg["user"])
    page.fill("#password", cfg["password"])
    page.click("#kc-login")
    for attempt in range(3):
        page.wait_for_selector("#otp", timeout=30000)
        page.fill("#otp", next_code(cfg))
        page.click("#kc-login")
        deadline = time.time() + 25
        while time.time() < deadline:
            time.sleep(0.5)
            url = page.url
            if "login-actions" not in url:
                return
            # The form is back with an error: the code was refused, so the next window's code is tried.
            if page.locator("#otp").count() and page.locator("#input-error-otp-code, .pf-m-error, .alert-error, .kc-feedback-text").count():
                break
    raise RuntimeError("Keycloak did not accept the one-time code in three windows")


def wait_for_origin(page, base, seconds=30):
    host = urlsplit(base).netloc
    page.wait_for_url(lambda u: urlsplit(u).netloc == host, timeout=seconds * 1000)
    page.wait_for_load_state("networkidle", timeout=seconds * 1000)


def api(page, url):
    """GET from inside the page, so the browser's own trust of the lab CA and its cookies apply (Playwright's request client trusts only
    the system store: it failed with 'unable to get local issuer certificate' on 2026-11-23 although the sign-in itself had worked)."""
    return page.evaluate("""async (u) => { const r = await fetch(u, {credentials: 'same-origin'});
        let b = null; if (r.status === 200) { try { b = await r.json(); } catch (e) { b = {}; } } return [r.status, b]; }""", url)


def sign_in_app(app, page, cfg):
    kc = cfg["base"]
    if app == "hub":
        page.goto(cfg["hub_base"] + "/", wait_until="networkidle", timeout=60000)  # signed out, the app sends the browser to Keycloak
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["hub_base"])
        page.wait_for_timeout(2000)
        if urlsplit(page.url).path.startswith("/auth/"):
            raise RuntimeError("the hub stayed on its sign-in path %s" % urlsplit(page.url).path)
        code, _ = api(page, cfg["hub_base"] + "/api/v1/catalog")
        if code != 200:
            raise RuntimeError("/api/v1/catalog answered HTTP %s" % code)
        return "the hub opens and /api/v1/catalog answers HTTP 200 for the test user"
    if app == "jellyfin":
        page.goto(cfg["jellyfin_base"] + "/web/", wait_until="networkidle", timeout=60000)
        page.locator('button:has-text("Sign in with")').first.click(timeout=30000)
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["jellyfin_base"])
        for _ in range(30):
            ok = page.evaluate("() => { try { return JSON.parse(localStorage.getItem('jellyfin_credentials')).Servers.some(s => !!s.AccessToken); }"
                               " catch (e) { return false; } }")
            if ok:
                page.wait_for_timeout(2000)
                return "Jellyfin holds an access token for the test user"
            time.sleep(1)
        raise RuntimeError("Jellyfin stored no access token after the sign-in")
    if app == "grafana":
        page.goto(cfg["grafana_base"] + "/login", wait_until="networkidle", timeout=60000)
        page.locator('a:has-text("Sign in with")').first.click(timeout=30000)
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["grafana_base"])
        code, body = api(page, cfg["grafana_base"] + "/api/user")
        if code != 200 or not body or not body.get("login"):
            raise RuntimeError("/api/user answered HTTP %s" % code)
        return "/api/user answers HTTP 200 for the test user"
    if app == "argocd":
        page.goto(cfg["argocd_base"] + "/login", wait_until="networkidle", timeout=60000)
        page.locator('a:has-text("LOG IN VIA")').first.click(timeout=30000)
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["argocd_base"])
        code, body = api(page, cfg["argocd_base"] + "/api/v1/session/userinfo")
        if code != 200 or not body or not body.get("loggedIn"):
            raise RuntimeError("userinfo answered HTTP %s, not logged in" % code)
        return "userinfo says logged in"
    if app == "pve":
        page.goto(cfg["pve_base"] + "/", wait_until="networkidle", timeout=60000)
        page.get_by_text("Login (OpenID redirect)").click(timeout=30000)
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["pve_base"])
        page.wait_for_timeout(3000)
        code, body = api(page, cfg["pve_base"] + "/api2/json/access/permissions")
        if code != 200:
            raise RuntimeError("/access/permissions answered HTTP %s" % code)
        return "/access/permissions answers HTTP 200"
    if app == "mealie":
        page.goto(cfg["mealie_base"] + "/login", wait_until="networkidle", timeout=60000)
        if "/openid-connect/" not in page.url:  # Mealie may send the browser straight to Keycloak; if not, press its OIDC button
            page.locator('button:has-text("OAuth"), button:has-text("OpenID"), button:has-text("Keycloak"), a:has-text("OAuth")').first.click(timeout=30000)
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["mealie_base"])
        page.wait_for_timeout(3000)
        code, body = api(page, cfg["mealie_base"] + "/api/users/self")
        if code != 200 or not body:
            raise RuntimeError("/api/users/self answered HTTP %s" % code)
        return "/api/users/self answers HTTP 200 for the test user"
    if app == "homeassistant":
        page.goto(cfg["homeassistant_base"] + "/auth/oidc/welcome", wait_until="networkidle", timeout=60000)
        page.locator("#login-button").click(timeout=30000)
        keycloak_sign_in(page, cfg)
        wait_for_origin(page, cfg["homeassistant_base"])
        if "/auth/oidc/finish" in page.url:  # "Logged in!": the component asks which device continues
            page.get_by_text("Continue on this device").first.click(timeout=30000)
            page.wait_for_load_state("networkidle", timeout=30000)
        for _ in range(30):
            ok = page.evaluate("() => { try { return !!JSON.parse(localStorage.getItem('hassTokens')).access_token; } catch (e) { return false; } }")
            if ok:
                page.wait_for_timeout(2500)
                # Who is this? Ask Home Assistant's own websocket (auth/current_user) with the stored token; only the role word is kept.
                role = page.evaluate("""() => new Promise((resolve) => {
                    try {
                        const t = JSON.parse(localStorage.getItem('hassTokens')).access_token;
                        const ws = new WebSocket('wss://' + location.host + '/api/websocket');
                        setTimeout(() => resolve('unknown'), 15000);
                        ws.onmessage = (m) => { const d = JSON.parse(m.data);
                            if (d.type === 'auth_required') ws.send(JSON.stringify({type: 'auth', access_token: t}));
                            else if (d.type === 'auth_ok') ws.send(JSON.stringify({id: 1, type: 'auth/current_user'}));
                            else if (d.id === 1) { resolve(d.result && d.result.is_admin ? 'admin' : 'user'); ws.close(); } };
                    } catch (e) { resolve('unknown'); } })""")
                return "Home Assistant holds its own access token for the test user, who is %s there" % role
            time.sleep(1)
        raise RuntimeError("Home Assistant stored no access token after the sign-in")
    if app == "sso":
        page.goto("%s/realms/%s/account/" % (kc, cfg["realm"]), wait_until="networkidle", timeout=60000)
        keycloak_sign_in(page, cfg)
        page.wait_for_selector("text=/personal info|account management/i", timeout=30000)
        page.wait_for_timeout(1500)
        return "the account console opens for the test user"
    raise RuntimeError("unknown app " + app)


def open_only(app, page, url):
    """An app with no Keycloak sign-in: open it, photograph it, say what the address answered."""
    resp = page.goto(url, wait_until="networkidle", timeout=60000)
    page.wait_for_timeout(1500)
    status = resp.status if resp else None
    return status, page.title()


def main(argv):
    if len(argv) != 2:
        print("usage: signin-browser <config.json> <shots-dir>", file=sys.stderr)
        return 2
    path, shots = argv
    st = os.stat(path)
    if st.st_mode & (stat.S_IRWXG | stat.S_IRWXO) or st.st_uid != os.getuid():
        print("refused: the config file must be mode 0600 or 0400 and owned by this user")
        return 2
    cfg = json.load(open(path))
    LAST_WINDOW["w"] = int(time.time() // int(cfg.get("period", 30)))  # the scripted checks before this used the windows up to now
    os.makedirs(shots, exist_ok=True)
    urls = {"hub": cfg["hub_base"], "openbao": cfg["openbao_base"].rstrip("/") + "/ui/", "ntfy": cfg["ntfy_base"], "opnsense": cfg["opnsense_base"]}
    results = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for n, app in enumerate(ORDER, 1):
            ctx = browser.new_context(ignore_https_errors=cfg.get("verify") is False, viewport={"width": 1280, "height": 800})
            page = ctx.new_page()
            png = os.path.join(shots, "%d-%s.png" % (n, app))
            try:
                if app in SSO:
                    try:
                        detail = sign_in_app(app, page, cfg)
                        results[app] = ("passed", detail)
                    except Exception as e:  # the message names a step, never a value
                        results[app] = ("failed", "%s: %s" % (type(e).__name__, str(e).splitlines()[0][:120]))
                else:
                    status, title = open_only(app, page, urls[app])
                    note = NO_SSO_NOTE.get(app, "")
                    detail = "the address answers HTTP %s, title %r%s" % (status, title[:40], "; " + note if note else "")
                    results[app] = ("no Keycloak sign-in yet", detail)
                    if status is None or status >= 500:
                        results[app] = ("failed", detail)
            except Exception as e:
                results[app] = ("failed", "the address did not load: %s" % type(e).__name__)
            try:
                shot(page, png)
            except Exception:
                pass
            where = urlsplit(page.url)
            print("%d %s: %s: %s (ended at %s%s; screenshot %s)" % (n, app, results[app][0], results[app][1], where.netloc, where.path, os.path.basename(png)))
            ctx.close()
        browser.close()
    counts = {k: sum(1 for r in results.values() if r[0] == k) for k in ("passed", "failed", "no Keycloak sign-in yet")}
    print("browser: %d passed, %d failed, %d no Keycloak sign-in yet" % (counts["passed"], counts["failed"], counts["no Keycloak sign-in yet"]))
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
