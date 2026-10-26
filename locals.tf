locals {
  module_version = "1.0.0" # x-release-please-version

  location = lower(var.location)

  labels = merge(var.labels, {
    managed-by = "faber-terraform"
  })

  base_services = ["storage.googleapis.com", "cloudkms.googleapis.com"]
  services      = var.enable_vertex_ai ? concat(local.base_services, ["aiplatform.googleapis.com"]) : local.base_services

  audited_services = var.enable_access_logging ? toset(local.base_services) : toset([])

  faber_member = "serviceAccount:${var.faber_service_account}"
}
