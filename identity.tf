# ---------------------------------------------------------------------------
# Microsoft Entra ID application + service principal
# The app registration is the global definition of the application.
# The service principal is its identity inside this tenant; role assignments
# point at the service principal's object ID.
# ---------------------------------------------------------------------------
data "azuread_client_config" "current" {}

resource "azuread_application" "deployer" {
  display_name     = local.sp_name
  description      = "IT 3200 M9 lab: deploys workloads into one AKS namespace."
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "deployer" {
  client_id = azuread_application.deployer.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Short-lived client secret. Terraform recreates it when the rotation period passes.
# NOTE: the secret value is stored in terraform.tfstate. State is gitignored and
# must never be committed. A production setup would use workload identity
# federation (OIDC) or a certificate instead of a secret.
resource "time_rotating" "sp_secret" {
  rotation_days = var.sp_secret_lifetime_days
}

resource "azuread_application_password" "deployer" {
  application_id = azuread_application.deployer.id
  display_name   = "m9-lab-secret"
  end_date       = time_rotating.sp_secret.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.sp_secret.id
  }
}
