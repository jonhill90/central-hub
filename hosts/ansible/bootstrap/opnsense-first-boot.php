<?php
// First boot of the OPNsense nano image without a person at the console: what
// docs/runbooks/set-up-lab-network-and-firewall.md step 5 does by hand. Run as root in OPNsense's shell:
//   php opnsense-first-boot.php <trunk> <mgmt tag> <mgmt gateway/prefix> <wan> <root hash file>
//   php opnsense-first-boot.php vtnet0 50 10.1.50.1/24 vtnet1 /root/root.hash
// It makes the mgmt VLAN on the trunk as the console's menu 1 names it (<trunk>_vlan<tag>, console.inc), puts LAN
// there with the mgmt gateway address and no DHCP, router advertisements or IPv6, keeps WAN on <wan> as a DHCPv4
// client only (the WAN safety check expects no dhcp6c), drops the setup wizard, and sets root's password to the
// SHA-512 crypt hash in the hash file (OPNsense writes the same kind itself: auth.inc, local_user_set_password).
// Then reboot to apply. Safe to run again. Written against opnsense/core 26.1.6 (config.inc, auth.inc, console.inc,
// config.xml.sample).
require_once('config.inc');
require_once('auth.inc');
require_once('util.inc');

if (count($argv) != 6) { echo "usage: opnsense-first-boot.php <trunk> <tag> <address/prefix> <wan> <root hash file>\n"; exit(2); }
[, $trunk, $tag, $cidr, $wanif, $hashfile] = $argv;
if (!preg_match('/^[a-z]+[0-9]+$/', $trunk) || !preg_match('/^[a-z]+[0-9]+$/', $wanif) || $trunk == $wanif) {
    echo "bad interface names\n"; exit(2);
}
if (!ctype_digit($tag) || (int)$tag < 1 || (int)$tag > 4094) { echo "bad VLAN tag\n"; exit(2); }
if (!preg_match('/^(\d{1,3}(\.\d{1,3}){3})\/(\d{1,2})$/', $cidr, $m) || !filter_var($m[1], FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)
    || (int)$m[3] < 8 || (int)$m[3] > 30) {
    echo "bad address\n"; exit(2);
}
$hash = trim((string)@file_get_contents($hashfile));
if (!preg_match('/^\$6\$[.\/A-Za-z0-9]{1,16}\$[.\/A-Za-z0-9]{86}$/', $hash)) { echo "bad root hash file\n"; exit(1); }

// The mgmt VLAN, as the console makes it.
$vlanif = "{$trunk}_vlan{$tag}";
$have = false;
foreach (config_read_array('vlans', 'vlan', false) as $v) {
    if (($v['vlanif'] ?? '') == $vlanif) { $have = true; }
}
if (!$have) {
    config_push_array('vlans', 'vlan', [
        '@attributes' => ['uuid' => generate_uuid()],
        'if' => $trunk, 'tag' => $tag, 'pcp' => '0', 'proto' => '', 'descr' => 'mgmt', 'vlanif' => $vlanif,
    ]);
}

// LAN on the mgmt VLAN, IPv4 only.
$lan = &config_read_array('interfaces', 'lan');
$lan['if'] = $vlanif;
$lan['enable'] = '1';
$lan['ipaddr'] = $m[1];
$lan['subnet'] = $m[3];
foreach (['ipaddrv6', 'subnetv6', 'track6-interface', 'track6-prefix-id'] as $k) { unset($lan[$k]); }

// WAN: a DHCPv4 client on its own NIC and nothing else.
$wan = &config_read_array('interfaces', 'wan');
$wan['if'] = $wanif;
$wan['enable'] = '1';
$wan['ipaddr'] = 'dhcp';
unset($wan['ipaddrv6'], $wan['subnetv6']);

// The default config serves DHCP and router advertisements on LAN (config.xml.sample); mgmt has neither.
if (isset($config['dnsmasq']['dhcp_ranges']) && is_array($config['dnsmasq']['dhcp_ranges'])) {
    foreach ($config['dnsmasq']['dhcp_ranges'] as $i => $r) {
        if (($r['interface'] ?? '') == 'lan') { unset($config['dnsmasq']['dhcp_ranges'][$i]); }
    }
}
unset($config['dnsmasq']['dhcp']['enable_ra']);
unset($config['trigger_initial_wizard']);

$root = &getUserEntryByUID(0);
if (!$root) { echo "no root user\n"; exit(1); }
$root['password'] = $hash;
local_user_set($root);

write_config('lab first boot: mgmt VLAN, LAN and WAN, root password');
echo "first boot: LAN {$vlanif} {$cidr}, WAN {$wanif} DHCPv4 only, root password set\n";
