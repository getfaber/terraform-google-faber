# Cloud Storage has its own resource so the service-agent lookup below depends
# on it alone. If it depended on every service, turning Vertex AI on later would
# defer that lookup to apply time and make Terraform recreate the key grant,
# briefly cutting off access to the encrypted bucket.
resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "kms" {
  project            = var.project_id
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vertex_ai" {
  count = var.enable_vertex_ai ? 1 : 0

  project            = var.project_id
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = var.key_ring_name
  location = local.kms_location

  depends_on = [google_project_service.kms]
}

# Cloud KMS keys can't be deleted, only scheduled for destruction, and destroying
# this one would make every object in the bucket unreadable. prevent_destroy
# stops a stray `terraform destroy` from doing that.

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

  depends_on = [google_project_service.storage]
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

  depends_on = [google_project_service.storage, google_kms_crypto_key_iam_member.gcs_encrypter]
}
