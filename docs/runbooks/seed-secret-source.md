---
title: Seed namespace secret-source on c1 from the controller
status: draft
kind: manual
trigger: when an app first needs a secret through store c1; at a lab rebuild, after step 1 of install-c1-add-ons-with-ansible.md, only if the file below has lines
runner: the owner, or an agent lane through the owner's Mac (D-0022)
outcome: every line of the controller's secret-source file is a Secret named after it in namespace secret-source, and store c1 can hand it to an ExternalSecret
needs: ClusterSecretStore c1 Ready (install-c1-add-ons-with-ansible.md step 1, or move-external-secrets-to-argo-cd.md); SSH to c1's control plane as D-0022 says; kubectl on the controller
private-values: [secret-source.env, c1-control-plane]
files: [hosts/kubernetes/clusters/c1/apps/secret-store/templates/store.yaml, hosts/ansible/roles/k8s_secrets/templates/store.yaml.j2, hosts/ansible/roles/k8s_secrets/defaults/main.yml]
last-tested: not yet run; nothing on c1 reads store c1 yet
superseded-by:
---

# Seed namespace secret-source on c1 from the controller

**Status:** draft. Written on 2026-11-08 from the store's manifest and the repository's search for its users. Not run.

## What goes in `secret-source` today: nothing

On 2026-11-08 no ExternalSecret in this repository names store `c1`. The only ExternalSecret on c1, Jellyfin's admin password ([setup-secret.yaml](../../hosts/kubernetes/clusters/c1/apps/jellyfin/templates/setup-secret.yaml)), comes from an ESO `Password` generator, not from the store. Sign-in reads its values from `inventories/home/identity.env` through Ansible (PR #69), and the lab CA keeps its own files (PR #65). So at a rebuild there is nothing to seed: skip this runbook while the file below is empty or missing.

Check before you trust that sentence, because a later change can add a user of the store:

```sh
git grep -n 'secretStoreRef' -- hosts/
```

expect: no hit (true on 2026-11-08). Every hit is an ExternalSecret whose `remoteRef.key` names a Secret that must be in the file below.

## How the store reads it

- Store `c1` is ESO's Kubernetes provider. It reads Secrets from namespace `secret-source` and nothing else, through service account `store-c1` with get, list and watch on Secrets there ([store.yaml](../../hosts/kubernetes/clusters/c1/apps/secret-store/templates/store.yaml)).
- Each Secret is named `<app>-<field>`, so one Secret maps to one entry when a vault replaces this store (the store's own header comment).
- The namespace carries `argocd.argoproj.io/sync-options: Delete=false`: Argo CD never deletes it, because its Secrets exist only on the cluster and on the controller.
- An ExternalSecret reads one with `remoteRef: {key: <app>-<field>, property: value}`.

## The file on the controller

`~/.config/central-hub/secret-source.env` on the owner's Mac, mode `600`, never in git and never in a password manager (the owner's standing order on secrets, 2026-11-08). One line per Secret:

```text
# <app>-<field>=<value>
example-api-token=REPLACE_ME
```

Everything after the first `=` is the value. Add it to the rebuild runbook's table of private files when its first line is written.

## Steps

1. Make sure the store is Ready.

   ```sh
   ssh <c1-control-plane> sudo kubectl get clustersecretstore c1
   ```

   expect: `READY True`.

2. Turn each line into a Secret and apply them all in one go. The values pass through a pipe, never through a command line.

   ```sh
   grep -v -e '^#' -e '^$' ~/.config/central-hub/secret-source.env |
   while IFS='=' read -r name value; do
     printf %s "$value" | kubectl create secret generic "$name" -n secret-source \
       --from-file=value=/dev/stdin --dry-run=client -o yaml
     echo ---
   done | ssh <c1-control-plane> sudo kubectl apply -f -
   ```

   why: `--dry-run=client` builds the YAML on the controller without talking to any cluster; `apply` makes the run safe to repeat, and a changed line updates its Secret.
   expect: one `secret/<name> created` or `configured` line per line in the file.

3. Check that ESO sees them.

   ```sh
   ssh <c1-control-plane> sudo kubectl -n secret-source get secrets
   ssh <c1-control-plane> sudo kubectl get externalsecrets -A
   ```

   expect: one Secret per line; every ExternalSecret on the store shows `SecretSynced`.

## If it fails

- `SecretSyncedError` with "not found": the ExternalSecret's `remoteRef.key` is not a line in the file, or the name differs. Fix the line and run step 2 again.
- A Secret that should be gone: this runbook only adds and updates. Delete it with `kubectl -n secret-source delete secret <name>` and take its line out of the file.

## Afterwards

Set `last-tested`. When the rebuild runbook gains a step that needs a secret through store `c1`, it points here.

## Picks in this runbook

Every item below is an agent pick, not a decision by the owner.

- One file, `~/.config/central-hub/secret-source.env`, with one `<app>-<field>=<value>` line per Secret. Reason: the owner's order puts secrets in git-ignored env files on the Mac, and the store already names Secrets `<app>-<field>`.
- One key per Secret, named `value`. Reason: one Secret holds one field by its name, so a second key would only repeat it.
- Build the YAML on the controller and apply it over SSH. Reason: D-0022 reaches c1 by SSH; the values never sit in a file on the node.

## Related

- [Install c1's add-ons and apps with Ansible](install-c1-add-ons-with-ansible.md), step 1: the store this fills.
- [Move External Secrets to Argo CD](move-external-secrets-to-argo-cd.md): rebuilding the store from nothing.
- [Rebuild the home lab from bare metal](rebuild-home-lab-from-scratch.md).
