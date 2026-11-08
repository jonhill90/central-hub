---
title: Create the lab root CA and c1's intermediate by hand
status: draft
kind: manual
trigger: on request, once for the root; once per new cluster for an intermediate; a year before an intermediate expires
runner: the owner
outcome: a root certificate trusted by the lab, an intermediate for c1 signed by it, and both private keys stored off every cluster
needs: a terminal on the owner's Mac with openssl; the private store; the root key's offline home
private-values: [lab-root-ca-key, lab-root-ca-key-passphrase, lab-c1-intermediate-ca-key, lab-c1-intermediate-ca-cert]
files: []
last-tested: not yet run
superseded-by:
---

# Create the lab root CA and c1's intermediate by hand

This is the root ceremony. It runs once. Everything else in the lab trusts what it makes, so it is done slowly, by hand, on one machine, with no cluster involved.

```mermaid
flowchart LR
  a["make root key<br/>and certificate"] --> b["make c1 intermediate<br/>key and request"] --> c["root signs it<br/>pathlen 0"] --> d["store keys:<br/>private store + offline"] --> e["delete working copies"]
```

## Before you start

- `openssl version` answers. macOS ships LibreSSL; OpenSSL 3 from Homebrew also works.
- You know where the root key's offline home is (D-0028 "Not decided here").
- Work in a new empty folder that is not synced to any cloud: `mkdir -m 700 ~/lab-ca && cd ~/lab-ca`.
- Stop if a lab root already exists in the private store. Making a second root means every device trusts again.

## Steps

1. Make the root key, protected by a passphrase you keep in the private store as `lab-root-ca-key-passphrase`.

   ```sh
   openssl ecparam -name secp384r1 -genkey | openssl ec -aes256 -out root.key
   ```

   why: P-384 matches the strength the owner's earlier labs used, and the passphrase means the key file alone is useless.
   ※ [D-0028 rule 1](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md)
   expect: `root.key` exists; openssl asked for the passphrase twice.

2. Make the root certificate, valid for 10 years.

   ```sh
   cat > root.cnf <<'EOF'
   [req]
   distinguished_name = dn
   prompt = no
   x509_extensions = v3_root
   [dn]
   CN = Home Lab Root CA
   [v3_root]
   basicConstraints = critical, CA:true
   keyUsage = critical, keyCertSign, cRLSign
   subjectKeyIdentifier = hash
   EOF
   openssl req -new -x509 -key root.key -sha384 -days 3650 -config root.cnf -out root.crt
   ```

   why: this certificate is what every device trusts, so it carries only CA powers and no names.
   expect: `openssl x509 -in root.crt -noout -subject -dates` shows the subject and a 10-year window.

3. Make c1's intermediate key and a signing request.

   ```sh
   openssl ecparam -name secp384r1 -genkey -noout -out c1-intermediate.key
   openssl req -new -key c1-intermediate.key -subj "/CN=Home Lab c1 Intermediate CA" -out c1-intermediate.csr
   ```

   why: each cluster gets its own intermediate, so losing one never puts the others at risk. This key has no passphrase, because cert-manager reads it unattended.
   ※ [D-0028 rule 2](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md)
   expect: `c1-intermediate.key` and `c1-intermediate.csr` exist.

4. Sign the intermediate with the root, valid for 5 years, path length 0.

   ```sh
   cat > intermediate.ext <<'EOF'
   basicConstraints = critical, CA:true, pathlen:0
   keyUsage = critical, keyCertSign, cRLSign
   subjectKeyIdentifier = hash
   authorityKeyIdentifier = keyid:always
   EOF
   openssl x509 -req -in c1-intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial \
     -sha384 -days 1825 -extfile intermediate.ext -out c1-intermediate.crt
   cat c1-intermediate.crt root.crt > c1-intermediate-chain.crt
   ```

   why: path length 0 means the intermediate can sign leaf certificates but never another CA. cert-manager needs the full chain in `tls.crt`.
   expect: `openssl verify -CAfile root.crt c1-intermediate.crt` prints `OK`.

5. Write down the root's fingerprint.

   ```sh
   openssl x509 -in root.crt -noout -fingerprint -sha256
   ```

   why: after a rebuild, the rebuild test compares against this value to prove the root did not change.
   expect: a SHA-256 fingerprint. It is not secret; keep it with the certificate.

6. Store the files.
   - In the private store: `c1-intermediate-chain.crt` as `lab-c1-intermediate-ca-cert`, `c1-intermediate.key` as `lab-c1-intermediate-ca-key`, and `root.key` as `lab-root-ca-key`.
   - In the root key's offline home: a second copy of `root.key` and `root.crt`.
   - `root.crt` is public. It may be kept anywhere, including this repository later.

   why: the intermediate must be restorable on every rebuild; the root key is needed only for the next intermediate.
   ※ [D-0028 rule 3](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md)
   expect: you can open each item in the private store and see the same file.

7. Delete the working copies of the keys: `rm root.key c1-intermediate.key`, then empty the Trash if the folder was ever moved there.
   why: the keys now live only where step 6 put them.
   expect: `ls ~/lab-ca` shows no `.key` file.

## If it fails

- Before step 6, nothing has left the folder: delete it and start again.
- If the root key is lost after devices trust the root, the lab keeps working until the intermediate expires, but no new intermediate can be made. Make a new root and trust it everywhere, then retire the old one.
- Tell the owner before trying anything not written here.

## Afterwards

- Set `last-tested` here, with the date and on what.
- Continue with [Trust the lab root CA on a Mac](trust-lab-root-ca-on-mac.md) and [Restore c1's intermediate CA](restore-c1-intermediate-ca.md).
- To renew the intermediate later, run steps 3, 4, 6 and 7 again with the root key from the private store, then the restore runbook.

## Related

- [D-0028](../decisions/0028-run-a-lab-ca-with-the-root-off-cluster-and-one-intermediate-per-cluster.md), [spec 2026-11-lab-pki](../specs/2026-11-lab-pki.md).
