# The board's selector, as the parity test's oracle

`task_board.py` and `task_owners.py` here are verbatim copies of the agent notebook's board scripts, taken from its main at commit `cb197776a5d279f5da5efe6ff43210747018f59c`. They are not run on the box and nothing installs them. `test_pickup_scan.sh` runs `task_board.py next` and `task_board.py stale` on made-up task notes and requires the box pickup scan (`hosts/ansible/roles/agent_box/files/pickup-scan.py`, which keeps its own copy of the rules) to give the same answer.

| File | SHA-256 at that commit |
|---|---|
| `task_board.py` | `5844751696bd6704afb6610b3d7da75d95028c7fd06680c67e8d0029ab33711f` |
| `task_owners.py` | `9447e84c7570e46370a497c6d8dacffa4a257fb89fa36244d250e4f226ea0a95` |

The test fails if either file's hash differs from this table, so the copy can't change unnoticed. When the notebook's selector changes, copy the new files here, update the commit and the hashes, and fix the scan until the parity test passes. This test can't see the notebook itself: it proves the scan matches this copy, not the notebook's current main.
