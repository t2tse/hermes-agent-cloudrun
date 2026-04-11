###############################################################################
# Hermes Agent on GCP -- Terraform Variables
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Project & Region
# ──────────────────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID where all resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "us-central1"
}

# ──────────────────────────────────────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────────────────────────────────────

variable "network_name" {
  description = "Name of the VPC network."
  type        = string
  default     = "hermes-vpc"
}

variable "gke_subnet_cidr" {
  description = "CIDR range for the GKE subnet."
  type        = string
  default     = "10.10.0.0/24"
}

variable "master_authorized_cidrs" {
  description = "Additional CIDR blocks allowed to access the GKE control plane."
  type        = map(string)
  default     = {}
}

variable "gke_pods_cidr" {
  description = "Secondary CIDR range for GKE Pods."
  type        = string
  default     = "10.100.0.0/16"
}

variable "gke_services_cidr" {
  description = "Secondary CIDR range for GKE Services."
  type        = string
  default     = "10.101.0.0/16"
}

# ──────────────────────────────────────────────────────────────────────────────
# GKE
# ──────────────────────────────────────────────────────────────────────────────

variable "gke_cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  type        = string
  default     = "hermes-cluster"
}

# ──────────────────────────────────────────────────────────────────────────────
# Secrets
# ──────────────────────────────────────────────────────────────────────────────

variable "gateway_auth_token" {
  description = "Hermes gateway auth token. Leave empty to auto-generate."
  type        = string
  sensitive   = true
  default     = ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Hermes Agent Configuration
# ──────────────────────────────────────────────────────────────────────────────

variable "hermes_image" {
  description = "Custom Hermes container image. Leave empty to use the Artifact Registry image."
  type        = string
  default     = ""
}

variable "hermes_default_model" {
  description = "Default model for Hermes Agent (Vertex AI model name)."
  type        = string
  default     = "gemini-2.5-pro-preview-06-05"
}

variable "vertex_location" {
  description = "Vertex AI location for model serving. Use 'global' for widest model availability."
  type        = string
  default     = "global"
}

variable "vertex_model_aliases" {
  description = "Map of short model names to Vertex AI model IDs. Hermes uses the short names."
  type        = map(string)
  default = {
    "gemini-2.5-pro-preview-06-05"  = "gemini-2.5-pro-preview-06-05"
    "gemini-2.5-flash"              = "gemini-2.5-flash-preview-04-17"
  }
}

variable "hermes_cpu_request" {
  description = "CPU request for Hermes pods."
  type        = string
  default     = "1"
}

variable "hermes_memory_request" {
  description = "Memory request for Hermes pods."
  type        = string
  default     = "2Gi"
}

variable "hermes_cpu_limit" {
  description = "CPU limit for Hermes pods."
  type        = string
  default     = "2"
}

variable "hermes_memory_limit" {
  description = "Memory limit for Hermes pods."
  type        = string
  default     = "4Gi"
}

variable "developers" {
  description = "Map of developer names to their configuration. Each developer gets a dedicated Hermes Agent pod and PVC."
  type = map(object({
    active = bool
  }))
  default = {
    "default" = { active = true }
  }

  validation {
    condition     = alltrue([for name in keys(var.developers) : can(regex("^[a-z0-9][a-z0-9-]{0,62}$", name))])
    error_message = "Developer names must be lowercase alphanumeric with hyphens, starting with a letter or digit (max 63 chars)."
  }
}

variable "deployer_service_account" {
  description = "Service account email for the deployer (granted IAP tunnel access). Leave empty to skip."
  type        = string
  default     = ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Monitoring & Alerting
# ──────────────────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email address for operational alerts."
  type        = string
  default     = ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Labels
# ──────────────────────────────────────────────────────────────────────────────

variable "labels" {
  description = "Labels to apply to all resources."
  type        = map(string)
  default = {
    app         = "hermes-agent"
    managed-by  = "terraform"
    environment = "production"
  }
}
