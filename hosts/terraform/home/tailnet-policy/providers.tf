# The provider logs in with a tailnet OAuth client, read from the environment at apply time, so it
# never appears in this repository or in a tfvars file:
#   TAILSCALE_OAUTH_CLIENT_ID      the client's ID
#   TAILSCALE_OAUTH_CLIENT_SECRET  its secret
# Both sit in the git-ignored hosts/.env on the operator's Mac (hosts/.env.example lists them).
# This folder needs the scope `policy_file`, which home/tailnet does not. Give it a client of its
# own, so the client that turns on routes can't rewrite who reaches what.
provider "tailscale" {}
