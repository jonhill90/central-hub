#!/bin/bash
# /usr/local/libexec/agent-box/c1-read.sh: read c1 with the read-only kubeconfig, which sessions
# can't open (it sits in /etc/agent-keys). It runs as user `keys`; the account behind the
# kubeconfig is app agent-read on c1, which reads everything but Secrets and changes nothing
# (docs/runbooks/give-agents-read-access-to-c1.md). Installed by the agent_box role; root owns it.
#   c1-read get pods -A
#   c1-read describe node <name>
#   c1-read logs -n <namespace> <pod>
#   c1-read auth can-i --list
# Only read verbs pass. Flags that pick other credentials or another server, or that make kubectl
# open a local file (which as `keys` could be a key), are refused, so the kubeconfig and the keys
# folder never reach the session.
set -euo pipefail
umask 077

work=/var/lib/agent-box
config=/etc/agent-keys/c1-readonly.kubeconfig
kubectl=/usr/local/bin/kubectl
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin KUBECTL_KUBERC=false   # no kuberc aliases or defaults
unset KUBECONFIG

die() { echo "c1-read: $*" >&2; exit 2; }

[[ $# -ge 1 ]] || die "usage: c1-read get|describe|logs|top|events|explain|api-resources|api-versions|version|auth can-i ..."
case $1 in
  get | describe | logs | top | events | explain | api-resources | api-versions | version) ;;
  auth) [[ ${2:-} == can-i ]] || die "only 'auth can-i' is allowed" ;;
  *) die "'$1' is not a read verb; allowed: get describe logs top events explain api-resources api-versions version 'auth can-i'" ;;
esac

for a in "$@"; do
  # kubectl reads "_" in a flag name as "-" (--cache_dir is --cache-dir), which would slip past the
  # names below, and none of its own flags has "_": refuse any long flag whose name has one.
  n=${a%%=*}
  [[ $n == --* && $n == *_* ]] && die "flag $a is not allowed (no flag name has \"_\")"
  case $a in
    # credentials, identity and server: the kubeconfig decides these
    --kubeconfig* | --context* | --cluster* | --user* | --token* | --as* | --server* | \
      --certificate-authority* | --client-certificate* | --client-key* | --password* | \
      --insecure-skip-tls-verify* | --tls-server-name* | --disable-compression* | --cache-dir*) die "flag $a is not allowed" ;;
    # local files: input, templates, output and profiles
    --filename* | --kustomize* | --recursive* | --template* | --output-directory* | --profile* | --log-file* | \
      --kuberc* | *template-file* | *jsonpath-file*) die "flag $a is not allowed (it reads or writes a local file)" ;;
    # short flags, alone or bunched (-Af): -f file, -k dir, -R and -s server are refused. A flag that
    # takes a value (-o, -l, -n, -L, -c) ends the bunch: the rest of the word is its value.
    -[!-]*)
      s=${a#-}
      while [[ -n $s ]]; do
        case ${s:0:1} in
          f | k | R | s) die "flag $a is not allowed" ;;
          o | l | n | L | c) break ;;
        esac
        s=${s:1}
      done ;;
  esac
done

[[ -f $config ]] || die "$config is missing; put it there through the keys wrapper (docs/runbooks/give-agents-read-access-to-c1.md)"
cd "$work"
exec "$kubectl" --kubeconfig "$config" --request-timeout=30s "$@"
