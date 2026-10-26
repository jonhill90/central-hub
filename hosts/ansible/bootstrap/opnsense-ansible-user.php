<?php
// Create or update OPNsense user "ansible" for hosts/ansible (opnsense.yml), with only the
// privileges that playbook needs, and set its API key from /root/ansible-apikey.line
// ("<key>|<sha512-crypt of the secret>"). The secret itself is never on this machine.
// Run as root through the QEMU guest agent (no login): copy this file and the key line in with
// the agent's file-write call in pieces under ~700 bytes (larger payloads hang OPNsense's agent),
// then `qm guest exec 100 -- php /root/ansible-user.php`. Make the key and secret on the
// controller, keep them in a 0600 file there, and send only "<key>|$(openssl passwd -6)".
require_once('script/load_phalcon.php');
use OPNsense\Core\Config;

$privs = [
    'page-interfaces-vlan-edit',            // api/interfaces/vlan_settings
    'page-interfaces-assignnetworkports',   // api/interfaces/assignment
    'page-services-dnsforwarder',           // api/dnsmasq
    'page-firewall-rules', 'page-filter-api', // api/firewall/filter (rules, apply)
    'page-firewall-alias-edit', 'page-firewall-aliases', // api/firewall/alias
    'page-services-dnsresolver-overrides',  // api/unbound host overrides
];
$line = trim(file_get_contents('/root/ansible-apikey.line'));
if (substr_count($line, '|') != 1 || strpos($line, '$6$') === false) { echo "bad key line\n"; exit(1); }

$mdl = new OPNsense\Auth\User();
$node = null;
foreach ($mdl->user->iterateItems() as $u) {
    if ((string)$u->name == 'ansible') { $node = $u; }
}
if ($node === null) {
    $node = $mdl->user->Add();
    $node->name = 'ansible';
    $node->password = $mdl->generatePasswordHash(bin2hex(random_bytes(32))); // nobody knows it
}
$node->descr = 'Ansible (hosts/ansible opnsense.yml), API only';
$node->priv = implode(',', $privs);
$node->apikeys = $line;   // replaces any earlier key of this user
$v = $mdl->performValidation();
if (count($v)) { foreach ($v as $m) { echo $m->getField() . ' ' . $m->getMessage() . "\n"; } exit(1); }
$mdl->serializeToConfig();
Config::getInstance()->save();
echo "ansible user saved, privileges: " . count($privs) . ", api keys: " . count($node->apikeys->all()) . "\n";
