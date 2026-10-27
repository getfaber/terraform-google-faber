# Faber can read, write and delete objects in the bucket, and nothing else: no
# bucket settings, no IAM changes, no access to other buckets.
# faber_access_enabled = false removes this and the Vertex AI grant, which is
# the customer's lasting off switch.
resource "google_storage_bucket_iam_member" "faber" {
  count = var.faber_access_enabled ? 1 : 0

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectUser"
  member = local.faber_member
}

# Vertex AI permissions are project-wide, which is one reason to give Faber a
# dedicated project.
resource "google_project_iam_member" "faber_vertex_ai" {
  count = var.enable_vertex_ai && var.faber_access_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = local.faber_member

  depends_on = [google_project_service.vertex_ai]
}

# 1.0.0 had a single bucket grant; keep it in place on upgrade.
moved {
  from = google_storage_bucket_iam_member.faber
  to   = google_storage_bucket_iam_member.faber[0]
}

# Data Access audit logs (ADMIN_READ, DATA_READ, DATA_WRITE), so every read and
# write of the bucket and key shows up in Cloud Audit Logs.
# google_project_iam_audit_config is authoritative for each service: it replaces
# any existing Data Access config for Cloud Storage and Cloud KMS in this project,
# and removing it (or turning access logging off) deletes that config entirely.
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
