# ──────────────────────────────────────────────────────────────────────────────
# IAM -- Per-Developer Service Accounts and Bindings
# One SA per developer — strict IAM isolation and separate audit trail.
# Each SA is bound to exactly one Cloud Run service and one GCS workspace bucket.
# ──────────────────────────────────────────────────────────────────────────────

resource "google_service_account" "hermes_agent" {
  for_each = var.developers

  account_id   = "hermes-agent-${each.key}"
  display_name = "Hermes Agent — ${each.key}"
  project      = var.project_id

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

# Vertex AI access for Hermes (Gemini models via ADC)
resource "google_project_iam_member" "hermes_vertex_ai_user" {
  for_each = var.developers
  project  = var.project_id
  role     = "roles/aiplatform.user"
  member   = google_service_account.hermes_agent[each.key].member
}

# Logging and monitoring
resource "google_project_iam_member" "hermes_logging_writer" {
  for_each = var.developers
  project  = var.project_id
  role     = "roles/logging.logWriter"
  member   = google_service_account.hermes_agent[each.key].member
}

# Cloud Monitoring — emit custom metrics
resource "google_project_iam_member" "hermes_monitoring_writer" {
  for_each = var.developers
  project  = var.project_id
  role     = "roles/monitoring.metricWriter"
  member   = google_service_account.hermes_agent[each.key].member
}

# Cloud Run invoker — allow services to call other internal Cloud Run services
resource "google_project_iam_member" "hermes_run_invoker" {
  for_each = var.developers
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = google_service_account.hermes_agent[each.key].member
}

# GCS workspace: each SA accesses only its own developer's bucket
resource "google_storage_bucket_iam_member" "hermes_workspace_access" {
  for_each = var.developers

  bucket = google_storage_bucket.hermes_workspace[each.key].name
  role   = "roles/storage.objectUser"
  member = google_service_account.hermes_agent[each.key].member
}

# Per-secret IAM: Hermes SA can access only specific secrets
resource "google_secret_manager_secret_iam_member" "hermes_gateway_token_accessor" {
  for_each = var.developers

  secret_id = google_secret_manager_secret.gateway_token.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.hermes_agent[each.key].member
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Build Service Account
# ──────────────────────────────────────────────────────────────────────────────

resource "google_service_account" "cloudbuild" {
  account_id   = "hermes-cloudbuild"
  display_name = "Hermes Cloud Build Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = google_service_account.cloudbuild.member
}

resource "google_project_iam_member" "cloudbuild_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = google_service_account.cloudbuild.member
}

resource "google_project_iam_member" "cloudbuild_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = google_service_account.cloudbuild.member
}

resource "google_project_iam_member" "cloudbuild_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.cloudbuild.member
}

# IAP Access for deployer (if provided) (optional — for SSH tunnels via IAP)
resource "google_project_iam_member" "iap_access" {
  count   = var.deployer_service_account != "" ? 1 : 0
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${var.deployer_service_account}"
}
