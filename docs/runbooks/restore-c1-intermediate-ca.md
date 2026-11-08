---
title: Restore c1's intermediate CA into cert-manager
status: draft
kind: manual
trigger: after every rebuild of c1, before any app needs a certificate; after the intermediate is renewed
runner: the owner, through SSH to c1's control plane (D-0022)
outcome: the Secret `lab-ca` in namespace `cert-manager` holds c1's intermediate, and the ClusterIssuer `lab-ca` is Ready
needs: SSH to c1's control plane; `kubectl` there; the folder ~/.config/central-hub/lab-ca on the owner's Mac
private-values: [c1-intermediate.key]
files: []
last-tested: not yet run
superseded-by:
---

# Restore c1's intermediate CA into cert-manager

This is the step that makes the PKI survive a rebuild. It puts the same intermediate back, so every device that trusts the root keeps working. The automated version is `playbooks/k8s-certs.yml --tags labca` with `k8s_certs_lab_ca: true` (`hosts/ansible/README.md`, "Certificates on c1"), which does steps 2 and 4 from two files on the controller.

## Before you start

- `kubectl -n cert-manager get deploy` shows cert-manager, its webhook and cainjector ready.
- `kubectl -n cert-manager get secret lab-ca` says not found, or you are replacing an intermediate on purpose.

## Steps

1. Copy `c1-intermediate-chain.crt` and `c1-intermediate.key` from `~/.config/central-hub/lab-ca/` on the Mac into a folder on the control plane that only you can read, as `tls.crt` and `tls.key`.
   why: these are the intermediate with the root appended, and its key, exactly as the root ceremony stored them.
   ※ [D-0028 rule 3](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md)
   expect: `openssl x509 -in tls.crt -noout -subject` shows the c1 intermediate.

2. Make the Secret.

   ```sh
   kubectl -n cert-manager create secret tls lab-ca --cert=tls.crt --key=tls.key
   ```

   why: cert-manager's CA issuer reads the signing key from a Secret in its own namespace when the issuer is a ClusterIssuer.
   ※ <https://cert-manager.io/docs/configuration/ca/>
   expect: `secret/lab-ca created`.

3. Delete the copies: `shred -u tls.crt tls.key`.
   why: the key now lives only in the Mac's lab-ca folder and the cluster.
   expect: the folder is empty.

4. Check the issuer. The ClusterIssuer `lab-ca` comes from the `k8s_certs` role; if it was made before the Secret existed, it turns Ready within a minute.

   ```sh
   kubectl get clusterissuer lab-ca
   ```

   expect: `READY True`.

5. Prove the root did not change: issue any certificate, then compare the last certificate in its chain with the root fingerprint you recorded.
   why: this is the rebuild test in the spec.
   expect: the same SHA-256 fingerprint.

## If it fails

- `READY False` with "secret not found": the Secret is in the wrong namespace or has the wrong name.
- "error decoding certificate" or a chain error: `tls.crt` is missing the root; copy `c1-intermediate-chain.crt` again.
- To go back to public certificates while this is fixed, point the Gateway certificate's `issuerRef` back at the Let's Encrypt ClusterIssuer.

## Afterwards

- Set `last-tested` here.

## Related

- [D-0028](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md), [spec 2026-11-lab-pki](../specs/2026-11-lab-pki.md), [Create the lab root CA](create-lab-root-ca.md).
