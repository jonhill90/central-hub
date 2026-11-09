# The provider logs in with the bootstrap token (Account API Tokens Write on the account, plus
# Zone Read on the one zone; see ../../README.md, "The bootstrap token"). It is read from its 0600
# file at plan time, so no environment variable or shell substitution is needed, and the value
# never appears in this repository or in a tfvars file.
provider "cloudflare" {
  api_token = trimspace(file(pathexpand(var.bootstrap_token_file)))
}

# No settings: the local provider writes the token file, the time provider keeps the rotation clock.
provider "local" {}
provider "time" {}
