<?php
// Create or update OPNsense user "box-backup" for the agent box's daily configuration copy
// (roles/agent_box/files/opnsense-backup.sh, pick 220), and set its API key from
// /root/box-backup-apikey.line ("<key>|<sha512-crypt of the secret>"). The secret itself is never on this
// machine. Run by opnsense-backup-user.sh on the controller, through the Proxmox host's QEMU guest agent.
//
// Two privileges and no more (OPNsense core, models/OPNsense/Core/ACL/ACL.xml and
// controllers/OPNsense/Core/Api/BackupController.php):
//   page-diagnostics-configurationhistory  the only privilege whose patterns cover api/core/backup/*, the
//                                          download the box calls. It also covers revertBackup and deleteBackup.
//   user-config-readonly                   "Deny config write": both of those call throwReadOnly() first and
//                                          refuse this user, so the key can read the configuration and change nothing.
// A separate user, not a privilege added to "ansible", so the box's backup key is its own and can be revoked
// alone, and the key that can write firewall rules is not the one a daily timer sends.
require_once('script/load_phalcon.php');
use OPNsense\Core\Config;

$name = 'box-backup';
$privs = ['page-diagnostics-configurationhistory', 'user-config-readonly'];
$file = '/root/box-backup-apikey.line';
$line = trim(file_get_contents($file));
if (substr_count($line, '|') != 1 || strpos($line, '$6$') === false) { echo "bad key line\n"; exit(1); }

$mdl = new OPNsense\Auth\User();
$node = null;
foreach ($mdl->user->iterateItems() as $u) {
    if ((string)$u->name == $name) { $node = $u; }
}
if ($node === null) {
    $node = $mdl->user->Add();
    $node->name = $name;
    $node->password = $mdl->generatePasswordHash(bin2hex(random_bytes(32))); // nobody knows it
}
$node->descr = 'Agent box configuration copy (central-hub opnsense-backup.sh), API only, read-only';
$node->priv = implode(',', $privs);
$node->apikeys = $line;   // replaces any earlier key of this user
$v = $mdl->performValidation();
if (count($v)) { foreach ($v as $m) { echo $m->getField() . ' ' . $m->getMessage() . "\n"; } exit(1); }
$mdl->serializeToConfig();
Config::getInstance()->save();
unlink($file);
echo "$name saved, privileges: " . implode(',', $privs) . ", api keys: " . count($node->apikeys->all()) . "\n";
