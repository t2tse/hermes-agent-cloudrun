###############################################################################
# Hermes Agent on Cloud Run -- Terraform Variables
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Project & Region
# ──────────────────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID where all resources will be created."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (Cloud Run, Artifact Registry, Secret Manager)."
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

variable "subnet_cidr" {
  description = "CIDR range for the Cloud Run Direct VPC Egress subnet."
  type        = string
  default     = "10.10.0.0/24"
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Run
# ──────────────────────────────────────────────────────────────────────────────

variable "execution_environment" {
  description = <<-EOT
    Cloud Run execution environment for Hermes Agent services:
      "gen2" — 2nd generation (MicroVM, seccomp syscall filtering + Sandbox2 Linux namespace
               isolation; required for GCS FUSE mounts, recommended)
      "gen1" — 1st generation (gVisor, user-space kernel with syscall interception;
               does NOT support GCS FUSE)
  EOT
  type    = string
  default = "gen2"

  validation {
    condition     = contains(["gen1", "gen2"], var.execution_environment)
    error_message = "execution_environment must be 'gen1' or 'gen2'."
  }
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
    "gemini-2.5-pro"   = "gemini-2.5-pro"
    "gemini-2.5-flash" = "gemini-2.5-flash"
  }
}

variable "developers" {
  description = "Map of developer names to their configuration. Each developer gets a dedicated Cloud Run service, GCS workspace bucket, and service account."
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
