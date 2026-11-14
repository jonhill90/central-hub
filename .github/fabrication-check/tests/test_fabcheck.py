#!/usr/bin/env python3
"""Tests for fabcheck.py. Fixtures copy the shapes of real claims but use made-up PR numbers,
SHAs, message ids and names (Council A): no hostnames, private names or the owner's words.

  python3 -I .github/fabrication-check/tests/test_fabcheck.py
"""
import datetime as dt, json, pathlib, sys, tempfile, unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import fabcheck as fc  # noqa: E402

AS_OF = fc.parse_time("2026-01-02T12:00:00Z")
MERGE = "aaaaaaa1111111111111111111111111111111aa"
HEAD = "bbbbbbb2222222222222222222222222222222bb"
OPEN_HEAD = "ccccccc3333333333333333333333333333333cc"
MID = "cmsg_00TESTtestTESTtestTESTtest01"
MID_AGENT = "cmsg_00TESTtestTESTtestTESTtest02"


class FakeGitHub(fc.GitHub):
    """Answers from a table instead of the network. A path missing from the table is a 404;
    a path mapped to None raises like a network error."""

    def __init__(self, table):
        super().__init__("example", "demo-repo")
        self.table = table

    def get(self, path):
        if path in self.table:
            if self.table[path] is None:
                raise fc.Unverifiable("lookup failed: URLError")
            return 200, self.table[path]
        return 404, None


TABLE = {
    "/repos/example/demo-repo/pulls/10": {"merged_at": "2026-01-01T10:00:00Z", "closed_at": "2026-01-01T10:00:00Z",
                                          "merge_commit_sha": MERGE, "state": "closed", "body": ""},
    "/repos/example/demo-repo/pulls/10/commits?per_page=100": [{"sha": HEAD}],
    "/repos/example/demo-repo/pulls/11": {"merged_at": None, "closed_at": None, "merge_commit_sha": None,
                                          "state": "open", "body": "#10 merged as aaaaaaa."},
    "/repos/example/demo-repo/pulls/11/commits?per_page=100": [{"sha": OPEN_HEAD}],
    "/repos/example/demo-repo": {"default_branch": "main"},
    f"/repos/example/demo-repo/compare/{MERGE[:7]}...main": {"status": "ahead"},
    "/repos/example/demo-repo/compare/ddddddd...main": {"status": "diverged"},
    "/repos/example/demo-repo/pulls/12": None,  # network error
}

MESSAGES = {
    MID: {"id": MID, "author": "user", "created_at": "2026-01-01T09:15:30Z", "body": "keep the blue widget for now"},
    MID_AGENT: {"id": MID_AGENT, "author": "user", "created_at": "2026-01-01T09:20:00Z",
                "body": "[AGENT · Other → This] keep the blue widget for now"},
}


def run(text, root=None, messages=MESSAGES):
    gh = FakeGitHub(TABLE)
    root = pathlib.Path(root or HERE)
    out = []
    for c in fc.extract(text, "fixture", "demo-repo"):
        try:
            c["result"], c["detail"] = fc.check(c, gh, root, messages, AS_OF)
        except fc.Unverifiable as e:
            c["result"], c["detail"] = "unverifiable", str(e)
        out.append(c)
    return out


def one(text, kind, **kw):
    got = [c for c in run(text, **kw) if c["kind"] == kind]
    assert len(got) == 1, (text, got)
    return got[0]["result"], got[0]["detail"]


class Extract(unittest.TestCase):
    def test_merge_and_head(self):
        r = run("D-0001 merged as aaaaaaa (#10, head bbbbbbb).")
        kinds = sorted(c["kind"] for c in r)
        self.assertEqual(kinds, ["head", "merged"])

    def test_repo_word(self):
        c = fc.extract("notebook #367 (e7dd1ab)", "x", "demo-repo")[0]
        self.assertEqual(c["repo"], "agent-notebook")

    def test_main_sha_repo(self):
        cs = fc.extract("measured on central-hub main aaaaaaa and agent-notebook main bbbbbbb", "x", "demo-repo")
        self.assertEqual([(c["repo"], c["sha"]) for c in cs], [("central-hub", "aaaaaaa"), ("agent-notebook", "bbbbbbb")])

    def test_merged_paren(self):
        c = fc.extract("evidence merged (#10, aaaaaaa).", "x", "demo-repo")
        self.assertEqual([(x["kind"], x["pr"], x["sha"]) for x in c], [("merged", 10, "aaaaaaa")])

    def test_line_numbers(self):
        cs = fc.extract("a\n\nb\n#10 merged as aaaaaaa", "x", "demo-repo")
        self.assertEqual(cs[0]["line"], 4)


class Checks(unittest.TestCase):
    def test_merged_pass(self):
        self.assertEqual(one("#10 merged as aaaaaaa", "merged")[0], "pass")

    def test_merged_wrong_sha(self):
        self.assertEqual(one("#10 merged as eeeeeee", "merged")[0], "wrong")

    def test_merged_but_open(self):
        self.assertEqual(one("#11 merged as aaaaaaa", "merged")[0], "wrong")

    def test_head_pass_and_wrong(self):
        self.assertEqual(one("#11 (ccccccc)", "head")[0], "pass")
        self.assertEqual(one("#11 (bbbbbbb)", "head")[0], "wrong")

    def test_state(self):
        self.assertEqual(one("#11 is open", "state")[0], "pass")
        self.assertEqual(one("#10 is open", "state")[0], "stale")
        self.assertEqual(one("#11 merged yesterday", "state")[0], "wrong")

    def test_missing_pr_in_own_repo_is_wrong(self):
        self.assertEqual(one("#99 merged as aaaaaaa", "merged")[0], "wrong")

    def test_network_error_is_unverifiable(self):  # Council C1
        self.assertEqual(one("#12 merged as aaaaaaa", "merged")[0], "unverifiable")

    def test_other_repo_404_is_unverifiable(self):  # no access is not proof of absence
        self.assertEqual(one("inpara #5 merged as aaaaaaa", "merged")[0], "unverifiable")

    def test_on_main(self):
        self.assertEqual(one("measured on main aaaaaaa", "on_main")[0], "pass")
        self.assertEqual(one("measured on main ddddddd", "on_main")[0], "wrong")

    def test_file_line(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d, "docs")
            p.mkdir()
            (p / "a.md").write_text("one\ntwo\nthe blue widget stays\nfour\n")
            self.assertEqual(one('docs/a.md:3 says "the blue widget stays"', "file_line", root=d)[0], "pass")
            self.assertEqual(one('docs/a.md:3 says "the red widget goes away"', "file_line", root=d)[0], "wrong")
            self.assertEqual(one("docs/a.md:9", "file_line", root=d)[0], "wrong")
            self.assertEqual(one("docs/b.md:1", "file_line", root=d)[0], "wrong")
            self.assertEqual(one("elsewhere/c.md:1", "file_line", root=d)[0], "unverifiable")

    def test_message(self):
        ok = f'The owner at 09:15:30 UTC ({MID}): "keep the blue widget for now"'
        self.assertEqual(one(ok, "message")[0], "pass")
        bad_time = f'The owner at 09:16 UTC ({MID})'
        self.assertEqual(one(bad_time, "message")[0], "wrong")
        bad_quote = f'The owner ({MID}): "remove the blue widget today"'
        self.assertEqual(one(bad_quote, "message")[0], "wrong")

    def test_agent_tag_is_not_jon(self):  # Council C2
        self.assertEqual(one(f"Jon said so ({MID_AGENT})", "message")[0], "wrong")

    def test_message_without_dump(self):
        self.assertEqual(one(f"Jon ({MID})", "message", messages=None)[0], "unverifiable")

    def test_rule21(self):
        self.assertEqual(one("Single sign-on is only in the paid edition.", "rule21")[0], "wrong")
        good = ("Single sign-on is only in the paid edition. Checks: web search, GitHub issue search, "
                "the docs index; hands-on was not done.")
        self.assertEqual(one(good, "rule21")[0], "pass")

    def test_measured_counted(self):
        self.assertEqual(one("30 files [measured]", "measured")[0], "unverifiable")


class Corrections(unittest.TestCase):
    def test_d1(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d, "docs/decisions")
            p.mkdir(parents=True)
            good = f"PR #10: approved 2026-01-01T09:15:30Z ({MID}), head bbbbbbb; merged as aaaaaaa."
            late = f"PR #10: approved 2026-01-01T11:00:00Z ({MID}), head bbbbbbb; merged as aaaaaaa."
            wrong_head = f"PR #10: approved 2026-01-01T09:15:30Z ({MID}), head ccccccc; merged as aaaaaaa."
            (p / "CORRECTIONS.md").write_text("\n".join([good, late, wrong_head]) + "\n")
            res = [c["result"] for c in fc.corrections(pathlib.Path(d), FakeGitHub(TABLE), "demo-repo")]
            self.assertEqual(res, ["pass", "wrong", "wrong"])


class Report(unittest.TestCase):
    def test_exit_code_and_as_of(self):
        claims = run("#10 merged as eeeeeee")
        text, counts = fc.report(claims, AS_OF, None, None)
        self.assertIn("as of 2026-01-02T12:00:00Z", text)
        self.assertEqual(counts["wrong"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
