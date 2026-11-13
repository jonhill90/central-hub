---
title: Give agents read-only access to c1
status: draft
kind: manual
trigger: once per cluster build, after Argo CD has synced app agent-read; again to rotate the token
runner: the owner, or an agent lane through the owner's Mac (D-0022), with the owner's go because it reads a token from prod c1
outcome: the agent box holds a kubeconfig that can read everything on c1 except Secrets, and can change nothing
needs: app agent-read Synced on c1; SSH to c1's control plane as D-0022 says; the agent box's keys wrapper (put-c1-readonly)
private-values: [c1-control-plane, k8s_control_plane_endpoint, c1-readonly.kubeconfig]
files: [hosts/kubernetes/home/c1/apps/agent-read/, hosts/kubernetes/home/c1/root/values.yaml]
last-tested: not yet run
superseded-by:
---

# Give agents read-only access to c1

Agents look at c1 from the agent box; they change it only through the repository and Argo CD. App `agent-read` makes ServiceAccount `agent-read` in namespace `agent-read`. It gets get, list and watch through the built-in ClusterRole `view`, which leaves out Secrets, plus its own ClusterRole for what `view` doesn't cover: nodes, namespaces, volumes, StorageClasses, CRDs, metrics, events, and the custom resources of Argo CD, the Gateway API, cert-manager, External Secrets and Prometheus (pick 216 in [AGENT-PICKS.md](../../hosts/AGENT-PICKS.md)). Kubernetes fills Secret `agent-read-token` with a long-lived token for it. This runbook turns that token into a kubeconfig on the controller and puts it on the box. A prod redeploy doesn't use it: the rebuild runs kubectl on the control plane through Ansible.

## Steps

1. Check the app and the token.

   ```sh
   ssh <c1-control-plane> sudo kubectl -n agent-read get serviceaccount,secret
   ```

   expect: ServiceAccount `agent-read` and Secret `agent-read-token` of type `kubernetes.io/service-account-token` with 3 data keys.

2. Write the kubeconfig on the controller. The token goes from the pipe straight into a 0600 file; it is never printed and never in a command line.

   ```sh
   umask 077
   ssh <c1-control-plane> sudo kubectl -n agent-read get secret agent-read-token -o json |
     python3 -I -c '
   import base64, json, sys
   d = json.load(sys.stdin)["data"]
   print("apiVersion: v1\nkind: Config")
   print("clusters:\n- name: c1\n  cluster:\n    server: https://%s:6443" % sys.argv[1])
   print("    certificate-authority-data: " + d["ca.crt"])
   print("users:\n- name: agent-read\n  user:\n    token: " + base64.b64decode(d["token"]).decode())
   print("contexts:\n- name: c1\n  context: {cluster: c1, user: agent-read}\ncurrent-context: c1")
   ' '<k8s_control_plane_endpoint>' > ~/.config/central-hub/c1-readonly.kubeconfig
   ```

   why: the server is the API's own name, which its certificate carries (kubeadm's `controlPlaneEndpoint`) and the lab DNS answers on the box. The Secret comes over as JSON and Python writes the file, so it works the same in zsh and bash; the CA stays base64, as the kubeconfig wants it.
   expect: the file exists, mode `600`.

3. Prove it reads and can't write or read Secrets, from the controller.

   ```sh
   k="kubectl --kubeconfig $HOME/.config/central-hub/c1-readonly.kubeconfig"
   $k get nodes
   $k auth can-i list secrets -A
   $k auth can-i create pods -n default
   $k auth can-i delete applications.argoproj.io -n argocd
   ```

   expect: the nodes list; then `no` three times.

4. Put it on the box: `agent-box-keys.sh put-c1-readonly` (through the Mac lane's wrapper).
   expect: `/etc/agent-keys/c1-readonly.kubeconfig`, owned by `keys`, mode 0600.

## Rotate

Delete Secret `agent-read-token` (`ssh <c1-control-plane> sudo kubectl -n agent-read delete secret agent-read-token`). The old token stops working at once; Argo CD makes the Secret again and Kubernetes fills in a new token. Run steps 2 to 4 again.

## If it fails

- Step 1 shows no data in the Secret: the ServiceAccount didn't exist when the Secret was made. Delete the Secret; Argo CD makes it again.
- Step 3 answers `yes` to any can-i: stop, delete the Secret, and look at what else binds `agent-read` (`kubectl get clusterrolebindings,rolebindings -A -o wide | grep agent-read`).

## Exit path

Remove app `agent-read` from `hosts/kubernetes/home/c1/root/values.yaml` by PR, delete namespace `agent-read` and the two ClusterRoleBindings, and delete `/etc/agent-keys/c1-readonly.kubeconfig` on the box.
