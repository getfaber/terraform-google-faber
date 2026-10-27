# The setup from Faber's IT guide, with AI features off.

provider "google" {}

module "faber" {
  source = "../.."

  project_id            = "acme-faber"
  bucket_name           = "acme-faber-content"
  location              = "us-central1"
  faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
}

output "faber_handoff" {
  value = module.faber.handoff
}
