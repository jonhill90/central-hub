#!/usr/bin/env python3
"""agent-browser: a long-running Chromium on the box that keeps its sign-ins, for agents' own accounts only.

  agent-browser start [--minutes N]   start Chromium; it stops after N minutes (default 30)
  agent-browser status                say whether it runs, its DevTools address and its stop time
  agent-browser open <url>            open a page in the running browser
  agent-browser shot <out.png>        save a screenshot of the page in front
  agent-browser stop                  stop Chromium

Runs as the session user and holds no key. The profile lives in ~/.agent-browser/profile, so a sign-in made there is
still there next time. Only agent accounts sign in here, never the owner's (project rule 14). Chromium runs in its
full headless mode, because AlmaLinux 10 ships no X server (no Xvfb or Xvnc in BaseOS, AppStream or CRB, checked
2026-11-20). Its DevTools port is bound to 127.0.0.1 only, so a session drives the browser with Playwright's
connect_over_cdp, or Playwright MCP with --cdp-endpoint, and a person watches or takes over through DevTools' own page
view (http://127.0.0.1:9222 through an SSH tunnel). The browser stops by itself after N minutes, so it never holds
memory that a dev rebuild needs.
"""
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request

HOME = os.path.expanduser("~")
STATE_DIR = os.environ.get("AGENT_BROWSER_STATE", os.path.join(HOME, ".agent-browser"))
STATE = os.path.join(STATE_DIR, "state.json")
PROFILE = os.path.join(STATE_DIR, "profile")
CDP_PORT = int(os.environ.get("AGENT_BROWSER_CDP_PORT", "9222"))
WIDTH, HEIGHT = 1280, 800
USAGE = "usage: agent-browser start [--minutes N] | status | open <url> | shot <out.png> | stop"


def read_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, TypeError):
        return False


def running():
    st = read_state()
    if st and alive(st.get("chromium_pid")):
        return st
    return None


def chromium_path():
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        return p.chromium.executable_path


def launch_chromium(log):
    return subprocess.Popen(
        [chromium_path(), "--headless=new", f"--user-data-dir={PROFILE}", "--remote-debugging-address=127.0.0.1",
         f"--remote-debugging-port={CDP_PORT}", f"--window-size={WIDTH},{HEIGHT}", "--window-position=0,0",
         "--no-first-run", "--no-default-browser-check", "--password-store=basic", "about:blank"],
        stdout=log, stderr=log, start_new_session=True)


def cdp_up(timeout_s=20):
    end = time.time() + timeout_s
    while time.time() < end:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/version", timeout=2) as r:
                return json.load(r)
        except OSError:
            time.sleep(0.5)
    return None


def start(minutes):
    if running():
        print("agent-browser: already running; `agent-browser status` shows it")
        return 0
    os.makedirs(PROFILE, mode=0o700, exist_ok=True)
    os.chmod(STATE_DIR, 0o700)
    log = open(os.path.join(STATE_DIR, "browser.log"), "ab")
    try:
        chrome = launch_chromium(log)
    except Exception as exc:
        print(f"agent-browser: Chromium did not start ({exc})", file=sys.stderr)
        return 1
    version = cdp_up()
    if not version:
        os.killpg(chrome.pid, signal.SIGTERM)
        print(f"agent-browser: Chromium's DevTools did not answer; see {STATE_DIR}/browser.log", file=sys.stderr)
        return 1
    stop_at = int(time.time()) + minutes * 60
    with open(STATE, "w") as f:
        json.dump({"chromium_pid": chrome.pid, "cdp": f"http://127.0.0.1:{CDP_PORT}", "stop_at": stop_at}, f)
    # The timer: a detached sleeper that runs `stop` at the deadline, if this same browser is still the one running.
    subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "_reap", str(chrome.pid), str(minutes * 60)],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, env=os.environ)
    print(f"agent-browser: running; browser={version.get('Browser')} cdp=http://127.0.0.1:{CDP_PORT} "
          f"stops in {minutes} min")
    return 0


def stop():
    st = read_state()
    if not st:
        print("agent-browser: not running")
        return 0
    # Close Chromium the way its own Quit does, through DevTools, so the profile (cookies, local storage) is written
    # to disk before the process ends. A signal alone lost local storage in the test of 2026-11-20.
    if alive(st.get("chromium_pid")):
        try:
            from playwright.sync_api import sync_playwright
            with sync_playwright() as p:
                browser = p.chromium.connect_over_cdp(st["cdp"], timeout=5000)
                browser.new_browser_cdp_session().send("Browser.close")
        except Exception:
            pass
        for _ in range(40):
            if not alive(st.get("chromium_pid")):
                break
            time.sleep(0.25)
    pid = st.get("chromium_pid")
    if alive(pid):
        try:
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            pass
        for _ in range(20):
            if not alive(pid):
                break
            time.sleep(0.25)
    os.remove(STATE)
    print("agent-browser: stopped")
    return 0


def reap(pid, seconds):
    time.sleep(seconds)
    st = read_state()
    if st and st.get("chromium_pid") == pid:
        stop()
    return 0


def status():
    st = running()
    if not st:
        print("agent-browser: not running")
        return 1
    left = max(0, st["stop_at"] - int(time.time())) // 60
    print(f"agent-browser: running; cdp={st['cdp']} stops in {left} min")
    return 0


def with_page(fn):
    st = running()
    if not st:
        print("agent-browser: not running; `agent-browser start` first", file=sys.stderr)
        return 1
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(st["cdp"])
        ctx = browser.contexts[0]
        page = ctx.pages[-1] if ctx.pages else ctx.new_page()
        fn(page)
    return 0


def main(argv):
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "start":
        minutes = 30
        if rest[:1] == ["--minutes"] and len(rest) == 2 and rest[1].isdigit() and 1 <= int(rest[1]) <= 240:
            minutes = int(rest[1])
        elif rest:
            print(USAGE + " (minutes 1 to 240)", file=sys.stderr)
            return 2
        return start(minutes)
    if cmd == "stop" and not rest:
        return stop()
    if cmd == "status" and not rest:
        return status()
    if cmd == "open" and len(rest) == 1 and rest[0].startswith(("http://", "https://")):
        def go(page):
            resp = page.goto(rest[0], wait_until="load", timeout=60000)
            print(f"url={page.url} title={page.title()!r} status={resp.status if resp else 'none'}")
        return with_page(go)
    if cmd == "shot" and len(rest) == 1:
        def shot(page):
            page.screenshot(path=rest[0])
            print(f"url={page.url} title={page.title()!r} png={rest[0]}")
        return with_page(shot)
    if cmd == "_reap" and len(rest) == 2:
        return reap(int(rest[0]), int(rest[1]))
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
