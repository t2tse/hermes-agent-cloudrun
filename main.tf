###############################################################################
# Hermes Agent on GCP -- Main Infrastructure
# GKE Autopilot with gVisor sandboxing, Vertex AI via Workload Identity.
###############################################################################

terraform {
  required_version = ">= 1.5"

  # Configure your own GCS backend bucket:
  #   gsutil mb -p YOUR_PROJECT -l us-central1 gs://YOUR_PROJECT-tf-state
  #   gsutil versioning set on gs://YOUR_PROJECT-tf-state
  backend "gcs" {
    bucket = "YOUR_PROJECT_ID-tf-state"
    prefix = "hermes-gke"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Refresh kubeconfig after cluster is created
resource "null_resource" "kubeconfig" {
  triggers = {
    cluster_endpoint = google_container_cluster.primary.endpoint
  }

  depends_on = [google_container_cluster.primary]

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Enable Required APIs
# ──────────────────────────────────────────────────────────────────────────────

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "containerscanning.googleapis.com",
    "aiplatform.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
