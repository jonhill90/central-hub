# Offline tests for home/tailnet: a plan against a mocked provider, so no tailnet or OAuth client
# is needed. Run from this folder: tofu init -backend=false && tofu test (STD-0005).

mock_provider "tailscale" {
  mock_data "tailscale_device" {
    defaults = {
      node_id = "nexample"
    }
  }
}

variables {
  vlans_file             = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  zone                   = "example.com" # made up, as in home.tfvars.example
  connector_hostname     = "examplenw01"
  connector_extra_routes = ["192.0.2.10/32"]
}

run "routes_cover_every_lab_vlan" {
  command = plan

  assert {
    condition     = alltrue([for v in yamldecode(file(var.vlans_file)).lab_vlans : contains(tailscale_device_subnet_routes.connector.routes, v.cidr)])
    error_message = "Every VLAN in the shared VLAN file must be a turned-on route of the connector."
  }

  assert {
    condition     = contains(tailscale_device_subnet_routes.connector.routes, "192.0.2.10/32")
    error_message = "The route the connector already advertises must stay turned on."
  }

  assert {
    condition     = tailscale_device_subnet_routes.connector.device_id == "nexample"
    error_message = "The routes must be set on the connector found by hostname."
  }
}

run "split_dns_goes_to_the_mgmt_gateway" {
  command = plan

  assert {
    condition     = toset(keys(tailscale_dns_split_nameservers.lab)) == toset(["c1.prod", "opnsense", "pve"])
    error_message = "One split DNS entry per name in split_dns_names."
  }

  assert {
    condition     = tailscale_dns_split_nameservers.lab["c1.prod"].domain == "c1.prod.example.com"
    error_message = "Each split DNS domain is the name under the zone."
  }

  assert {
    condition     = alltrue([for d in tailscale_dns_split_nameservers.lab : d.nameservers == toset(["10.1.50.1"])])
    error_message = "Every split DNS name must go to the mgmt VLAN's .1 address, OPNsense Unbound (STD-0002)."
  }
}

run "rejects_a_name_with_a_trailing_dot" {
  command = plan

  variables {
    split_dns_names = ["c1.prod."]
  }

  expect_failures = [var.split_dns_names]
}
