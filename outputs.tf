output "handoff" {
  description = "Values to send to Faber once the apply finishes. None of them are secret."
  value = {
    bucket_name           = google_storage_bucket.this.name
    project_id            = var.project_id
    kms_key_name          = google_kms_crypto_key.this.id
    location              = local.location
    vertex_ai_enabled     = var.enable_vertex_ai
    faber_service_account = var.faber_service_account
    module_version        = local.module_version
  }
}

output "bucket_name" {
  description = "Name of the bucket that holds your Faber content."
  value       = google_storage_bucket.this.name
}

output "kms_key_name" {
  description = "Full resource name of the Cloud KMS key that encrypts the bucket."
  value       = google_kms_crypto_key.this.id
}
