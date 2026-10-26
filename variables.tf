variable "project_id" {
  description = "ID of the Google Cloud project that will hold the bucket and key. A project dedicated to Faber is recommended, because access logging and the Vertex AI grant apply to the whole project."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9.-]+:)?[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID, such as \"acme-faber\"."
  }
}

variable "bucket_name" {
  description = "Name of the Cloud Storage bucket to create, for example \"acme-faber-content\". Bucket names are global and can't be changed later."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9_-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !startswith(var.bucket_name, "goog") &&
      !strcontains(var.bucket_name, "google")
    )
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dashes or underscores, start and end with a letter or digit, and not start with \"goog\" or contain \"google\"."
  }
}

variable "location" {
  description = "Location for both the bucket and the key ring. They must match for customer-managed encryption. Faber runs in us-central1."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.location))
    error_message = "location must be a Cloud Storage location such as \"us-central1\" or \"us\"."
  }
}

variable "faber_service_account" {
  description = "The Faber service account for your workspace. Faber sends you this value; it always looks like faber-ws-YOUR-COMPANY@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com."
  type        = string

  validation {
    condition     = can(regex("^faber-ws-[a-z0-9-]*[a-z0-9]@project-54fc229c-12bb-4421-919\\.iam\\.gserviceaccount\\.com$", var.faber_service_account))
    error_message = "faber_service_account must be the Faber workspace service account Faber sent you: faber-ws-<your-company>@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com."
  }
}

variable "enable_vertex_ai" {
  description = "Turn on Vertex AI in the project and let the Faber service account use it. Leave false to skip AI features."
  type        = bool
  default     = false
}

variable "enable_access_logging" {
  description = "Turn on Data Access audit logs (ADMIN_READ, DATA_READ and DATA_WRITE) for Cloud Storage and Cloud KMS. These settings apply to the whole project and replace any existing Data Access audit config for those two services."
  type        = bool
  default     = true
}

variable "key_ring_name" {
  description = "Name of the Cloud KMS key ring. Key rings can never be deleted, so pick this once."
  type        = string
  default     = "faber"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,63}$", var.key_ring_name))
    error_message = "key_ring_name must be 1-63 letters, digits, underscores or dashes."
  }
}

variable "key_name" {
  description = "Name of the Cloud KMS key that encrypts the bucket."
  type        = string
  default     = "faber-content"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,63}$", var.key_name))
    error_message = "key_name must be 1-63 letters, digits, underscores or dashes."
  }
}

variable "key_rotation_period" {
  description = "How often Cloud KMS creates a new key version, in seconds with an \"s\" suffix. Defaults to 90 days."
  type        = string
  default     = "7776000s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.key_rotation_period)) && try(tonumber(trimsuffix(var.key_rotation_period, "s")) >= 86400, false)
    error_message = "key_rotation_period must be a number of seconds ending in \"s\", at least 86400s (1 day)."
  }
}

variable "key_protection_level" {
  description = "Protection level for new key versions: SOFTWARE or HSM. HSM costs more and isn't available in every location."
  type        = string
  default     = "SOFTWARE"

  validation {
    condition     = contains(["SOFTWARE", "HSM"], var.key_protection_level)
    error_message = "key_protection_level must be SOFTWARE or HSM."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep an object's previous versions after it's overwritten or deleted. Older versions are also removed once 5 newer versions exist."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a whole number of at least 1."
  }
}

variable "labels" {
  description = "Extra labels for the bucket and key. A managed-by = \"faber-terraform\" label is always added."
  type        = map(string)
  default     = {}
}
