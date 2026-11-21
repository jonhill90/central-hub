---
title: Edit the lab's private inventory on the agent box
status: draft
kind: automated
trigger: a firewall, host or c1 job needs a private value changed, such as a firewall rule's address or which store the apps read
runner: an agent lane on the agent box, through the `inventory` wrapper
outcome: one listed value in the box's working copy of the private inventory is changed with no Mac step, and the job that uses it shows the change in its next check
needs: the `inventory` wrapper installed on the box (the agent box role); the standing go's message ID for a value of class firewall, tailnet, access or money (D-0061)
private-values: [hosts.yml]
files: [hosts/ansible/roles/agent_box/files/inventory.sh, hosts/ansible/inventories/home/editable-values.yml]
last-tested:
superseded-by:
---

# Edit the lab's private inventory on the agent box

The private inventory (`hosts/ansible/inventories/home/hosts.yml`, git-ignored) used to be edited only on the owner's Mac. The box keeps a working copy that only its own user `invops` can read, and the `inventory` wrapper is the one way to read or change it. Why it is built this way: [the spec](../specs/2026-11-private-values-on-the-box.md). No action prints a value except `view`, which only the jobs' own users may run.

## Steps

1. List what is held: `inventory names`. It prints key paths such as `proxmox_host.proxmox_firewall_enable`, never a value.
2. Fill the first copy, once: `inventory import prod`, then `inventory import-compare`. `import` refuses if a working copy exists. `import-compare` names the key paths where the prod and guard copies differ; read them before the jobs switch to the working copy.
3. Change one value: `inventory set <scope.variable> [<cmsg_...>] < value` with the value on standard input as YAML or JSON. Only paths in `hosts/ansible/inventories/home/editable-values.yml` are accepted, each with a type the value must pass. A path of class `firewall`, `tailnet`, `access` or `money` needs the standing go's message ID after the path. A secret key is refused.
4. See what changed: `inventory diff` prints the key paths the last `set` touched, each as `changed`. `inventory get <path>` prints a type and a 12-hex tag (an HMAC under a key only `invops` holds); the tag tells whether a value changed, not what it is. `inventory log` shows the last five changes (path, class, message ID, two tags).
5. A value change is not a live change. Run the job that uses it (`proxmox-host check`, `opnsense-prod check`, and so on) and take it through its own gate: a check hash, a reviewer pass and a go, then `apply-recorded`.

## Adding a settable value

Add a line to `hosts/ansible/inventories/home/editable-values.yml` (path, part, type, class) by pull request. Never list a credential of the owner's, a purchase, his Mac, malware or leaking his data (D-0061 rule 2).

## What is not proven

Nothing here has run on the real box yet: the wrapper is tested against a made-up inventory, and its sudo lines, user and folders are rendered and checked in tests only. The host job's proxy, firewall, connector and sso jobs now read the settable host values (the names the reviewed list gives under `proxmox_host`) from `inventory view proxmox`, in a mode-0600 vars file deleted when the run ends, passed after the job's own inventory so it wins; if the view fails the job stops and says so, with no fallback to the old copy. The other jobs still read their own copies until each is switched to `view` in later pull requests. A `set` rewrites the working copy from parsed data, so the example file's comments are not kept.
