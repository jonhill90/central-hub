terraform {
  required_version = ">= 1.10.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.27.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }
}
