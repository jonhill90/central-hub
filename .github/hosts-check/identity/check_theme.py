#!/usr/bin/env python3
"""Check that realm lab's sign-in page uses the theme the realm names.

Usage: check_theme.py <Keycloak URL> <theme name>
Asks for the authorization page of client argocd (code flow, no PKCE required), then checks that
the page links <theme>/css/styles.css under Keycloak's resources path, and that the stylesheet
answers 200 with the theme's own text.
"""
import re
import sys
import urllib.parse
import urllib.request


def fetch(url):
    # Keycloak runs with --proxy-headers=xforwarded and an https hostname; say the request came in
    # over https, as the Gateway does on c1.
    req = urllib.request.Request(url, headers={"X-Forwarded-Proto": "https"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.status, r.read().decode("utf-8", "replace")


def main(base, theme):
    query = urllib.parse.urlencode({
        "client_id": "argocd", "response_type": "code", "scope": "openid",
        "redirect_uri": "https://argocd.example.com/auth/callback"})
    status, page = fetch(f"{base}/realms/lab/protocol/openid-connect/auth?{query}")
    print(f"sign-in page: {status}")
    links = re.findall(r'href="([^"]*/login/' + re.escape(theme) + r'/css/styles\.css)"', page)
    if status != 200 or not links:
        sys.exit(f"FAIL: the sign-in page does not link theme {theme}'s css/styles.css")
    path = urllib.parse.urlparse(links[0]).path
    status, css = fetch(base + path)
    print(f"{path}: {status}")
    if status != 200 or "Test theme for the realm test" not in css:
        sys.exit(f"FAIL: {path} did not serve the theme's stylesheet")
    print(f"ok   sign-in page uses theme {theme}")


if __name__ == "__main__":
    main(*sys.argv[1:])
