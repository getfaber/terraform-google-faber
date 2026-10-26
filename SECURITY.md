# Security

## Reporting a problem

Please report security problems with this module through GitHub:

- If **private vulnerability reporting** is available on this repository (Security tab → "Report a vulnerability"), use it, so the details stay private until a fix is out.
- Otherwise, [open an issue](https://github.com/getfaber/terraform-google-faber/issues/new/choose) that says you have a security report, **without the details**, and we'll arrange a private way to share them.

Please don't put credentials, project IDs or other details of your own environment in public issues.

## What this module grants

The Faber service account gets `roles/storage.objectUser` on the bucket this module creates, and `roles/aiplatform.user` on the project only if `enable_vertex_ai = true`. It gets no access to the Cloud KMS key, no IAM permissions and no service account keys. See the [README](README.md) for details.
