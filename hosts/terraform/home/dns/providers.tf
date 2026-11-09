# The provider logs in with the DNS token that ../dns-token makes (DNS Write and Zone Read on the
# one zone only), read from its 0600 file at plan time. No environment variable is needed.
provider "cloudflare" {
  api_token = trimspace(file(pathexpand(var.token_file)))
}
