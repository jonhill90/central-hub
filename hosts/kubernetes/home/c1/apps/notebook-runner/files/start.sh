#!/bin/bash
# The notebook runner's start: unpack the pinned actions/runner release into /runner/app once (and again
# when the pin moves), register once with the one-hour token, then run. Registration files live on
# the pod's volume, so a restart only runs. The release goes in a folder this user makes, because tar
# can't change the mode of the volume's own top folder, which this user doesn't own.
set -euo pipefail
export HOME=/runner/home
mkdir -p "$HOME" /runner/app
cd /runner/app
if [[ $(cat .pin 2>/dev/null) != "$RUNNER_VERSION" ]]; then
  echo "notebook-runner: unpacking actions/runner $RUNNER_VERSION"
  tarball=/tmp/actions-runner.tar.gz
  curl -fsSL --retry 3 -o "$tarball" \
    "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz"
  echo "$RUNNER_SHA256  $tarball" | sha256sum -c -
  tar -xzf "$tarball" -C /runner/app
  rm -f "$tarball"
  echo "$RUNNER_VERSION" > .pin
fi
if [[ ! -f .runner ]]; then
  token=$(cat /token/value 2>/dev/null || true)
  [[ -n $token ]] || { echo "notebook-runner: not registered and no registration token in the store (kv c1/notebook-runner)" >&2; exit 1; }
  # config.sh refuses with "already configured" if an earlier half-done registration left files.
  rm -f .credentials .credentials_rsaparams .runner_migrated .credentials_migrated
  ./config.sh --unattended --url "$REPO_URL" --token "$token" --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" --work _work --replace --disableupdate
fi
exec ./run.sh
