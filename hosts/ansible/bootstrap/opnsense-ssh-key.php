<?php
// SSH by key into OPNsense as root, on LAN only, for the lab test copy's VM 100 (docs/runbooks/build-the-lab-test-copy.md,
// lab-test firstboot), so the steps after it can run commands on that firewall. Run as root in OPNsense's shell:
//   php opnsense-ssh-key.php <public key file>
// The file holds one ed25519 public key line, which the agent box made for this copy only. The script turns OpenSSH on
// (system/ssh/enabled) for root (permitrootlogin), with password and keyboard-interactive sign-in off (no
// passwordauth), listening on LAN only (interfaces lan; openssh.inc adds lo0), and sets root's authorized keys to that
// one line (the user's authorizedkeys, base64; auth.inc local_user_set writes /root/.ssh/authorized_keys from it).
// sshd starts with these settings at the next boot (openssh.inc, openssh_configure_do). With SSH on, OPNsense's
// anti-lockout rule passes its port on LAN (filter.lib.inc, filter_core_get_antilockout). Safe to run again: it
// replaces root's keys with this one line. Written against opnsense/core 26.1.6.
// Not run on the lab firewall: there, SSH for agents is a new access right and a firewall change, which wait for the
// owner's go (docs/runbooks/sign-in-to-opnsense-through-keycloak.md, step 5).
require_once('config.inc');
require_once('auth.inc');

if (count($argv) != 2) { echo "usage: opnsense-ssh-key.php <public key file>\n"; exit(2); }
$key = trim((string)@file_get_contents($argv[1]));
// One ed25519 key: its type, the 68-character blob of a 32-byte key, and at most a one-word comment.
if (!preg_match('/^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+\/]{43}( [A-Za-z0-9@._-]{1,64})?$/', $key)) {
    echo "bad public key file\n"; exit(1);
}

$ssh = &config_read_array('system', 'ssh');
$ssh['enabled'] = 'enabled';
$ssh['permitrootlogin'] = '1';
unset($ssh['passwordauth'], $ssh['noauto']);
$ssh['interfaces'] = 'lan';

$root = &getUserEntryByUID(0);
if (!$root) { echo "no root user\n"; exit(1); }
$root['authorizedkeys'] = base64_encode($key);
local_user_set($root);

write_config('lab test copy: SSH for root by key only, on LAN only');
echo "ssh: root by key only, on LAN only, from the next boot\n";
