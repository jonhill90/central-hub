#!/usr/bin/env bash
# Sign in for SSH with a one-hour certificate (D-0064 rule 8). Run on the owner's Mac:
#   ssh-sign.sh
# Needs, from the Mac's own private settings file (outside this repository, never committed), the names of the secrets
# store and of Keycloak's realm: ~/.config/central-hub/ssh-sign.env with BAO_ADDR=https://<store> and, if the store's
# certificate is signed by the lab CA, BAO_CACERT=<path to the CA file>. And `bao` (OpenBao's CLI) on PATH, or BAO_BIN=<path>.
# What it does: makes a throwaway ed25519 key in a private temporary folder, logs in to the store with
# `bao login -method=oidc role=ssh-admin -no-store` (a browser opens at Keycloak: password and one-time code), has the
# store sign the public key at ssh-user/sign/admin, loads key and certificate into ssh-agent for one hour, and deletes
# the folder. Nothing stays on disk and no token is stored. Prints the certificate's principals and end time.
set -euo pipefail
umask 077
conf=${SSH_SIGN_ENV:-$HOME/.config/central-hub/ssh-sign.env}
[[ -r $conf ]] || { echo "ssh-sign: $conf is missing (BAO_ADDR=https://<store>)" >&2; exit 2; }
set -a
# shellcheck source=/dev/null
. "$conf"
set +a
[[ ${BAO_ADDR:-} =~ ^https://[A-Za-z0-9.-]+$ ]] || { echo "ssh-sign: BAO_ADDR must be https://<store name>" >&2; exit 2; }
bao=${BAO_BIN:-bao}
command -v "$bao" >/dev/null || { echo "ssh-sign: the bao command is not on PATH (set BAO_BIN)" >&2; exit 2; }
[[ -n ${SSH_AUTH_SOCK:-} ]] || { echo "ssh-sign: no ssh-agent is running" >&2; exit 2; }
life=${SSH_SIGN_LIFE:-3600}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
ssh-keygen -q -t ed25519 -N '' -C "lab-ssh-$(date -u +%Y%m%dT%H%M%SZ)" -f "$work/key"
token=$("$bao" login -method=oidc role=ssh-admin -no-store -token-only)
[[ -n $token ]] || { echo "ssh-sign: the login gave no token" >&2; exit 1; }
BAO_TOKEN=$token "$bao" write -field=signed_key ssh-user/sign/admin "public_key=@$work/key.pub" >"$work/key-cert.pub"
unset token
grep -q '^ssh-.*-cert-v01@openssh.com ' "$work/key-cert.pub" || { echo "ssh-sign: the store returned no certificate" >&2; exit 1; }
ssh-add -t "$life" "$work/key" 2>&1 | sed 's/^/ssh-sign: /'
ssh-keygen -L -f "$work/key-cert.pub" | grep -E 'Principals|Valid:|^ +lab-' | sed 's/^ */ssh-sign: /'
