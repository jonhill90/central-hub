# The provider logs in with a tailnet OAuth client, read from the environment at apply time, so it
# never appears in this repository or in a tfvars file:
#   TAILSCALE_OAUTH_CLIENT_ID      the client's ID
#   TAILSCALE_OAUTH_CLIENT_SECRET  its secret
# Both sit in the git-ignored hosts/.env on the operator's Mac (hosts/.env.example lists them).
# The client needs the scopes `dns` (split DNS) and `devices:routes` plus `devices:core:read`
# (find the connector, turn on its routes). The tailnet is the one that owns the client.
provider "tailscale" {}
