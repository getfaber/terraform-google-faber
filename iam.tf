# Faber can read, write and delete objects in the bucket, and nothing else: no
# bucket settings, no IAM changes, no access to other buckets.
resource "google_storage_bucket_iam_member" "faber" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectUser"
  member = local.faber_member
}

# Vertex AI permissions are project-wide, which is one reason to give Faber a
# dedicated project.
resource "google_project_iam_member" "faber_vertex_ai" {
  count = var.enable_vertex_ai ? 1 : 0

  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = local.faber_member

  depends_on = [google_project_service.this]
}

# Data Access audit logs (ADMIN_READ, DATA_READ, DATA_WRITE), so every read and
# write of the bucket and key shows up in Cloud Audit Logs.
# google_project_iam_audit_config is authoritative for each service: it replaces
# any existing Data Access config for Cloud Storage and Cloud KMS in this project.
resource "google_project_iam_audit_config" "access_logs" {
  for_each = local.audited_services

  project = var.project_id
  service = each.value

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
