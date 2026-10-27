#!/usr/bin/env bash
#
# Creates the same Google Cloud resources as the terraform-google-faber module,
# for teams that don't use Terraform. Safe to re-run: existing resources are
# reused and their settings brought in line.
#
# Needs: gcloud (signed in with rights to manage the project), jq, bash 3.2+.

set -euo pipefail

SCRIPT_VERSION="1.0.0" # x-release-please-version

FABER_SA_PATTERN='^faber-ws-[a-z0-9-]*[a-z0-9]@project-54fc229c-12bb-4421-919\.iam\.gserviceaccount\.com$'

project=""
bucket=""
service_account=""
location="us-central1"
key_ring="faber"
key="faber-content"
rotation_period="7776000s"
protection_level="SOFTWARE"
retention_days="30"
enable_vertex_ai="false"
enable_access_logging="true"
adopt_bucket="false"

usage() {
  cat <<'USAGE'
Usage: setup.sh --project PROJECT_ID --bucket BUCKET_NAME --service-account FABER_SA [options]

Required:
  --project ID               Google Cloud project for the bucket and key
  --bucket NAME              Bucket to create, e.g. <your-company>-faber-content
  --service-account EMAIL    The Faber service account Faber sent you

Options:
  --location LOCATION        Bucket and key ring location (default: us-central1)
  --enable-vertex-ai         Turn on Vertex AI and let Faber use it (default: off)
  --no-access-logging        Skip Data Access audit logs (default: on)
  --key-ring NAME            Key ring name (default: faber)
  --key NAME                 Key name (default: faber-content)
  --rotation-period SECONDS  Key rotation, e.g. 7776000s (default: 90 days)
  --protection-level LEVEL   SOFTWARE or HSM (default: SOFTWARE)
  --retention-days N         Days to keep previous object versions (default: 30)
  --adopt                    Apply Faber's settings to an existing bucket in this project
                             that wasn't created by this script or the Faber module
  -h, --help                 Show this help
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*" >&2
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# An RFC 3339 UTC timestamp the given number of seconds from now. Works with
# both GNU date (Linux) and BSD date (macOS).
utc_in_seconds() {
  local when=$(($(date +%s) + $1))
  date -u -d "@${when}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "${when}" +%Y-%m-%dT%H:%M:%SZ
}

# Retries a command a few times. A newly created service agent or IAM grant can
# take a little while to be visible everywhere in Google Cloud.
retry() {
  local attempt=1
  until "$@"; do
    if ((attempt >= 5)); then
      return 1
    fi
    log "Retrying in $((attempt * 10))s while Google Cloud catches up"
    sleep $((attempt * 10))
    attempt=$((attempt + 1))
  done
}

need_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) need_value "$@"; project="$2"; shift 2 ;;
    --bucket) need_value "$@"; bucket="$2"; shift 2 ;;
    --service-account) need_value "$@"; service_account="$2"; shift 2 ;;
    --location) need_value "$@"; location="$2"; shift 2 ;;
    --key-ring) need_value "$@"; key_ring="$2"; shift 2 ;;
    --key) need_value "$@"; key="$2"; shift 2 ;;
    --rotation-period) need_value "$@"; rotation_period="$2"; shift 2 ;;
    --protection-level) need_value "$@"; protection_level="$2"; shift 2 ;;
    --retention-days) need_value "$@"; retention_days="$2"; shift 2 ;;
    --enable-vertex-ai) enable_vertex_ai="true"; shift ;;
    --no-access-logging) enable_access_logging="false"; shift ;;
    --adopt) adopt_bucket="true"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

# Same checks as the Terraform module's variable validations.
[[ -n "$project" && -n "$bucket" && -n "$service_account" ]] || { usage >&2; die "--project, --bucket and --service-account are required"; }
[[ "$project" =~ ^([a-z0-9.-]+:)?[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "--project must be a valid Google Cloud project ID"
[[ "$bucket" =~ ^[a-z0-9][a-z0-9_-]{1,61}[a-z0-9]$ && "$bucket" != goog* && "$bucket" != *google* ]] ||
  die "--bucket must be 3-63 lowercase letters, digits, dashes or underscores, not starting with \"goog\" or containing \"google\""
[[ "$service_account" =~ $FABER_SA_PATTERN ]] ||
  die "--service-account must be the Faber workspace service account: faber-ws-<your-company>@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
[[ "$location" =~ ^[A-Za-z0-9-]+$ ]] || die "--location must be a Cloud Storage location such as us-central1"
[[ "$key_ring" =~ ^[A-Za-z0-9_-]{1,63}$ ]] || die "--key-ring must be 1-63 letters, digits, underscores or dashes"
[[ "$key" =~ ^[A-Za-z0-9_-]{1,63}$ ]] || die "--key must be 1-63 letters, digits, underscores or dashes"
if ! [[ "$rotation_period" =~ ^[0-9]+s$ ]] || ((10#${rotation_period%s} < 86400)); then
  die "--rotation-period must be seconds ending in \"s\", at least 86400s"
fi
[[ "$protection_level" == "SOFTWARE" || "$protection_level" == "HSM" ]] || die "--protection-level must be SOFTWARE or HSM"
if ! [[ "$retention_days" =~ ^[0-9]+$ ]] || ((10#$retention_days < 1)); then
  die "--retention-days must be a whole number of at least 1"
fi

# Drop leading zeros so the numbers aren't read as octal or written as invalid JSON.
rotation_period="$((10#${rotation_period%s}))s"
retention_days="$((10#$retention_days))"

command -v gcloud >/dev/null || die "gcloud is not installed"
command -v jq >/dev/null || die "jq is not installed"

location="$(lower "$location")"
# Cloud KMS names the EU multi-region "europe"; other locations match.
kms_location="$location"
if [[ "$location" == "eu" ]]; then
  kms_location="europe"
fi
key_id="projects/${project}/locations/${kms_location}/keyRings/${key_ring}/cryptoKeys/${key}"
faber_member="serviceAccount:${service_account}"
labels="managed-by=faber-setup-script"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# 1. APIs
if [[ "$enable_vertex_ai" == "true" ]]; then
  log "Enabling Cloud Storage, Cloud KMS and Vertex AI APIs"
  gcloud services enable storage.googleapis.com cloudkms.googleapis.com aiplatform.googleapis.com --project "$project"
else
  log "Enabling Cloud Storage and Cloud KMS APIs"
  gcloud services enable storage.googleapis.com cloudkms.googleapis.com --project "$project"
fi

# 2. Key ring and key
if gcloud kms keyrings describe "$key_ring" --location "$kms_location" --project "$project" >/dev/null 2>&1; then
  log "Key ring ${key_ring} already exists"
else
  log "Creating key ring ${key_ring} in ${kms_location}"
  gcloud kms keyrings create "$key_ring" --location "$kms_location" --project "$project"
fi

if key_json="$(gcloud kms keys describe "$key" --keyring "$key_ring" --location "$kms_location" --project "$project" --format=json 2>/dev/null)"; then
  current_rotation="$(jq -r '.rotationPeriod // ""' <<<"$key_json")"
  current_level="$(jq -r '.versionTemplate.protectionLevel // "SOFTWARE"' <<<"$key_json")"
  if [[ "$current_level" != "$protection_level" ]]; then
    log "Warning: key ${key} already exists with protection level ${current_level}, not ${protection_level}. Protection level can't be changed; keeping ${current_level}."
  fi
  if [[ "$current_rotation" == "$rotation_period" ]]; then
    log "Key ${key} already exists"
  else
    log "Key ${key} already exists; setting rotation to every ${rotation_period}"
    gcloud kms keys update "$key" --keyring "$key_ring" --location "$kms_location" --project "$project" \
      --rotation-period "$rotation_period" --next-rotation-time "$(utc_in_seconds "${rotation_period%s}")" >/dev/null
  fi
else
  log "Creating key ${key} (${protection_level}, rotates every ${rotation_period})"
  gcloud kms keys create "$key" --keyring "$key_ring" --location "$kms_location" --project "$project" \
    --purpose encryption \
    --protection-level "$(lower "$protection_level")" \
    --rotation-period "$rotation_period" \
    --next-rotation-time "$(utc_in_seconds "${rotation_period%s}")" \
    --labels "$labels"
fi

# 3. Let Cloud Storage encrypt with the key. Faber itself gets no key access.
gcs_agent="$(gcloud storage service-agent --project "$project")"
log "Granting the Cloud Storage service agent use of the key"
retry gcloud kms keys add-iam-policy-binding "$key" --keyring "$key_ring" --location "$kms_location" --project "$project" \
  --member "serviceAccount:${gcs_agent}" --role roles/cloudkms.cryptoKeyEncrypterDecrypter >/dev/null

# 4. Bucket
if bucket_json="$(gcloud storage buckets describe "gs://${bucket}" --raw --format=json 2>/dev/null)"; then
  # Never touch a bucket in another project, or one this script didn't create
  # unless asked to: the settings below replace its lifecycle rules and key.
  project_number="$(gcloud projects describe "$project" --format='value(projectNumber)')"
  bucket_project="$(jq -r '.projectNumber // ""' <<<"$bucket_json")"
  [[ "$bucket_project" == "$project_number" ]] ||
    die "gs://${bucket} already exists in another project (number ${bucket_project}). Choose a different --bucket."
  managed_by="$(jq -r '.labels["managed-by"] // ""' <<<"$bucket_json")"
  if [[ "$managed_by" != faber-* && "$adopt_bucket" != "true" ]]; then
    die "gs://${bucket} already exists and wasn't set up for Faber. Re-run with --adopt to apply Faber's settings to it; this replaces its lifecycle rules and default encryption key."
  fi
  log "Bucket gs://${bucket} already exists"
else
  log "Creating bucket gs://${bucket} in ${location}"
  retry gcloud storage buckets create "gs://${bucket}" --project "$project" --location "$location" \
    --uniform-bucket-level-access --public-access-prevention --default-encryption-key "$key_id"
fi

cat >"${workdir}/lifecycle.json" <<JSON
{
  "rule": [
    { "action": { "type": "Delete" }, "condition": { "daysSinceNoncurrentTime": ${retention_days} } },
    { "action": { "type": "Delete" }, "condition": { "numNewerVersions": 5, "isLive": false } }
  ]
}
JSON

log "Applying bucket settings: versioning, encryption, privacy, version pruning"
retry gcloud storage buckets update "gs://${bucket}" \
  --versioning \
  --uniform-bucket-level-access \
  --public-access-prevention \
  --default-encryption-key "$key_id" \
  --lifecycle-file "${workdir}/lifecycle.json" \
  --update-labels "$labels" >/dev/null

# 5. Faber's access: read, write and delete objects in this bucket only.
log "Granting ${service_account} object access on gs://${bucket}"
gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
  --member "$faber_member" --role roles/storage.objectUser >/dev/null

# 6. Vertex AI (optional)
if [[ "$enable_vertex_ai" == "true" ]]; then
  log "Letting ${service_account} use Vertex AI in ${project}"
  gcloud projects add-iam-policy-binding "$project" \
    --member "$faber_member" --role roles/aiplatform.user --condition=None >/dev/null
fi

# 7. Data Access audit logs (optional). Unlike the Terraform module, this merges
# into the project's existing audit config rather than replacing it.
if [[ "$enable_access_logging" == "true" ]]; then
  gcloud projects get-iam-policy "$project" --format=json >"${workdir}/policy.json"
  jq '
    .auditConfigs = (
      reduce ("storage.googleapis.com", "cloudkms.googleapis.com") as $svc ((.auditConfigs // []);
        if any(.[]; .service == $svc) then
          map(if .service == $svc then
                .auditLogConfigs = (
                  reduce ("ADMIN_READ", "DATA_READ", "DATA_WRITE") as $t ((.auditLogConfigs // []);
                    if any(.[]; .logType == $t) then . else . + [{ logType: $t }] end))
              else . end)
        else
          . + [{ service: $svc, auditLogConfigs: [{ logType: "ADMIN_READ" }, { logType: "DATA_READ" }, { logType: "DATA_WRITE" }] }]
        end))
  ' "${workdir}/policy.json" >"${workdir}/policy.new.json"

  if [[ "$(jq -S .auditConfigs "${workdir}/policy.json")" == "$(jq -S .auditConfigs "${workdir}/policy.new.json")" ]]; then
    log "Data Access audit logs already on for Cloud Storage and Cloud KMS"
  else
    log "Turning on Data Access audit logs for Cloud Storage and Cloud KMS"
    gcloud projects set-iam-policy "$project" "${workdir}/policy.new.json" >/dev/null
  fi
fi

log "Done. Send this to Faber (none of it is secret):"
jq -n \
  --arg bucket_name "$bucket" \
  --arg project_id "$project" \
  --arg kms_key_name "$key_id" \
  --arg location "$location" \
  --argjson vertex_ai_enabled "$enable_vertex_ai" \
  --arg faber_service_account "$service_account" \
  --arg module_version "$SCRIPT_VERSION" \
  '{bucket_name: $bucket_name, project_id: $project_id, kms_key_name: $kms_key_name, location: $location,
    vertex_ai_enabled: $vertex_ai_enabled, faber_access_enabled: true, faber_service_account: $faber_service_account,
    module_version: $module_version}'
