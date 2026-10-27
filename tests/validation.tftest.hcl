mock_provider "google" {}

variables {
  project_id            = "acme-faber"
  bucket_name           = "acme-faber-content"
  faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
}

run "rejects_non_faber_service_account" {
  command = plan

  variables {
    faber_service_account = "someone@evil-project.iam.gserviceaccount.com"
  }

  expect_failures = [var.faber_service_account]
}

run "rejects_faber_lookalike_project" {
  command = plan

  variables {
    faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-918.iam.gserviceaccount.com"
  }

  expect_failures = [var.faber_service_account]
}

run "rejects_user_account" {
  command = plan

  variables {
    faber_service_account = "user:alice@example.com"
  }

  expect_failures = [var.faber_service_account]
}

run "rejects_bad_bucket_name" {
  command = plan

  variables {
    bucket_name = "Acme_Faber"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_google_in_bucket_name" {
  command = plan

  variables {
    bucket_name = "acme-google-faber"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_bad_project_id" {
  command = plan

  variables {
    project_id = "1-bad"
  }

  expect_failures = [var.project_id]
}

run "rejects_short_rotation" {
  command = plan

  variables {
    key_rotation_period = "3600s"
  }

  expect_failures = [var.key_rotation_period]
}

run "rejects_unknown_protection_level" {
  command = plan

  variables {
    key_protection_level = "EXTERNAL"
  }

  expect_failures = [var.key_protection_level]
}

run "rejects_zero_retention" {
  command = plan

  variables {
    noncurrent_version_retention_days = 0
  }

  expect_failures = [var.noncurrent_version_retention_days]
}
