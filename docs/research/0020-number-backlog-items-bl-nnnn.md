---
record: D-0020
batch: RB-0077
researched: 2026-10-23
method: repository mining of the decision map, the backlog and their citations; reading of six published tracker and record practices; claim ledger; independent check
checks: an independent check recounted the tables, read the ledger locators and fetched the sources; its corrections are in the ledger and the option it added is in the synthesis. The recall check parsed 49 of 49 decision-map rows and 110 of 110 backlog rows
---

# Evidence for D-0020: backlog item numbers

This file summarises the research behind D-0020. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

The decision map and the backlog label their rows with one capital letter plus a number (`D1`, `K1`, `S7`), with lowercase word labels, or with other uppercase labels. How should these rows be identified, given the ID family registry?

## Findings

1. **The decision map has 49 rows** with one-letter labels: A 14, I 12, S 7, W 6, D 4, K 4 and P 2. An agent made the scheme on 2026-10-10 (measured, sourced).
2. **The backlog has 110 rows in three label styles.** 25 reuse a decision-map label, 83 use a lowercase word label, and 2 use other uppercase labels (measured).
3. **24 decision-map rows are not in the backlog,** and 15 of them are still open, proposed or parked (measured). One of the 15, D1, is already covered by the backlog's repo-layout row. The other 9 are decided or applied.
4. **The one-letter labels collide by eye.** `D1` (repo layout) looks like `D-0001` (inferred). Other files use their own D1 to D5, an earlier proposal called A2, and other meanings of K1 (sourced). D-0003 records 21 clashing labels, all with one-letter prefixes, and `P1` with 7 meanings (sourced).
5. **None of the letters could be registered,** because a prefix needs at least two characters (inferred from D-0018 rule 2).
6. **Trackers give each item one key from one sequence and keep the topic in the title** (inferred from references 1 to 5). Jira forms a key from a space key and a sequential number [1]. GitHub cites issues and pull requests by number [2]. Kubernetes prefixes each enhancement proposal with its tracking issue number [3]. Python PEPs take the next number not already used [4]. Rust RFCs are not numbered until their pull request opens [5].
7. **Decision-record practice numbers records too** (sourced). MADR names records `NNNN-title-with-dashes` and lists statuses from proposed to superseded [6].
8. **Renaming the labels is a large change** (measured). The backlog's word labels are cited about 370 times as `BACKLOG.md:<label>`. Map IDs are cited 236 times as "DECISION-MAP" plus an ID (this counts copies twice and includes 11 in the chat archive, which is never renamed), 47 times as `DECISION-MAP#` plus an ID, and 74 times in the backlog table. A map drawn from the table has 118 nodes keyed by label. The scripts that draw the backlog have no label-specific code, so a rename by script is possible (inferred).

## How the decision used it

(Written from the record, not from the batch.)

D-0020 gives every backlog item a `BL-NNNN` number, as the trackers in finding 6 do. That ends the look-alike in finding 4 and gives the rows a prefix that passes the rule in finding 5. Every decision-map row is added to the backlog first (finding 3). The owner asked for the options to be weighed without the renaming cost in finding 8, and on that basis numbers were recommended.

## Limits

- Citations of bare one-letter labels outside the backlog could not be counted reliably, because the same letters mean other things (finding 4).
- Standards bodies (IETF, W3C) and practitioner writing on decision logs were planned but not searched. The six tracker and record sources met the stop rule.
- The counts in finding 8 include copies of the same files in two places. The first count script missed the chat archive's location; the independent check corrected the figures.
- The ISO/IEC/IEEE vocabulary (SEVOCAB) was planned but not searched, and the skills check was not run.

## References

Relied on (the decision depends on these):

1. Atlassian, "What is a work item?" (work item keys). <https://support.atlassian.com/jira-software-cloud/docs/what-is-an-issue/>
2. GitHub Docs, "Autolinked references and URLs". <https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls>
3. Kubernetes enhancements, KEP README. <https://github.com/kubernetes/enhancements/blob/master/keps/README.md>
4. Python, PEP 1. <https://peps.python.org/pep-0001/>
5. Rust RFCs, README. <https://github.com/rust-lang/rfcs/blob/master/README.md>

Background (read, not relied on):

- [6] MADR, "Markdown Architectural Decision Records". <https://adr.github.io/madr/>

All six fetched during the batch (2026-10-23).

## Working files

The full ledger (31 claims), the recall check and the independent check are kept in the owner's private research archive as batch RB-0077. They are not needed to read this file.
