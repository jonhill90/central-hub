# Runbooks

A runbook is a page for one job, step by step: `docs/runbooks/<verb>-<object>.md`. The format, the status words and the step rules are set in [D-0012](../decisions/0012-sort-docs-by-kind-of-document.md) ("Runbook format" and "Runbook steps"). Each step has a short `why:` line and links back with ※ to what it relies on. Each runbook is marked `manual` or `automated`, and for any job the `manual` runbook comes first.

A runbook is living: it is edited in place, and git keeps the history. No hostnames, single machine addresses, contacts or secrets are written here; a runbook names the key that holds a value in the private store (D-0012 rule 10).

| Runbook | Kind | Status |
|---|---|---|
| [Rebuild the home lab from bare metal (top-level order)](rebuild-home-lab-from-scratch.md) | manual | draft |
| [Set up the lab controller](set-up-lab-controller.md) | manual | draft |
| [Set up the lab network, the OPNsense firewall and the tailnet connector container from code](set-up-lab-network-and-firewall.md) | automated | draft |
| [Put the OPNsense image and the Debian 13 template on the Proxmox host](stage-lab-images-on-proxmox.md) | manual | draft |
| [Install the tailnet client in CT 900](set-up-tailnet-client-in-ct-900.md) | manual | draft |
| [Create the c1 node VMs on Proxmox from code](create-c1-node-vms.md) | automated | draft |
| [Restore the home lab from its backups](restore-home-lab-from-backups.md) | manual | draft |
| [Seed namespace secret-source on c1 from the controller](seed-secret-source.md) | manual | draft |
| [Build cluster c1 with Ansible](build-c1-with-ansible.md) | automated | draft |
| [Issue c1's wildcard app certificate](issue-c1-app-certificate.md) | automated | draft |
| [Install Argo CD on c1](install-argo-cd-on-c1.md) | automated | draft |
| [Install c1's add-ons and apps with Ansible](install-c1-add-ons-with-ansible.md) | automated | draft |
| [Build a single-node kubeadm cluster by hand (CKA practice)](build-kubeadm-cluster.md) | manual | draft |
| [Set up a Proxmox VE host by hand](set-up-proxmox-host.md) | manual | draft |
| [Create the lab root CA and c1's intermediate by hand](create-lab-root-ca.md) | manual | draft |
| [Trust the lab root CA on a Mac](trust-lab-root-ca-on-mac.md) | manual | draft |
| [Restore c1's intermediate CA into cert-manager](restore-c1-intermediate-ca.md) | manual | draft |
| [Move metrics-server on c1 from Ansible to Argo CD](move-metrics-server-to-argo-cd.md) | automated | draft |
| [Move c1's volume provisioner and default StorageClass from Ansible to Argo CD](move-local-path-to-argo-cd.md) | automated | draft |
| [Move Jellyfin on c1 from Ansible to Argo CD, with its first-run setup as code](move-jellyfin-to-argo-cd.md) | automated | draft |
| [Move logging on c1 (Loki and Alloy) from Ansible to Argo CD](move-logging-to-argo-cd.md) | automated | draft |
| [Move monitoring on c1 (kube-prometheus-stack) from Ansible to Argo CD](move-monitoring-to-argo-cd.md) | automated | draft |
| [Move c1's External Secrets and its store from Ansible to Argo CD](move-external-secrets-to-argo-cd.md) | automated | draft |
| [Move cert-manager on c1 from Ansible to Argo CD](move-cert-manager-to-argo-cd.md) | automated | draft |
| [Move c1's Gateway and app routes from Ansible to Argo CD](move-gateway-to-argo-cd.md) | automated | draft |
| [Check c1's health from its dashboard and alerts](check-c1-alerts-and-dashboard.md) | manual | draft |
| [Get c1's alerts on a phone or in a browser](get-c1-alerts-on-your-phone.md) | manual | draft |
| [Turn on sign-in to Argo CD through the lab's Keycloak](sign-in-to-argo-cd-with-keycloak.md) | automated | draft |
| [Back up c1 off the box](back-up-c1-off-box.md) | automated | draft |
| [Test the etcd restore](test-etcd-restore.md) | automated | draft |
| [Set up lab DNS and make the owner's Mac resolve lab names](set-up-lab-dns.md) | automated | draft |
| [Use break-glass access](use-break-glass-access.md) | manual | draft |
| [Give agents their own access to the owner's Azure tenant](give-agents-access-to-azure.md) | manual | draft |
| [Set up sign-in for lab apps on c1](set-up-lab-sign-in.md) | automated | draft |
| [Give lab apps short names under the zone](set-up-short-app-names.md) | automated | draft |
| [Let agents run a new command without a permission block](allow-a-command-for-agents.md) | manual | draft |

## Template

```markdown
---
title: <task, verb first>
status: draft            # draft | tested | superseded | retired
kind: manual             # manual | automated
trigger: <alert, schedule, event, or "on request">
runner: <the owner, or an agent lane>
outcome: <what is true when it is done>
needs: <tools and permissions>
private-values: [<key names in the private store; never the values>]
files: [<paths this runbook runs or reads>]
last-tested: <YYYY-MM-DD, who ran it, on what>
superseded-by:
---

# <title>

## Before you start
<check the current state; stop if it is not what this runbook expects>

## Steps
1. <one action: the exact command, or a link to the script>
   why: <one or two sentences: why this step, and how it connects to the last one>
   ※ <optional: what this relies on, linked to where it is explained>
   expect: <what you should see>

## If it fails
<where to stop, how to undo, and when to tell the owner>

## Afterwards
<what to record and where: a postmortem after an incident, a spec's done-evidence after a build>

## Related
<the decision, spec, standard or postmortem behind it>
```
