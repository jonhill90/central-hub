# Adopts the signer's role assignment, which existed before this folder managed it (it was made
# by hand on 2026-11-09, and the first apply of azurerm_role_assignment.sas_signer stopped with
# RoleAssignmentExists). STD-0004 rule 1: this file stays only while the folder adopts objects;
# remove it once the import is applied. The ID holds no subscription ID: it is built from the
# storage account's own ID at plan time.
import {
  to = azurerm_role_assignment.sas_signer
  id = "${azurerm_storage_account.backup.id}/providers/Microsoft.Authorization/roleAssignments/6b131d9d-53a9-47a0-9254-613206b52df0"
}
