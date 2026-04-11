# ──────────────────────────────────────────────────────────────────────────────
# GKE Autopilot Cluster
# All pods run on gVisor (runsc) by default -- no Kata or nested virt needed.
# ──────────────────────────────────────────────────────────────────────────────

resource "google_container_cluster" "primary" {
  name     = var.gke_cluster_name
  location = var.region

  deletion_protection = false

  # Autopilot mode -- Google manages node pools, gVisor is the default sandbox
  enable_autopilot = true

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.gke_subnet.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.gke_subnet_cidr
      display_name = "GKE subnet"
    }
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = cidr_blocks.key
      }
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [
    google_compute_subnetwork.gke_subnet,
    google_project_service.apis["container.googleapis.com"],
  ]
}
