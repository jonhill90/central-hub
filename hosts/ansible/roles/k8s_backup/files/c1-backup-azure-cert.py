#!/usr/bin/python3 -I
"""The node's own Azure sign-in for c1's backups (role k8s_backup, agent pick 189).

restic signs in to Azure Blob as the backup app registration with a certificate whose key is made
on this node and never leaves it (azidentity's EnvironmentCredential reads AZURE_CLIENT_ID,
AZURE_TENANT_ID and AZURE_CLIENT_CERTIFICATE_PATH). This script makes that key and certificate, and
rolls them before they expire, with no person, agent or stored Azure secret involved:

  init    Make the key and a self-signed certificate if the file is missing. Prints JSON with the
          public certificate, for the playbook's first upload.
  check   Ask Entra ID for a token with the certificate. Exit 0: it works. Exit 3: Entra ID does not
          know this certificate (upload it). Exit 1: anything else.
  renew   Run by a daily systemd timer. With more than BACKUP_CERT_RENEW_DAYS left, do nothing.
          Otherwise make a new key and certificate, add it to the app with Microsoft Graph addKey
          (an app needs no permission to roll its own keys; the proof is a JWT signed by the
          current key), wait until Entra ID accepts it, switch the file over, then remove the old
          certificate with removeKey. Any failure exits non-zero and leaves the current file alone.

Settings come from the environment, then from the env file (CENTRAL_HUB_BACKUP_ENV, default
/etc/central-hub/backup.env): AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_CERTIFICATE_PATH,
AZURE_APP_OBJECT_ID (the app's object ID, which addKey takes), and optionally BACKUP_CERT_DAYS
(default 90), BACKUP_CERT_RENEW_DAYS (default 30), AZURE_AUTHORITY_HOST and BACKUP_GRAPH_ENDPOINT
(for tests). Needs only Python's standard library and the openssl command.
"""

import base64
import datetime
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

NOT_REGISTERED = 3
GRAPH_POP_AUDIENCE = "00000002-0000-0000-c000-000000000000"
STORAGE_SCOPE = "https://storage.azure.com/.default"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"


def log(msg):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"{stamp} {msg}", flush=True)


def die(msg, code=1):
    log(f"FAIL: {msg}")
    sys.exit(code)


def settings():
    conf = {}
    env_file = os.environ.get("CENTRAL_HUB_BACKUP_ENV", "/etc/central-hub/backup.env")
    if os.path.isfile(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                    value = value[1:-1]
                conf[key.strip()] = value
    conf.update({k: v for k, v in os.environ.items() if k.startswith(("AZURE_", "BACKUP_"))})
    conf.setdefault("AZURE_AUTHORITY_HOST", "https://login.microsoftonline.com")
    conf.setdefault("BACKUP_GRAPH_ENDPOINT", "https://graph.microsoft.com")
    conf.setdefault("BACKUP_CERT_DAYS", "90")
    conf.setdefault("BACKUP_CERT_RENEW_DAYS", "30")
    return conf


def need(conf, *keys):
    missing = [k for k in keys if not conf.get(k)]
    if missing:
        die(f"not set: {', '.join(missing)} (env file or environment)")


# --- the certificate file: the private key, then the certificate, in one 0600 PEM file ----------


def pem_blocks(text, kind):
    begin, end = f"-----BEGIN {kind}-----", f"-----END {kind}-----"
    out, rest = [], text
    while begin in rest:
        rest = rest[rest.index(begin) + len(begin):]
        body, rest = rest.split(end, 1)
        out.append(base64.b64decode("".join(body.split())))
    return out


class Cert:
    def __init__(self, path):
        self.path = path
        with open(path) as f:
            text = f.read()
        ders = pem_blocks(text, "CERTIFICATE")
        if not ders or "PRIVATE KEY-----" not in text:
            die(f"{path} must hold a private key and a certificate")
        self.der = ders[0]
        self.sha1 = hashlib.sha1(self.der).digest()
        self.thumbprint = self.sha1.hex().upper()
        out = subprocess.run(["openssl", "x509", "-noout", "-enddate"], input=self.pem(),
                             capture_output=True, text=True, check=True).stdout
        self.not_after = datetime.datetime.strptime(
            out.strip().split("=", 1)[1], "%b %d %H:%M:%S %Y GMT").replace(tzinfo=datetime.timezone.utc)

    def pem(self):
        body = base64.b64encode(self.der).decode()
        lines = [body[i:i + 64] for i in range(0, len(body), 64)]
        return "-----BEGIN CERTIFICATE-----\n" + "\n".join(lines) + "\n-----END CERTIFICATE-----\n"

    def days_left(self):
        return (self.not_after - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 86400

    def sign(self, data):
        return subprocess.run(["openssl", "dgst", "-sha256", "-sign", self.path], input=data,
                              capture_output=True, check=True).stdout

    def jwt(self, claims):
        header = {"alg": "RS256", "typ": "JWT", "x5t": b64url(self.sha1), "kid": self.thumbprint}
        signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}"
        return f"{signing_input}.{b64url(self.sign(signing_input.encode()))}"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_cert(path, days):
    """Write a new key and self-signed certificate to path (0600), replacing nothing else."""
    folder = os.path.dirname(os.path.abspath(path))
    with tempfile.TemporaryDirectory(dir=folder) as tmp:
        key, crt = os.path.join(tmp, "key.pem"), os.path.join(tmp, "cert.pem")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256",
                        "-keyout", key, "-out", crt, "-days", str(days), "-subj", "/CN=c1-backup"],
                       check=True, capture_output=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as out:
            out.write(open(key).read() + open(crt).read())


# --- Entra ID and Microsoft Graph ----------------------------------------------------------------


def http(method, url, body=None, headers=None, form=False):
    data = None
    headers = dict(headers or {})
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            return err.code, json.loads(raw)
        except ValueError:
            return err.code, {"error": raw.decode(errors="replace")[:300]}


def token(conf, cert, scope):
    """Client credentials with a certificate (Microsoft identity platform, certificate credentials).
    Returns (access token or None, error text)."""
    url = f"{conf['AZURE_AUTHORITY_HOST'].rstrip('/')}/{conf['AZURE_TENANT_ID']}/oauth2/v2.0/token"
    now = int(time.time())
    assertion = cert.jwt({"aud": url, "iss": conf["AZURE_CLIENT_ID"], "sub": conf["AZURE_CLIENT_ID"],
                          "jti": str(uuid.uuid4()), "nbf": now - 60, "iat": now - 60, "exp": now + 540})
    status, answer = http("POST", url, form=True, body={
        "client_id": conf["AZURE_CLIENT_ID"], "grant_type": "client_credentials", "scope": scope,
        "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "client_assertion": assertion})
    if status == 200 and answer.get("access_token"):
        return answer["access_token"], ""
    return None, f"{answer.get('error', status)}: {answer.get('error_description', '')}".strip()


def proof(conf, cert):
    """The proof-of-possession JWT addKey and removeKey require: aud 00000002-..., iss the app's
    object ID, valid for 10 minutes (Microsoft Graph, "Generate proof-of-possession tokens")."""
    now = int(time.time())
    return cert.jwt({"aud": GRAPH_POP_AUDIENCE, "iss": conf["AZURE_APP_OBJECT_ID"], "nbf": now, "exp": now + 600})


def graph(conf, bearer, action, body):
    url = f"{conf['BACKUP_GRAPH_ENDPOINT'].rstrip('/')}/v1.0/applications/{conf['AZURE_APP_OBJECT_ID']}/{action}"
    return http("POST", url, body=body, headers={"Authorization": f"Bearer {bearer}"})


# --- commands ------------------------------------------------------------------------------------


def cmd_init(conf):
    need(conf, "AZURE_CLIENT_CERTIFICATE_PATH")
    path = conf["AZURE_CLIENT_CERTIFICATE_PATH"]
    made = False
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(os.path.abspath(path)), mode=0o700, exist_ok=True)
        make_cert(path, int(conf["BACKUP_CERT_DAYS"]))
        made = True
    cert = Cert(path)
    print(json.dumps({"made": made, "thumbprint": cert.thumbprint,
                      "thumbprint_b64": base64.b64encode(cert.sha1).decode(),
                      "not_after": cert.not_after.strftime("%Y-%m-%dT%H:%M:%SZ"),
                      "days_left": int(cert.days_left()), "certificate": cert.pem()}))


def cmd_check(conf):
    need(conf, "AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_CLIENT_CERTIFICATE_PATH")
    path = conf["AZURE_CLIENT_CERTIFICATE_PATH"]
    if not os.path.exists(path):
        die(f"{path} is missing: run the playbook's timers tag", NOT_REGISTERED)
    cert = Cert(path)
    got, err = token(conf, cert, STORAGE_SCOPE)
    if got:
        log(f"ok: Entra ID accepts certificate {cert.thumbprint}, {int(cert.days_left())} days left")
        return
    # AADSTS700027: the certificate that signed the assertion is not registered on the app.
    if "AADSTS700027" in err:
        die(f"Entra ID does not know certificate {cert.thumbprint}: {err}", NOT_REGISTERED)
    die(f"no token: {err}")


def wait_accepted(conf, cert, seconds):
    deadline = time.time() + seconds
    while True:
        got, err = token(conf, cert, STORAGE_SCOPE)
        if got:
            return True, ""
        if time.time() > deadline:
            return False, err
        time.sleep(float(conf.get("BACKUP_CERT_WAIT_STEP", "15")))


def cmd_renew(conf):
    need(conf, "AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_CLIENT_CERTIFICATE_PATH", "AZURE_APP_OBJECT_ID")
    path = conf["AZURE_CLIENT_CERTIFICATE_PATH"]
    keyid_file = path + ".keyid"
    if not os.path.exists(path):
        die(f"{path} is missing: run the playbook's timers tag, which makes and uploads it")
    cur = Cert(path)
    left = cur.days_left()
    if left > float(conf["BACKUP_CERT_RENEW_DAYS"]):
        log(f"ok: certificate {cur.thumbprint} has {int(left)} days left, renewal starts at {conf['BACKUP_CERT_RENEW_DAYS']}")
        return
    if left <= 0:
        die(f"certificate {cur.thumbprint} expired on {cur.not_after:%Y-%m-%d}: Graph needs a valid one to roll it, "
            "so run the playbook's timers tag, which uploads a new one")
    log(f"certificate {cur.thumbprint} has {int(left)} days left: rolling it")

    bearer, err = token(conf, cur, GRAPH_SCOPE)
    if not bearer:
        die(f"no Graph token with the current certificate: {err}")

    new_path = path + ".new"
    if os.path.exists(new_path):
        os.unlink(new_path)  # left by a run that failed before it was added
    make_cert(new_path, int(conf["BACKUP_CERT_DAYS"]))
    new = Cert(new_path)

    status, answer = graph(conf, bearer, "addKey", {
        "keyCredential": {"type": "AsymmetricX509Cert", "usage": "Verify", "key": base64.b64encode(new.der).decode()},
        "passwordCredential": None, "proof": proof(conf, cur)})
    if status != 200:
        os.unlink(new_path)
        die(f"addKey answered {status}: {json.dumps(answer)[:500]}")
    new_keyid = answer.get("keyId", "")
    log(f"added certificate {new.thumbprint} (key {new_keyid or 'id not returned'})")

    ok, err = wait_accepted(conf, new, int(conf.get("BACKUP_CERT_WAIT_SECONDS", "900")))
    if not ok:
        die(f"Entra ID still refuses the new certificate {new.thumbprint}: {err}. The current one stays in use; "
            f"{new_path} is kept for a look")

    old_keyid = open(keyid_file).read().strip() if os.path.exists(keyid_file) else ""
    os.replace(new_path, path)
    new.path = path
    with open(keyid_file + ".tmp", "w") as f:
        f.write(new_keyid + "\n")
    os.replace(keyid_file + ".tmp", keyid_file)
    log(f"switched to certificate {new.thumbprint}, valid until {new.not_after:%Y-%m-%d}")

    if not old_keyid:
        log(f"WARN: the old certificate's key ID is not known, so it stays on the app until it expires on "
            f"{cur.not_after:%Y-%m-%d}; the playbook's timers tag removes expired ones")
        return
    bearer, err = token(conf, new, GRAPH_SCOPE)
    if not bearer:
        log(f"WARN: no Graph token with the new certificate to remove the old one: {err}")
        return
    status, answer = graph(conf, bearer, "removeKey", {"keyId": old_keyid, "proof": proof(conf, new)})
    if status in (200, 204):
        log(f"removed the old certificate {cur.thumbprint} (key {old_keyid})")
    else:
        log(f"WARN: removeKey answered {status}: {json.dumps(answer)[:300]}; the old certificate expires on "
            f"{cur.not_after:%Y-%m-%d}")


def main():
    commands = {"init": cmd_init, "check": cmd_check, "renew": cmd_renew}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(f"usage: {sys.argv[0]} init|check|renew")
    os.umask(0o077)
    commands[sys.argv[1]](settings())


if __name__ == "__main__":
    main()
