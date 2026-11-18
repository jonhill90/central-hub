#!/usr/bin/env python3
"""web-shot <url> <out.png> [--insecure]: open a page in headless Chromium and save a screenshot.

Runs as the session user and holds no key. It prints the final address, the page title and the HTTP status, so a
sign-in proof can say what it reached. --insecure accepts a certificate the box does not trust (a dev cluster's
throwaway CA); without it a bad certificate fails the run. It only loads the page and types nothing.
"""
import sys

from playwright.sync_api import sync_playwright


def main(argv):
    args = [a for a in argv if a != "--insecure"]
    insecure = len(args) != len(argv)
    if len(args) != 2 or not args[0].startswith(("http://", "https://")):
        print("usage: web-shot <http(s) url> <out.png> [--insecure]", file=sys.stderr)
        return 2
    url, out = args
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_context(ignore_https_errors=insecure, viewport={"width": 1280, "height": 800}).new_page()
        resp = page.goto(url, wait_until="networkidle", timeout=60000)
        page.screenshot(path=out, full_page=True)
        print(f"url={page.url} title={page.title()!r} status={resp.status if resp else 'none'} png={out}")
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
