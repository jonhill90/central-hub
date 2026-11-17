---
title: Merge a pull request with the box's sweep
status: draft
kind: manual
trigger: each time a PR's head has CI green, the reviewer's clearance and the three council passes (D-0042)
runner: the orchestrator session records the passes over ssh; the box's timer merges
outcome: the PR is squash-merged at the head that was passed, and the PR carries a comment listing the recorded passes and the merge commit
needs: the box's limit install of the merge machinery (D-0042 rule 6, the owner's tap), the box's runner and App key (set-up-the-agent-box.md)
private-values: []
files: [hosts/ansible/roles/agent_box/files/pr-merge.sh, hosts/ansible/roles/agent_box/files/pr-merge-verdict.py, hosts/ansible/roles/agent_box/files/pass-record.sh, hosts/ansible/roles/agent_box/templates/pr-merge-sweep.service.j2, hosts/ansible/roles/agent_box/files/runner-job-started.sh]
last-tested: not yet run
superseded-by:
---

# Merge a pull request with the box's sweep

**Status:** in use. Written 2026-11-14 with the sweep ([D-0056](../decisions/0056-merge-with-a-sweep-on-the-box-in-place-of-the-merge-job.md)). The sweep, `pr-merge check`, the verdict script and `pass-record` reached the box by two controller runs of the agent box playbook on 2026-11-15: the first at 05:40 to 05:44 UTC (owner card row 19a), the second at 08:21 to 08:23 UTC at main e0a9b3e (row 19d), which also put #367's owner path on the box (run times as the orchestrator reported them). The workflow `merge.yml` that D-0042 rule 2 first named was removed, and D-0042 rule 2 and AGENTS.md rule 2 name the sweep. This page keeps its old file name because D-0042 links to it.

A cloud session cannot start a GitHub workflow here (the GitHub integration answers 403, measured 2026-11-14), so the merge does not run by dispatch. A timer on the agent box runs `pr-merge.sh sweep` as the keys user every few minutes. It merges a PR only when that PR's exact head holds four recorded passes: the reviewer's clearance and the passes of councils A, B and C. It is not GitHub's auto-merge, and it never passes `--admin`.

## Before you start

1. CI is green on the PR's head. The sweep checks it again itself: open, not a draft, base `main`, a clean merge, every check on the head completed and passed or skipped, at least one ran, fewer than 3000 files (the most GitHub lists for a PR; a server not yet updated by the tapped apply still stops at 100).
2. You have read, in the project's chat, the reviewer's clearance of that exact head and a pass from each of councils A, B and C for that exact head. A pass for an older head does not count: the ledger is a file per head.

## Record the passes

The orchestrator records each pass over ssh, one call per role:

```text
pass-record add <role> jonhill90/<repo> <pr number> <40-character head> <relay message id> <relay time> orchestrator
```

- `<role>` is one of `reviewer`, `council-a`, `council-b`, `council-c`, `owner-tap`. `<relay message id>` is a `cmsg_` id and `<relay time>` an ISO time like `2026-11-14T13:00:00Z`. A wrong argument exits 2 and writes nothing.
- The builder lane records only when the orchestrator's session cannot reach the box, and never for a PR the builder wrote (the wrapper reads the PR body's `Author-Lane:` line, any label such as `OpenBao thread`, and refuses a builder record when the label contains the word `builder` in any case, as in `agent box builder`, or cannot be read).
- One identity records all four roles, so a ledger line is the recorder's word and the relay id it gave, not four separate judgements. The sweep posts every line on the PR when it merges, for the owner to check.
- `pass-record show jonhill90/<repo> <head>` prints a head's ledger.

expect: `pass-record: <role> recorded for <repo>#<pr> <head7>`.

## What happens next

The timer's next turn reads the ledger. With four roles recorded and every check green, it squash-merges pinned to the head and comments on the PR. Anything else, it skips and tries again next turn. Read `journalctl -t pr-merge -u pr-merge-sweep` on the box for the reasons, or run the read-only check yourself:

```text
pr-merge check jonhill90/<repo> <pr number> <40-character head>
```

- `GREEN`: the sweep will merge it at its next turn.
- `NOT GREEN: ...`: every reason is printed (a missing role, a failed check, a moved head, a ledger that does not parse). Fix it or wait; a new head needs its own four passes.
- `OWNER: rule 11 PR ... needs an owner-tap line`: printed by the verdict the box runs until D-0059 is accepted and the box has installed the new verdict. The PR changes a file that guards the merge itself (D-0042 rule 11, D-0056 rule 4), or a record that supersedes or amends D-0042 or D-0034. The orchestrator records the owner's tap as role `owner-tap` with the decide event id, and the sweep merges it. Once D-0059's verdict is installed, no file needs an `owner-tap` line and the verdict no longer prints `OWNER:`.
- A changed record or standard whose content at the head cannot be read is never green (only a PR that removes the file may skip it), and a failed read of it stops the whole evaluation, so a 5xx or rate limit skips the PR until the next turn.
- A status change to `accepted`, `rejected`, `parked` or `active` is checked too (D-0042 rule 3): `approved-by: agents` for an acceptance, an `approved-commit` with four passes of its own, and the PR's net change equal to the approved commit's apart from the status, date and `accepted-evidence` lines and the index row. If it does not fit, reshape the PR (acceptance as its own PR on top of the passed proposal head) and record passes again.
- An acceptance with `approved-by: owner` is the owner's own card tap, not a fold-in of an agents' pass. It is GREEN only when the PR's ledger holds an `owner-tap` line whose relay ref equals the record's `approval-ref` (the decide event id of the tap, the same id the orchestrator records for any owner-tap line), the PR's net change is the owner's approved commit's net change (when the record names an `approved-commit`, the content commit the card showed; apart from the acceptance fields and the index row, the same compare an agents' fold-in uses) or, with no `approved-commit`, nothing but the acceptance fields, and the head has its four passes. No passes on the `approved-commit` are needed. One record per PR: a PR that accepts two owner-approved records is `NOT GREEN`, because the second record's changes count as extra changes for the first. A different relay ref, no tap line, an empty `approval-ref`, an extra changed line or file, or an unreadable compare is `NOT GREEN`. The verdict prints `NOTE: <record> is accepted on the owner's card tap <ref>`.

## Merge from the Mac, while the sweep is not installed

`hosts/wrappers/mac/merge-checked.sh OWNER/REPO PR HEAD` is the only merge the Mac may run on an allow line. It asks the box for the verdict (`pr-merge check` over ssh, so one verdict and one ledger), merges only when that says `GREEN` and the box says `HALT: clear` (`pr-merge check` prints `HALT: set` or `HALT: clear` on every run, as the keys user; the Mac cannot read the flag's folder, so the wrapper never guesses from an exit code and refuses on anything but exactly `HALT: clear`), prints the head's ledger with its pass times in its report (the Mac merge posts no PR comment, unlike the sweep), and again just before the merge (two reads, each matched as whole lines), and then runs `gh pr merge --squash --match-head-commit HEAD`. It refuses a repository outside the four `pass-record` accepts, a checkout that is not at `origin/main` or has tracked changes, and any PR whose verdict is `OWNER` (a rule 11 file) or not green. A refused PR waits for the sweep; the raw `gh pr merge` is never the fallback. The wrapper is no stronger than the sweep, because the ledger is the recorder's own word. It is a rule 11 file, so loosening it needs the owner's tap. It also refuses any rule 11 PR, even one with an owner-tap line, because the verdict prints a `NOTE: rule 11 PR` line for it. It runs from its own checkout on the Mac, one that no pin wrapper touches, and fast-forwards that checkout to `origin/main` once, then starts again from the new copy; a checkout that has diverged or has tracked changes is refused. Two things must hold before the Mac's allow line for it is written: the box runs this change's `pr-merge-verdict.py` or later (the wrapper requires the line `NOTE: verdict v2` on every run and `LEDGER: reviewer council-a council-b council-c` on a GREEN, and refuses without them, so until the tapped install puts this change on the box, Mac merges are refused and wait; an older `pr-merge` prints GREEN with no ledger and no rule 11 check), and a non-interactive `ssh` to the box finds `pr-merge` (not measured; if it does not, the wrapper refuses, which is safe). The allow line itself is not part of this change.

## Stop the sweep (D-0042 rule 8)

```text
pass-record halt <relay message id> <orchestrator|builder|reviewer|council-a|council-b|council-c>
pass-record resume <relay message id> orchestrator
```

While the flag exists, the sweep merges nothing, including a merge it was about to make. The wrapper accepts `resume` only with the recorder `orchestrator`, so a halt the orchestrator relays from the owner isn't lifted by another lane's call. Any session can name itself the orchestrator, so the flag stops a mistake, not a determined agent; the owner's own stop is `systemctl stop pr-merge-sweep.timer` on the box from the controller.

## What the green checks do not prove

A PR that edits the workflows or scripts that make its own checks reports green on its own copy. The sweep does not guard those edits; the reviewer's clearance reads them. The sweep's output says `NOTE: this PR edits N files under .github/` with their names.

## Workflows that run on the box

The runner's job-started hook (`runner-job-started.sh`) lists each workflow file whose jobs run on the box (`lab-redeploy-dev.yml`, `lab-tailnet.yml`) with its sha256, fetches the file at the run's commit from the public repository and refuses a job whose file has another hash or cannot be fetched. A merged edit to one of these does nothing on the box until a tapped install updates the list. CI runs `.github/hosts-check/check-hook-allowlist.py`, so a PR that edits a box workflow without updating the list, or adds a `uses:` step to one, fails.

## Not measured yet

- That a session's safety check lets `pass-record add` through over ssh (only `rebuild.sh` and `pr-merge.sh check` were run).
- That the hook can fetch a workflow by commit and the box can reach `raw.githubusercontent.com`; the hook fails closed.
- Whether the ruleset on `main` accepts the App's squash-merge.
- The installed copies of the scripts, until the owner's install.
