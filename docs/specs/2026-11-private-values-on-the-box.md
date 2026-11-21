---
title: Keep the lab's private inventory on the agent box, with one fixed wrapper to read and edit it
status: proposed
date: 2026-11-21
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Keep the lab's private inventory on the agent box, with one fixed wrapper to read and edit it

## What and why

Every firewall, host and prod-c1 job on the agent box reads values that are not in this public repository: the filled-in inventory `hosts/ansible/inventories/home/hosts.yml` (git-ignored; its example, `hosts.example.yml`, lists the groups `proxmox`, `agent_box`, `opnsense` and `k8s_nodes`). The only place that file is edited is the owner's Mac. The box holds copies, and a copy has no reviewed way to change. The result is that most firewall changes and most prod changes still start with a Mac step, which is the largest part of what is left on the Mac. Goal served: the owner's signal 1, no Mac step ([PRD](../PRD.md)).

What the box holds today, from the code:

| Copy on the box | Owner | Read by | Written by |
|---|---|---|---|
| `/etc/agent-keys/prod/inventory-hosts.yml` | `keys` | `c1-ansible.sh:26`, `openbao-prod.sh:75`, `rebuild-prod.sh:126`, `desktop.sh:39`, `dev-worker-address.sh:48` | the role's `prod_files` tag, from the controller only (`tasks/prod_files.yml:1-12`) |
| `/etc/agent-keys-guard/inventory/hosts.yml` | `guardops` | `opnsense-prod.sh:42` (and the tailnet job's own files) | the role's `guard_files` tag, from the controller only (`defaults/main.yml:354-359`) |
| the host job's inventory, `<host dir>/inventory/hosts.yml` | `hostops` | `proxmox-host.sh:67` | the role's `proxmox_host_inventory` tag, built from the controller's entry (`tasks/proxmox_host_inventory.yml:1-6`) |
| the dev inventory, `/etc/agent-keys/rebuild-dev/inventory/hosts.yml` | `keys` | `rebuild.sh:214` | the controller |
| `box-apply`'s inventory (only the `agent_box_*` variables) | root | `box-apply.py` | the controller only (D-0036 rule 7) |

All three tags are in `agent_box_self_apply_skip_tags` (`defaults/main.yml:542`), so no run on the box can write them.

**The copies already disagree.** The Mac lane copied the guard files at 2026-11-20 05:54 UTC and reported `hosts.yml` as 15188 bytes. It then added one line to the Mac's file, `k8s_gitops_source_app_secrets_store: openbao`, and copied only the prod copy at 07:33 UTC, which it reported as 15357 bytes, 169 bytes longer. So today the guard copy lacks that line [source: the Mac lane's two reports of 2026-11-20, read in the project's Mac lane thread; sizes are as reported, the files were not re-read here]. A value is now in one place on the Mac and in up to four on the box, and only the Mac edits them.

## The choices

Each choice cites what it rests on. Where a choice is an agent pick for the owner to change, it says so.

1. **The home of these values is a SOPS-class file on the box, not OpenBao.** D-0038 rule 10 lists the private inventory, the `home.tfvars` files, the env files and the OpenTofu state as "the private bootstrap files, the ones a rebuild needs before OpenBao is up" (`0038-...md:93`), and D-0058 rule 8, which replaces D-0038 rule 11, keeps with SOPS "what is needed before OpenBao starts, what the jobs of rule 5 need while c1 is down" (`0058-...md:54`). D-0058 rule 5 says the jobs that "rebuild or repair c1 or the layers under it" read files in the box's keys folder, "the c1 rebuild, Proxmox, the firewall, the tailnet connector" (`0058-...md:51`). The firewall, host and prod-c1 jobs are exactly those, so a store inside c1 cannot be their source: they must run when c1 is down. OpenBao stays what the apps read at run time (D-0058 rule 8, `:54`); no inventory value moves into it.
2. **One working copy, owned by one new user, `invops`.** A new user is a change to D-0036 rule 3(d) and so a box-limit change, applied by the agents' pass of its digest and an approvals line (D-0036 rule 6; D-0044). Why not reuse `keys`: D-0063 (status proposed, so every D-0063 line here is a design the box follows, not a rule in force) chose a user per key group because "every wrapper that runs as `keys` (more than twenty) can read the firewall key" (`0063-...md:46`), and D-0063 rule 1(c) deliberately put the inventory where "a wrapper that needs a private value reads it there; nothing copies the file into a session's reach" (`:67`). The working copy keeps that shape: mode 0600 in a 0700 folder of `invops`, under the keys folder's tree (`/etc/agent-keys/inventory/`) so the nightly bundle (the SOPS copy of D-0038 rule 10: a working copy stays 0600 beside its key, and only the encrypted bundle leaves the machine, `0038-...md:93`), which tars the keys folder's `prod` and `dev` folders (`secrets-bundle.sh:5,59`), is extended to carry it. The guard and host folders are not in that bundle today, so a lost box would lose those copies; one working copy in the bundle fixes that [agent pick].
3. **Consumers ask for a part; no one holds a copy.** Each consumer wrapper gets only its own part of the file by calling `sudo -n -u invops .../inventory.sh view <part>` and reading standard output into a file in its own run folder, mode 0600, deleted when the run ends. The sudoers line for `view` is given to the wrappers' users (`keys`, `guardops`, `hostops`) and to no session, the same shape as #776's `hostops` call into a `keys` wrapper (central-hub #776, merged; its body says the call was not yet run, so this shape is not proven here). The parts are the inventory's groups: `proxmox` (host job and host firewall), `opnsense` with the shared VLAN file (the firewall job), `k8s_nodes` with `all.vars` (the c1 jobs). The `agent_box` group is not a part: it is `box-apply`'s inventory, a limit (D-0036 rule 3(f) and rule 7, `0036-...md:82`), and stays controller-only until its own decision. The four copies in the table go away as each consumer switches, so they cannot drift again.
4. **The edit is one wrapper with fixed arguments, and no value is ever printed.** `inventory.sh set <key path>` takes the value on standard input, as `secrets-store.sh put` does (`secrets-store.sh:46`), and the session's sudoers line names only that form. A key path is accepted only if a reviewed file in this repository lists it: `hosts/ansible/inventories/home/editable-values.yml`, one entry per path with its part, its type (address, CIDR, port, bool, name, or a list or mapping with a schema) and its class. The file holds names and types only, never a value, so it is public-safe. The wrapper refuses a path that is not listed, a value that fails its type, and any key the example marks `# secret` (`opnsense_api_key`, `opnsense_api_secret`: `hosts.example.yml:73-74`). Secrets stay in their key files (D-0063 rule 1) or, for app secrets, in OpenBao through `secrets-store put`. `get` prints a type and the first 12 hex digits of the value's SHA-256; `names` prints key paths; `diff` prints key paths with every address, name and email replaced (the scrub `tailnet-policy.sh` already uses, `tailnet-policy.sh:37`). A session therefore never reads a private value from the box, which is how D-0063 rule 1(c) already treats it.
5. **A value change is not a live change; the job that applies it keeps its gate.** A value in the file changes nothing until a job runs. The firewall, tailnet and host jobs apply only through `apply-recorded` with a check hash, a reviewer pass for that hash and a go (D-0063 rule 3, `0063-...md:69`), and the apply refuses if the hash moved. Because the check's diff hashes what the new value would do, a value edit shows in the hash the reviewer passes. Each `set` is also logged with the key path, the time, the calling message id, the class and the before and after SHA-256 prefixes, never the values. The entries' classes decide the extra step: `firewall`, `tailnet`, `access` and `money` classes need the standing go's message id on the `set` line (D-0061 rules 1 and 3, `0061-...md:57,64`); a `plain` class does not; D-0061 rule 2 items (his own credentials, buying, his Mac, malware, leaking his data) are never `set` through this wrapper.
6. **What a reviewer can and cannot see.** A reviewer reads the check's task names, counts and hash (the host job prints only the commit, the hash, counts and the pass ID: `proxmox-host.sh:55`). It cannot read an address. That is a gap against reviewing a PR line by line, and this spec does not close it: the scrubbed `diff` (the scrub of `tailnet-policy.sh:37` hides IP addresses, email addresses and tailnet names only, so the new wrapper's own scrub must also hide every other value type) shows which paths changed and how the shape changed, for example "one rule added to `proxmox_firewall_extra_rules`: tcp, port 443, source `<ip>`", which is the information the reviewer needs to name the step, and the address is checked by the apply's own check run. A change to an address that is wrong fails the job's own proofs (for example the firewall role's dead-man timer and the OPNsense guard of D-0063 rule 4) before it is final.
7. **First fill: adopt what the box already holds, no new copy of a secret leaves a place it is already kept.** `inventory.sh import prod|guard` (two fixed forms, no path argument) reads the prod copy or the guard copy and writes the working copy, and `import-compare` prints the key paths where the two differ. The prod copy is the newer of the two (the sizes above), so it is the source; the compare names the paths that differ, and the owner's Mac file is not read. Moving a file between folders of the same box is not sending his data anywhere it is not kept, so it is not a D-0061 rule 2 step [agent pick; if the owner reads it otherwise, the import waits for his words].
8. **The Mac stops being the editor, not yet the owner of the lab.** After the consumers switch and the proofs below pass, the three tags (`prod_files`, `guard_files`, `proxmox_host_inventory`) are removed from the role in a last PR, and the Mac's `hosts.yml` becomes a stale snapshot. D-0063 is proposed, not in force; its rule 6 would keep the Mac's copies until the owner answers the card that stops the Mac lane (`0063-...md:72`); this spec does not stop the Mac lane.
9. **Amendments it needs as decision records.** D-0036 rule 7 ("stay in the private inventory on the Mac", `0036-...md:82`) and D-0063 rule 1(c) (an amendment to that record if it is still proposed) are changed for these three parts: one record, written after this spec is accepted, naming `invops` and the wrapper. The `agent_box` group and `box-apply`'s inventory are not amended.

## Out of scope

- The `agent_box` group and the controller's full apply of the box role (it clears a stop that guards the box's own limits: D-0036 rules 5 and 6). It stays on the controller. A box-side clear loosens a rule and is not decided here.
- Keys and tokens: the Cloudflare token and its Terraform state, the Tailscale OAuth client, the lab CA keys, the OPNsense and Proxmox keys. They are not inventory values; moving the Cloudflare token to the box is a copy of the owner's credential and needs his words (D-0061 rule 2).
- OpenTofu state and the per-folder `home.tfvars` files other than the tailnet one the guard job already holds. They need the same treatment later, after the wrapper proves itself on the inventory.
- Stopping the Mac lane (D-0063 rule 6), and the Mac's keychain trust of the lab CA.
- Putting any value in this repository, in a log, or in a message.

## Acceptance criteria

### Automated

- [ ] `.github/hosts-check/tests/test_inventory_wrapper.sh` (new, written with the code): `set` refuses an unlisted path, a bad type, and a `# secret` key; `set` of a listed key changes only that key and logs the path and two 12-hex prefixes and no value; `get`, `names` and `diff` print no address, name or email (the output is searched for the test's sample values); `view <part>` returns only its group and the shared variables that group needs; `import` of a copy then `import-compare` names the one key that differs.
- [ ] `.github/hosts-check/tests/test_sudoers_session_args.sh` (extended): the session's line allows exactly `set`, `get`, `names`, `diff` and `import prod|guard`; only the wrapper users' lines allow `view`; no line allows a path argument.
- [ ] `.github/hosts-check/tests/test_secrets_bundle.sh` or its equivalent (extended): the bundle holds `inventory/` and still excludes the guard and host key files.

### Manual (what the owner checks)

- [ ] Nothing for the owner to type, click or run. He reads the one decision record of choice 9 if he wants to change an agent pick (choices 2, 4, 5 and 7).

### Proofs run from the box (raw output goes in the PR that runs each)

- [ ] `inventory.sh import prod`, then `import-compare`: it names the paths that differ between the prod and guard copies (expected from the sizes: `k8s_gitops_source_app_secrets_store` and whatever else differs).
- [ ] `inventory.sh set` of one plain key (the example in `editable-values.yml`), then `opnsense-prod.sh check`: the check shows the change and the hash moved, with no Mac step.
- [ ] `proxmox-host.sh check firewall` and `opnsense-prod.sh check` read their part through `view` after the switch and end with the same task counts as before it.
- [ ] A second, separate run of the guard job's `apply-recorded` for a no-change run ends with 0 changed (the shape of D-0063's Confirmation).
- [ ] `sudo -n -l` as the session shows the new lines and nothing wider; `ls /etc/agent-keys/inventory` as the session is refused.

## Points to (read when)

- [D-0036](../decisions/0036-let-the-agent-box-apply-its-own-reviewed-setup.md): read when changing which files the box may apply or which are limits.
- [D-0038](../decisions/0038-run-openbao-on-its-own-vm-as-the-secrets-store-with-sops-for-bootstrap-files.md) and [D-0058](../decisions/0058-run-openbao-inside-c1-from-its-helm-chart-with-a-sops-copy-of-every-secret.md): read when deciding what goes in OpenBao and what in SOPS.
- [D-0063](../decisions/0063-let-the-agent-box-hold-the-keys-that-guard-it.md): proposed, not in force; read when touching the guard and host jobs or the Mac copy.
- [D-0061](../decisions/0061-count-the-owners-standing-go-for-rule-6-steps-within-his-limits.md): read when a step's class decides whether the owner's words are needed.
- [Rebuild the home lab from scratch](../runbooks/rebuild-home-lab-from-scratch.md), "The private files on the controller": the list of private files and what each holds.

## Not proven

- Whether the filled-in `hosts.yml` holds real values in the `# secret` fields or only key-file paths. The example marks them secret; the real file was not read. If it holds them, the import must lift them out into key files first, and that step is a secret move the spec would need to name.
- Whether the guard and prod copies differ only by the one line above (169 bytes is a size, not a diff). The `import-compare` proof settles it.
- Whether a wrapper's Python inventory builder (`c1-ansible.sh:215`, `openbao-prod.sh:205`, `rebuild-prod.sh:295`) accepts a part from standard input without change. It reads a file today; the PR that switches each consumer shows it.
- That `hostops` and `guardops` can call a wrapper of another user the way #776's `hostops` call to `keys` is meant to work: #776 said "written, not run".

## Decision log

- 2026-11-21: Drafted by the box builder lane at the orchestrator's order, from D-0036, D-0038, D-0058, D-0061, D-0063 and the box's code at main `6d56549` and later. The home of the values (choice 1) is not a free pick: it follows from D-0038 rule 11 and D-0058 rule 5. Choices 2, 4, 5 and 7 are agent picks for the owner to change.
