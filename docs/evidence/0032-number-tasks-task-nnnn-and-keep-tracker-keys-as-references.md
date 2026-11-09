---
record: D-0032
batch: RB-0174 (task IDs, light research)
researched: 2026-11-09
method: count of BL citations in the four repositories; reading of the notebook's task notes, ORGANIZE 1.22 and its Obsidian settings; reading of five published pages on Obsidian task tools and tracker keys
checks: none yet; an independent check by a reviewing agent is still to do
---

# Evidence for D-0032: task numbers and tracker references

This file summarises the light research behind D-0032. The owner asked for a little research, so batch RB-0174 has no ledger.

## Question

What should replace `BL-NNNN` for tasks, so that tasks from other trackers can be synced into the notebook later?

## Findings

1. **Tasks are one note each, with their state in front matter** (sourced: notebook `99-meta/ORGANIZE.md`, version 1.22; `01-notes/01t-tasks/01t-tasks.md`). There are 190 task notes.
2. **`BL-NNNN` is cited about 2,200 times in about 290 notebook files, 64 times in 38 central-hub files, and 4 times in 2 INPARA files** (measured 2026-11-09 with `grep -E 'BL-[0-9]{4}'`, `.git` excluded). The Library was not counted.
3. **The notebook's vault already has the tools for task views** (measured from `.obsidian/`): the core Bases plugin and Properties are on, and the Tasks, Dataview and Kanban community plugins are listed.
4. **Bases builds table, list, cards, kanban and map views from front matter properties** and saves them in `.base` files [1]. So the task notes as they are can be shown as views without a new plugin (inferred).
5. **The TaskNotes plugin uses the same shape as the notebook: one note per task with YAML front matter,** lets its field names be mapped onto existing keys, and builds its views on Bases [2]. A comparison page says one note per task suits metadata-heavy, linkable tasks, while one line per task (the Tasks plugin) suits quick inline capture [3].
6. **Linear issue identifiers are a team key plus a number,** such as `CEN-123` [4]. GitHub cites issues as `owner/repo#number` [5].
7. **A tracker key can change when the item moves** (model knowledge, not checked: a Linear issue moved to another team takes that team's key; a GitHub issue transferred to another repository takes a number there). Each tracker numbers on its own, so two trackers can both have `123` (inferred).

## How the decision used it

(Written from the record.)

Finding 7 is why the source key is kept as a reference and not used as the ID (rules 2 and 3). Finding 6 sets the `<system>:<key>` shape. Findings 3 to 5 show that the views can come from the front matter the notes already have, so the record changes only the ID and adds one field. Finding 2 sizes the rename.

## Limits

- Finding 7 is model knowledge; neither tracker's documentation on moving items was fetched.
- No sync tool was tested, and the Obsidian properties editor's handling of `external-refs` was not tried.
- The Library's own `BL-NNNN` citations were not counted.

## References

Relied on:

1. Obsidian Help, "Bases". <https://obsidian.md/help/bases>
2. TaskNotes, "Core concepts". <https://tasknotes.dev/core-concepts/>
3. Obsidian Stats, "Tasks vs TaskNotes: one line vs one note" (2026-07-03). <https://www.obsidianstats.com/posts/2026-07-03-tasks-vs-tasknotes-one-line-vs-one-note>
4. linear-cli, package `identifiers`. <https://pkg.go.dev/github.com/joa23/linear-cli/internal/linear/identifiers>
5. GitHub Docs, "Autolinked references and URLs". <https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls>

All five fetched 2026-11-09.
