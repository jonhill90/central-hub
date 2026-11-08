terraform {
  required_version = ">= 1.10.0"

  required_providers {
    # 0.29.2 (2026-05-26) is the newest release at least two weeks old on 2026-11-08 (STD-0003
    # rule 1); 0.29.3 came out on 2026-10-28.
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}
