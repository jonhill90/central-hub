# The lab already exists (built by hand and by script). These blocks adopt the running objects
# into state on the first plan instead of creating new ones. Untested: run `tofu plan` first and
# read every proposed change before any apply.

import {
  to = proxmox_virtual_environment_container.ts_connector
  id = "${var.proxmox_node_name}/900"
}
