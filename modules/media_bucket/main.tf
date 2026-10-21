# main.tf — private GCS bucket for EcoFolk's user media, photos and audio (ecofolk-infra#21, BUILD_PLAN
# §11.5's storage half). Architect re-spec 2026-10-09: Google Cloud Storage in Montréal, not Cloudflare R2.
#
# Private: media is never served from the bucket. The API proxies it (`GET /media`, access-checked, served
# `private, max-age=300`, ecofolk#377), so uniform bucket-level access only, public access prevention
# enforced, and no CORS (the browser never talks to the bucket).
#
# Storage NEVER deletes by age. The app owns retention: ecofolk#310's sweep deletes unpublished media on
# publish and on a 30-day TTL. A storage-side age rule would delete published media the app still serves.
# The only lifecycle rule aborts incomplete multipart uploads after 1 day.
#
# Soft delete is declared explicitly (7 days) as a cheap safety net against a bad sweep.
#
# Location is upper(var.region): GCS reports bucket locations upper-case, and var.region is validated to
# northamerica-northeast1 (ef#391). It is never hardcoded here.
#
# Needs storage.googleapis.com (modules/project); callers order it with `depends_on`.
#
# LOCAL FOLLOW-UP (L-RUN, ecofolk#890): roles/storage.objectAdmin for the Cloud Run API's runtime service
# account, on this bucket only. IAM is never written in this repo by a cloud session. No HMAC key is ever
# created: the app reaches the bucket through ADC (ecofolk#926).
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  abort_multipart_after_days = 1
  soft_delete_seconds        = 7 * 24 * 60 * 60
}

resource "google_storage_bucket" "media" {
  project       = var.project_id
  name          = "${var.project_id}-media${local.env_suffix}"
  location      = upper(var.region)
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Never empty a bucket of user media on destroy.
  force_destroy = false

  versioning {
    enabled = false
  }

  soft_delete_policy {
    retention_duration_seconds = local.soft_delete_seconds
  }

  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = local.abort_multipart_after_days
    }
  }

  labels = {
    env       = var.env
    component = "media"
  }
}
