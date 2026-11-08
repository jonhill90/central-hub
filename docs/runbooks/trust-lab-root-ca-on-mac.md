---
title: Trust the lab root CA on a Mac
status: draft
kind: manual
trigger: once per Mac; again only if the root is replaced
runner: the owner
outcome: browsers and command-line tools on the Mac trust certificates from the lab CA
needs: an administrator account on the Mac; the root certificate `root.crt`
private-values: []
files: []
last-tested: not yet run
superseded-by:
---

# Trust the lab root CA on a Mac

The Mac trusts the root, never the intermediate, so a c1 rebuild or a new intermediate needs nothing here.

## Before you start

- You have `root.crt` from [Create the lab root CA](create-lab-root-ca.md), and its SHA-256 fingerprint.
- `openssl x509 -in root.crt -noout -fingerprint -sha256` prints that same fingerprint. Stop if it doesn't.

## Steps

1. Add the root to the System keychain, trusted for TLS.

   ```sh
   sudo security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain root.crt
   ```

   why: the System keychain is what Safari, Chrome and the system's own TLS library read; `-d` makes it an admin-level trust setting for all users, and `-p ssl` trusts it for TLS only, as `playbooks/controller-trust.yml` does for the Proxmox CA.
   ※ [D-0028 rule 6](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md)
   expect: macOS asks for your password, then returns with no output.

2. Check it.

   ```sh
   security find-certificate -c "Home Lab Root CA" -a -Z /Library/Keychains/System.keychain | grep SHA-256
   ```

   why: proves the certificate in the keychain is the one with the fingerprint you recorded.
   expect: the same SHA-256 fingerprint.

3. Open a c1 app's name in a browser.
   why: the end-to-end check that the chain from the Gateway reaches this root.
   expect: no certificate warning. Firefox keeps its own store; turn on `security.enterprise_roots.enabled` there if it warns.

## If it fails

- To undo: `sudo security delete-certificate -c "Home Lab Root CA" /Library/Keychains/System.keychain`.
- If a browser still warns, run `openssl s_client -connect <name>:443 -showcerts` and check the chain ends at this root.

## Afterwards

- Set `last-tested` here.

## Related

- [D-0028](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md), [spec 2026-11-lab-pki](../specs/2026-11-lab-pki.md).
