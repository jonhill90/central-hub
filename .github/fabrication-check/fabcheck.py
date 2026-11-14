#!/usr/bin/env python3
"""Fabrication check v0.1: look up every checkable pointer an agent wrote, with no model.

It pulls pointers out of text (PR numbers with "merged as" or "head" SHAs, PR states, SHAs
said to be on main, file:line references with quoted words, message ids with times and
quoted words, rule-21 sentences, [measured] labels) and looks each one up in GitHub, the
checkout or a dump of the project's messages. Each claim gets one result:

  pass          the lookup agrees with the claim
  wrong         a lookup that worked contradicts the claim
  stale         true when written, but a living file still says it after it stopped being true
  unverifiable  the lookup could not be made (network, rate limit, no access, outside reach)

A network, rate-limit or API error is always `unverifiable`, never `wrong`. One as-of time is
pinned per run and printed at the top of the report. Only `wrong` fails the run.

Design: Library plans/fabrication-check/DESIGN.md (passed Councils A, B and C, 2026-11-14).
Standard library only. Exit path: delete this folder and its workflow.

  python3 -I fabcheck.py --root . --repo OWNER/NAME [--pr N] [--diff BASE] [--file PATH ...]
                         [--corrections] [--messages DUMP.json] [--as-of ISO]
                         [--md OUT.md] [--jsonl OUT.jsonl]
"""
import argparse, datetime as dt, json, os, pathlib, re, subprocess, sys, urllib.error, urllib.request

SHA = r"[0-9a-f]{7,40}"
REPO_WORDS = {"central-hub": "central-hub", "agent-notebook": "agent-notebook", "notebook": "agent-notebook",
              "inpara": "inpara", "obsidian-graph-3d": "obsidian-graph-3d"}
PR_REF = re.compile(r"(?:\b([a-z][\w-]*)\s+)?(?:PR\s+)?#(\d{1,6})\b")
MERGED_A = re.compile(rf"#(\d{{1,6}})\b[^#\n]{{0,80}}?\bmerged as ({SHA})\b")
MERGED_B = re.compile(rf"\bmerged as ({SHA})\b\s*\([^)#\n]{{0,40}}?#(\d{{1,6}})")
MERGED_C = re.compile(rf"\bmerged\s*\(#(\d{{1,6}}),\s*({SHA})\)")
HEAD_A = re.compile(rf"#(\d{{1,6}})\b[^#\n]{{0,60}}?\bhead ({SHA})\b")
HEAD_B = re.compile(rf"#(\d{{1,6}})\s*\(({SHA})\)")
ON_MAIN = re.compile(rf"(?:\b([a-z][\w-]*)\s+)?\bmain(?: at)? ({SHA})\b")
STATE = re.compile(r"#(\d{1,6})\b,?\s+(?:is\s+|was\s+)?\(?(merged|open|closed)\b(?! as)")
FILE_LINE = re.compile(r"`?((?:\.?[\w.-]+/)*[\w.-]+\.(?:md|py|ya?ml|sh|tf|json|txt|tsv|toml)`?)"
                       r"(?::(\d+)(?:-(\d+))?|\s+lines?\s+(\d+)(?:\s*(?:-|to)\s*(\d+))?)")
QUOTE = re.compile(r"[\"\u201c]([^\"\u201c\u201d\n]{12,200})[\"\u201d]")
MSG = re.compile(r"\bcmsg_[A-Za-z0-9]{20,}\b")
CLOCK = re.compile(r"\b(\d{2}):(\d{2})(?::(\d{2}))?\s*(?:UTC|Z)\b|T(\d{2}):(\d{2})(?::(\d{2}))?Z")
MEASURED = re.compile(r"\[measured\]|\(measured\b")
RULE21 = re.compile(r"\b(?:not supported|isn't supported|not documented|isn't documented|not available|"
                    r"isn't available|not possible|isn't possible|only (?:in|on) (?:the )?(?:paid|business|"
                    r"enterprise|pro)\b|no (?:official|native) )", re.I)
RULE21_CHECKS = [r"search", r"issue", r"\bdocs?\b|documentation|docs index", r"hands-on|not tested|tested"]
CORR = re.compile(rf"PR #(\d+): approved (\d{{4}}-\d\d-\d\dT\d\d:\d\d:\d\dZ) \((cmsg_\w+)\), head ({SHA}); "
                  rf"merged as ({SHA})")
AGENT_TAG = re.compile(r"^\s*\[AGENT\s*·|not Jon's own words|not the owner's own words", re.I)


class Unverifiable(Exception):
    pass


class GitHub:
    """Read-only GitHub REST lookups. Any error that is not a clear 'no such thing' in a repo we can
    read is Unverifiable."""

    def __init__(self, owner, own_repo, token=None, api="https://api.github.com"):
        self.owner, self.own, self.token, self.api, self.cache = owner, own_repo, token, api, {}

    def get(self, path):
        if path in self.cache:
            return self.cache[path]
        req = urllib.request.Request(self.api + path, headers={"Accept": "application/vnd.github+json",
                                                              "User-Agent": "fabrication-check"})
        if self.token:
            req.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                val = (200, json.load(r))
        except urllib.error.HTTPError as e:
            val = (e.code, None)
        except Exception as e:  # network, timeout, bad JSON
            raise Unverifiable(f"lookup failed: {type(e).__name__}")
        self.cache[path] = val
        return val

    def _ok(self, repo, path):
        code, body = self.get(f"/repos/{self.owner}/{repo}{path}")
        if code == 200:
            return body
        if code == 404 and repo == self.own:
            return None  # a clear "no such thing" in the repo this job can read
        raise Unverifiable(f"GitHub answered {code} for {repo}{path}")

    def pr(self, repo, n):
        return self._ok(repo, f"/pulls/{n}")

    def pr_commits(self, repo, n):
        body = self._ok(repo, f"/pulls/{n}/commits?per_page=100")
        return [c["sha"] for c in body or []]

    def on_main(self, repo, sha):
        meta = self._ok(repo, "")
        if meta is None:
            raise Unverifiable("repository not readable")
        cmp_ = self._ok(repo, f"/compare/{sha}...{meta.get('default_branch', 'main')}")
        if cmp_ is None:
            return None  # the SHA does not exist
        return cmp_.get("status") in ("ahead", "identical")


def parse_time(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def repo_for(line, start, default):
    """The repository a '#N' at `start` belongs to: the word right before it, if it names one."""
    m = re.search(r"([a-z][\w-]*)\s+(?:PR\s+)?$", line[:start])
    return REPO_WORDS.get(m.group(1), default) if m else default


def extract(text, src, default_repo):
    claims = []
    for ln, line in enumerate(text.splitlines(), 1):
        base = {"src": src, "line": ln, "text": line.strip()[:300]}
        merged_prs = set()
        for rx, order in ((MERGED_A, (1, 2)), (MERGED_B, (2, 1)), (MERGED_C, (1, 2))):
            for m in rx.finditer(line):
                pr, sha = m.group(order[0]), m.group(order[1])
                if (pr, sha) in merged_prs:
                    continue
                merged_prs.add((pr, sha))
                claims.append({**base, "kind": "merged", "repo": repo_for(line, m.start(order[0]) - 1, default_repo),
                               "pr": int(pr), "sha": sha})
        for rx in (HEAD_A, HEAD_B):
            for m in rx.finditer(line):
                claims.append({**base, "kind": "head", "repo": repo_for(line, m.start(), default_repo),
                               "pr": int(m.group(1)), "sha": m.group(2)})
        merged_nums = {pr for pr, _ in merged_prs}
        for m in STATE.finditer(line):
            if m.group(2) == "merged" and m.group(1) in merged_nums:
                continue
            claims.append({**base, "kind": "state", "repo": repo_for(line, m.start(), default_repo),
                           "pr": int(m.group(1)), "state": m.group(2)})
        for m in ON_MAIN.finditer(line):
            claims.append({**base, "kind": "on_main", "repo": REPO_WORDS.get(m.group(1) or "", default_repo), "sha": m.group(2)})
        quotes = QUOTE.findall(line)
        for m in FILE_LINE.finditer(line):
            a = m.group(2) or m.group(4)
            b = m.group(3) or m.group(5) or a
            claims.append({**base, "kind": "file_line", "path": m.group(1).strip("`"),
                           "from": int(a), "to": int(b), "quotes": quotes})
        ids = MSG.findall(line)
        if ids:
            clock = CLOCK.search(line)
            claims.append({**base, "kind": "message", "ids": ids, "quotes": quotes,
                           "jon": bool(re.search(r"\bJon\b|\bthe owner\b", line)),
                           "clock": clock_of(clock) if clock else None})
        if MEASURED.search(line):
            claims.append({**base, "kind": "measured"})
    for pm in re.finditer(r"\S(?:[^\n]|\n(?![ \t]*\n))*", text):
        para = pm.group(0)
        for m in RULE21.finditer(para):
            ln = text.count("\n", 0, pm.start() + m.start()) + 1
            named = sum(bool(re.search(p, para, re.I)) for p in RULE21_CHECKS)
            claims.append({"src": src, "line": ln, "text": para.strip()[:300], "kind": "rule21",
                           "checks_named": named,
                           "not_done_named": bool(re.search(r"not done|were not|was not|not run", para, re.I))})
    return claims


def clock_of(m):
    g = [x for x in m.groups() if x is not None]
    return ":".join(g[:2]), (g[2] if len(g) > 2 else None)


def norm(s):
    return re.sub(r"\s+", " ", s).strip().lower()


def check(c, gh, root, messages, as_of):
    k = c["kind"]
    if k == "merged":
        pr = gh.pr(c["repo"], c["pr"])
        if pr is None:
            return "wrong", f"{c['repo']} has no PR #{c['pr']}"
        if not pr.get("merged_at") or parse_time(pr["merged_at"]) > as_of:
            return "wrong", f"PR #{c['pr']} is not merged"
        msha = pr.get("merge_commit_sha") or ""
        if not msha.startswith(c["sha"]):
            return "wrong", f"PR #{c['pr']} merged as {msha[:7]}, not {c['sha']}"
        return "pass", f"merged {pr['merged_at']} as {msha[:7]}"
    if k == "head":
        shas = gh.pr_commits(c["repo"], c["pr"])
        if shas is None or not shas:
            return "wrong", f"{c['repo']} has no PR #{c['pr']}"
        return ("pass", "a commit of the PR") if any(s.startswith(c["sha"]) for s in shas) else \
            ("wrong", f"{c['sha']} is not a commit of PR #{c['pr']}")
    if k == "state":
        pr = gh.pr(c["repo"], c["pr"])
        if pr is None:
            return "wrong", f"{c['repo']} has no PR #{c['pr']}"
        merged = bool(pr.get("merged_at")) and parse_time(pr["merged_at"]) <= as_of
        closed = bool(pr.get("closed_at")) and parse_time(pr["closed_at"]) <= as_of
        now = "merged" if merged else "closed" if closed else "open"
        if now == c["state"]:
            return "pass", f"PR #{c['pr']} is {now}"
        if c["state"] == "open" and now in ("merged", "closed"):
            return "stale", f"PR #{c['pr']} is {now} now"
        return "wrong", f"PR #{c['pr']} is {now}"
    if k == "on_main":
        res = gh.on_main(c["repo"], c["sha"])
        if res is None:
            return "wrong", f"{c['sha']} is not a commit of {c['repo']}"
        return ("pass", "on main") if res else ("wrong", f"{c['sha']} is not on {c['repo']} main")
    if k == "file_line":
        p = root / c["path"]
        if not p.is_file():
            top = c["path"].split("/")[0]
            if "/" in c["path"] and (root / top).is_dir():
                return "wrong", f"{c['path']} does not exist"
            return "unverifiable", "outside this repository"
        lines = p.read_text(errors="replace").splitlines()
        if c["to"] > len(lines) or c["from"] < 1:
            return "wrong", f"{c['path']} has {len(lines)} lines"
        window = norm(" ".join(lines[max(0, c["from"] - 4):c["to"] + 3]))
        missing = [q for q in c["quotes"] if norm(q) not in window]
        if missing and len(missing) == len(c["quotes"]):
            return "wrong", f"quoted words not at lines {c['from']}-{c['to']}: {missing[0][:60]}"
        return "pass", f"lines {c['from']}-{c['to']} exist" + (", quote found" if c["quotes"] else "")
    if k == "message":
        if messages is None:
            return "unverifiable", "no message dump in this run (CI cannot read project messages)"
        problems = []
        bodies = []
        for mid in c["ids"]:
            m = messages.get(mid)
            if m is None:
                problems.append(f"{mid[:16]}… not found")
                continue
            bodies.append(norm(m.get("body", "")))
            is_jon = m.get("author") == "user" and not AGENT_TAG.search(m.get("body", ""))
            if c["jon"] and len(c["ids"]) == 1 and not is_jon:
                problems.append(f"{mid[:16]}… is not Jon's own message")
            if c["clock"] and len(c["ids"]) == 1:
                hm, ss = c["clock"]
                t = parse_time(m["created_at"])
                if t.strftime("%H:%M") != hm or (ss and t.strftime("%S") != ss):
                    problems.append(f"{mid[:16]}… was at {t.strftime('%H:%M:%S')}, not {hm}{':' + ss if ss else ''}")
        for q in c["quotes"]:
            if bodies and not any(norm(q) in b for b in bodies):
                problems.append(f"quote not in the cited message: {q[:60]}")
        return ("wrong", "; ".join(problems)) if problems else ("pass", "id, author, time and quotes match")
    if k == "measured":
        return "unverifiable", "re-run not built in v0.1; counted"
    if k == "rule21":
        if c["checks_named"] >= 4 or (c["checks_named"] >= 1 and c["not_done_named"]):
            return "pass", f"{c['checks_named']} of 4 checks named"
        return "wrong", f"negative claim names {c['checks_named']} of the 4 rule-21 checks and none as not done"
    return "unverifiable", "unknown kind"


def corrections(root, gh, default_repo):
    """D1: every approval-facts line in docs/decisions/CORRECTIONS.md matches GitHub."""
    p = root / "docs/decisions/CORRECTIONS.md"
    out = []
    if not p.is_file():
        return out
    for n, line in enumerate(p.read_text().splitlines(), 1):
        for m in CORR.finditer(line):
            pr, approved, mid, head, merged = int(m.group(1)), parse_time(m.group(2)), m.group(3), m.group(4), m.group(5)
            c = {"src": "docs/decisions/CORRECTIONS.md", "line": n, "kind": "corrections", "text": m.group(0),
                 "repo": default_repo, "pr": pr}
            try:
                prj = gh.pr(default_repo, pr)
                shas = gh.pr_commits(default_repo, pr)
                if prj is None:
                    r = ("wrong", f"no PR #{pr}")
                elif not (prj.get("merge_commit_sha") or "").startswith(merged):
                    r = ("wrong", f"merged as {(prj.get('merge_commit_sha') or '')[:7]}, not {merged}")
                elif not any(s.startswith(head) for s in shas):
                    r = ("wrong", f"head {head} is not a commit of PR #{pr}")
                elif prj.get("merged_at") and approved > parse_time(prj["merged_at"]):
                    r = ("wrong", f"approved after the merge ({prj['merged_at']})")
                else:
                    r = ("pass", "merge commit, head and order match")
            except Unverifiable as e:
                r = ("unverifiable", str(e))
            c["result"], c["detail"] = r
            out.append(c)
    return out


def added_lines(root, base):
    """Text added by this change in Markdown files: {path: text with removed lines blanked}."""
    diff = subprocess.run(["git", "-C", str(root), "diff", "--unified=0", f"{base}...HEAD", "--", "*.md"],
                          capture_output=True, text=True, check=True).stdout
    files, cur, lines = {}, None, {}
    for l in diff.splitlines():
        if l.startswith("+++ "):
            cur = l[6:] if l.startswith("+++ b/") else None
            if cur:
                files[cur] = {}
        elif l.startswith("@@") and cur:
            m = re.search(r"\+(\d+)", l)
            lineno = int(m.group(1))
        elif l.startswith("+") and cur:
            files[cur][lineno] = l[1:]
            lineno += 1
    out = {}
    for f, ls in files.items():
        if ls:
            n = max(ls)
            out[f] = "\n".join(ls.get(i, "") for i in range(1, n + 1))
    return out


def report(claims, as_of, md, jsonl):
    order = {"wrong": 0, "stale": 1, "unverifiable": 2, "pass": 3}
    claims.sort(key=lambda c: (order[c["result"]], c["src"], c["line"]))
    counts = {k: sum(c["result"] == k for c in claims) for k in order}
    lines = [f"# Fabrication check, as of {as_of.isoformat().replace('+00:00', 'Z')}", "",
             " · ".join(f"{k} {v}" for k, v in counts.items()), "",
             "| Result | Where | Kind | Claim | Detail |", "|---|---|---|---|---|"]
    for c in claims:
        cell = c["text"].replace("|", "\\|")[:160]
        lines.append(f"| {c['result']} | {c['src']}:{c['line']} | {c['kind']} | {cell} | {c['detail'].replace('|', '/')} |")
    text = "\n".join(lines) + "\n"
    if md:
        pathlib.Path(md).write_text(text)
    if jsonl:
        with open(jsonl, "w") as f:
            for c in claims:
                f.write(json.dumps(c, default=str) + "\n")
    return text, counts


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--repo", required=True, help="OWNER/NAME of the repository this run checks")
    ap.add_argument("--pr", type=int, help="check this PR's body")
    ap.add_argument("--diff", help="check lines added since this base ref in Markdown files")
    ap.add_argument("--file", action="append", default=[], help="check a whole text file")
    ap.add_argument("--corrections", action="store_true", help="D1: check CORRECTIONS.md approval facts")
    ap.add_argument("--messages", help="JSON dump of project messages: list of {id, author, created_at, body}")
    ap.add_argument("--as-of", help="pinned time for every lookup (default: now)")
    ap.add_argument("--md")
    ap.add_argument("--jsonl")
    ap.add_argument("--api", default=os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    a = ap.parse_args(argv)
    as_of = parse_time(a.as_of) if a.as_of else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    owner, own = a.repo.split("/", 1)
    root = pathlib.Path(a.root)
    gh = GitHub(owner, own, os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"), a.api)
    messages = None
    if a.messages:
        messages = {m["id"]: m for m in json.loads(pathlib.Path(a.messages).read_text())}
    sources = {}
    if a.pr:
        try:
            pr = gh.pr(own, a.pr)
            sources[f"PR #{a.pr} body"] = (pr or {}).get("body") or ""
        except Unverifiable as e:
            print(f"PR body not read: {e}", file=sys.stderr)
    if a.diff:
        sources.update(added_lines(root, a.diff))
    for f in a.file:
        sources[f] = pathlib.Path(f).read_text(errors="replace")
    claims = []
    for src, text in sources.items():
        for c in extract(text, src, own):
            try:
                c["result"], c["detail"] = check(c, gh, root, messages, as_of)
            except Unverifiable as e:
                c["result"], c["detail"] = "unverifiable", str(e)
            claims.append(c)
    if a.corrections:
        claims += corrections(root, gh, own)
    text, counts = report(claims, as_of, a.md, a.jsonl)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(text)
    return 1 if counts["wrong"] else 0


if __name__ == "__main__":
    sys.exit(main())
