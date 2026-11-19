#!/bin/bash
# The notebook runner's start: unpack the pinned actions/runner release into /runner/app once (and again
# when the pin moves), register once with the one-hour token, then run. Registration files live on
# the pod's volume, so a restart only runs. The release goes in a folder this user makes, because tar
# can't change the mode of the volume's own top folder, which this user doesn't own.
set -euo pipefail
# The token's volume is optional and is filled after the pod exists (the runbook's step 3), so a pod with no token waits
# here instead of exiting: a restart loop would trip C1PodCrashLooping and page ntfy. It prints one line when it starts
# waiting and one every 5 minutes. Only the token goes to stdout.
# wait_for_token begin
wait_for_token() {
  local f=${TOKEN_FILE:-/token/value} every=${TOKEN_WAIT_SECONDS:-10} n=0 t
  while :; do
    t=$(cat "$f" 2>/dev/null || true)
    if [[ -n $t ]]; then printf '%s' "$t"; return 0; fi
    if (( n % (300 / (every > 0 ? every : 1) + 1) == 0 )); then
      echo "notebook-runner: not registered and no registration token yet (kv c1/notebook-runner); waiting" >&2
    fi
    n=$((n + 1)); sleep "$every"
  done
}
# wait_for_token end
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
  token=$(wait_for_token)
  # config.sh refuses with "already configured" if an earlier half-done registration left files.
  rm -f .credentials .credentials_rsaparams .runner_migrated .credentials_migrated
  ./config.sh --unattended --url "$REPO_URL" --token "$token" --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" --work _work --replace --disableupdate
fi
exec ./run.sh
