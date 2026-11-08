---
title: Build cluster c1 with Ansible (kubeadm, Cilium, the Gateway and volumes)
status: draft
kind: automated
trigger: on request; at a lab rebuild, after the node VMs exist
runner: an agent lane, through the owner's Mac (D-0022)
outcome: c1 runs Kubernetes with Cilium as its network and kube-proxy replacement, Secrets encrypted at rest, both nodes Ready, the shared Gateway apps answering HTTP at its pinned address, and a default StorageClass on the worker's data disk
needs: the controller from set-up-lab-controller.md; the node VMs from create-c1-node-vms.md; the lab DNS override for the API name (opnsense.yml)
private-values: [k8s_control_plane_endpoint, k8s_gateway_zone, k8s_gateway_address, k8s_control_plane_encryption_key_file, node-addresses]
files: [hosts/ansible/playbooks/k8s.yml, hosts/ansible/playbooks/k8s-gateway.yml, hosts/ansible/playbooks/k8s-storage.yml, hosts/ansible/roles/k8s_node/, hosts/ansible/roles/k8s_control_plane/, hosts/ansible/roles/k8s_worker/, hosts/ansible/roles/k8s_gateway/, hosts/ansible/roles/k8s_storage/]
last-tested:
superseded-by:
---

# Build cluster c1 with Ansible

**Status:** draft. c1 was built by these playbooks; this runbook puts the order down on 2026-11-08 from the playbooks' own headers and has not been replayed from empty VMs.

The playbooks are the by-hand runbook as code. For why each step exists, read [Build a single-node kubeadm cluster by hand](build-kubeadm-cluster.md): `k8s.yml` is its steps 1-10, 8a and the worker form of 36, changed for the home lab in each role's comments.

```mermaid
flowchart LR
  k["1 secrets key"] --> a["2 k8s.yml<br/>nodes, kubeadm init, 8a,<br/>Cilium, join, smoke"]
  a --> g["3 k8s-gateway.yml<br/>Gateway apps (HTTP)"]
  g --> s["4 k8s-storage.yml<br/>data disk + local-path"]
```

## Before you start

- Both nodes answer SSH through the host ([Create the c1 node VMs](create-c1-node-vms.md) step 2).
- `dig api.c1.prod.<zone> @10.1.50.1` from the host answers with the control plane's address (the override is in `opnsense_lab_host_overrides`).
- The filled-in inventory has the `k8s_nodes` group with real names and addresses, `k8s_control_plane_endpoint`, `k8s_gateway_zone` and `k8s_gateway_address` (one address from VLAN 10's `.224/27` load-balancer pool, [STD-0002](../standards/0002-ip-address-plan.md)).

## Steps

Run from `hosts/ansible/`.

1. Make the Secrets-at-rest key once, if `~/.config/central-hub/c1-secrets-encryption.key` doesn't exist.

   ```sh
   (umask 077; head -c 32 /dev/urandom | base64 > ~/.config/central-hub/c1-secrets-encryption.key)
   ```

   Name the file in `k8s_control_plane_encryption_key_file`.
   why: the API server stores Secrets in etcd encrypted with this key; a restored etcd backup can't be read without it ([hosts/ansible/README.md, Secrets at rest on c1](../../hosts/ansible/README.md#secrets-at-rest-on-c1)). On a rebuild that restores etcd, keep the old key instead.
   expect: the file is `-rw-------` and holds 44 base64 characters.

2. Build the cluster.

   ```sh
   ansible-playbook -i inventories/home/ playbooks/k8s.yml
   ```

   why: role `k8s_node` prepares every node (kernel, SELinux, firewalld lab zone, containerd, kubeadm, kubelet, kubectl); `k8s_control_plane` runs `kubeadm init`, turns on Secrets at rest, applies the Gateway API CRDs and installs Cilium by Helm with kube-proxy replacement and its Gateway API controller ([D-0017](../decisions/0017-replace-kube-proxy-and-announce-lb-addresses-with-cilium.md), [D-0021](../decisions/0021-use-gateway-api-on-cilium-as-the-way-in-for-web-traffic.md)); `k8s_worker` joins the worker; the last play runs a smoke test pod.
   ※ Cilium is a step inside this playbook, so it has no runbook of its own.
   expect: the smoke test passes (DNS for `kubernetes.default` and a way out to `pkgs.k8s.io`). On the control plane, `kubectl get nodes` shows both `Ready`, and `cilium status --wait` shows every component OK.

3. Make the shared Gateway (HTTP only for now) and prove it.

   ```sh
   ansible-playbook -i inventories/home/ playbooks/k8s-gateway.yml --tags gateway
   ansible-playbook -i inventories/home/ playbooks/k8s-gateway.yml --tags smoke
   ```

   why: one Gateway `apps` for `*.apps.c1.prod.<zone>` at the pinned address is the way in for every app; HTTPS comes after the certificate ([Issue c1's app certificate](issue-c1-app-certificate.md)).
   expect: the smoke run calls an echo app through the Gateway from the host, gets a 404 for an unknown name, resolves the wildcard from the worker, then deletes the echo app.

4. Give c1 volumes: the worker's data disk and the default StorageClass.

   ```sh
   ansible-playbook -i inventories/home/ playbooks/k8s-storage.yml --check --diff
   ansible-playbook -i inventories/home/ playbooks/k8s-storage.yml
   ```

   why: apps ask for volumes with a plain claim; each volume is a folder on the worker's data disk ([hosts/ansible/README.md, Storage on c1](../../hosts/ansible/README.md#storage-on-c1)). The disk is formatted only while `blkid` sees nothing on it, so a kept data disk is never wiped.
   expect: the proof tag writes and reads a file on a claim, then removes it; `kubectl get storageclass` shows `local-path (default)`.

## If it fails

- `k8s.yml` stops before `kubeadm init`: fix and run it again; the node roles are safe to repeat.
- After `kubeadm init`: compare with the matching step of the by-hand runbook. To start the cluster over, `kubeadm reset` on every node ([by-hand runbook step 20](build-kubeadm-cluster.md#20-kubeadm-tokens-a-config-file-reset-ca3)), or rebuild the VMs.
- The encryption step stops if the node holds a different key than the controller's file: never change it here; key rotation is a separate job.

## Afterwards

Set `last-tested`. After any later `playbooks/k8s-upgrade.yml`, set the new versions in the inventory, as `hosts.example.yml` says, so a re-run of `k8s.yml` never downgrades the cluster.

## Related

- [Rebuild the home lab from bare metal](rebuild-home-lab-from-scratch.md).
- [Build a single-node kubeadm cluster by hand](build-kubeadm-cluster.md): the whys.
- [Spec: c1's way in for web traffic](../specs/2026-10-c1-way-in-for-web-traffic.md).
