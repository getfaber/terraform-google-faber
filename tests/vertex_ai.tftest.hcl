mock_provider "google" {}

variables {
  project_id            = "acme-faber"
  bucket_name           = "acme-faber-content"
  faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  enable_vertex_ai      = true
}

run "vertex_ai_on" {
  command = plan

  assert {
    condition     = length(google_project_service.vertex_ai) == 1 && google_project_service.vertex_ai[0].service == "aiplatform.googleapis.com"
    error_message = "Vertex AI API must be enabled when AI is on."
  }

  assert {
    condition     = length(google_project_iam_member.faber_vertex_ai) == 1
    error_message = "Faber must get one Vertex AI grant when AI is on."
  }

  assert {
    condition     = google_project_iam_member.faber_vertex_ai[0].role == "roles/aiplatform.user"
    error_message = "Vertex AI grant must be roles/aiplatform.user."
  }

  assert {
    condition     = google_project_iam_member.faber_vertex_ai[0].member == "serviceAccount:faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
    error_message = "Vertex AI grant must go to the Faber workspace service account."
  }

  assert {
    condition     = output.handoff.vertex_ai_enabled == true
    error_message = "Handoff must report Vertex AI as enabled."
  }
}

run "access_off_removes_both_grants" {
  command = plan

  variables {
    enable_vertex_ai     = true
    faber_access_enabled = false
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.faber) == 0 && length(google_project_iam_member.faber_vertex_ai) == 0
    error_message = "With access off, Faber must have no bucket or Vertex AI grant."
  }

  assert {
    condition     = google_storage_bucket.this.name == "acme-faber-content" && google_kms_crypto_key.this.name == "faber-content"
    error_message = "Turning access off must keep the bucket and key."
  }

  assert {
    condition     = output.handoff.faber_access_enabled == false
    error_message = "Handoff must show that access is off."
  }
}
