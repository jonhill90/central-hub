---
record: D-0052
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: Jellyfin's licence file read from its repository and its about page opened; central-hub searched for every file naming it; on 2026-11-14 at about 11:55 UTC, the licence file and the about page read again, the owner's words looked up in the project decisions inbox, and the reach, image, storage and backup re-read at main 37eb02d
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0052: Jellyfin

This file summarises the research behind D-0052. It adds nothing the research and the pages listed below did not find.

## Question

Is Jellyfin free, with nothing held back behind a paywall, and how does c1 run it?

## Findings

1. **Licence.** Jellyfin's licence file is the GNU General Public License, version 2 [1] (sourced).
2. **No paid tier.** Jellyfin's about page says "There are no strings attached, no premium licenses or features, and no hidden agendas" [2] (sourced).
3. **How c1 runs it.** At main 37eb02d [3] (measured):
   - the image is `docker.io/jellyfin/jellyfin:12.2`, pinned by digest, in role `k8s_jellyfin` and the app's `values.yaml`;
   - namespace `media`, with `/config` and `/media` on claims of the default StorageClass (picks 115 and 117);
   - the off-box backup copies the whole local-path folder, and its app-level restore check uses Jellyfin's configuration claim (role `k8s_backup`).
4. **The owner's words.** The project decisions inbox records his message of 2026-11-08 07:06 UTC asking the agents to set up Jellyfin and the other apps and write the runbooks [4] (sourced).
5. **Reach.** At main 37eb02d, 33 files in `hosts/`, 12 runbooks and D-0037 name Jellyfin. Runbook and decision indexes are not counted [3] (measured, 2026-11-14).

## How the decision used it

(Written from the record, not from the batch.)

Findings 1 and 2 set rule 1. Findings 3 to 5 are the context, rules 2 and 3 and the confirmation.

## Limits

- No other media server was compared.
- The draft's claim of an owner acceptance on 2026-10-29 was not found in the inbox or in this repository's history, so the record does not use it.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. Jellyfin LICENSE. <https://raw.githubusercontent.com/jellyfin/jellyfin/master/LICENSE>
2. Jellyfin, "About". <https://jellyfin.org/docs/general/about>
3. Repository search and code read of central-hub at 37eb02d (this repository).
4. The project decisions inbox, row for 2026-11-08 07:06 UTC, message cmsg_01X43rfNYp4H1dL1V2dkfkwNNp8M1Uu2RmiKR53RXNQVLR. The inbox is private; the message id is the record.

The batch is RB-0208; its working files are private.
