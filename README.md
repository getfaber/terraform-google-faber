# terraform-google-faber

Terraform module that sets up a Google Cloud project to hold your [Faber](https://www.getfaber.app) content. Everything your team publishes in Faber is stored in a bucket you own, encrypted with a key you own. Faber's database keeps only account details such as names, emails and permissions.

The module creates:

- a private, versioned **Cloud Storage bucket** that's encrypted by default with your key
- a **Cloud KMS key** that rotates automatically
- **read, write and delete access** on that bucket for your Faber workspace's service account, and nothing else
- **Data Access audit logs** for Cloud Storage and Cloud KMS, so every access shows up in Cloud Audit Logs (optional, on by default)
- **Vertex AI** access for the same service account, so prompts stay in your project (optional, off by default)

Nothing runs in your project, and Faber holds no long-lived keys.

## Usage

```hcl
module "faber" {
  source  = "getfaber/faber/google"
  version = "~> 1.0"

  project_id            = "<your-gcp-project-id>"
  bucket_name           = "<your-company>-faber-content"
  location              = "us-central1"
  faber_service_account = "faber-ws-<your-company>@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"

  # enable_vertex_ai = true # optional: turn on AI features
}

output "faber_handoff" {
  value = module.faber.handoff
}
```

Faber sends you the exact `faber_service_account` value for your workspace. After `terraform apply`, run `terraform output faber_handoff` and send the result to Faber. None of it is secret.

See [`examples/`](https://github.com/getfaber/terraform-google-faber/tree/main/examples) for complete configurations.

### Without Terraform

[`scripts/setup.sh`](https://github.com/getfaber/terraform-google-faber/blob/main/scripts/setup.sh) creates the same resources with `gcloud` and `jq` (bash 3.2 or later, so it runs on macOS and Linux), and prints the same handoff as JSON. It's safe to re-run.

```sh
./scripts/setup.sh \
  --project <your-gcp-project-id> \
  --bucket <your-company>-faber-content \
  --service-account faber-ws-<your-company>@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com \
  --enable-vertex-ai
```

Run `./scripts/setup.sh --help` for every option. Differences from the Terraform module:

- It **merges** into the project's existing Data Access audit config instead of replacing it.
- It labels what it creates `managed-by=faber-setup-script`, and has no option for extra labels.
- It refuses to touch an existing bucket in another project, and only takes over an existing bucket in this project that it didn't create if you pass `--adopt`.
- It can't change the protection level of an existing key; it warns instead.

## Before you apply

- **Use a dedicated project if you can.** Two settings apply to the whole project, not just this bucket:
  - **Access logging.** `google_project_iam_audit_config` is authoritative per service. With `enable_access_logging = true` it **replaces** any existing Data Access audit config for Cloud Storage and Cloud KMS in the project, including exemptions, and it logs reads and writes of every bucket and key there. Turning it off again, or removing the module, **deletes** that config for both services. Data Access logs can add Cloud Logging cost for busy projects. If you already manage audit config elsewhere, set `enable_access_logging = false` and add the `ADMIN_READ`, `DATA_READ` and `DATA_WRITE` log types for both services yourself. (`setup.sh` merges into existing audit config instead of replacing it.)
  - **Vertex AI.** `roles/aiplatform.user` is granted at project level, so Faber's service account can use Vertex AI resources anywhere in the project.
- **Domain-restricted sharing.** If your organization enforces `iam.allowedPolicyMemberDomains` (on by default for organizations created since 2024), the IAM grants to Faber's service account fail until your admin allows it for this project. That constraint allows organizations rather than single accounts, so either add Faber's Google Workspace customer ID to the allowed values for this project (ask Faber for it), or, if you use the managed constraint `iam.managed.allowedPolicyMembers`, allow the Faber service account itself.
- **VPC Service Controls.** If the project is inside a perimeter, add an ingress rule that lets the Faber service account reach Cloud Storage, and Vertex AI if you turn it on.
- **Claude on Vertex AI.** Gemini works straight away. To use Claude, enable it in Vertex AI Model Garden first.
- **Names are permanent.** Bucket names are global and fixed. Cloud KMS key rings and keys can't be deleted, so pick `key_ring_name` and `key_name` once.

## Safety

- The bucket and key have `prevent_destroy`, and the bucket has `force_destroy = false`. `terraform destroy` stops with an error instead of removing them. To really remove them, take them out of state or delete the `lifecycle` blocks in your own copy.
- **Deleting or disabling the key makes the data unreadable, for you as well as for Faber.**
- To cut Faber off, remove its service account from the bucket or disable the key. Within a few minutes content, lists and search stop loading in Faber, though people can still sign in.
- Old object versions are kept for `noncurrent_version_retention_days` (30 by default). A version is also removed once 5 newer versions of the object exist, counting the live one, so a live object keeps at most 4 previous versions.
- Check with Faber before you change the bucket's permissions or lifecycle rules, move or rename it, or disable or delete the key.

## Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.5 |
| OpenTofu | >= 1.6 |
| `hashicorp/google` provider | >= 5.0, < 9.0 |

Whoever runs the module needs rights to enable services, manage Cloud KMS and Cloud Storage, and set project IAM, for example `roles/owner`, or `roles/serviceusage.serviceUsageAdmin` + `roles/cloudkms.admin` + `roles/storage.admin` + `roles/resourcemanager.projectIamAdmin`.

## Troubleshooting

- **"Service account … does not exist"** on the key or bucket grant, or **"permission denied" creating the bucket** on the first apply in a new project: Google Cloud is still creating the Cloud Storage service agent or propagating the grant. Wait a minute and run `terraform apply` again. (`setup.sh` retries these steps on its own.)
- **IAM grant to `faber-ws-…` fails with a policy or domain error**: see domain-restricted sharing above.
- **`Instance cannot be destroyed`**: that's `prevent_destroy` protecting the bucket and key. See Safety.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
|------|------|
| [google_kms_crypto_key.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key_iam_member.gcs_encrypter](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring) | resource |
| [google_project_iam_audit_config.access_logs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_project_iam_member.faber_vertex_ai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.kms](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.storage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_project_service.vertex_ai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_storage_bucket.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.faber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket_name | Name of the Cloud Storage bucket to create, for example "acme-faber-content". Bucket names are global and can't be changed later. | `string` | n/a | yes |
| enable_access_logging | Turn on Data Access audit logs (ADMIN_READ, DATA_READ and DATA_WRITE) for Cloud Storage and Cloud KMS. These settings apply to the whole project, replace any existing Data Access audit config for those two services, and are deleted again if you turn this off. | `bool` | `true` | no |
| enable_vertex_ai | Turn on Vertex AI in the project and let the Faber service account use it. Leave false to skip AI features. | `bool` | `false` | no |
| faber_service_account | The Faber service account for your workspace. Faber sends you this value; it looks like faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com. | `string` | n/a | yes |
| key_name | Name of the Cloud KMS key that encrypts the bucket. | `string` | `"faber-content"` | no |
| key_protection_level | Protection level for the key: SOFTWARE or HSM. HSM costs more and isn't available in every location. This can't be changed after the first apply. | `string` | `"SOFTWARE"` | no |
| key_ring_name | Name of the Cloud KMS key ring. Key rings can never be deleted, so pick this once. | `string` | `"faber"` | no |
| key_rotation_period | How often Cloud KMS creates a new key version, in seconds with an "s" suffix. Defaults to 90 days. | `string` | `"7776000s"` | no |
| labels | Extra labels for the bucket and key. A managed-by = "faber-terraform" label is always added. | `map(string)` | `{}` | no |
| location | Location for the bucket and the key ring, which must match for customer-managed encryption: a region such as "us-central1", a multi-region ("US", "EU", "ASIA"), or a predefined dual-region such as "NAM4". Faber runs in us-central1. | `string` | `"us-central1"` | no |
| noncurrent_version_retention_days | Days to keep an object's previous versions after it's overwritten or deleted. A previous version is also removed once 5 newer versions of the object exist, counting the live one. | `number` | `30` | no |
| project_id | ID of the Google Cloud project that will hold the bucket and key. A project dedicated to Faber is recommended, because access logging and the Vertex AI grant apply to the whole project. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Name of the bucket that holds your Faber content. |
| handoff | Values to send to Faber once the apply finishes. None of them are secret. |
| kms_key_name | Full resource name of the Cloud KMS key that encrypts the bucket. |
<!-- END_TF_DOCS -->

## Support

Questions, problems or ideas: please [open an issue](https://github.com/getfaber/terraform-google-faber/issues). For security reports, see [SECURITY.md](https://github.com/getfaber/terraform-google-faber/blob/main/SECURITY.md).

## License

[Apache 2.0](https://github.com/getfaber/terraform-google-faber/blob/main/LICENSE)
