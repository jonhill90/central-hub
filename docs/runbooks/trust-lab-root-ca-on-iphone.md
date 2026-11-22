---
title: Trust the lab root CA on an iPhone
status: draft
kind: manual
trigger: once per iPhone or iPad; again only if the root is replaced
runner: the owner, with an agent making and sending the profile
outcome: Safari and apps on the phone open the lab's apps over https with no certificate warning
needs: the phone on the tailnet with split DNS working ([Set up lab DNS](set-up-lab-dns.md)); the public root certificate `root.crt`; a Mac or another device that can AirDrop to the phone
private-values: []
files: [hosts/ios-trust-profile.sh, hosts/ansible/roles/k8s_certs/templates/issuers.yaml.j2]
last-tested: not yet run on a phone. The profile was built and read back from the box on 2026-11-22; no iPhone has installed it
superseded-by:
---

# Trust the lab root CA on an iPhone

The lab's apps use certificates from the lab's own CA, so an iPhone warns until it trusts the root. Like the Mac ([Trust the lab root CA on a Mac](trust-lab-root-ca-on-mac.md)), the phone trusts the root only, so a rebuilt intermediate or a new app certificate needs nothing here. The profile holds the public root certificate and nothing else: no key, no password, no host name.

Two taps on the phone cannot be skipped. iOS lets a person, not a program, install a profile and then switch on full trust for a root that was installed by hand. This page makes those the only things the owner does.

## Before you start

- The phone reaches the lab names first. If it does not, fix that before this page ([Set up lab DNS](set-up-lab-dns.md), the entry about tailnet devices that resolve the names but load nothing).
- `root.crt` is the root from [Create the lab root CA](create-lab-root-ca.md). Its SHA-256 fingerprint is `E9:4A:C3:5D:32:C9:CF:BD:7B:0C:80:77:ED:1E:1B:9C:D4:2C:C6:20:D6:DE:BE:DE:06:D6:F7:B4:36:A1:8C:3D` (valid 2026-11-08 to 2036-11-05). The fingerprint is public.
- The gateway's certificate must list server authentication. Apple asks for it on TLS server certificates ([Apple's requirements, iOS 13 and macOS 10.15](https://support.apple.com/en-us/103769)), and the certificate issued before this page's change did not carry it. Check, from the agent box: `echo | openssl s_client -connect <app>.<zone>:443 -servername <app>.<zone> 2>/dev/null | openssl x509 -noout -ext extendedKeyUsage`. Expect `TLS Web Server Authentication`. If it prints nothing, apply the `k8s_certs` role's `usages` change first, so cert-manager issues the certificate again.

## Steps

1. An agent makes the profile.

   ```sh
   hosts/ios-trust-profile.sh root.crt E9:4A:C3:5D:32:C9:CF:BD:7B:0C:80:77:ED:1E:1B:9C:D4:2C:C6:20:D6:DE:BE:DE:06:D6:F7:B4:36:A1:8C:3D > lab-root.mobileconfig
   ```

   why: the script stops unless the certificate is a CA named "Home Lab Root CA" with that fingerprint, and it builds the same file every time from that root.
   expect: `lab-root.mobileconfig` exists; `python3 -c "import plistlib;print(plistlib.load(open('lab-root.mobileconfig','rb'))['PayloadContent'][0]['PayloadType'])"` prints `com.apple.security.root`.

2. Send the file to the phone. The owner does nothing in a browser or terminal: an agent on the Mac AirDrops it, or sends it over the tailnet with `tailscale file cp lab-root.mobileconfig <phone's tailnet name>:`.
   why: both reach the phone without a web page. Neither has been run to a phone yet.
   expect: the phone shows the received file.

3. On the phone, open the file. iOS says "Profile Downloaded". Open Settings, tap the banner at the top, then Install, enter the passcode, and Install again.
   expect: Settings, General, VPN & Device Management lists "Home Lab Root CA".

4. Turn on full trust: Settings, General, About, Certificate Trust Settings, then switch on "Home Lab Root CA" and tap Continue.
   why: without this switch iOS keeps a hand-installed root out of TLS trust, even though the profile is installed.
   expect: the switch is green.

5. Open a lab app's address in Safari.
   expect: the page loads with no warning.

## If it fails

- **No "Profile Downloaded" banner:** open the file again from where it arrived (Files or the Tailscale app). If the file would not open, send it by AirDrop instead.
- **The switch in step 4 is missing:** step 3 did not finish; look under VPN & Device Management for the profile.
- **Safari still warns after step 4:** run the server-authentication check above. A certificate with no extended key usage is the first thing to rule out; the next is `openssl s_client -connect <name>:443 -showcerts` showing a chain that does not end at this root.
- **To undo:** Settings, General, VPN & Device Management, "Home Lab Root CA", Remove Profile.

## Afterwards

- Set `last-tested` here, with the date and the iOS version.

## Related

- [Trust the lab root CA on a Mac](trust-lab-root-ca-on-mac.md), [Create the lab root CA](create-lab-root-ca.md), [Set up short app names](set-up-short-app-names.md), [spec 2026-11-lab-pki](../specs/2026-11-lab-pki.md).
