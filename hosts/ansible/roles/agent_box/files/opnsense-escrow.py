#!/usr/bin/python3 -I
"""The restic password of the box's off-box OPNsense copies, made on the box and kept off it (pick 222,
docs/runbooks/copy-opnsense-backup-off-box.md). Run as the keys user by opnsense-offbox.sh.

  ensure  Make the password file (0600) if it is missing. Then make sure the newest version of the
          password secret in Key Vault is this password: the box's custom role lets it set the secret
          and read secrets' metadata, never a value, so each version carries the password's SHA-256 as
          a tag, and the tag is what is compared. If it differs or there is no version, write the
          password as a new version and check the tag again. Exit 0 only when the vault holds it.

The value goes from the file to Key Vault's HTTPS API and nowhere else: it is never printed or logged.
Sign-in is the box's own certificate, through azure-cert.py (the c1 nodes' script, same folder).
Settings come from the same env file (CENTRAL_HUB_BACKUP_ENV): AZURE_CLIENT_ID, AZURE_TENANT_ID,
AZURE_CLIENT_CERTIFICATE_PATH, RESTIC_PASSWORD_FILE, OFFBOX_VAULT_URL and OFFBOX_VAULT_SECRET.
"""

import base64
import hashlib
import importlib.util
import os
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("azure_cert", os.environ.get("AZURE_CERT_SCRIPT", os.path.join(HERE, "azure-cert.py")))
az = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(az)

API = "api-version=7.4"
SCOPE = "https://vault.azure.net/.default"


def password(path):
    """The password, made once: 32 random bytes in base64, written with O_EXCL so a second run never
    replaces it."""
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(os.path.abspath(path)), mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(base64.b64encode(os.urandom(32)).decode() + "\n")
        az.log("made a new repository password")
    with open(path) as f:
        value = f.read().rstrip("\r\n")
    if len(value) < 32:
        az.die(f"{path} holds less than 32 characters; it is not a password this script made")
    return value


def newest_tag(conf, bearer):
    """The sha256 tag of the newest enabled version, or "" when there is none (readMetadata only)."""
    url = f"{conf['OFFBOX_VAULT_URL'].rstrip('/')}/secrets/{conf['OFFBOX_VAULT_SECRET']}/versions?{API}"
    versions = []
    while url:
        status, answer = az.http("GET", url, headers={"Authorization": f"Bearer {bearer}"})
        if status == 404:
            return ""
        if status != 200:
            az.die(f"listing the secret's versions answered {status}: {str(answer)[:300]}")
        versions += answer.get("value", [])
        url = answer.get("nextLink") or ""
    live = [v for v in versions if v.get("attributes", {}).get("enabled", True)]
    if not live:
        return ""
    newest = max(live, key=lambda v: v.get("attributes", {}).get("created", 0))
    return (newest.get("tags") or {}).get("sha256", "")


def cmd_ensure(conf):
    az.need(conf, "AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_CLIENT_CERTIFICATE_PATH", "RESTIC_PASSWORD_FILE",
            "OFFBOX_VAULT_URL", "OFFBOX_VAULT_SECRET")
    if urllib.parse.urlparse(conf["OFFBOX_VAULT_URL"]).scheme not in ("https", "http"):
        az.die("OFFBOX_VAULT_URL must be a URL")
    value = password(conf["RESTIC_PASSWORD_FILE"])
    digest = hashlib.sha256(value.encode()).hexdigest()
    cert = az.Cert(conf["AZURE_CLIENT_CERTIFICATE_PATH"])
    bearer, err = az.token(conf, cert, SCOPE)
    if not bearer:
        az.die(f"no Key Vault token with the box's certificate: {err}")
    if newest_tag(conf, bearer) == digest:
        az.log("ok: the vault holds the current password")
        return
    url = f"{conf['OFFBOX_VAULT_URL'].rstrip('/')}/secrets/{conf['OFFBOX_VAULT_SECRET']}?{API}"
    status, answer = az.http("PUT", url, headers={"Authorization": f"Bearer {bearer}"}, body={
        "value": value, "contentType": "restic-password", "tags": {"sha256": digest}})
    if status != 200:
        az.die(f"setting the secret answered {status}: {str(answer.get('error', answer))[:300]}")
    if newest_tag(conf, bearer) != digest:
        az.die("the vault's newest version still is not the current password after setting it")
    az.log("wrote the current password to the vault")


def main():
    if len(sys.argv) != 2 or sys.argv[1] != "ensure":
        sys.exit(f"usage: {sys.argv[0]} ensure")
    os.umask(0o077)
    cmd_ensure(az.settings())


if __name__ == "__main__":
    main()
