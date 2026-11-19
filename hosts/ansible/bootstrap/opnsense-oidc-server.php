<?php
// The os-openid-connect server's settings on a running OPNsense, by code (docs/runbooks/sign-in-to-opnsense-through-keycloak.md
// step 2, which the lab firewall otherwise sets under System > Access > Servers). Run as root in OPNsense's shell:
//   php opnsense-oidc-server.php <settings file>
// The file is JSON. It holds a secret, so the script removes it as soon as it is read, however the run ends:
//   {"name": "<server name>", "issuer": "https://...", "client_id": "...", "client_secret": "...",
//    "app_code": "<the redirect path's last part>",
//    "ca": {"descr": "...", "pem": "<one CA certificate>"},   (optional: a CA the issuer's certificate chains to)
//    "proof_admin": "<user name>"}                             (optional, test copies only: a local admin to bind to)
// D-0037 rule 5's settings are fixed here, not read from the file: provider profile Keycloak, admission policy
// Administrator approval, no account made on first login, root not allowed, PAR disabled, logout notifications
// off, shared signals off. The server sits in <system><authserver>, where OPNsense's AuthenticationFactory reads
// it, with the same fields the opnsense-test proof seeds (opnsense-test-seed.py, config). The CA goes in as an
// imported one (refid, descr, crt), as Trust's CaController saves an existing CA, and the trust store is written
// again (configd `system trust configure`). The proof admin is a local user with page-all and an unknown password,
// made through the user model as opnsense-ansible-user.php makes its user; its uid is printed for the prover.
// Safe to run again: the server, the CA and the user are found by name and replaced. Written against
// opnsense/core 26.1.6 and os-openid-connect 1.0.0.beta5. Run on the lab test copy's VM 100 by `lab-test signin`;
// on the lab firewall only with the owner's go (runbook step 5).
require_once('script/load_phalcon.php');
use OPNsense\Core\Backend;
use OPNsense\Core\Config;

if (count($argv) != 2) { echo "usage: opnsense-oidc-server.php <settings file>\n"; exit(2); }
$raw = @file_get_contents($argv[1]);
@unlink($argv[1]);
$in = is_string($raw) ? json_decode($raw, true) : null;
if (!is_array($in)) { echo "the settings file is not JSON\n"; exit(1); }

function need($in, $key, $pattern) {
    $v = $in[$key] ?? null;
    if (!is_string($v) || !preg_match($pattern, $v)) { echo "bad or missing $key\n"; exit(1); }
    return $v;
}
$name = need($in, 'name', '/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/');
$issuer = need($in, 'issuer', '/^https:\/\/[A-Za-z0-9.\-\[\]:]+(\/[A-Za-z0-9._~\/-]*)?$/');
$client = need($in, 'client_id', '/^[A-Za-z0-9._-]{1,64}$/');
$secret = need($in, 'client_secret', '/^[\x21-\x7e]{16,256}$/');
$code = need($in, 'app_code', '/^[a-z0-9_-]{1,32}$/');
$admin = null;
if (array_key_exists('proof_admin', $in)) {
    $admin = need($in, 'proof_admin', '/^[a-z][a-z0-9_-]{2,31}$/');
    if ($admin === 'root') { echo "root is not a proof admin\n"; exit(1); }
}
$ca = null;
if (array_key_exists('ca', $in)) {
    $ca = $in['ca'];
    $pem = is_array($ca) ? trim((string)($ca['pem'] ?? '')) : '';
    $descr = is_array($ca) ? (string)($ca['descr'] ?? '') : '';
    $x509 = $pem === '' ? false : openssl_x509_parse($pem);
    if (substr_count($pem, '-----BEGIN CERTIFICATE-----') != 1 || $x509 === false
        || empty($x509['extensions']['basicConstraints']) || stripos($x509['extensions']['basicConstraints'], 'CA:TRUE') === false
        || !preg_match('/^[A-Za-z0-9 ._-]{1,64}$/', $descr)) {
        echo "bad ca: one CA certificate and a plain description\n"; exit(1);
    }
    $ca = ['descr' => $descr, 'pem' => $pem . "\n"];
}

$uid = null;
if ($admin !== null) {
    $mdl = new OPNsense\Auth\User();
    $descr = 'Proof admin, bound to the Keycloak test user (lab test copy)';
    $node = null;
    foreach ($mdl->user->iterateItems() as $u) {
        if ((string)$u->name == $admin) { $node = $u; }
    }
    // Only a user this script made is replaced: any other account keeps its rights.
    if ($node !== null && (string)$node->descr !== $descr) { echo "user $admin exists and is not a proof admin\n"; exit(1); }
    if ($node === null) {
        $node = $mdl->user->Add();
        $node->name = $admin;
    }
    $node->password = $mdl->generatePasswordHash(bin2hex(random_bytes(32))); // nobody knows it
    $node->descr = $descr;
    $node->priv = 'page-all';
    $v = $mdl->performValidation();
    if (count($v)) { foreach ($v as $m) { echo $m->getField() . ' ' . $m->getMessage() . "\n"; } exit(1); }
    $mdl->serializeToConfig();
    $uid = (string)$node->uid;
}

$cfg = Config::getInstance()->object();
if ($ca !== null) {
    $entry = null;
    foreach ($cfg->ca as $c) {
        if ((string)$c->descr === $ca['descr']) { $entry = $c; }
    }
    if ($entry === null) {
        $entry = $cfg->addChild('ca');
        $entry->addChild('refid', uniqid());
        $entry->addChild('descr', $ca['descr']);
        $entry->addChild('crt', '');
    }
    $entry->crt = base64_encode($ca['pem']);
}

$server = null;
foreach ($cfg->system->authserver as $s) {
    if ((string)$s->name === $name) { $server = $s; }
}
if ($server === null) {
    $server = $cfg->system->addChild('authserver');
    $server->addChild('refid', uniqid());
    $server->addChild('type', 'openidconnect');
    $server->addChild('name', $name);
}
if ((string)$server->type !== 'openidconnect') { echo "a server named $name is not an OpenID Connect server\n"; exit(1); }
$fields = [
    'openidconnect_enabled' => '1',
    'openidconnect_app_code' => $code,
    'openidconnect_provider_profile' => 'keycloak',
    'openidconnect_provider_url' => $issuer,
    'openidconnect_client_id' => $client,
    'openidconnect_client_secret' => $secret,
    'openidconnect_par_mode' => 'disabled',
    'openidconnect_ssf_enabled' => '0',
    'openidconnect_logout_notifications' => 'off',
    'openidconnect_bootstrap_mode' => 'approval',
    'openidconnect_create_users' => '0',
    'openidconnect_allow_root' => '0',
];
foreach ($fields as $k => $v) {
    if (isset($server->$k)) { $server->$k = $v; } else { $server->addChild($k, htmlspecialchars($v, ENT_XML1)); }
}
Config::getInstance()->save();

if ($ca !== null) {
    (new Backend())->configdRun('system trust configure');
}
if ($admin !== null) {
    (new Backend())->configdpRun('auth user changed', [$admin]);
}
echo "openidconnect server $name: issuer $issuer, client $client, app code $code, admission approval, root not allowed, "
    . "PAR disabled, shared signals and logout notifications off\n";
if ($ca !== null) { echo "trust: CA " . $ca['descr'] . " in the trust store\n"; }
if ($uid !== null) { echo "proof admin $admin uid $uid\n"; }
