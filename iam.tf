# ──────────────────────────────────────────────────────────────────────────────
# IAM -- Service Accounts and Bindings
# ──────────────────────────────────────────────────────────────────────────────

# Service Account for Hermes Agent pods (Workload Identity -> Vertex AI)
resource "google_service_account" "hermes_agent" {
  account_id   = "hermes-agent"
  display_name = "Hermes Agent Service Account"
  project      = var.project_id

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

# Vertex AI access for Hermes (Gemini models via ADC)
resource "google_project_iam_member" "hermes_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.hermes_agent.email}"
}

# Logging and monitoring
resource "google_project_iam_member" "hermes_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.hermes_agent.email}"
}

resource "google_project_iam_member" "hermes_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.hermes_agent.email}"
}

# Per-secret IAM: Hermes SA can access only specific secrets
resource "google_secret_manager_secret_iam_member" "hermes_gateway_token_accessor" {
  secret_id = google_secret_manager_secret.gateway_token.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.hermes_agent.email}"
}

# Workload Identity Binding
resource "google_service_account_iam_binding" "workload_identity_user" {
  service_account_id = google_service_account.hermes_agent.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${google_container_cluster.primary.workload_identity_config[0].workload_pool}[hermes/hermes-agent]"
  ]
}

# Service Account for Cloud Build
resource "google_service_account" "cloudbuild" {
  account_id   = "hermes-cloudbuild"
  display_name = "Hermes Cloud Build Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Autopilot default compute SA needs AR reader to pull images
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_iam_member" "autopilot_ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# IAP access for deployer (if provided)
resource "google_project_iam_member" "iap_access" {
  count   = var.deployer_service_account != "" ? 1 : 0
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${var.deployer_service_account}"
}
