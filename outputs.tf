###############################################################################
# Hermes Agent on GCP -- Outputs
###############################################################################

output "gke_cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "Endpoint for GKE Autopilot cluster."
  value       = google_container_cluster.primary.endpoint
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for Hermes images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.hermes.repository_id}"
}

output "gateway_token_secret" {
  description = "Secret Manager resource name for the gateway token."
  value       = google_secret_manager_secret.gateway_token.name
}

output "cloudbuild_service_account" {
  description = "Cloud Build service account email."
  value       = google_service_account.cloudbuild.email
}

output "hermes_agent_service_account" {
  description = "Hermes Agent GCP service account email."
  value       = google_service_account.hermes_agent.email
}

output "developer_pods" {
  description = "Map of developer names to their Hermes pod deployment names."
  value = {
    for name, _ in var.developers : name => "hermes-agent-${name}"
  }
}
