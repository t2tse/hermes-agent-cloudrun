locals {
  gateway_auth_token = var.gateway_auth_token != "" ? var.gateway_auth_token : random_id.gateway_token.hex
  hermes_image       = var.hermes_image != "" ? var.hermes_image : "${var.region}-docker.pkg.dev/${var.project_id}/hermes-agent/hermes:latest"
}

resource "random_id" "gateway_token" {
  byte_length = 24
}

# Artifact Registry for Hermes container images
resource "google_artifact_registry_repository" "hermes" {
  location      = var.region
  repository_id = "hermes-agent"
  description   = "Docker images for Hermes Agent"
  format        = "DOCKER"
  project       = var.project_id

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = 5
    }
  }

  labels = var.labels

  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
}

# Wait for Cloud Build IAM grants to propagate before building
resource "time_sleep" "wait_for_cloudbuild_iam" {
  create_duration = "30s"

  depends_on = [
    google_project_iam_member.cloudbuild_builder,
    google_project_iam_member.cloudbuild_ar_writer,
    google_project_iam_member.cloudbuild_storage,
    google_project_iam_member.cloudbuild_logging,
  ]
}

# Build and push Hermes container image via Cloud Build
resource "null_resource" "build_hermes_image" {
  triggers = {
    dockerfile_hash = filesha256("${path.module}/Dockerfile")
    entrypoint_hash = filesha256("${path.module}/scripts/entrypoint.sh")
    proxy_hash      = filesha256("${path.module}/scripts/vertex_ai_proxy.py")
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/scripts/build_and_push.sh"
    working_dir = path.module
    environment = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
  }

  depends_on = [
    google_artifact_registry_repository.hermes,
    time_sleep.wait_for_cloudbuild_iam,
  ]
}

# Secret Manager Secrets

resource "google_secret_manager_secret" "gateway_token" {
  secret_id = "hermes-gateway-token"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_version" "gateway_token" {
  secret      = google_secret_manager_secret.gateway_token.id
  secret_data = local.gateway_auth_token
}
