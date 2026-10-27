locals {
  module_version = "1.0.0" # x-release-please-version

  location = lower(var.location)

  # Cloud KMS names the EU multi-region "europe". Every other Cloud Storage
  # location that supports a matching key ring uses the same name in both.
  kms_location = local.location == "eu" ? "europe" : local.location

  labels = merge(var.labels, {
    managed-by = "faber-terraform"
  })

  audited_services = var.enable_access_logging ? toset(["storage.googleapis.com", "cloudkms.googleapis.com"]) : toset([])

  faber_member = "serviceAccount:${var.faber_service_account}"
}
