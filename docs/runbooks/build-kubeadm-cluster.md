---
title: Build a single-node kubeadm cluster by hand (CKA practice)
status: draft
kind: manual
trigger: on request; also after each rebuild of the practice machine
runner: the owner
outcome: a one-node Kubernetes 1.36.5 cluster (later 1.37.1) with Cilium, reachable only over the private network, and every CKA topic practised on it
needs: a fresh AlmaLinux 10 machine with root access; a Tailscale tailnet; a DNS zone for the endpoint name
private-values: [tailscale-auth-key, endpoint-name, node-name, backup-age-public-key]
files: []
last-tested:
superseded-by:
---

# Build a single-node kubeadm cluster by hand (CKA practice)

**Status:** draft. Steps 0-11 were proven by an agent in proof runs 1-3; practice steps 12-36 were proven on 2026-10-19, except where a step says NOT PROVEN. Not yet run by the owner. This runbook has not been replayed from a fresh rebuild as a whole.

## Before you start

### The story

**What we are building.** One Kubernetes cluster on one machine. The proof runs used the rented VPS; any fresh AlmaLinux 10 machine works the same way. The same machine is the control plane (the brain) and the worker (where apps run). We build it by hand, one command at a time, so you see every part.

**Why by hand.** The owner asked for a manual runbook first, so the value of each abstraction is clear before it is used (D-0012, "Manual first"). The CKA exam draws the line. What the exam asks you to do by hand, this runbook does by hand. What comes after is code (see [Where the manual runbook stops](#where-the-manual-runbook-stops)).

**The arc.**

```text
   BUILD IT  (steps 0-11)
   ─────────────────────
    0     make a machine
    1     lock it down
    2-4   prepare it          (kernel, DNS, firewall)
    5-6   install the parts   (containerd, kubeadm, kubelet, kubectl)
    7-8   start the cluster   (a name, then kubeadm init)
    9     give it a network   (Cilium)
    10    prove it works      (a test pod)
    11    back it up          (deferred for now)
          │
          ▼
   RUN IT AND FIX IT  (steps 12-36, the CKA topics)
   ─────────────────────
    look      logs, metrics                  12-13
    break     and fix, on purpose            14-16
    care      upgrade, certificates          17-18
    control   who can do what, kubeadm       19-20
    extend    Kustomize, CRDs                21-22
    connect   Services, policies, Ingress    23-28
    run apps  Deployments, config, probes    29-33
    keep data volumes, storage classes       34-35
    grow      more machines (read only)      36
          │
          ▼
   NEXT: do it all again as code  (Ansible → Kubespray → Talos)
```

**How the parts talk.** Keep this picture in mind. Most steps build one box or one arrow.

```text
   you ──kubectl──► API server :6443 ◄──── scheduler, controller-manager
                        │
                        ▼
                      etcd             (the cluster's memory)

   kubelet (on the node) ──► containerd ──► containers in pods
   Cilium gives each pod an address.  CoreDNS gives Services names.
```

### How to read this runbook

Each step has:

- **why**: one to three sentences, in a `why:` line. Why the step exists, and what breaks without it.
- the commands, in a box. They are the commands the proof runs used.
- an **expect** line: what you should see.
- **page**: the kubernetes.io page the step follows. You may open kubernetes.io during the exam. A few steps also name a project's own page.
- **status**: PROVEN (the agent ran it on the VPS and it worked) or NOT PROVEN (with the reason).
- the CKA competency ID from the synthesis (for example TS4).

**※ reminders** link back to an earlier step. They show how the pieces connect. Click one to jump back.

**What PROVEN means here.** The agent ran the commands over a non-interactive SSH session. So commands that wait for you (`-f`, `-w`, `--watch`, `kubectl edit`, `kubectl run -it`, `exec bash`) were run in their non-waiting form (a loop, `kubectl wait`, a `sed` edit, `-i` without `-t`). The results are the same; the step says so where it matters.

**Rules for practice.** Run everything as root on the node. `<node name>` is your node's hostname, following [STD-0001](../standards/0001-vm-hostnames.md). Real names are not written here. `<endpoint name>` is the DNS name from [step 7](#7-endpoint-name). Most practice steps clean up after themselves. Four leave something behind on purpose: the exam habits (shell settings), step 13 (metrics-server, needed by step 33), step 17 (the cluster is now 1.37.1) and step 26 (Traefik, needed by step 27). Otherwise you can skip any step: nothing on the cluster depends on one.

**Versions after step 17.** Step 17 upgrades the cluster from 1.36.5 to 1.37.1, the exam's version as of 2026-10-24 (see step 17). Steps after it ran on 1.37.1.

**The owner's run-through (watch here).** The owner will run this runbook by hand and update it during the run. Things to watch, since the agent's proof could not cover them:

- **Typed commands.** Every step that waits for you (`kubectl edit`, `-w`, `run -it`, `exec bash`) was proven only in its non-waiting form. Type the real form and fix the text if it differs.
- **NOT PROVEN steps.** These parts are first run by the owner: the real `kubeadm reset` and re-init ([step 20](#20-kubeadm-tokens-a-config-file-reset-ca3)), dynamic provisioning ([step 35](#35-storageclass-and-dynamic-provisioning-st1)), the CoreDNS stub domain ([step 28](#28-coredns-read-and-change-the-corefile-sn6)), HA and `kubeadm join` ([step 36](#36-high-availability-and-kubeadm-join-ca5-ca3)), and CSI.
- **The runbook as a whole.** Its commands are the proven ones, but the whole runbook has not been replayed from a fresh rebuild.
- **Where the tasks come from.** The agent wrote the tasks from the CKA curriculum lines and the kubernetes.io pages. They are not exam questions. The two killer.sh sessions that come with the exam registration are the test under exam conditions.
- **Recordings.** Later, record the steps as terminal recordings (VHS or a similar tool) for the docs and knowledge base. A step gets a recording once its text is right.
- **Organisation and replaceability (the owner's request, 2026-10-21).** At [step 32](#32-requests-limits-quotas-node-affinity-taints-ws5), and before the first real apps, plan namespaces (names, access, quotas) and placement (labels and taints written on the app, naming the role, never the machine). Decide then whether it needs a research batch.

## Steps

### Part 1. Build it

The agent found the traps in these steps by running them (PROOF-RUN-1.md), then replayed them twice more. Run 3 replayed steps 0-10 with no edits and took about 8 minutes (PROOF-RUN-3.md).

#### 0. Fresh machine

why: every build starts from a clean machine, so the runbook makes the cluster, not leftovers. The machine is greenfield: no snapshot is kept. The private-network client goes on at first boot, so you can reach the machine privately before step 1 closes the public doors.

- Make a single-use, one-hour, pre-authorized Tailscale auth key with the machine's tag. It is a secret: it lives in the private store under `tailscale-auth-key` and is never written here.
- Reinstall the machine from the provider's AlmaLinux 10 image with a first-boot script that installs Tailscale and runs `tailscale up --auth-key=<key> --advertise-tags=<tag> --ssh --hostname=<node name>`. The script can run `hostnamectl set-hostname <node name>` first (run 2). Delete the script afterwards.
- expect: the node shows in `tailscale status`; `tailscale ssh root@<node name>` works. Takes about 2.5 minutes.
- status: **PROVEN** (proof runs 1-3, through the provider's API). CKA: CA2.

#### 1. Lock down the host

why: The VPS sits on the public internet. The image ships with no firewall and lets SSH log in with a password and as root (measured, PROOF-RUN-1.md). So before anything else: SSH only over the tailnet, keys only.

```bash
hostnamectl set-hostname <node name>            # before kubeadm init; otherwise the node gets the provider's name
dnf -y install firewalld && systemctl enable --now firewalld
firewall-cmd --permanent --new-zone=tailnet
firewall-cmd --permanent --zone=tailnet --add-interface=tailscale0
firewall-cmd --permanent --zone=tailnet --add-service=ssh
firewall-cmd --permanent --zone=public --remove-service=ssh
firewall-cmd --permanent --zone=public --remove-service=cockpit
firewall-cmd --reload
printf 'PasswordAuthentication no\nPermitRootLogin prohibit-password\nKbdInteractiveAuthentication no\n' \
  > /etc/ssh/sshd_config.d/01-central-hub-hardening.conf     # sorts before cloud-init's 50- file
sshd -t && systemctl reload sshd
```

- The hostname line: kubeadm names the node after the hostname. Proof run 1 skipped it and the node got the provider's name (PROOF-RUN-1.md).
- Two zones: `public` (the internet) and `tailnet` (your private network). Everything Kubernetes needs will go in `tailnet` only.
- expect: `sshd -T | grep -E '^(passwordauthentication|permitrootlogin) '` shows `no` and `without-password`; `firewall-cmd --zone=public --list-services` shows only `dhcpv6-client`; a new `tailscale ssh` login still works.
- status: **PROVEN** (PROOF-RUN-3.md). CKA: CA2.

#### 2. Host prerequisites

why: The kubelet, containerd and the pod network expect a few Linux settings. Each line below says what one is for.

```bash
swapoff -a; sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab        # the image has no swap; harmless
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf && modprobe overlay && modprobe br_netfilter
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/k8s.conf && sysctl --system
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
touch /.autorelabel && systemctl reboot                     # the image ships SELinux Disabled; a relabel boot is needed
```

- **swap:** by default the kubelet will not start if swap is on (install page). This image has no swap, so the line is a safe habit.
- **overlay, br_netfilter:** overlay is a Linux filesystem that lays one folder tree over another (source: <https://docs.kernel.org/filesystems/overlayfs.html>). containerd's default `overlayfs` snapshotter stacks image layers with it (source: <https://github.com/containerd/containerd/blob/main/docs/snapshotters/README.md>); on the node, every running container is an overlay mount (measured). br_netfilter sends traffic that crosses a Linux bridge through the firewall's iptables rules (`bridge-nf-call-iptables`, source: <https://docs.kernel.org/networking/ip-sysctl.html>; it is 1 on the node, measured). The current container runtimes page no longer names these two modules. The `modules-load.d` file loads them again after every reboot.
- **ip_forward:** by default Linux does not pass packets from one network interface to another (container runtimes page). Pod traffic must cross from the pod's interface to the host's. Most CNIs turn this on themselves; the page says some expect you to.
- **SELinux permissive:** the OS choice, as the kubeadm install page says (it lets containers reach the host's files, which some network plugins need). The image ships SELinux **Disabled**, not permissive (measured, PROOF-RUN-1.md). Files made while SELinux was off have no labels, so turning it on needs one relabel boot, done in permissive mode (source: <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_selinux/changing-selinux-states-and-modes>).
- ※ Later, the agent ran the cluster with SELinux **Enforcing** too (SELINUX-TRIAL-LEVEL1.md). It worked, but pods run unconfined at that level. The OS choice stays permissive.
- expect after reboot: `getenforce` = Permissive; `lsmod | grep -E '^(overlay|br_netfilter)'`; `sysctl net.ipv4.ip_forward` = 1.
- page: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/> ; <https://kubernetes.io/docs/setup/production-environment/container-runtimes/>
- status: **PROVEN** (PROOF-RUN-3.md). CKA: CA2.

#### 3. DNS that pods can use

why: Pods ask CoreDNS. CoreDNS's default Corefile has `forward . /etc/resolv.conf`: every name outside the cluster goes to the DNS servers it got from the node (source: <https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/>; the link to the node is under Known issues on <https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/>). Two node settings broke pods (measured trap, PROOF-RUN-1.md): Tailscale's MagicDNS server can't be reached from inside a pod, and cloud-init's search domain `localhost` reached the pods, so names resolved to the node itself. Fix the node, and pods get working DNS.

```bash
tailscale set --accept-dns=false                            # pods can't reach MagicDNS
C=$(nmcli -g NAME con show --active | grep -m1 cloud-init)
nmcli con mod "$C" ipv4.dns-search "" ipv6.dns-search "" && nmcli con up "$C"   # cloud-init adds search "localhost"
```

- expect: `/etc/resolv.conf` has the provider's nameservers and no `localhost` search domain.
- status: **PROVEN** (PROOF-RUN-3.md). CKA: TS5 (partly; a found-and-fixed trap).

#### 4. Firewall for Kubernetes and Cilium (tailnet zone only)

why: Each Kubernetes part listens on its own port (measured with `ss` on the proof node). They open only on the tailnet, so the public zone stays closed (but see the NodePort finding in [step 23](#23-services-clusterip-nodeport-loadbalancer-sn3)). And pods must reach the host: without the trusted pod range, firewalld blocked pod-to-host traffic and CoreDNS never became Ready (measured trap, PROOF-RUN-1.md).

```bash
for p in 6443/tcp 2379-2380/tcp 10250/tcp 10256/tcp 10257/tcp 10259/tcp 8472/udp 4240/tcp; do
  firewall-cmd --permanent --zone=tailnet --add-port=$p; done
firewall-cmd --permanent --zone=trusted --add-source=10.244.0.0/16   # pods must reach the API and host; without it CoreDNS never gets Ready
firewall-cmd --reload
```

- the ports: 6443 the API server; 2379-2380 etcd; 10250 the kubelet; 10256 kube-proxy; 10257 the controller-manager; 10259 the scheduler (ports page). 10256 is kube-proxy's health check (source: <https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/>). **Cilium-specific:** 8472/udp carries pod traffic between nodes, wrapped in VXLAN (Cilium's default mode, and this node's, measured); 4240/tcp is Cilium's health check between nodes (source: <https://docs.cilium.io/en/v1.20/operations/system_requirements/>). Another CNI needs its own ports here.
- ※ `10.244.0.0/16` is the pod range. You will give the same range to kubeadm in [step 8](#8-init) and to Cilium in [step 9](#9-cilium-1204).
- note: trusting the whole pod range is broad. Narrowing it is a hardening item.
- page: <https://kubernetes.io/docs/reference/networking/ports-and-protocols/>
- status: **PROVEN** (PROOF-RUN-3.md). CKA: CA2, TS5 (partly).

#### 5. containerd 2.3.6

why: Kubernetes does not run containers itself. It asks a container runtime to do it. containerd is that runtime here (the "CRI" in the CKA's "CNI, CSI, CRI"). The 2.3 branch is a long-term (LTS) branch, supported until April 2028, and works with Kubernetes 1.36 and 1.37 (source: <https://github.com/containerd/containerd/blob/main/RELEASES.md>).

```bash
dnf -y install dnf-plugins-core python3-dnf-plugin-versionlock
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install containerd.io-2.3.6-1.el10                   # GPG 060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35
dnf versionlock add containerd.io
containerd config default > /etc/containerd/config.toml
sed -i 's/^\(\s*\)SystemdCgroup = false/\1SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
```

- **versionlock:** dnf stops seeing any other version of the package, so a routine `dnf update` will not move containerd. You choose when it changes (source: <https://dnf-plugins-core.readthedocs.io/en/latest/versionlock.html>).
- **SystemdCgroup:** the kubelet and containerd must use the same "cgroup driver" (who manages resource limits), and on a systemd host it should be `systemd` (container runtimes page). Since Kubernetes 1.34 the kubelet asks containerd which driver to use, so this line decides it for both (feature gate `KubeletCgroupDriverFromCRI`, <https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/>; the node's kubelet log says "Using cgroup driver setting received from the CRI runtime" cgroupDriver="systemd", measured).
- expect: `containerd --version` = v2.3.6; `grep SystemdCgroup /etc/containerd/config.toml` = true.
- note (2026-10-24): upstream containerd 2.3.7 (2026-10-13) fixes four security advisories in 2.3.6 (<https://github.com/containerd/containerd/releases/tag/v2.3.7>). Docker's EL10 repo has no `containerd.io-2.3.7` build yet; its newest 2.3 build is 2.3.6-1 (<https://download.docker.com/linux/centos/10/x86_64/stable/Packages/>). Which containerd to install is an open choice for the owner.
- page: <https://kubernetes.io/docs/setup/production-environment/container-runtimes/>
- status: **PROVEN** (PROOF-RUN-3.md). CKA: CA2, CA7 (CRI).

#### 6. kubeadm, kubelet, kubectl 1.36.5

why: Three tools. **kubeadm** builds the cluster. **kubelet** is the agent on the node that runs pods. **kubectl** is how you talk to the cluster. This runbook pins 1.36, one version behind the exam, so you can practise a real upgrade later.

```bash
cat > /etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf -y install kubelet-1.36.5 kubeadm-1.36.5 kubectl-1.36.5 'cri-tools-1.36.*' \
  --disableexcludes=kubernetes --setopt=install_weak_deps=False   # DNF4 flag form; cri-tools named because weak deps are off
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\n' > /etc/crictl.yaml
systemctl enable --now kubelet
```

- **exclude line:** stops a routine `dnf update` from upgrading Kubernetes by surprise, because upgrades need their own procedure (install page; [step 17](#17-upgrade-the-cluster-from-1365-to-1371-ca4)). You lift it on purpose with `--disableexcludes`. (Proof run 1 found DNF 4 is the right flag form, and that `cri-tools` must be named, PROOF-RUN-1.md. The install page now shows a `--setopt=` form for RHEL 10; the form here is the one proven on AlmaLinux 10.2.)
- **crictl.yaml:** tells `crictl` where containerd listens. `crictl` talks to containerd directly, so it still works when the API server is down.
- **kubelet now restarts every few seconds.** That is expected: it waits for kubeadm to tell it what to do (install page).
- expect: `kubeadm version -o short` = v1.36.5; `crictl info` works. k8s repo GPG DE15 B144 86CD 377B 9E87 6E1A 2346 54DA 9A29 6436.
- page: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/>
- status: **PROVEN** (PROOF-RUN-3.md). CKA: CA2.

#### 7. Endpoint name

why: The cluster's address goes into its certificates and every kubeconfig. Use a name, not an IP. Then a rebuilt node only needs the DNS record changed. And kubeadm cannot add high availability later to a cluster made without `--control-plane-endpoint` (create-cluster page, quoted in FIRST-STEPS.md).

- do (the owner): in the DNS provider, a DNS-only A record `<endpoint name>` → the node's tailnet IP (`tailscale ip -4`). Update it after every rebuild.
- expect: `getent hosts <endpoint name>` returns the tailnet IP. (Proof run 1 used an `/etc/hosts` entry instead.)
- status: the DNS record is the owner's step. The proof runs used an `/etc/hosts` entry (PROOF-RUN-3.md).

#### 8. Init

why: This is the moment the cluster is born. `kubeadm init` makes the cluster's certificates, writes the control plane's pod files, starts etcd and the API server, and writes your admin kubeconfig (source: <https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/>).

```bash
kubeadm config images pull --kubernetes-version v1.36.5
kubeadm init --kubernetes-version v1.36.5 --control-plane-endpoint <endpoint name>:6443 \
  --pod-network-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12
mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
```

- ※ `--control-plane-endpoint` uses the name from [step 7](#7-endpoint-name). `--pod-network-cidr` is the range [step 4](#4-firewall-for-kubernetes-and-cilium-tailnet-zone-only) trusted. The pod range must not overlap the host's networks (create-cluster page).
- `--service-cidr` is where Service addresses come from (`10.96.0.1` is the API's own Service).
- Remember three places. You will come back to them:
  - `/etc/kubernetes/manifests/`: the control plane's pod files. The kubelet runs whatever is in this folder.
  - `/etc/kubernetes/pki/`: the certificates and the cluster CA.
  - `/etc/kubernetes/admin.conf`: the admin kubeconfig. It can do anything.
- expect: about 8 seconds; `openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName` lists the endpoint name; `grep server: /etc/kubernetes/admin.conf` shows the name, not an IP. Images: etcd 3.6.8-0, coredns v1.14.2, pause 3.10.2.
- note: the node is not Ready yet, and CoreDNS waits. Both need a network (next step).
- page: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/>
- status: **PROVEN** (PROOF-RUN-3.md). CKA: CA3.

#### 9. Cilium 1.20.4

why: A CNI gives pods a network: each pod gets an address and a way to reach the others. kubeadm does not install one. Until a CNI is in, CoreDNS will not start (create-cluster page; the kubeadm troubleshooting page calls its Pending state "expected"). This runbook uses Cilium; everything CNI-specific is kept in this one step, so another CNI could replace it here.

```bash
curl -fsSLO https://get.helm.sh/helm-v4.3.1-linux-amd64.tar.gz
curl -fsSL https://get.helm.sh/helm-v4.3.1-linux-amd64.tar.gz.sha256sum | sha256sum -c -
tar xzf helm-v4.3.1-linux-amd64.tar.gz && install -m 0755 linux-amd64/helm /usr/local/bin/helm
helm repo add cilium https://helm.cilium.io/ && helm repo update
helm install cilium cilium/cilium --version 1.20.4 -n kube-system \
  --set ipam.mode=cluster-pool --set "ipam.operator.clusterPoolIPv4PodCIDRList={10.244.0.0/16}" \
  --set devices=tailscale0 --set MTU=1230 --set kubeProxyReplacement=false --set operator.replicas=1
kubectl -n kube-system rollout status ds/cilium && kubectl -n kube-system rollout status deploy/coredns
```

- **Any CNI needs:** the same pod range as step 8. **Helm** installs packaged apps ("charts"); the checksum line proves the download is the real one. Helm is used again in step 26.
- **Cilium-specific settings:** `devices=tailscale0` (pod traffic goes over the tailnet); `MTU=1230` (the tailnet interface takes packets of at most 1280 bytes, measured, and Cilium's VXLAN wrapper needs room inside that; known limit: 1230 is below IPv6's 1280-byte minimum, so pod IPv6 can't work as built, research batch RB-0068; no change unless the owner picks IPv6); `kubeProxyReplacement=false` (kube-proxy kept for the first builds; step 27 depends on this; note: Cilium's L2 announcements and Cilium's own Gateway API both need `kubeProxyReplacement=true`, research batch RB-0067, so the ingress and load-balancer-address decisions may change this line; no change until the owner decides); `operator.replicas=1` (one node). Cilium also enforces NetworkPolicy (step 25). ※ With more than one node, `devices` alone does not put pod traffic on the tailnet; see the `--node-ip` note in [step 36](#36-high-availability-and-kubeadm-join-ca5-ca3). Swap the CNI and these lines change.
- ※ CoreDNS gets Ready here only because [step 4](#4-firewall-for-kubernetes-and-cilium-tailnet-zone-only) trusted the pod range: CoreDNS must reach the API server on the host (PROOF-RUN-1.md). Another CNI would likely need the same while firewalld is on; only Cilium was tested.
- expect: node Ready; CoreDNS 2/2. Value keys (`ipam.mode`, `ipam.operator.clusterPoolIPv4PodCIDRList`, `devices`, `MTU`, `kubeProxyReplacement`, `operator.replicas`) checked against the v1.20.4 values.yaml on 2026-10-24 (<https://raw.githubusercontent.com/cilium/cilium/v1.20.4/install/kubernetes/cilium/values.yaml>).
- versions (checked 2026-10-24): Cilium 1.20.4 (2026-10-23) is an out-of-band security patch (CVE-2026-111943, Go 1.26.10) that also fixes a 1.20.3 Gateway API BackendTLSPolicy regression (<https://github.com/cilium/cilium/releases/tag/v1.20.4>). Helm v4.3.1 (2026-10-15) is the current Helm patch release (<https://github.com/helm/helm/releases/tag/v4.3.1>). The proof runs used Cilium 1.20.3 and Helm v4.3.0; the value keys are the same in 1.20.4.
- page: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/> (section on the pod network add-on)
- status: **PROVEN** (PROOF-RUN-3.md: ready 32 s after install). CKA: CA7 (CNI), CA6 (Helm).

#### 10. Single node scheduling and a smoke test

why: By default, the control plane node carries a taint that keeps normal pods off it (create-cluster page). This is our only node, so remove it. Then one test pod proves the three things every app needs: an address, DNS, and a way out to the internet.

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl run t1 --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --restart=Never --command -- sleep 600
kubectl exec t1 -- nslookup kubernetes.default
kubectl exec t1 -- sh -c 'wget -q -T 8 -O /dev/null https://pkgs.k8s.io && echo egress-ok'
```

- ※ The DNS lines pass because of [step 3](#3-dns-that-pods-can-use) (the node's DNS) and [step 9](#9-cilium-1204) (CoreDNS up).
- expect: pod IP in 10.244.0.0/16; `kubernetes.default` → 10.96.0.1; egress-ok.
- page: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/> (section on control plane node isolation)
- status: **PROVEN** (PROOF-RUN-3.md). CKA: WS5 (partly), SN1 (partly).

#### 11. Backup and restore

why: etcd is the cluster's memory: it stores all the API server's data (source: <https://kubernetes.io/docs/concepts/overview/components/>). With one control plane, losing that node can lose the cluster's data; the create-cluster page's answer is "Regularly back up etcd". The plan is encrypted off-site backups to Azure Blob storage.

- Backup: `etcdctl snapshot save` inside the etcd pod (certs under `/etc/kubernetes/pki/etcd/`, write to `/var/lib/etcd`), then bundle the snapshot, `kubectl -n kube-system get cm kubeadm-config -o yaml` and `/etc/kubernetes/pki`, and `age -r <public key>`. The private key never sits on the VPS. Proof run: 5.2 MB snapshot, 1.1 MB encrypted bundle.
- Restore: move `/etc/kubernetes/manifests/*.yaml` out; wait for etcd and the apiserver to stop; move `/var/lib/etcd` aside; `etcdutl snapshot restore <db> --data-dir /var/lib/etcd --name <from etcd.yaml> --initial-cluster <name>=<peer url> --initial-advertise-peer-urls <peer url>`; move the manifests back. Proof run: 36 seconds; test data came back.
- ※ Moving the manifests out stops the control plane. That works because the kubelet runs whatever is in that folder ([step 8](#8-init)).
- Tools: etcdutl from the etcd v3.6.8 release tarball (checked against SHA256SUMS; it matches the etcd image kubeadm 1.36.5 runs; the newest 3.6.x is v3.6.16, <https://github.com/etcd-io/etcd/releases>, checked 2026-10-24); age v1.3.2 (**signature not yet verified**).
- Restore onto a rebuilt VPS (proven, PROOF-RUN-2.md): after steps 0-6, copy only the CA files (`ca.*`, `sa.*`, `front-proxy-ca.*`, `etcd/ca.*`) to `/etc/kubernetes/pki`; `etcdutl snapshot restore` with the new node name and `https://<advertise IP>:2380`; then the step 8 `kubeadm init` plus `--ignore-preflight-errors=DirAvailable--var-lib-etcd`; then `kubectl delete node <old node>`. Cilium returns from etcd; skip step 9 except installing Helm.
- **Not yet proven:** upload to Azure Blob with a short immutability lock. Deferred by the owner on 2026-10-17 until the repo layout and an Azure config-as-code tool are chosen; until then, recovery is a rebuild from configuration.
- note: after step 17 the cluster runs etcd 3.7.0. The etcdutl 3.6.8 tool above was not tested against a 3.7.0 snapshot.
- status: local backup and restore **PROVEN** (PROOF-RUN-1.md); restore onto a rebuilt VPS **PROVEN** (PROOF-RUN-2.md); Azure upload **NOT PROVEN** (deferred). CKA: CA4.

---

### Part 2. Run it and fix it (the CKA)

Start here once step 10 passes. Step 11 (backups) is still deferred, so you can skip it.

**Why this part exists.** Part 1 covers only 1 of the CKA's 27 topics fully (SYNTHESIS). It builds the cluster but does almost nothing *inside* it. And the fixes in Part 1 were found by the agent: you replay them, you don't diagnose them. Troubleshooting is 30% of the exam, the biggest part (SYNTHESIS). So Part 2 starts with looking and breaking things, then works through the rest in the synthesis's gap order.

#### Exam habits (do these once, first)

why: The exam is 15-20 hands-on tasks in 2 hours, and the timer never stops (SYNTHESIS). Speed comes from aliases, dry-run YAML and knowing where the docs are. The exam gives every host a `k` alias, Bash completion and `yq`. Set up the same on your node.

```bash
dnf -y install bash-completion
cat >> /root/.bashrc <<'B'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
B
exec bash                                                       # reload the shell
k get nodes                                                     # the alias works
k run web --image=nginx $do                                     # print a Pod's YAML without creating it
kubectl create deployment web --image=nginx --replicas=2 --dry-run=client -o yaml > web.yaml   # start a file, then edit it
kubectl explain pod.spec.containers.livenessProbe               # field docs, offline
kubectl explain deployment.spec.strategy --recursive            # every field under it
kubectl api-resources | grep -i netpol                          # short names and API groups
kubectl config get-contexts                                     # which cluster am I on?
```

- expect: `type k` says `k is aliased to kubectl`; `complete -p k` shows the completion line; the `$do` command prints YAML and creates nothing.
- Using the docs: in the exam you may open kubernetes.io/docs (and its search), the Kubernetes blog, helm.sh/docs and, for the CKA only, gateway-api.sigs.k8s.io (SYNTHESIS, "The exam, in facts"). Every step below names its page: open it while you practise, so you know where things are. Many steps apply the page's own example with `kubectl apply -f https://k8s.io/examples/...`, which is the fastest way to get a correct file.
- Exam habit: always check the context and namespace first. Working in the wrong one is a common way to lose time.
- page: <https://kubernetes.io/docs/reference/kubectl/quick-reference/>
- status: **PROVEN 2026-10-19** (`yq` was not installed; the exam has it).

#### 12. Container logs (TS4)

why: Logs are the first place to look when something is wrong. `kubectl logs` reads them through the API server. When the API server itself is broken, the same logs are still on the node, and `crictl` and `journalctl` can read them.

```bash
kubectl apply -f https://k8s.io/examples/debug/counter-pod.yaml
kubectl logs counter                                  # all output so far
kubectl logs counter --tail=2                         # last 2 lines
kubectl logs counter --since=3s                       # last 3 seconds
kubectl logs -f counter                               # follow; Ctrl+C to stop
kubectl delete pod counter

# a container that crashes and restarts
kubectl run crash --image=busybox:1.28 -- sh -c 'echo started at $(date +%T); sleep 20; echo failing; exit 1'
kubectl get pod crash -w                              # wait until RESTARTS is 1 and STATUS is Running, then Ctrl+C
kubectl logs crash --previous                         # the output of the container that died
kubectl delete pod crash --now

# a pod with several containers
kubectl apply -f https://k8s.io/examples/admin/logging/two-files-counter-pod-streaming-sidecar.yaml
kubectl logs counter count-log-1                      # one container, by name
kubectl logs counter -c count-log-2                   # the same, with -c
kubectl logs counter --all-containers --tail=1

# the same logs on the node
ls /var/log/pods/                                     # one folder per pod: <namespace>_<pod>_<uid>
crictl ps --name count-log-1                          # find the container ID
crictl logs --tail=1 <container id>
journalctl -u kubelet -n 20                           # the kubelet itself logs to the journal, not to a pod
kubectl delete pod counter --now
```

- ※ `crictl` works with no extra flags because [step 6](#6-kubeadm-kubelet-kubectl-1365) wrote `/etc/crictl.yaml`.
- ※ The kubelet logs to the journal because it is a systemd service, not a pod. [Step 6](#6-kubeadm-kubelet-kubectl-1365) started it with `systemctl`.
- expect: `kubectl logs counter` prints numbered lines; `--previous` prints `started at ...` and `failing`; `count-log-1` and `count-log-2` print different formats; `/var/log/pods/default_counter_<uid>/` has one folder per container.
- catch: `--previous` only works while the new container is running. If the pod is in `Error` or `CrashLoopBackOff`, the dead container is the "current" one: use plain `kubectl logs crash` instead (the kubelet keeps only one dead container). (Found in PROOF-RUN-4.md.)
- catch: the sidecar example is also called `counter`. Delete the first `counter` pod before you apply it.
- page: <https://kubernetes.io/docs/concepts/cluster-administration/logging/>
- status: **PROVEN 2026-10-19**.

#### 13. metrics-server and `kubectl top` (TS3)

why: `kubectl top` and the autoscaler (step 33) need live CPU and memory numbers. Nothing in a kubeadm cluster collects them until you install metrics-server.

**The kubeadm catch.** metrics-server talks to each kubelet over TLS. On kubeadm the kubelet's serving certificate is self-signed, so metrics-server refuses it. metrics-server's README (<https://github.com/kubernetes-sigs/metrics-server>) offers two ways out: a kubelet certificate signed by the cluster CA, or the `--kubelet-insecure-tls` flag ("for testing purposes only"). **This runbook uses the first**, because it is the one kubernetes.io documents ("Enabling signed kubelet serving certificates" on the kubeadm certificates page). It means you must approve one certificate request per node by hand, now and about once a year when it renews.

```bash
# 1. Tell kubeadm's stored kubelet settings to ask for a signed certificate
kubectl -n kube-system edit cm kubelet-config         # under "kind: KubeletConfiguration" add the line:  serverTLSBootstrap: true
# 2. Tell this node's kubelet the same, and restart it
echo 'serverTLSBootstrap: true' >> /var/lib/kubelet/config.yaml
systemctl restart kubelet
# 3. The kubelet now asks for a certificate. Look at the request, then approve it
kubectl get csr                                       # a kubernetes.io/kubelet-serving request, Pending
kubectl get csr <csr name> -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text | grep -E 'Subject:|DNS:'
kubectl certificate approve <csr name>
openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -issuer -enddate
# 4. Install metrics-server v0.9.0 (supports Kubernetes 1.34+)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
kubectl -n kube-system rollout status deploy/metrics-server
kubectl top node
kubectl top pod -A --sort-by=memory
```

- ※ The certificate is signed by the cluster CA that [step 8](#8-init) made in `/etc/kubernetes/pki/`.
- Why two places for one setting: the kubelet reads only `/var/lib/kubelet/config.yaml`. kubeadm keeps the cluster's copy in the `kubelet-config` ConfigMap and writes it over that file at join and at every `kubeadm upgrade`. Change only the file, and the next upgrade undoes it (source: <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/>).
- expect: the request is from `system:node:<node name>` and names only your node (its name and its addresses); after approval it shows `Approved,Issued`; the certificate's issuer is `CN=kubernetes` (the cluster CA), valid one year; `kubectl get apiservice v1beta1.metrics.k8s.io` shows `True`; `kubectl top node` shows CPU and memory.
- why check the request first: the kubeadm certificates page warns that an approver that does not check the requested names and IPs lets anyone with a kubelet client certificate get a serving certificate for any name. Here you are the approver, so check the names before you approve.
- note: the agent did step 1 with a one-line `sed` piped to `kubectl apply` instead of `edit`; the result is the same line. After step 17 the setting was still there (the upgrade keeps it).
- page: <https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/> and <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#kubelet-serving-certs>
- status: **PROVEN 2026-10-19**. `kubectl top` worked about 30 s after metrics-server was ready.

#### 14. Drill A: the kubelet is stopped (TS1)

why: The kubelet is the agent that runs pods on the node. If it stops, the node goes `NotReady` and nothing new starts. "Fix a broken kubelet" is a common exam task (SYNTHESIS). Here you break it on purpose, so you learn the symptoms.

- **break:** `systemctl stop kubelet`
- **symptom:** after about 45 s, `kubectl get nodes` shows `NotReady`. New pods stay `Pending`. The control plane still answers, because its containers keep running without the kubelet.
- **diagnose** (the standard commands from the Troubleshooting Clusters page):

```bash
kubectl get nodes
kubectl describe node <node name>        # Conditions: "Kubelet stopped posting node status."; Taints: node.kubernetes.io/unreachable
systemctl status kubelet                 # Active: inactive (dead)
journalctl -u kubelet -n 20              # "Stopped kubelet.service"
```

- **fix:** `systemctl start kubelet` (and `systemctl enable kubelet` if it was disabled).
- ※ The control plane survives because its containers belong to containerd ([step 5](#5-containerd-236)), not to the kubelet (the drill showed it: kubectl kept answering, PROOF-RUN-4.md). `systemctl enable` in [step 6](#6-kubeadm-kubelet-kubectl-1365) is what brings the kubelet back after a reboot.
- expect: node `Ready` again within seconds; the pending pod starts.
- catch: finish within 5 minutes. After 5 minutes of `NotReady`, pods are evicted (the page says so).
- page: <https://kubernetes.io/docs/tasks/debug/debug-cluster/>
- status: **PROVEN 2026-10-19**. NotReady after 46 s; Ready 2 s after the restart.

#### 15. Drill B: a broken static pod manifest (TS2)

why: The control plane parts (API server, scheduler, controller-manager, etcd) are "static pods": files the kubelet runs straight from a folder. One typo in a file and that part stops. Learn to find which part and why.

```bash
mkdir -p /root/drill && cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/drill/kube-scheduler.yaml.good   # backup OUTSIDE the manifests folder
sed -i 's#--kubeconfig=/etc/kubernetes/scheduler.conf#--kubeconfig=/etc/kubernetes/scheduler.conff#' /etc/kubernetes/manifests/kube-scheduler.yaml
```

- ※ This is the folder [step 8](#8-init) wrote. [Step 11](#11-backup-and-restore)'s restore uses the same trick: move files out to stop a part, move them back to start it.
- **symptom:** `kubectl run p --image=busybox:1.28 -- sleep 600` stays `Pending` with **no events** (nobody is scheduling it).
- **diagnose:**

```bash
kubectl -n kube-system get pods                  # kube-scheduler-<node name> in CrashLoopBackOff
crictl ps -a --name kube-scheduler               # Exited, ATTEMPT going up
crictl logs <container id>                       # "stat /etc/kubernetes/scheduler.conff: no such file or directory"
kubectl -n kube-system logs kube-scheduler-<node name>    # the same message
journalctl -u kubelet | grep -i scheduler | tail # back-off messages from the kubelet
```

- **fix:** `cp /root/drill/kube-scheduler.yaml.good /etc/kubernetes/manifests/kube-scheduler.yaml` (or correct the typo with an editor). The kubelet watches that folder and restarts the pod by itself.
- expect: the scheduler pod is `Running`; the pending pod starts. Then `kubectl delete pod p`.
- catch: never keep backup copies inside `/etc/kubernetes/manifests`. The kubelet runs every manifest in that folder.
- catch: if `kubectl` itself stops working, the broken component is the API server or etcd. Then only `crictl` and `journalctl` on the node can help. ※ That is why [step 12](#12-container-logs-ts4) practised them.
- page: <https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/> and <https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/>
- status: **PROVEN 2026-10-19**. The pending pod ran 16 s after the fix.

#### 16. Drill C: a Service with a wrong selector (TS5)

why: A Service finds its pods by their labels. One wrong letter and it finds none. DNS still works, so it looks like the app is down. It is not. Learn to check each link in the chain, in order.

```bash
kubectl create deployment hostnames --image=registry.k8s.io/serve_hostname
kubectl scale deployment hostnames --replicas=3
kubectl expose deployment hostnames --port=80 --target-port=9376
kubectl run tmp --image=registry.k8s.io/busybox:1.27.2 --restart=Never -- sleep 600
kubectl exec tmp -- wget -qO- -T 3 hostnames                       # works: prints a pod name
kubectl patch svc hostnames -p '{"spec":{"selector":{"app":"hostname"}}}'   # break: one letter missing
```

- **symptom:** a few seconds later, `kubectl exec tmp -- wget -qO- -T 3 hostnames` fails with `Connection refused`. DNS still resolves the name, so it looks like the app is down. It is not.
- **diagnose** (the Debug Services page, in order):

```bash
kubectl exec tmp -- nslookup hostnames                              # DNS works
kubectl get svc hostnames -o jsonpath='{.spec.selector}'            # {"app":"hostname"}
kubectl get endpointslices -l kubernetes.io/service-name=hostnames  # ENDPOINTS <unset>: the Service selects no pods
kubectl get pods --show-labels                                      # the pods say app=hostnames
```

- **fix:** `kubectl patch svc hostnames -p '{"spec":{"selector":{"app":"hostnames"}}}'` (or `kubectl edit svc hostnames`).
- expect: the EndpointSlice lists 3 addresses on port 9376; `wget` prints pod names again.
- clean up: `kubectl delete deploy hostnames; kubectl delete svc hostnames; kubectl delete pod tmp`
- catch: the change takes a second or two to reach kube-proxy. In the proof, a `wget` right after the patch still worked; wait 5 s before you check the symptom.
- page: <https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/>
- status: **PROVEN 2026-10-19**.

#### 17. Upgrade the cluster from 1.36.5 to 1.37.1 (CA4)

why: Kubernetes patches only its three newest minor versions, each for about a year (source: <https://kubernetes.io/releases/>), so every cluster must be upgraded. This runbook started you on 1.36 exactly so you could do this once for real. 1.37 is the exam's version as of 2026-10-24; the exam moves to a new minor about 4-8 weeks after its release, and 1.38.0 is due 2026-12-16 (<https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks> ; <https://github.com/kubernetes/sig-release/tree/master/releases/release-1.38>).

Read first: on one node, **draining stops every workload**, and you cannot skip a minor version (1.36 → 1.37 only; upgrade page).
**Known risk:** as of 2026-10-24, Cilium 1.20's compatibility page (stable, 1.20.4) lists Kubernetes 1.33-1.36 as tested, not 1.37, and Cilium 1.21 is still a pre-release (<https://docs.cilium.io/en/stable/network/kubernetes/compatibility/> ; <https://github.com/cilium/cilium/releases>). It worked in the proof (Cilium 1.20.3), but it is outside what Cilium tests.

```bash
kubeadm certs check-expiration                                    # before: note the dates
cp /etc/yum.repos.d/kubernetes.repo /root/kubernetes.repo.v1.36
sed -i 's#/v1\.36/#/v1.37/#g' /etc/yum.repos.d/kubernetes.repo      # switch the package repo to 1.37 (baseurl and gpgkey)
dnf list --showduplicates kubeadm --disableexcludes=kubernetes   # find the newest 1.37.x
dnf -y install kubeadm-'1.37.1-*' --disableexcludes=kubernetes
kubeadm version -o short                                          # v1.37.1
kubeadm upgrade plan                                              # shows what will change
kubeadm upgrade apply v1.37.1                                     # answer y (or add --yes)
kubectl drain <node name> --ignore-daemonsets --delete-emptydir-data
dnf -y install kubelet-'1.37.1-*' kubectl-'1.37.1-*' --disableexcludes=kubernetes
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon <node name>
```

- The order matters: kubeadm first, then the control plane, then the kubelet. `drain` moves pods off the node before the kubelet restarts; `uncordon` lets them back.
- ※ The package repo has one folder per minor version, and [step 6](#6-kubeadm-kubelet-kubectl-1365)'s `exclude` line is why every install here needs `--disableexcludes`.
- expect: `kubectl get nodes` shows `Ready` and `v1.37.1`; `kubectl version` shows client and server v1.37.1; every pod in `kubectl get pods -A` is `Running` again (give it a minute); the step 10 smoke test passes; `kubectl top node` works.
- what you will see: `kubeadm upgrade plan` showed etcd 3.6.8-0 → 3.7.0-0 and CoreDNS v1.14.2 → v1.14.6. `upgrade apply` took 174 s. kubeadm keeps backups of the old manifests and etcd data in `/etc/kubernetes/tmp/` (delete them by hand later).
- catch: `drain` without `--delete-emptydir-data` stops at metrics-server (it uses an emptyDir). ※ That is the metrics-server from [step 13](#13-metrics-server-and-kubectl-top-ts3).
- catch: while drained, CoreDNS, metrics-server and cilium-operator are `Pending`. That is expected on one node.
- catch: for about a minute after `uncordon`, `nslookup` and `kubectl top` can fail while CoreDNS and metrics-server start. Retry before you look for a fault.
- note: AlmaLinux 10.2 has DNF 4 (4.20), so the page's "DNF4" flag `--disableexcludes` is the right one. cri-tools stays at 1.36; the page does not upgrade it.
- note: Cilium is a separate Helm release. kubeadm does not upgrade it; the page says to check your CNI's own upgrade notes. ※ It was installed by Helm in [step 9](#9-cilium-1204), outside kubeadm.
- page: <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/> ; <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/> ; <https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/>
- status: **PROVEN 2026-10-19** (zero new SELinux denials under Enforcing).

#### 18. Certificates: check and renew (CA4)

why: The parts of the cluster prove who they are with certificates. kubeadm's client certificates expire after 1 year, its CAs after 10 (source: <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/>). The 1-year ones include `admin.conf` (your kubectl) and the scheduler's and controller-manager's. An expired one is refused with `x509: certificate has expired or is not yet valid` (source: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/>), so whatever uses it can no longer talk to the API server. Know how to check and renew them.

```bash
kubeadm certs check-expiration                     # each certificate's expiry; the CAs last 10 years
kubeadm certs renew all
# restart the control plane so it loads the new certificates (static pods cannot be restarted with kubectl)
mkdir -p /root/manifests-off && mv /etc/kubernetes/manifests/*.yaml /root/manifests-off/
sleep 25                                           # wait until crictl ps shows no kube-apiserver
mv /root/manifests-off/*.yaml /etc/kubernetes/manifests/
cp /etc/kubernetes/admin.conf /root/.kube/config   # admin.conf was renewed too
kubeadm certs check-expiration
```

- ※ These are the certificates [step 8](#8-init) made. The restart is the move-out, move-back trick from [step 15](#15-drill-b-a-broken-static-pod-manifest-ts2). The `cp` is the same line as in step 8.
- expect: `check-expiration` shows new dates (one year from now); `openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -serial` matches `echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null | openssl x509 -noout -serial` (the API server serves the new certificate); `kubectl get nodes` works.
- note: `kubeadm upgrade apply` (step 17) already renews all these certificates. Upgrading at least once a year is the simple way to keep them valid.
- note: the kubelet's own certificates (`/var/lib/kubelet/pki`) are not in this list; the kubelet rotates them. The serving one from step 13 needs a fresh `kubectl certificate approve` each year.
- page: <https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/>
- status: **PROVEN 2026-10-19**. API back 11 s after the manifests returned.

#### 19. RBAC: a ServiceAccount, a Role, a RoleBinding (CA1)

why: Until now you used the admin kubeconfig, which can do anything. Apps and people should get only what they need. RBAC is how: a Role says what is allowed, a RoleBinding says who gets it.

```bash
kubectl create namespace dev
kubectl -n dev create serviceaccount dev-sa
kubectl -n dev create role pod-reader --verb=get --verb=list --verb=watch --resource=pods
kubectl -n dev create rolebinding dev-sa-pod-reader --role=pod-reader --serviceaccount=dev:dev-sa
kubectl auth can-i list pods   --namespace dev     --as system:serviceaccount:dev:dev-sa    # yes
kubectl auth can-i delete pods --namespace dev     --as system:serviceaccount:dev:dev-sa    # no
kubectl auth can-i list pods   --namespace default --as system:serviceaccount:dev:dev-sa    # no
kubectl auth can-i --list --namespace dev --as system:serviceaccount:dev:dev-sa
# use the ServiceAccount's own token (an empty kubeconfig, so your admin certificate is not sent)
TOKEN=$(kubectl -n dev create token dev-sa --duration=10m)
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl --kubeconfig=/dev/null --server=$SERVER --certificate-authority=/etc/kubernetes/pki/ca.crt --token=$TOKEN -n dev get pods
kubectl --kubeconfig=/dev/null --server=$SERVER --certificate-authority=/etc/kubernetes/pki/ca.crt --token=$TOKEN -n default get pods
kubectl delete namespace dev
```

- ※ The admin kubeconfig is the `admin.conf` you copied in [step 8](#8-init). `ca.crt` is the cluster CA from the same step.
- expect: the three `can-i` answers are yes, no, no; with the token, `-n dev get pods` works and `-n default get pods` is `Forbidden ... User "system:serviceaccount:dev:dev-sa" cannot list resource "pods"`.
- catch: `kubectl --token=...` with your normal kubeconfig still sends the admin client certificate, and the certificate wins. The proof hit this; use `--kubeconfig=/dev/null` as above.
- page: <https://kubernetes.io/docs/reference/access-authn-authz/rbac/> ; `can-i`: <https://kubernetes.io/docs/reference/access-authn-authz/authorization/>
- status: **PROVEN 2026-10-19**.

#### 20. kubeadm: tokens, a config file, reset (CA3)

why: Three kubeadm skills the exam asks for. A token lets a new node join. A config file replaces step 8's long flags with one file you can keep and re-use. Reset wipes the node so you can start over.

**20a. Tokens** (what a second node needs to join)

```bash
kubeadm token list
kubeadm token create --print-join-command     # prints "kubeadm join <endpoint name>:6443 --token ... --discovery-token-ca-cert-hash sha256:..."
kubeadm token list                            # the new token, valid 23-24 h
kubeadm token delete <token id>
```

- ※ The join command names the endpoint from [step 7](#7-endpoint-name), not an IP.
- expect: the join command names your endpoint; the token disappears from `token list` after `delete`. Treat a printed token as a secret.
- status: **PROVEN 2026-10-19**.

**20b. A kubeadm config file** (replaces the flags of step 8)

```bash
kubeadm config print init-defaults            # every field, with defaults
cat > /root/kubeadm-config.yaml <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.37.1
controlPlaneEndpoint: "<endpoint name>:6443"
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
serverTLSBootstrap: true                      # step 13's setting, from the start
EOF
kubeadm config validate --config /root/kubeadm-config.yaml
kubeadm config images list --config /root/kubeadm-config.yaml
```

- ※ Each line maps to a flag in [step 8](#8-init), plus the kubelet setting from [step 13](#13-metrics-server-and-kubectl-top-ts3). This file is your first piece of configuration as code.
- expect: `validate` prints `ok`; the image list is kube-* v1.37.1, coredns v1.14.6, pause 3.10.2, etcd 3.7.0-0.
- status: **PROVEN 2026-10-19** (validated; not used for an init, see 20c).

**20c. Reset and init again from the file** (this deletes the cluster)

```bash
kubeadm reset --dry-run -f                    # shows what reset would delete; changes nothing
kubeadm reset -f
rm -rf /etc/cni/net.d /root/.kube             # reset does not clean these (the reset page says so)
kubeadm init --config /root/kubeadm-config.yaml
mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
# then step 9 (Cilium) and step 10 (taint, smoke test); approve the kubelet-serving CSR and apply metrics-server as in step 13
```

- ※ Reset does not touch the host work of [steps 1-6](#1-lock-down-the-host) (firewall, kernel settings, packages). That is why you can init again right away.
- expect: as steps 8-10; `grep serverTLSBootstrap /var/lib/kubelet/config.yaml` shows `true` without editing anything.
- status: `reset --dry-run` **PROVEN 2026-10-19** (it lists: remove the etcd member, empty `/var/lib/etcd`, stop the kubelet, remove containers, empty `/etc/kubernetes/manifests` and `pki`, delete the kubeconfig files; and says it does not clean CNI config, firewall rules or kubeconfig). The real `reset -f` and `init --config` are **NOT PROVEN**: the agent's tool permissions refused `kubeadm reset` on the node, so the agent did not run it.
- page: <https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/> ; <https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/> ; <https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/> ; <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/>

#### 21. Kustomize (CA6)

why: You often need the same app in slightly different forms (dev and prod: other names, other namespace). Kustomize keeps one base and layers small changes on top, without copying or editing the base. It is built into kubectl.

A base, and a `dev` overlay that changes the name, namespace and labels without editing the base.

```bash
mkdir -p /root/kustomize/base /root/kustomize/dev && cd /root/kustomize
cat > base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      run: my-nginx
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: app-config
EOF
cat > base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
configMapGenerator:
- name: app-config
  literals:
  - GREETING=hello
EOF
cat > dev/kustomization.yaml <<'EOF'
resources:
- ../base
namespace: kustomize-dev
namePrefix: dev-
labels:
- pairs:
    env: dev
EOF
kubectl create namespace kustomize-dev
kubectl kustomize dev/                                    # see the result; nothing is applied
kubectl apply -k dev/
kubectl get -k dev/
kubectl -n kustomize-dev exec deploy/dev-my-nginx -- printenv GREETING     # hello
sed -i 's/GREETING=hello/GREETING=hi/' base/kustomization.yaml
kubectl diff -k dev/                                      # a new ConfigMap name (new hash) and the Deployment pointing to it
kubectl apply -k dev/
kubectl -n kustomize-dev exec deploy/dev-my-nginx -- printenv GREETING     # hi
kubectl delete -k dev/ && kubectl delete namespace kustomize-dev
```

- expect: names come out as `dev-my-nginx` and `dev-app-config-<hash>` in namespace `kustomize-dev`; changing the literal changes the hash, which rolls the Deployment and the pod sees `hi`.
- note: Kustomize is built into kubectl (v5.8.1 on 1.37.1). Helm is already used for Cilium (step 9). The same `kubectl apply -k <folder>` installs a cluster component that ships a kustomization. ※ The CKA topic names both tools; you used Helm in [step 9](#9-cilium-1204).
- page: <https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/>
- status: **PROVEN 2026-10-19**.

#### 22. CustomResourceDefinitions (CA8)

why: Kubernetes can learn new kinds of objects. A CRD teaches it one. Tools like Cilium add their own kinds this way, and an "operator" is a program that watches those objects and acts on them.

```bash
kubectl get crd                                           # Cilium already installed 10 CRDs
kubectl api-resources --api-group=cilium.io
kubectl explain ciliumnetworkpolicies.spec
mkdir -p /root/crd && cd /root/crd
cat > resourcedefinition.yaml <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                cronSpec:
                  type: string
                image:
                  type: string
                replicas:
                  type: integer
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames:
    - ct
EOF
cat > my-crontab.yaml <<'EOF'
apiVersion: "stable.example.com/v1"
kind: CronTab
metadata:
  name: my-new-cron-object
spec:
  cronSpec: "* * * * */5"
  image: my-awesome-cron-image
EOF
kubectl apply -f resourcedefinition.yaml
kubectl wait --for=condition=Established crd/crontabs.stable.example.com
kubectl apply -f my-crontab.yaml
kubectl get crontab ; kubectl get ct -o yaml
kubectl explain crontab.spec
kubectl patch ct my-new-cron-object --type=merge -p '{"spec":{"replicas":"three"}}'   # rejected by the schema
kubectl delete -f resourcedefinition.yaml                 # also deletes every CronTab
```

- expect: `kubectl get crontab` lists `my-new-cron-object`; `explain` shows the three fields; the patch fails with `spec.replicas in body must be of type integer`; after the delete, `kubectl get crontab` says the server does not know the resource.
- operators: cilium-operator (installed in step 9) is an operator. It watches Cilium's CRDs and acts on them. Its options are Helm values, for example `operator.replicas=1` in step 9. ※ See [step 9](#9-cilium-1204).
- page: <https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/> ; <https://kubernetes.io/docs/concepts/extend-kubernetes/operator/>
- status: **PROVEN 2026-10-19**.

#### 23. Services: ClusterIP, NodePort, LoadBalancer (SN3)

why: Pods come and go, and each new pod gets a new address. A Service gives a group of pods one address and name that stay put. The three types decide who can reach it: only the cluster (ClusterIP), a port on the node (NodePort), or an outside load balancer (LoadBalancer).

```bash
kubectl apply -f https://k8s.io/examples/service/networking/run-my-nginx.yaml     # Deployment my-nginx, 2 pods
kubectl get pods -l run=my-nginx -o custom-columns=POD_IP:.status.podIPs
kubectl expose deployment/my-nginx                                                # ClusterIP Service
kubectl get svc my-nginx
kubectl get endpointslices -l kubernetes.io/service-name=my-nginx                 # the two pod IPs, port 80
kubectl patch svc my-nginx -p '{"spec":{"type":"NodePort"}}'
kubectl get svc my-nginx                                                          # PORT(S) 80:3xxxx/TCP
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<node port>            # 200 (wait a few seconds after the patch)
kubectl expose deployment my-nginx --name=my-nginx-lb --type=LoadBalancer --port=80
kubectl get svc my-nginx-lb                                                       # EXTERNAL-IP <pending>
kubectl delete svc my-nginx-lb
kubectl patch svc my-nginx -p '{"spec":{"type":"ClusterIP"}}'                     # keep it for step 24
```

- ※ The ClusterIP comes from the `--service-cidr` in [step 8](#8-init). The EndpointSlice is the same list that was empty in [step 16](#16-drill-c-a-service-with-a-wrong-selector-ts5).
- expect: the EndpointSlice lists both pod IPs; the NodePort answers 200 on the node; the LoadBalancer Service stays `<pending>`, because nothing on this VPS hands out load-balancer addresses.
- **security note:** do not leave NodePort Services running. firewalld does not list ports 30000-32767, but the proof found that firewalld's forward chain accepts all DNAT'd traffic (`ct status dnat accept`), and kube-proxy reaches a NodePort by DNAT. So a NodePort may be reachable on the VPS's public address. The agent could not test this from outside (no outside test point). See PROOF-RUN-4.md. ※ So [step 1](#1-lock-down-the-host)'s public zone does not cover this path.
- page: <https://kubernetes.io/docs/concepts/services-networking/service/> ; <https://kubernetes.io/docs/tutorials/services/connect-applications-service/>
- status: **PROVEN 2026-10-19** (ClusterIP, EndpointSlices, NodePort from the node, LoadBalancer pending).

#### 24. Pod-to-pod traffic across namespaces (SN1)

why: In Kubernetes, every pod can reach every other pod by its address, on any node, unless something blocks it on purpose, such as a NetworkPolicy (source: <https://kubernetes.io/docs/concepts/services-networking/>). Namespaces do not block it (this step shows it). Names are different: a short Service name is looked up only in the pod's own namespace (source: <https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/>). Know both.

Needs `my-nginx` from step 23.

```bash
kubectl create namespace other
kubectl -n other run client --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --restart=Never --command -- sleep 900
P=$(kubectl get pods -l run=my-nginx -o jsonpath='{.items[0].status.podIP}')
kubectl -n other exec client -- curl -s -o /dev/null -w '%{http_code}\n' http://$P                          # pod IP directly
kubectl -n other exec client -- curl -s -o /dev/null -w '%{http_code}\n' http://my-nginx.default.svc.cluster.local
kubectl -n other exec client -- curl -s -m 5 http://my-nginx       # fails: the short name only works in the same namespace
kubectl delete namespace other; kubectl delete svc my-nginx; kubectl delete deploy my-nginx
```

- ※ The pod addresses come from Cilium ([step 9](#9-cilium-1204)).
- expect: 200 to the pod IP; 200 to the full Service name; the short name fails from another namespace (curl exit code 6, name not found).
- page: <https://kubernetes.io/docs/tutorials/services/connect-applications-service/>
- status: **PROVEN 2026-10-19**.

#### 25. NetworkPolicy (SN2)

why: Step 24 showed every pod can reach every pod. A NetworkPolicy closes that down: only the traffic you allow gets through. A policy only works if the CNI enforces it (source: <https://kubernetes.io/docs/concepts/services-networking/network-policies/>). Cilium does, so these work.

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80
kubectl run busybox --rm -it --restart=Never --image=busybox -- wget --spider --timeout=1 nginx                  # remote file exists
kubectl apply -f https://k8s.io/examples/service/networking/nginx-policy.yaml                                    # only pods labelled access=true may connect
kubectl run busybox --rm -it --restart=Never --image=busybox -- wget --spider --timeout=1 nginx                  # download timed out
kubectl run busybox --rm -it --restart=Never --labels="access=true" --image=busybox -- wget --spider --timeout=1 nginx   # remote file exists
kubectl get networkpolicy ; kubectl describe networkpolicy access-nginx
# default deny for a whole namespace
kubectl create namespace np-demo
kubectl -n np-demo create deployment web --image=nginx
kubectl -n np-demo expose deployment web --port=80
kubectl -n np-demo run t --rm -it --restart=Never --image=busybox -- wget --spider --timeout=2 web              # works
kubectl apply -n np-demo -f https://k8s.io/examples/service/networking/network-policy-default-deny-ingress.yaml
kubectl -n np-demo run t --rm -it --restart=Never --image=busybox -- wget --spider --timeout=2 web              # download timed out
kubectl delete namespace np-demo; kubectl delete networkpolicy access-nginx; kubectl delete svc nginx; kubectl delete deploy nginx
```

- ※ The enforcement comes from the Cilium you installed in [step 9](#9-cilium-1204). The policy selects pods by label, the same way the Service did in [step 16](#16-drill-c-a-service-with-a-wrong-selector-ts5).
- expect: as the comments say: blocked without the label, allowed with it; in `np-demo`, everything is blocked after the default-deny policy.
- note: the page recommends two worker nodes; on one node the policy is still enforced (proven here).
- page: <https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/> ; default deny: <https://kubernetes.io/docs/concepts/services-networking/network-policies/>
- status: **PROVEN 2026-10-19**.

#### 26. Ingress (SN5)

why: You don't want one open port per app. An Ingress is one front door that sends each request to the right Service by its host name or path. It does nothing without a controller, the program that does the sending (the page says so).

ingress-nginx is retired (source: <https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/>), so this uses **Traefik**, which also implements the Gateway API (step 27). One install covers both. Cilium is not changed (`kubeProxyReplacement` stays `false`).

```bash
# the Gateway API CRDs, version 1.6.3 (the version Traefik v3.7.16 is built against); needed by step 27, harmless here
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm install traefik traefik/traefik --version 42.1.3 -n traefik --create-namespace \
  --set providers.kubernetesGateway.enabled=true \
  --set gateway.listeners.web.namespacePolicy.from=All \
  --set service.spec.type=ClusterIP                     # no LoadBalancer or NodePort: nothing new is exposed on the node
kubectl -n traefik rollout status deploy/traefik
kubectl get ingressclass                                # traefik (default)
kubectl create deployment web1 --image=registry.k8s.io/serve_hostname
kubectl expose deployment web1 --port=80 --target-port=9376
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web1-ingress
spec:
  ingressClassName: traefik
  rules:
  - host: web1.lab.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web1
            port:
              number: 80
EOF
kubectl run client --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --restart=Never --command -- sleep 600
kubectl exec client -- curl -s -H 'Host: web1.lab.test' http://traefik.traefik.svc.cluster.local          # a web1 pod name
kubectl exec client -- curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: nothing.lab.test' http://traefik.traefik.svc.cluster.local   # 404
```

- ※ Traefik stays ClusterIP because of the NodePort finding in [step 23](#23-services-clusterip-nodeport-loadbalancer-sn3). The Gateway API files are CRDs, like the ones in [step 22](#22-customresourcedefinitions-ca8).
- expect: `kubectl get ingress` lists `web1-ingress`; the request with `Host: web1.lab.test` returns a `web1-...` pod name; an unknown host returns 404.
- note: `.test` is a name reserved for testing; nothing outside the cluster resolves it, which is why the test sends the `Host` header by hand.
- choice made by the agent: Traefik chart 42.1.3 (Traefik v3.7.16, chart published 2026-10-22; <https://traefik.github.io/charts/index.yaml>). v3.7.14-v3.7.16 fix 12 security advisories (<https://github.com/traefik/traefik/releases>), so this pin takes the security fixes instead of waiting two weeks. Chart 42 needs Kubernetes 1.30 or later and changes nothing this step sets (<https://github.com/traefik/traefik-helm-chart/releases/tag/v42.0.0>). Envoy Gateway or NGINX Gateway Fabric would also do for step 27; Traefik was picked because one install also covers Ingress.
- page: <https://kubernetes.io/docs/concepts/services-networking/ingress/> ; <https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/>
- status: **PROVEN 2026-10-19** on chart 41.6.1 (Traefik v3.7.13) with Gateway API 1.6.1; chart 42.1.3 has not been run yet.

#### 27. Gateway API (SN4)

why: The Gateway API is the newer way to do what Ingress does, with more control. The CKA tests both. It splits the job: a Gateway is the front door, and an HTTPRoute says where each request goes.

Needs step 26 (Traefik with its Gateway provider, and the Gateway API CRDs). The chart already made a GatewayClass `traefik` and a Gateway `traefik-gateway` in namespace `traefik`.

```bash
kubectl get gatewayclass,gateway -A                     # ACCEPTED True, PROGRAMMED True
kubectl create deployment web2 --image=registry.k8s.io/serve_hostname
kubectl expose deployment web2 --port=80 --target-port=9376
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web2-route
spec:
  parentRefs:
  - name: traefik-gateway
    namespace: traefik
  hostnames:
  - web2.lab.test
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web2
      port: 80
EOF
kubectl get httproute web2-route -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}'
kubectl exec client -- curl -s -H 'Host: web2.lab.test' http://traefik.traefik.svc.cluster.local          # a web2 pod name
kubectl delete httproute web2-route; kubectl delete ingress web1-ingress
kubectl delete deploy web1 web2; kubectl delete svc web1 web2; kubectl delete pod client
```

- expect: the route shows `Accepted=True ResolvedRefs=True`; the request with `Host: web2.lab.test` returns a `web2-...` pod name.
- catch: the Gateway only accepts routes from its own namespace unless its listener allows others. That is why step 26 sets `gateway.listeners.web.namespacePolicy.from=All`.
- ※ Why not Cilium's own Gateway API? It needs `kubeProxyReplacement=true`, and [step 9](#9-cilium-1204) set it to `false` (SYNTHESIS).
- to remove Traefik later: `helm uninstall traefik -n traefik`; the Gateway API CRDs stay until you `kubectl delete -f` the same standard-install.yaml.
- page: <https://kubernetes.io/docs/concepts/services-networking/gateway/> (and, allowed in the CKA, <https://gateway-api.sigs.k8s.io>)
- status: **PROVEN 2026-10-19**, with Traefik and without changing Cilium's `kubeProxyReplacement`. Cilium's own Gateway API (which needs `kubeProxyReplacement=true`) was not tried; that would be a decision for the owner.

#### 28. CoreDNS: read and change the Corefile (SN6)

why: Every Service name you used (`hostnames`, `my-nginx.default.svc.cluster.local`) was answered by CoreDNS. Its settings live in a ConfigMap called the Corefile. When names fail, this is where you look.

```bash
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'      # read it; compare with the page's default
kubectl -n kube-system edit configmap coredns                                    # add a line "log" under "errors"
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl exec -i -t dnsutils -- nslookup kubernetes.default
kubectl logs --namespace=kube-system -l k8s-app=kube-dns | grep kubernetes.default   # each query is now logged
kubectl -n kube-system edit configmap coredns                                    # remove the "log" line again
kubectl delete pod dnsutils
```

- ※ Look for the `forward . /etc/resolv.conf` line (it is in the page's default Corefile): names outside the cluster go to the DNS servers CoreDNS got from the node. That is why [step 3](#3-dns-that-pods-can-use) had to fix the node's DNS first.
- expect: within about a minute (the `reload` plugin re-reads the ConfigMap; the page says to allow up to two minutes), the CoreDNS logs show `"A IN kubernetes.default.svc.cluster.local. udp ..." NOERROR`.
- also read: the page's stub-domain example (`consul.local:53 { forward . <dns server> }`) sends one domain to its own DNS server. It was not tried: there is no second DNS server to send it to.
- catch: if you restore the ConfigMap from a saved YAML file, `kubectl replace` fails with "the object has been modified". Edit it, or remove `resourceVersion` from the saved file first.
- page: <https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/> ; <https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/>
- status: **PROVEN 2026-10-19** (the log plugin; the stub domain is NOT PROVEN, reason above). Found 47 s after the edit.

#### 29. Deployments: rolling update and rollback (WS1)

why: You will change apps: new versions, new settings. A Deployment swaps pods a few at a time and keeps the old ones serving until the new ones work. If the new version is bad, one command rolls back.

```bash
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml          # 3 pods, nginx:1.14.2, RollingUpdate 25%/25%
kubectl rollout status deployment/nginx-deployment
kubectl set image deployment/nginx-deployment nginx=nginx:1.16.1
kubectl rollout status deployment/nginx-deployment
kubectl get rs                                                                      # old ReplicaSet 0, new ReplicaSet 3
kubectl set image deployment/nginx-deployment nginx=nginx:1.161                     # a typo: this image does not exist
kubectl rollout status deployment/nginx-deployment                                  # hangs; Ctrl+C
kubectl get pods -l app=nginx                                                       # 3 old pods still Running, 1 new pod ErrImagePull
kubectl rollout history deployment/nginx-deployment
kubectl rollout history deployment/nginx-deployment --revision=2
kubectl rollout undo deployment/nginx-deployment                                    # back to revision 2 (1.16.1)
kubectl scale deployment/nginx-deployment --replicas=5
kubectl delete deploy nginx-deployment
```

- ※ `rollout status` is the same check [step 9](#9-cilium-1204) used to wait for Cilium and CoreDNS.
- expect: after the bad update, 3 pods keep serving (the rolling update never takes away more than 25%); after `undo`, the image is `nginx:1.16.1` and the rollout completes.
- page: <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
- status: **PROVEN 2026-10-19**.

#### 30. ConfigMaps and Secrets (WS2)

why: Keep settings out of the container image, so one image runs anywhere with different settings. ConfigMaps hold normal settings; Secrets hold passwords and keys. Both reach the app as environment variables or as files.

```bash
kubectl create configmap special-config --from-literal=special.how=very
kubectl create -f https://kubernetes.io/examples/pods/pod-single-configmap-env-variable.yaml    # as an env var
kubectl logs dapi-test-pod | grep SPECIAL_LEVEL_KEY                                              # SPECIAL_LEVEL_KEY=very
kubectl delete pod dapi-test-pod
kubectl create -f https://kubernetes.io/examples/pods/pod-configmap-volume.yaml                  # as files
kubectl logs dapi-test-pod                                                                       # special.how (a file name)
kubectl delete pod dapi-test-pod; kubectl delete configmap special-config

kubectl create secret generic test-secret --from-literal='username=my-app' --from-literal='password=not-a-real-password'
kubectl get secret test-secret -o jsonpath='{.data.username}' | base64 -d                       # Secrets are only base64, not encrypted
kubectl apply -f https://k8s.io/examples/pods/inject/secret-pod.yaml                            # as files
kubectl exec secret-test-pod -- ls /etc/secret-volume                                           # password  username
kubectl create secret generic backend-user --from-literal=backend-username='backend-admin'
kubectl create -f https://k8s.io/examples/pods/inject/pod-single-secret-env-variable.yaml       # as an env var
kubectl exec env-single-secret -- /bin/sh -c 'echo $SECRET_USERNAME'                            # backend-admin
kubectl delete pod secret-test-pod env-single-secret; kubectl delete secret test-secret backend-user
```

- ※ Secrets are stored in etcd ([step 11](#11-backup-and-restore)), unencrypted by default (source: <https://kubernetes.io/docs/concepts/configuration/secret/>). That is one reason the backup bundle is encrypted.
- ※ You already used a ConfigMap in [step 21](#21-kustomize-ca6) (`configMapGenerator`).
- expect: the values in the comments.
- note: the proof used the page's own example password; the value does not matter.
- page: <https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/> ; <https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/>
- status: **PROVEN 2026-10-19**.

#### 31. Probes and self-healing (WS4)

why: A running process is not always a working app. Probes let the kubelet check: a failed liveness probe restarts the container; a failed readiness probe keeps the pod out of its Service until it is ready. A Deployment also replaces pods that disappear.

```bash
kubectl apply -f https://k8s.io/examples/pods/probe/exec-liveness.yaml          # removes its health file after 30 s
kubectl apply -f https://k8s.io/examples/pods/probe/http-liveness.yaml          # /healthz starts failing after 10 s
kubectl apply -f https://k8s.io/examples/pods/probe/tcp-liveness-readiness.yaml # TCP liveness and readiness
kubectl get pod liveness-exec liveness-http goproxy                             # after ~75 s: RESTARTS above 0 for the first two
kubectl describe pod liveness-exec                                              # Events: "Liveness probe failed", "will be restarted"
kubectl delete pod liveness-exec liveness-http goproxy
# self-healing: a Deployment replaces a deleted pod
kubectl create deployment heal --image=nginx --replicas=2
kubectl delete pod <one heal pod>
kubectl get pods -l app=heal                                                    # 2 pods again, one of them new
kubectl delete deploy heal
```

- ※ "Out of its Service" means out of the EndpointSlice you read in [step 16](#16-drill-c-a-service-with-a-wrong-selector-ts5).
- expect: `liveness-exec` restarted after about 75 s; `liveness-http` restarted 3 times in 75 s with "statuscode: 500"; `goproxy` stays Ready; the Deployment is back to 2 pods within seconds.
- page: <https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/> ; <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
- status: **PROVEN 2026-10-19**.

#### 32. Requests, limits, quotas, node affinity, taints (WS5)

why: The scheduler decides where each pod runs. It looks at what the pod asks for (requests), what a namespace may use (quotas), which nodes the pod wants (affinity), and which nodes push pods away (taints). When a pod is stuck `Pending`, one of these is usually why.

- ※ The owner's reminder ([run-through notes](#how-to-read-this-runbook)): namespaces group things (names, access, quotas); they don't decide where pods run. Placement goes on the app (label + nodeSelector, taint + toleration), naming a role like `site=vps`, so a node can be swapped by moving the label. Plan both here, before real apps.

```bash
kubectl create namespace quota-mem-cpu-example
kubectl apply -f https://k8s.io/examples/admin/resource/quota-mem-cpu.yaml --namespace=quota-mem-cpu-example
kubectl apply -f https://k8s.io/examples/admin/resource/quota-mem-cpu-pod.yaml --namespace=quota-mem-cpu-example
kubectl get resourcequota mem-cpu-demo --namespace=quota-mem-cpu-example -o jsonpath='{ .status.used }'
kubectl apply -f https://k8s.io/examples/admin/resource/quota-mem-cpu-pod-2.yaml --namespace=quota-mem-cpu-example   # refused
kubectl describe node <node name> | sed -n '/Allocated resources/,/memory/p'
kubectl delete namespace quota-mem-cpu-example
# node affinity
kubectl apply -f https://k8s.io/examples/pods/pod-nginx-required-affinity.yaml   # needs a node labelled disktype=ssd
kubectl get pod nginx                                                           # Pending: "didn't match Pod's node affinity/selector"
kubectl label nodes <node name> disktype=ssd
kubectl get pod nginx -o wide                                                   # Running on your node
kubectl delete pod nginx; kubectl label nodes <node name> disktype-
# taints
kubectl taint nodes <node name> demo=true:NoSchedule
kubectl run taint-test --image=nginx                                            # Pending: "had untolerated taint(s)"
kubectl taint nodes <node name> demo=true:NoSchedule-
kubectl get pod taint-test                                                      # Running
kubectl delete pod taint-test
```

- ※ You already removed one taint: the control-plane taint in [step 10](#10-single-node-scheduling-and-a-smoke-test). Same mechanism.
- ※ Without a scheduler, pods stay Pending with no message at all. You saw that in [step 15](#15-drill-b-a-broken-static-pod-manifest-ts2).
- expect: quota used shows `requests.memory 600Mi`; the second pod is `Forbidden: exceeded quota: mem-cpu-demo`; the affinity and taint pods are Pending with the messages above, then Running once the label is added or the taint removed.
- note: with one node, affinity and taints can only show "Pending or Running". Spreading pods across nodes needs more nodes.
- page: <https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/> ; <https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/> ; <https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/>
- status: **PROVEN 2026-10-19**.

#### 33. HorizontalPodAutoscaler (WS3)

why: Load goes up and down. An autoscaler adds pods when CPU is high and removes them when it falls, so you don't have to watch.

Needs metrics-server (step 13).

```bash
kubectl apply -f https://k8s.io/examples/application/php-apache.yaml
kubectl autoscale deployment php-apache --cpu=50% --min=1 --max=10
kubectl get hpa                                                                  # cpu: 0%/50% after ~30 s
kubectl run load-generator --image=busybox:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
kubectl get hpa php-apache --watch                                               # REPLICAS climbs; Ctrl+C
kubectl describe hpa php-apache | grep SuccessfulRescale
kubectl delete pod load-generator
kubectl get hpa php-apache --watch                                               # scales back to 1 after about 5 minutes
kubectl delete hpa php-apache; kubectl delete -f https://k8s.io/examples/application/php-apache.yaml
```

- ※ The CPU numbers come from the metrics-server you set up in [step 13](#13-metrics-server-and-kubectl-top-ts3). The autoscaler compares them to the pod's CPU request, the same request as in [step 32](#32-requests-limits-quotas-node-affinity-taints-ws5).
- expect: within about a minute of load, the HPA scales up (proof: 1 → 4 → 5 → 7 replicas, CPU near the 50% target).
- note: `--cpu=50%` is the 1.37 form used by the page; older pages say `--cpu-percent=50`.
- page: <https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/>
- status: **PROVEN 2026-10-19** (scale-up; scale-down was not waited for).

#### 34. PersistentVolume and PersistentVolumeClaim, access modes, reclaim policy (ST3, ST2)

why: A container's own files are lost when it restarts (volumes page). Data that must survive needs a volume. A PersistentVolume (PV) is the storage; a PersistentVolumeClaim (PVC) is a pod's request for it. The pod asks for a claim, not a disk, so the app does not care where the storage lives.

A `hostPath` volume: a folder on the node. Fine on one node for practice, not for real data.

```bash
mkdir -p /mnt/data && echo 'Hello from Kubernetes storage' > /mnt/data/index.html
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: task-pv-volume
spec:
  storageClassName: manual
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: task-pv-claim
spec:
  storageClassName: manual
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: task-pv-pod
spec:
  volumes:
  - name: task-pv-storage
    persistentVolumeClaim:
      claimName: task-pv-claim
  containers:
  - name: task-pv-container
    image: nginx
    volumeMounts:
    - mountPath: /usr/share/nginx/html
      name: task-pv-storage
EOF
kubectl get pv,pvc                                         # both Bound
kubectl exec task-pv-pod -- curl -s http://localhost/      # Hello from Kubernetes storage
kubectl exec task-pv-pod -- sh -c 'echo written-by-pod > /usr/share/nginx/html/pod.txt'
cat /mnt/data/pod.txt                                      # the file is on the node
kubectl delete pod task-pv-pod; kubectl delete pvc task-pv-claim
kubectl get pv task-pv-volume                              # Released: Retain keeps the PV and its data
kubectl patch pv task-pv-volume --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl get pv task-pv-volume                              # Available: a new claim can bind it
kubectl delete pv task-pv-volume; rm -rf /mnt/data
```

- expect: as the comments say. A 500Mi claim binds the 1Gi volume (a claim gets a volume at least as big as it asks for).
- note: access modes are RWO (one node read-write), ROX, RWX and RWOP (one pod). Reclaim policies: `Retain` keeps the volume, `Delete` deletes it with its storage, `Recycle` is deprecated.
- note: the old task page "Configure a Pod to Use a PersistentVolume for Storage" is gone (404, LEDGER P30); this step uses the concept page.
- ※ SELinux: the proof ran under Enforcing and the pod could still write, because Level 1 pods run unconfined (SELINUX-TRIAL-LEVEL1.md). Your node from [step 2](#2-host-prerequisites) is permissive, so this works there too.
- page: <https://kubernetes.io/docs/concepts/storage/persistent-volumes/> ; volume types: <https://kubernetes.io/docs/concepts/storage/volumes/>
- status: **PROVEN 2026-10-19** (SELinux Enforcing; files were labelled `mnt_t` and the pod could write, because Level 1 pods run unconfined).

#### 35. StorageClass and dynamic provisioning (ST1)

why: In step 34 you made the volume by hand before the claim. A StorageClass describes a kind of storage. With a provisioner behind it, a claim creates its own volume (dynamic provisioning). Without one, you still make volumes by hand, but you can practise the class settings.

The simple documented option: a StorageClass with **no provisioner** for `local` volumes. It shows `WaitForFirstConsumer` and a default class, but you still make each volume by hand.

```bash
mkdir -p /mnt/local-disk1
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-1
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/local-disk1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - <node name>
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get storageclass                    # local-storage (default)
kubectl get pvc local-claim                 # Pending: "waiting for first consumer to be created before binding"
kubectl run local-user --image=busybox:1.28 --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"local-claim"}}],"containers":[{"name":"local-user","image":"busybox:1.28","command":["sh","-c","echo hi > /data/x; sleep 600"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
kubectl get pvc local-claim                 # Bound to local-pv-1 once the pod is scheduled
cat /mnt/local-disk1/x                      # hi
kubectl delete pod local-user; kubectl delete pvc local-claim; kubectl delete pv local-pv-1; kubectl delete storageclass local-storage
rm -rf /mnt/local-disk1
```

- ※ The PV's `nodeAffinity` is the same node affinity you practised in [step 32](#32-requests-limits-quotas-node-affinity-taints-ws5). `WaitForFirstConsumer` waits until the scheduler has placed the pod, so the volume and the pod end up on the same node.
- expect: the claim (with no class named) gets the default class; it stays Pending until a pod uses it, then binds.
- what is missing: **dynamic provisioning** (a claim that creates its own volume). With no provisioner, a second claim stays Pending ("didn't find available persistent volumes to bind"). Proving it needs a provisioner installed, which this runbook does not do (the task said no heavy storage). Picking one is a choice for the owner.
- page: <https://kubernetes.io/docs/concepts/storage/storage-classes/> (section "Local") ; <https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/>
- status: **PROVEN 2026-10-19** for the StorageClass, default class and WaitForFirstConsumer. Dynamic provisioning: **NOT PROVEN** (no provisioner).

#### 36. High availability and `kubeadm join` (CA5, CA3)

why: One control plane is one point of failure. High availability runs three or more (source: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/>), so the cluster keeps going when one dies. This needs more machines, so here you only read the commands.

- **Needs more machines, not on this VPS.** `kubeadm join` needs a second machine.
- **Before a second node joins over the tailnet (NOT PROVEN):** `devices=tailscale0` (step 9) does not choose the VXLAN path. Cilium's tunnel goes to each node's Kubernetes address, and the kubelet takes the node's default IPv4 address unless `--node-ip` is set (sources: Cilium helm-values.rst `devices`; kubelet reference; the CNI and lab networking research batches). On a node whose default route is the internet or the home LAN, set the tailnet address before `init` or `join`: `echo "KUBELET_EXTRA_ARGS=--node-ip=$(tailscale ip -4)" > /etc/sysconfig/kubelet`. With home nodes on the LAN and the VPS on the tailnet only, every node needs its tailnet address here, or the home side needs a route to the tailnet; that is a design choice for the first two-node build. A highly-available control plane needs three or more control-plane machines and a load balancer in front of the API server.
- What already fits: step 8 uses a DNS name (`--control-plane-endpoint <endpoint name>:6443`), which is the groundwork the HA page asks for. Step 20a prints the join command a second node would run.
- ※ This is the payoff of [step 7](#7-endpoint-name): the endpoint is a name, so more control planes can stand behind it later. And [step 4](#4-firewall-for-kubernetes-and-cilium-tailnet-zone-only) already opened etcd's and Cilium's ports on the tailnet for other nodes.
- The commands, for reading only: on the first node `kubeadm init --control-plane-endpoint <endpoint name>:6443 --upload-certs`; on each other control-plane node `kubeadm join <endpoint name>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <key>`; on a worker, the same without `--control-plane --certificate-key`.
- page: <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/> ; <https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/>
- status: **NOT PROVEN**: needs more machines.

#### 37. Teardown

why: Rebuilding often is how you prove the runbook, not memory, makes the cluster.

- Rebuild from step 0. Delete the old node from the tailnet afterwards.
- ※ Back to [step 0](#0-fresh-machine).

## Not in this version

- **CSI driver** (synthesis gap row 9, CA7): not asked for in this round; nothing installed.
- **LoadBalancer with a real address**: needs a load-balancer implementation (Cilium's LB-IPAM and L2 announcements, or MetalLB). A choice for the owner.
- **Operators beyond cilium-operator** (CA8): not installed.
- **Upgrading Cilium** to a release that tests Kubernetes 1.37: not done; Cilium 1.20.3 ran fine on 1.37.1 in the proof.

## Where the manual runbook stops

**The line.** The CKA scope is the line. Everything above is what the exam expects you to do by hand: prepare a host, run kubeadm, fix a broken kubelet, upgrade, write objects with kubectl. This runbook stops there on purpose.

**What comes next.** The operational-excellence runbook. Same cluster, built as code (IaC and CaC). The owner's ladder, from FIRST-STEPS.md (2026-10-19). Since 2026-10-20 the rungs are options, not a fixed order:

```text
   1  by hand            this runbook              you learn every part
   2  your own Ansible   the same steps as code    you learn what to automate
   3  Kubespray          kubeadm run by Ansible    you learn someone else's automation
   4  Talos (later)      an immutable OS           no SSH, no kubeadm
```

**What doing it by hand first teaches you to value.**

- **Knowing what the code replaces.** Each Ansible task will stand for a step here. When you write "set SELinux to permissive", you'll know about the relabel boot ([step 2](#2-host-prerequisites)). When you write the DNS fix, you'll know why ([step 3](#3-dns-that-pods-can-use)).
- **Repeating without drift.** By hand, the same 10 steps can come out slightly different each time. Code runs them the same way every time. You will feel that after a few rebuilds ([step 37](#37-teardown)).
- **Reading automation when it breaks.** Kubespray still runs kubeadm, so what you learned in steps 8, 17, 18 and 20 still applies inside it (SYNTHESIS).
- **The config file is the bridge.** [Step 20b](#20-kubeadm-tokens-a-config-file-reset-ca3) already turned step 8's flags into a file. That is the first piece of configuration as code.
- **What stays the same.** The `kubectl` work (RBAC, apps, Services, policies, storage, logs) is the same whether the cluster was built by hand, by Ansible or by Kubespray (SYNTHESIS).
- **What changes.** Join, upgrade, certificates and HA change with each rung. Talos has no SSH and no kubeadm, so kubeadm practice ends before that rung (SYNTHESIS).

**And the repo.** A hand-built cluster that does not read central-hub is allowed now. No cluster reads the repo until the Activation gate's 7 checks pass ([AGENTS.md, Activation gate](../../AGENTS.md#activation-gate)).

## Sources for the whys

Checked 2026-10-19. Every page below was fetched that day.

- **kubernetes.io:** [install-kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) (swap, SELinux, exclude line, kubelet crashloop), [create-cluster-kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) (endpoint, pod range overlap, CoreDNS waits for a CNI, control-plane taint, etcd backups), [container-runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) (ip_forward, cgroup driver), [ports-and-protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/), [kube-proxy](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/) (10256), [feature-gates](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/) (KubeletCgroupDriverFromCRI), [kubeadm-init](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/), [troubleshooting-kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/), [kubeadm-reconfigure](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/), [kubelet-integration](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/kubelet-integration/), [kubeadm-certs](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/), [kubeadm-upgrade](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/), [releases](https://kubernetes.io/releases/), [components](https://kubernetes.io/docs/concepts/overview/components/), [network model](https://kubernetes.io/docs/concepts/services-networking/), [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/), [dns-custom-nameservers](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/), [dns-debugging-resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/), [network-policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/), [logging](https://kubernetes.io/docs/concepts/cluster-administration/logging/), [static-pod](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/), [debug-cluster](https://kubernetes.io/docs/tasks/debug/debug-cluster/), [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/), [Ingress NGINX retirement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/), [secret](https://kubernetes.io/docs/concepts/configuration/secret/), [volumes](https://kubernetes.io/docs/concepts/storage/volumes/), [ha-topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/).
- **Other projects' docs:** [Cilium 1.20 system requirements](https://docs.cilium.io/en/v1.20/operations/system_requirements/) (8472/udp, 4240/tcp); [containerd RELEASES.md](https://github.com/containerd/containerd/blob/main/RELEASES.md) and [snapshotters](https://github.com/containerd/containerd/blob/main/docs/snapshotters/README.md); [metrics-server README](https://github.com/kubernetes-sigs/metrics-server); [dnf versionlock](https://dnf-plugins-core.readthedocs.io/en/latest/versionlock.html); [RHEL 10, changing SELinux states](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_selinux/changing-selinux-states-and-modes); Linux kernel [overlayfs](https://docs.kernel.org/filesystems/overlayfs.html) and [ip-sysctl](https://docs.kernel.org/networking/ip-sysctl.html) (bridge-nf-call-iptables).
- **Proof files:** PROOF-RUN-1.md to PROOF-RUN-4.md, SELINUX-TRIAL-LEVEL1.md, research/cka-runbook/SYNTHESIS.md (exam facts).
- **Measured on the proof node** (read only, 2026-10-19, before its rebuild): listening ports (`ss`); Cilium in VXLAN tunnel mode; tailscale0 MTU 1280; overlay mounts and `bridge-nf-call-iptables = 1`; the kubelet log line "Using cgroup driver setting received from the CRI runtime".
- **Not sourced:** step 8's note that the node is not Ready before a CNI is installed (no page or proof file says it).

## If it fails

Stop at the step that fails and compare with its `expect:` line and its catches. Steps 1-11 can be undone only by a rebuild from step 0; practice steps 12-36 clean up after themselves, except the four named under "Rules for practice". Tell the owner before changing a command, and fix the runbook text in the same change.

## Afterwards

Record a replay in the PR that changes this runbook: set `last-tested` with the date, who ran it and on what, and only then set `status: tested` (D-0012).

## Related

- [D-0012](../decisions/0012-sort-docs-by-kind-of-document.md): runbook format, manual first.
- [STD-0001](../standards/0001-vm-hostnames.md): node names.
- The proof runs (PROOF-RUN-1 to PROOF-RUN-4, the SELinux trial, FIRST-STEPS) and the CKA research batch (SYNTHESIS, LEDGER) are kept in the owner's private research archive. They are named here, not linked.
