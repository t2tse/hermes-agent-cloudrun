resource "kubernetes_namespace" "hermes" {
  metadata {
    name = "hermes"
  }

  depends_on = [null_resource.kubeconfig]
}

# K8s service account with Workload Identity annotation
resource "kubernetes_service_account" "hermes_agent" {
  metadata {
    name      = "hermes-agent"
    namespace = kubernetes_namespace.hermes.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.hermes_agent.email
    }
  }
}

# Gateway auth token as K8s secret
resource "kubernetes_secret" "gateway_token" {
  metadata {
    name      = "hermes-gateway-token"
    namespace = kubernetes_namespace.hermes.metadata[0].name
  }

  data = {
    token = local.gateway_auth_token
  }

  type = "Opaque"
}

# Hermes config template as ConfigMap
resource "kubernetes_config_map" "hermes_config" {
  metadata {
    name      = "hermes-config"
    namespace = kubernetes_namespace.hermes.metadata[0].name
  }

  data = {
    "config.yaml.template" = file("${path.module}/hermes-config.yaml.template")
  }
}

# Vertex AI model aliases as ConfigMap
resource "kubernetes_config_map" "vertex_model_aliases" {
  metadata {
    name      = "vertex-model-aliases"
    namespace = kubernetes_namespace.hermes.metadata[0].name
  }

  data = {
    aliases = jsonencode(var.vertex_model_aliases)
  }
}

# Per-developer PVCs
resource "kubernetes_persistent_volume_claim" "hermes_pvc" {
  for_each = var.developers

  metadata {
    name      = "hermes-pvc-${each.key}"
    namespace = kubernetes_namespace.hermes.metadata[0].name
    labels = {
      app       = "hermes"
      developer = each.key
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

# Per-developer Hermes Agent deployments
# Runs on gVisor (Autopilot default) -- the sandbox IS the pod itself
resource "kubernetes_deployment" "hermes_agent" {
  for_each = var.developers

  metadata {
    name      = "hermes-agent-${each.key}"
    namespace = kubernetes_namespace.hermes.metadata[0].name
    labels = {
      app       = "hermes"
      component = "agent"
      developer = each.key
    }
  }

  wait_for_rollout = false

  depends_on = [null_resource.build_hermes_image]

  spec {
    replicas = each.value.active ? 1 : 0

    selector {
      match_labels = {
        app       = "hermes"
        component = "agent"
        developer = each.key
      }
    }

    template {
      metadata {
        labels = {
          app       = "hermes"
          component = "agent"
          developer = each.key
        }
      }

      spec {
        service_account_name = kubernetes_service_account.hermes_agent.metadata[0].name

        # Autopilot resource requests (required)
        # gVisor sandbox is automatic on Autopilot
        container {
          name  = "hermes"
          image = local.hermes_image

          resources {
            requests = {
              cpu               = var.hermes_cpu_request
              memory            = var.hermes_memory_request
              "ephemeral-storage" = "1Gi"
            }
            limits = {
              cpu               = var.hermes_cpu_limit
              memory            = var.hermes_memory_limit
              "ephemeral-storage" = "10Gi"
            }
          }

          env {
            name  = "HERMES_HOME"
            value = "/opt/data"
          }
          env {
            name  = "HERMES_DEFAULT_MODEL"
            value = var.hermes_default_model
          }
          env {
            name  = "VERTEX_PROJECT"
            value = var.project_id
          }
          env {
            name  = "VERTEX_LOCATION"
            value = var.vertex_location
          }
          env {
            name  = "VERTEX_PROXY_PORT"
            value = "8081"
          }
          env {
            name = "VERTEX_MODEL_ALIASES"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map.vertex_model_aliases.metadata[0].name
                key  = "aliases"
              }
            }
          }
          env {
            name = "GATEWAY_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.gateway_token.metadata[0].name
                key  = "token"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/opt/data"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.hermes_pvc[each.key].metadata[0].name
          }
        }
      }
    }
  }
}

# Per-developer Hermes gateway services (ClusterIP for internal access)
resource "kubernetes_service" "hermes_gateway" {
  for_each = var.developers

  metadata {
    name      = "hermes-gateway-${each.key}"
    namespace = kubernetes_namespace.hermes.metadata[0].name
    labels = {
      app       = "hermes"
      component = "agent"
      developer = each.key
    }
  }

  spec {
    selector = {
      app       = "hermes"
      component = "agent"
      developer = each.key
    }

    port {
      name        = "gateway"
      port        = 8443
      target_port = 8443
    }
  }
}
