###############################################################################
# Hermes Agent on GCP -- Outputs
###############################################################################

output "cloudrun_subnet" {
  description = "Name of the Cloud Run Direct VPC Egress subnet (use in --subnet flag of gcloud run deploy or gcloud beta run instances create)."
  value       = google_compute_subnetwork.cloudrun_subnet.name
}

output "workspace_bucket_names" {
  description = "Map of developer name to their GCS workspace bucket name (used in --add-volume flag of gcloud run deploy or gcloud beta run instances create)."
  value = {
    for dev, _ in var.developers :
    dev => google_storage_bucket.hermes_workspace[dev].name
  }
}

output "brain_service_accounts" {
  description = "Map of developer name to their Cloud Run service account email (use in --service-account flag of gcloud run deploy or gcloud beta run instances create)."
  value = {
    for dev, _ in var.developers :
    dev => google_service_account.hermes_agent[dev].email
  }
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
