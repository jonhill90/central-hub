# Standards register

This register lists every standard in force: the current rule, one row per standard. A decision record in `docs/decisions/` says once why a rule was chosen and keeps that history. A standard here says what the rule is now.

The `STD-NNNN` family is registered in D-0009. Each standard is one file in this folder, named `NNNN-slug.md`. A draft has no number and is cited as `STD-TBD` (D-0009 rule 3).

## How a standard changes

- Agents only propose. A standard becomes `active` when Jon accepts its PR by naming the PR number and its head SHA, the same way decision records are accepted (D-0001).
- Any change to an `active` standard's rule needs Jon's approval again. The change goes in the same file, and git keeps the history.
- A standard is never deleted, and its number is never reused (D-0009 rule 6). One that is no longer used becomes `deprecated` or `retired` and links to whatever replaced it.

## Status words

| Status | Meaning |
|---|---|
| `proposed` | Written by an agent. Not in force. |
| `active` | Accepted by Jon. In force. |
| `deprecated` | Still allowed, but don't use it for anything new. |
| `retired` | No longer allowed. Kept for history. |

## Fields in each standard's front matter

| Field | What it holds |
|---|---|
| `id` | `STD-NNNN`. Matches the file name number. |
| `title` | What the standard is about. The topic goes here, never in the ID (D-0009 rule 7). |
| `status` | One of the status words above. |
| `scope` | What the rule applies to. |
| `owner-system` | The system that owns it, from the 13 systems (draft v0.1). |
| `why` | Jon's yes (date and time) or the decision record behind the rule. |
| `follows` | Outside standards or published guidance the rule follows. |
| `check` | A script or review step that checks the rule, or `none yet`. |
| `accepted-evidence` | Required when `status: active`. Same shape as in decision records (D-0001). |

The body holds the rule itself, worded with BCP 14 key words (RFC 2119, RFC 8174), plus an example that passes.

## Register

| ID | Title | Status | Scope | Owner system |
|---|---|---|---|---|
| STD-0001 | [VM hostnames](0001-vm-hostnames.md) | proposed | every VM and host, local or cloud | 8 Platform |
