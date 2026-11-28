# When Argo CD takes over from Ansible

A c1 build runs in three parts. **Ansible** builds the machines, the cluster and Argo CD. **Argo CD** then installs every app in git and keeps each one equal to git. **Ansible** finally checks the Gateway and runs the pieces that haven't moved to Argo CD yet.

The rule of thumb: whatever has to exist before Argo CD can run, Ansible builds. Whatever runs inside the cluster and can be written in git without a private value, Argo CD owns.

![The three parts of a c1 build, Ansible then Argo CD then Ansible, and the five steps by which an app moves from an Ansible role to Argo CD](images/argo-ansible.svg)

The stage names are the ones `hosts/rebuild-k8s.sh` runs, in the order of [Rebuild one cluster's Kubernetes layer with one command](../runbooks/rebuild-k8s-layer-with-one-command.md#stages). Dev runs a shorter list (same runbook, line 28).

## Why the line sits there

| Ansible keeps it | Because |
|---|---|
| The node VMs and the cluster itself | Argo CD runs inside the cluster, so it can't make the cluster it runs in. Ansible installs Argo CD from its pinned upstream manifest ([D-0023](../decisions/0023-use-argo-cd-as-the-gitops-engine.md) rule 2), and "Argo CD itself stays installed by Ansible" (spec [2026-11-c1-apps-under-argo-cd](../specs/2026-11-c1-apps-under-argo-cd.md), line 82). |
| Cilium, the pod network | Without the network, no pod runs, Argo CD included. The spec moves it last or leaves it with Ansible, as the owner chooses (same spec, line 80). Today `k8s.yml` installs it with Helm into `kube-system` (`hosts/ansible/roles/k8s_control_plane/tasks/main.yml` line 158). |
| The data disk | It is the machine, not the cluster. Argo CD installs the provisioner and the StorageClass, but formatting and mounting the disk stays with Ansible ([Move c1's volume provisioner to Argo CD](../runbooks/move-local-path-to-argo-cd.md), line 19). |
| The root Application | It carries the private values. The lab zone reaches the cluster only as the root Application's Helm parameter `zone`, which Ansible sets from the private inventory, so nothing in git holds it (spec, line 51). |
| Argo CD's web page and sign-in | They are part of Argo CD's own install, which stays with Ansible (`k8s-gitops.yml --tags ui,sso`, rebuild runbook line 53). |
| Keycloak and the lab certificates, for now | Not moved yet. Each is still its own playbook, `k8s-identity.yml` and `k8s-certs.yml` (rebuild runbook, lines 46-47). The spec moves identity seventh, after the pattern is proven, because it holds state (spec, line 77). |

| Argo CD owns it | Because |
|---|---|
| Every app in `hosts/kubernetes/home/c1/root/values.yaml` | git becomes the one record of what runs. One Application reads the repository, and the root chart makes one child per app (spec, line 50). |
| Fixing drift | With auto-sync on, Argo CD puts a changed app back to what git says. A fresh cluster installs an app only if its `autoSync` is on (rebuild runbook, line 164). |
| No credentials | The repository is public and is read over anonymous HTTPS, with no repository secret and no image automation (spec, line 52; [D-0023](../decisions/0023-use-argo-cd-as-the-gitops-engine.md) rule 5). |

## How an app moved from Ansible to Argo CD

Every app on c1 was first put there by Ansible. Each one moved on its own, with a runbook. The app went into git, Argo CD synced it once by hand, auto-sync went on, and then the role's switch `*_by_argocd` was set to true so Ansible stopped applying the same objects (spec, "Taking over a running component"; the switches are listed in the rebuild runbook, line 68). [Move c1's volume provisioner to Argo CD](../runbooks/move-local-path-to-argo-cd.md) is one worked example.

**The way back,** for any app, is to delete its child Application without deleting what it made. The objects stay, and the Ansible role runs as before (spec, line 65).

## Sources

- In this repository: [D-0023](../decisions/0023-use-argo-cd-as-the-gitops-engine.md), the spec [Move c1's apps and add-ons under Argo CD](../specs/2026-11-c1-apps-under-argo-cd.md), [Rebuild one cluster's Kubernetes layer with one command](../runbooks/rebuild-k8s-layer-with-one-command.md), [Install Argo CD on c1](../runbooks/install-argo-cd-on-c1.md), and [hosts/kubernetes/home/c1/README.md](../../hosts/kubernetes/home/c1/README.md).
- Upstream: Argo CD, [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/), the "app of apps" pattern that the root Application follows.
