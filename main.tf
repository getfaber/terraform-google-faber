resource "google_project_service" "this" {
  for_each = toset(local.services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Encryption key. Cloud KMS key rings and keys can't be deleted, only disabled, so
# prevent_destroy stops a stray `terraform destroy` from scheduling the key for
# destruction, which would make every object in the bucket unreadable.
resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = var.key_ring_name
  location = local.location

  depends_on = [google_project_service.this]
}

resource "google_kms_crypto_key" "this" {
  name            = var.key_name
  key_ring        = google_kms_key_ring.this.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = var.key_rotation_period
  labels          = local.labels

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = var.key_protection_level
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Cloud Storage encrypts objects with the key on Faber's behalf through the
# project's Cloud Storage service agent, so Faber itself never needs key access.
data "google_storage_project_service_account" "gcs" {
  project = var.project_id

  depends_on = [google_project_service.this]
}

resource "google_kms_crypto_key_iam_member" "gcs_encrypter" {
  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

# Access is recorded with Cloud Audit Logs (see iam.tf) rather than legacy
# usage-log buckets.
#trivy:ignore:GCP-0077
resource "google_storage_bucket" "this" {
  project  = var.project_id
  name     = var.bucket_name
  location = local.location
  labels   = local.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.this.id
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = var.noncurrent_version_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_encrypter]
}
