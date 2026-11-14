# Fabrication check

`fabcheck.py` looks up the pointers an agent writes, so a wrong one is caught by code, not by a reader. No model decides any result.

| It finds | It checks |
|---|---|
| `#N … merged as <sha>`, `merged as <sha> (#N)`, `merged (#N, <sha>)` | the PR is merged, and its merge commit starts with the SHA |
| `#N … head <sha>`, `#N (<sha>)` | the SHA is one of the PR's commits |
| `#N is open`, `#N merged`, `#N closed` | the PR's state at the run's as-of time; a claim of `open` on a PR that has since merged or closed is `stale` |
| `<repo> main <sha>` | the SHA is on that repository's main |
| `path:line`, `path lines a-b`, with any "quoted words" on the line | the file and lines exist in the checkout; the quoted words are within three lines of the range |
| `cmsg_…` with a time, "Jon" or "the owner", and quoted words | only when a message dump is given (`--messages`), as the hourly checkpoint does: the id exists, the time matches to the minute, the quote is in the body, and a body that starts with `[AGENT ·` or says it is not Jon's own words is never counted as Jon's |
| a "not supported", "not documented", "not available" or "only in the paid …" sentence | its paragraph names the four rule-21 checks, or says which were not done |
| `[measured]` | counted only; a re-run is not built yet |
| `PR #N: approved <time> (<cmsg>), head <sha>; merged as <sha>` in `docs/decisions/CORRECTIONS.md` (`--corrections`) | the merge commit, the head and the approval coming before the merge all match GitHub |

Each claim gets `pass`, `wrong`, `stale` or `unverifiable`. A network, rate-limit or API error, a repository this job can't read, and a file outside the checkout all give `unverifiable`, never `wrong`. Each run pins one as-of time and prints it at the top. Only `wrong` fails the job.

## Where it runs

`.github/workflows/fabrication.yml`:

- On a pull request, it checks the PR body and the lines the PR adds to Markdown files.
- On a push to main, it checks every approval line in `CORRECTIONS.md`.
- The verifier is always the copy on main, fetched by ref, so a PR can't change the check that judges it. The PR's own copy runs only its tests.

The hourly checkpoint runs the same file over Library files and thread reports, with a dump of the project's messages.

## Run it

```sh
python3 -I .github/fabrication-check/tests/test_fabcheck.py
GH_TOKEN=… python3 -I .github/fabrication-check/fabcheck.py --root . --repo OWNER/NAME --pr 123 --diff origin/main
```

The tests use made-up PR numbers, SHAs and message ids and need no network.

## Limits

- A sentence with no pointer is not seen.
- A paraphrase is checked only for id, author and time; only quoted words are matched.
- The rule-21 pattern is a heuristic. It misses a negative claim worded another way, and it can flag a sentence that only quotes one.
- The script lives in the repository it checks. Taking it from main stops a PR from editing its own check, but anyone who merges to main can still change it. A separate repository is the follow-up for Activation gate item 2.

## Exit path

Standard-library Python and read-only GitHub REST calls; no service, no stored state. To remove it, delete this folder and `.github/workflows/fabrication.yml`.
