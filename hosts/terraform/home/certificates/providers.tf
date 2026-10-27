# The provider logs in with the bootstrap token, read from the environment at apply time, so it
# never appears in this repository or in a tfvars file:
#   CLOUDFLARE_API_TOKEN  the one hand-made Cloudflare credential, made from the dashboard's
#                         "Create additional tokens" template (User > API Tokens > Edit, nothing
#                         else), kept in a 0600 file on the Mac. See ../../README.md.
provider "cloudflare" {}

# No settings: the local provider writes the token file, the time provider keeps the rotation clock.
provider "local" {}
provider "time" {}
