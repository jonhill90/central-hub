#!/usr/bin/python3 -I
"""Files the opnsense-test wrapper makes for one proof (docs/runbooks/prove-opnsense-sign-in-on-dev.md).

  opnsense-test-seed.py seed   <settings.json> <vlans.yml> <root key.pub> <out dir>
      meta-data and user-data for the NoCloud seed ISO (label cidata).
  opnsense-test-seed.py config <settings.json> <vlans.yml> <root key.pub> <proof dir> <out file>
      the /conf/config.xml OPNsense 26.1 boots with, from the proof dir's ca.pem, root.hash,
      proofadmin.hash and client.secret.
  opnsense-test-seed.py realm  <settings.json> <proof dir> <out file>
      the throwaway Keycloak realm, from the proof dir's client.secret, user.pass and stranger.pass.

Every secret here is made for the one proof by the wrapper and removed by `opnsense-test destroy`.
None comes from the repository or the inventory.
"""
import base64
import ipaddress
import json
import os
import re
import sys
import uuid
from xml.sax.saxutils import escape

import yaml

REALM = "opnsense-proof"
CLIENT = "opnsense"
SERVER = "keycloak-proof"   # the OPNsense authentication server's name
# The plugin's application code, the same as the lab realm's OPNsense client (role k8s_identity): it is the
# last part of the callback and logout-test paths.
APP_CODE = "keycloak"
PROOF_ADMIN = "proofadmin"  # the new local admin the test user is bound to
PROOF_ADMIN_UID = 2000


def load(settings, vlans):
    s = json.load(open(settings))
    dev = [v for v in yaml.safe_load(open(vlans))["lab_vlans"] if v["name"] == "dev"][0]
    net = ipaddress.ip_network(dev["cidr"])
    addr = ipaddress.ip_address(s["address"])
    if addr not in net or addr in (net.network_address, net.broadcast_address, net.network_address + 1):
        sys.exit(f"opnsense-test: address {addr} is not a host address in dev's {net}, other than its gateway")
    if not re.fullmatch(r"[a-z][a-z0-9]{10,14}", s["name"]):
        sys.exit("opnsense-test: the name is not a STD-0001 hostname")
    ipaddress.ip_address(s["keycloak_address"])
    return s, net, str(net.network_address + 1)


def read(folder, name):
    return open(os.path.join(folder, name)).read().strip()


def seed(settings, vlans, pubkey, out):
    s, net, gw = load(settings, vlans)
    key = open(pubkey).read().strip()
    if not re.fullmatch(r"ssh-ed25519 [A-Za-z0-9+/=]+( \S+)?", key):
        sys.exit("opnsense-test: the root key is not one ed25519 public key")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "meta-data"), "w") as f:
        f.write(f"instance-id: opnsense-test-257\nlocal-hostname: {s['name']}\n")
    # Not cloud-config: FreeBSD 14.3's nuageinit runs any other user-data as a script, as root, before
    # the network starts (rc.d/nuageinit: BEFORE: NETWORKING). It makes no user with a known password,
    # turns password logins off, and skips the image's first-boot freebsd-update: the bootstrap
    # replaces the base system anyway.
    script = f"""#!/bin/sh
set -e
sysrc -x ifconfig_DEFAULT || true
sysrc ifconfig_vtnet0="inet {s['address']}/{net.prefixlen}"
sysrc defaultrouter="{gw}"
sysrc firstboot_freebsd_update_enable=NO
echo "nameserver {gw}" > /etc/resolv.conf
install -d -m 700 /root/.ssh
echo "{key}" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
sed -i '' -e '/^PasswordAuthentication/d' -e '/^UsePAM/d' -e '/^PermitRootLogin/d' /etc/ssh/sshd_config
printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\nPermitRootLogin prohibit-password\\n' >> /etc/ssh/sshd_config
"""
    path = os.path.join(out, "user-data")
    with open(path, "w") as f:
        f.write(script)
    os.chmod(path, 0o755)


def config(settings, vlans, pubkey, proof, out):
    s, net, gw = load(settings, vlans)
    key = base64.b64encode((open(pubkey).read().strip() + "\n").encode()).decode()
    ca = base64.b64encode(open(os.path.join(proof, "ca.pem"), "rb").read()).decode()
    issuer = f"https://{s['keycloak_address']}:8443/realms/{REALM}"
    v = {k: escape(x) for k, x in {
        "name": s["name"], "addr": s["address"], "prefix": str(net.prefixlen), "gw": gw, "key": key,
        "root_hash": read(proof, "root.hash"), "admin_hash": read(proof, "proofadmin.hash"),
        "secret": read(proof, "client.secret"), "ca": ca, "issuer": issuer,
        "gw_uuid": str(uuid.uuid4()), "ca_ref": uuid.uuid4().hex[:13], "srv_ref": uuid.uuid4().hex[:13],
    }.items()}
    # From OPNsense 26.1's own default (core stable/26.1 src/etc/config.xml.sample), with: no WAN, no
    # DHCP (dnsmasq) or DNS server (unbound), no IPv6; LAN static on vtnet0 with dev's gateway;
    # the GUI and SSH on LAN only, SSH by key only; the proof's CA in the trust store; and the
    # os-openid-connect server's settings (CODE-READ-v3): PAR disabled, shared signals off, logout
    # notifications off, admission `approval`, root not allowed, no account made on first login.
    # The plugin itself is not in here: `opnsense-test configure` installs it with pkg add.
    xml = f"""<?xml version="1.0"?>
<opnsense>
  <theme>opnsense</theme>
  <system>
    <optimization>normal</optimization>
    <hostname>{v['name']}</hostname>
    <domain>internal</domain>
    <dnsserver>{v['gw']}</dnsserver>
    <group>
      <name>admins</name>
      <description>System Administrators</description>
      <scope>system</scope>
      <gid>1999</gid>
      <member>0</member>
      <member>{PROOF_ADMIN_UID}</member>
      <priv>page-all</priv>
    </group>
    <user>
      <name>root</name>
      <descr>System Administrator</descr>
      <scope>system</scope>
      <groupname>admins</groupname>
      <password>{v['root_hash']}</password>
      <uid>0</uid>
      <authorizedkeys>{v['key']}</authorizedkeys>
    </user>
    <user>
      <name>{PROOF_ADMIN}</name>
      <descr>Proof admin, bound to the Keycloak test user</descr>
      <scope>user</scope>
      <groupname>admins</groupname>
      <password>{v['admin_hash']}</password>
      <uid>{PROOF_ADMIN_UID}</uid>
    </user>
    <nextuid>{PROOF_ADMIN_UID + 1}</nextuid>
    <nextgid>2000</nextgid>
    <timezone>Etc/UTC</timezone>
    <webgui>
      <protocol>https</protocol>
      <interfaces>lan</interfaces>
    </webgui>
    <usevirtualterminal>1</usevirtualterminal>
    <disableconsolemenu/>
    <ssh>
      <group>admins</group>
      <enabled>enabled</enabled>
      <permitrootlogin>1</permitrootlogin>
      <interfaces>lan</interfaces>
    </ssh>
  </system>
  <interfaces>
    <lan>
      <enable>1</enable>
      <if>vtnet0</if>
      <descr>DEV</descr>
      <ipaddr>{v['addr']}</ipaddr>
      <subnet>{v['prefix']}</subnet>
      <gateway>DEV_GW</gateway>
    </lan>
  </interfaces>
  <OPNsense>
    <Gateways version="1.0.0">
      <gateway_item uuid="{v['gw_uuid']}">
        <disabled>0</disabled>
        <name>DEV_GW</name>
        <interface>lan</interface>
        <ipprotocol>inet</ipprotocol>
        <gateway>{v['gw']}</gateway>
        <defaultgw>1</defaultgw>
        <monitor_disable>1</monitor_disable>
        <priority>255</priority>
        <weight>1</weight>
      </gateway_item>
    </Gateways>
  </OPNsense>
  <filter>
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <descr>Default allow LAN to any rule</descr>
      <interface>lan</interface>
      <source>
        <network>lan</network>
      </source>
      <destination>
        <any/>
      </destination>
    </rule>
  </filter>
  <ca>
    <refid>{v['ca_ref']}</refid>
    <descr>opnsense-test proof CA</descr>
    <crt>{v['ca']}</crt>
  </ca>
  <authserver>
    <refid>{v['srv_ref']}</refid>
    <type>openidconnect</type>
    <name>{SERVER}</name>
    <openidconnect_enabled>1</openidconnect_enabled>
    <openidconnect_app_code>{APP_CODE}</openidconnect_app_code>
    <openidconnect_provider_profile>keycloak</openidconnect_provider_profile>
    <openidconnect_provider_url>{v['issuer']}</openidconnect_provider_url>
    <openidconnect_client_id>{CLIENT}</openidconnect_client_id>
    <openidconnect_client_secret>{v['secret']}</openidconnect_client_secret>
    <openidconnect_par_mode>disabled</openidconnect_par_mode>
    <openidconnect_ssf_enabled>0</openidconnect_ssf_enabled>
    <openidconnect_logout_notifications>off</openidconnect_logout_notifications>
    <openidconnect_bootstrap_mode>approval</openidconnect_bootstrap_mode>
    <openidconnect_create_users>0</openidconnect_create_users>
    <openidconnect_allow_root>0</openidconnect_allow_root>
  </authserver>
</opnsense>
"""
    with open(out, "w") as f:
        f.write(xml)


def realm(settings, proof, out):
    s = json.load(open(settings))
    origin = f"https://{s['address']}"
    users = [("proof-user", read(proof, "user.pass")), ("proof-stranger", read(proof, "stranger.pass"))]
    json.dump({
        "realm": REALM, "enabled": True, "sslRequired": "all",
        "clients": [{
            "clientId": CLIENT, "enabled": True, "protocol": "openid-connect", "publicClient": False,
            "clientAuthenticatorType": "client-secret", "secret": read(proof, "client.secret"),
            "standardFlowEnabled": True, "implicitFlowEnabled": False, "directAccessGrantsEnabled": False,
            # The same exact URIs as the lab realm's OPNsense client (role k8s_identity).
            "serviceAccountsEnabled": False, "rootUrl": origin, "baseUrl": "/",
            "redirectUris": [f"{origin}/api/openidconnect/auth/callback/{APP_CODE}"], "webOrigins": [origin],
            "attributes": {"pkce.code.challenge.method": "S256",
                           "post.logout.redirect.uris": f"{origin}/api/openidconnect/auth/logouttestcallback/{APP_CODE}"},
        }],
        "users": [{
            "username": u, "enabled": True, "emailVerified": True, "email": f"{u}@example.invalid",
            "firstName": "Proof", "lastName": u, "credentials": [{"type": "password", "value": p, "temporary": False}],
        } for u, p in users],
    }, open(out, "w"), indent=1)


if __name__ == "__main__":
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    fn = {"seed": (seed, 4), "config": (config, 5), "realm": (realm, 3)}.get(cmd)
    if fn is None or len(args) != fn[1]:
        sys.exit(__doc__)
    fn[0](*args)
