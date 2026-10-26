# Plan-only tests: prevent_destroy on the bucket and key would block the destroy
# step that `terraform test` runs after an apply.

mock_provider "google" {
  override_during = plan

  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-123456789012@gs-project-accounts.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_kms_key_ring" {
    defaults = {
      id = "projects/acme-faber/locations/us-central1/keyRings/faber"
    }
  }

  mock_resource "google_kms_crypto_key" {
    defaults = {
      id = "projects/acme-faber/locations/us-central1/keyRings/faber/cryptoKeys/faber-content"
    }
  }
}

variables {
  project_id            = "acme-faber"
  bucket_name           = "acme-faber-content"
  faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
}

run "bucket_is_private_versioned_and_encrypted" {
  command = plan

  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access == true
    error_message = "Bucket must use uniform bucket-level access."
  }

  assert {
    condition     = google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "Bucket must enforce public access prevention."
  }

  assert {
    condition     = google_storage_bucket.this.force_destroy == false
    error_message = "Bucket must not be force-destroyable."
  }

  assert {
    condition     = google_storage_bucket.this.versioning[0].enabled == true
    error_message = "Bucket versioning must be on."
  }

  assert {
    condition     = google_storage_bucket.this.encryption[0].default_kms_key_name == "projects/acme-faber/locations/us-central1/keyRings/faber/cryptoKeys/faber-content"
    error_message = "Bucket must default to the module's KMS key."
  }

  assert {
    condition     = google_storage_bucket.this.location == "us-central1" && google_kms_key_ring.this.location == "us-central1"
    error_message = "Bucket and key ring must share the default location."
  }

  assert {
    condition     = google_storage_bucket.this.labels["managed-by"] == "faber-terraform"
    error_message = "Bucket must carry the managed-by label."
  }
}

run "old_versions_are_pruned" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.this.lifecycle_rule) == 2
    error_message = "Expected two lifecycle rules."
  }

  assert {
    condition = anytrue([
      for rule in google_storage_bucket.this.lifecycle_rule :
      anytrue([for c in rule.condition : c.days_since_noncurrent_time == 30]) &&
      alltrue([for a in rule.action : a.type == "Delete"])
    ])
    error_message = "Noncurrent versions must be deleted after 30 days by default."
  }

  assert {
    condition = anytrue([
      for rule in google_storage_bucket.this.lifecycle_rule :
      anytrue([for c in rule.condition : c.num_newer_versions == 5 && c.with_state == "ARCHIVED"]) &&
      alltrue([for a in rule.action : a.type == "Delete"])
    ])
    error_message = "Noncurrent versions beyond 5 must be deleted."
  }
}

run "key_rotates_every_90_days_in_software" {
  command = plan

  assert {
    condition     = google_kms_crypto_key.this.rotation_period == "7776000s"
    error_message = "Key must rotate every 90 days by default."
  }

  assert {
    condition     = google_kms_crypto_key.this.version_template[0].protection_level == "SOFTWARE"
    error_message = "Key must default to SOFTWARE protection."
  }

  # The service agent's email is read at apply time (the data source waits for
  # the APIs), so only the role is checkable in a plan.
  assert {
    condition     = google_kms_crypto_key_iam_member.gcs_encrypter.role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    error_message = "The Cloud Storage service agent must get the encrypter/decrypter role."
  }
}

run "faber_gets_object_access_only" {
  command = plan

  assert {
    condition     = google_storage_bucket_iam_member.faber.role == "roles/storage.objectUser"
    error_message = "Faber must get roles/storage.objectUser on the bucket."
  }

  assert {
    condition     = google_storage_bucket_iam_member.faber.member == "serviceAccount:faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
    error_message = "The bucket grant must go to the Faber workspace service account."
  }

  assert {
    condition     = length(google_project_iam_member.faber_vertex_ai) == 0
    error_message = "No Vertex AI grant when AI is off."
  }

  assert {
    condition     = toset(keys(google_project_service.this)) == toset(["storage.googleapis.com", "cloudkms.googleapis.com"])
    error_message = "Only Cloud Storage and Cloud KMS should be enabled when AI is off."
  }
}

run "access_logging_on_by_default" {
  command = plan

  assert {
    condition     = toset(keys(google_project_iam_audit_config.access_logs)) == toset(["storage.googleapis.com", "cloudkms.googleapis.com"])
    error_message = "Data Access audit logs must cover Cloud Storage and Cloud KMS."
  }

  assert {
    condition = alltrue([
      for config in google_project_iam_audit_config.access_logs :
      toset([for c in config.audit_log_config : c.log_type]) == toset(["ADMIN_READ", "DATA_READ", "DATA_WRITE"])
    ])
    error_message = "Audit configs must log ADMIN_READ, DATA_READ and DATA_WRITE."
  }
}

run "access_logging_can_be_turned_off" {
  command = plan

  variables {
    enable_access_logging = false
  }

  assert {
    condition     = length(google_project_iam_audit_config.access_logs) == 0
    error_message = "No audit configs when access logging is off."
  }
}

run "handoff_output" {
  command = plan

  assert {
    condition = output.handoff == {
      bucket_name           = "acme-faber-content"
      project_id            = "acme-faber"
      kms_key_name          = "projects/acme-faber/locations/us-central1/keyRings/faber/cryptoKeys/faber-content"
      location              = "us-central1"
      vertex_ai_enabled     = false
      faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
      module_version        = "1.0.0"
    }
    error_message = "Handoff output doesn't match what Faber expects."
  }
}

run "location_is_normalised" {
  command = plan

  variables {
    location = "US"
  }

  assert {
    condition     = google_kms_key_ring.this.location == "us" && google_storage_bucket.this.location == "us"
    error_message = "Location must be lower-cased for both bucket and key ring."
  }
}
