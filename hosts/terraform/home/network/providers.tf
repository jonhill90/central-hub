# The endpoint and the API token are read from the environment at apply time, filled from the
# secret store, so neither appears in this repository:
#   PROXMOX_VE_ENDPOINT   the host's API URL
#   PROXMOX_VE_API_TOKEN  "<user>@<realm>!<token-id>=<secret>"
#   PROXMOX_VE_INSECURE   "true" only while the host still uses its self-signed certificate
provider "proxmox" {}
