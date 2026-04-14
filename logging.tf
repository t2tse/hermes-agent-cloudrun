###############################################################################
# Hermes Agent Logging -- Alerts, Dashboard, and Log Routing
###############################################################################

resource "google_project_service" "monitoring_api" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# ──────────────────────────────────────────────────────────────────────────────
# Notification Channel
# ──────────────────────────────────────────────────────────────────────────────

resource "google_monitoring_notification_channel" "hermes_email" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "Hermes Agent Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.monitoring_api]
}

# ──────────────────────────────────────────────────────────────────────────────
# Log-Based Alerts
# ──────────────────────────────────────────────────────────────────────────────

# Alert: Hermes pod crash / restart
resource "google_logging_metric" "hermes_crash" {
  name    = "hermes/pod_restart"
  project = var.project_id
  filter  = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="hermes"
    resource.labels.container_name="hermes"
    jsonPayload.reason="BackOff" OR textPayload=~"CrashLoopBackOff"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "hermes_crash" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "Hermes Agent: Pod CrashLoop"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Hermes pod in CrashLoopBackOff"

    condition_threshold {
      filter          = "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.hermes_crash.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.hermes_email[0].name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "A Hermes Agent pod is crash-looping. Check `kubectl logs -n hermes` for details. Common causes: Vertex AI proxy connection issues, config errors, or OOM."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring_api]
}

# Alert: Vertex AI proxy errors
resource "google_logging_metric" "vertex_proxy_error" {
  name    = "hermes/vertex_proxy_error"
  project = var.project_id
  filter  = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="hermes"
    textPayload=~"vertex-proxy.*error"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "vertex_proxy_error" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "Hermes Agent: Vertex AI Proxy Errors"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "High rate of Vertex AI proxy errors"

    condition_threshold {
      filter          = "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.vertex_proxy_error.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.hermes_email[0].name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "High rate of Vertex AI proxy errors. Check Workload Identity binding, IAM permissions (roles/aiplatform.user), and Vertex AI API quota."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring_api]
}

# ──────────────────────────────────────────────────────────────────────────────
# Log Storage -- GCS Bucket Sink
# ──────────────────────────────────────────────────────────────────────────────

resource "google_storage_bucket" "hermes_logs" {
  name          = "${var.project_id}-hermes-logs"
  location      = var.region
  project       = var.project_id
  force_destroy = false

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  labels = var.labels
}

resource "google_logging_project_sink" "hermes_gcs" {
  name        = "hermes-logs-to-gcs"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.hermes_logs.name}"

  filter = <<-EOT
    resource.type="k8s_container" AND resource.labels.namespace_name="hermes"
  EOT

  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.hermes_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.hermes_gcs.writer_identity
}

# ──────────────────────────────────────────────────────────────────────────────
# Dashboard
# ──────────────────────────────────────────────────────────────────────────────

resource "google_monitoring_dashboard" "hermes" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Hermes Agent Operations"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          xPos   = 0
          yPos   = 0
          width  = 6
          height = 4
          widget = {
            title = "Hermes Agent Logs (all developers)"
            logsPanel = {
              filter = <<-EOT
                resource.type="k8s_container"
                resource.labels.namespace_name="hermes"
                resource.labels.container_name="hermes"
              EOT
            }
          }
        },
        {
          xPos   = 6
          yPos   = 0
          width  = 6
          height = 4
          widget = {
            title = "Vertex AI Proxy Logs"
            logsPanel = {
              filter = <<-EOT
                resource.type="k8s_container"
                resource.labels.namespace_name="hermes"
                textPayload=~"\[vertex-proxy\]"
              EOT
            }
          }
        },
        {
          xPos   = 0
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Pod Restarts"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.hermes_crash.name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Vertex AI Proxy Errors"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.vertex_proxy_error.name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
              }]
              timeshiftDuration = "0s"
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos   = 0
          yPos   = 8
          width  = 12
          height = 4
          widget = {
            title = "Hermes Errors Only"
            logsPanel = {
              filter = <<-EOT
                resource.type="k8s_container"
                resource.labels.namespace_name="hermes"
                severity>="ERROR"
              EOT
            }
          }
        },
        # ── Resource Monitoring ──────────────────────────────────
        {
          xPos   = 0
          yPos   = 12
          width  = 12
          height = 2
          widget = {
            title = "Resource Monitoring"
            text = {
              content = ""
              format  = "RAW"
            }
          }
        },
        {
          xPos   = 0
          yPos   = 14
          width  = 6
          height = 4
          widget = {
            title = "Pod CPU Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_container\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/container/cpu/core_usage_time\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR", label = "cores" }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 14
          width  = 6
          height = 4
          widget = {
            title = "Pod Memory Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_container\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/container/memory/used_bytes\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR", label = "bytes" }
            }
          }
        },
        {
          xPos   = 0
          yPos   = 18
          width  = 6
          height = 4
          widget = {
            title = "Pod Restart Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_container\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/container/restart_count\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 18
          width  = 6
          height = 4
          widget = {
            title = "PVC Disk Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_pod\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/pod/volume/used_bytes\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR", label = "bytes" }
            }
          }
        },
        {
          xPos   = 0
          yPos   = 22
          width  = 6
          height = 4
          widget = {
            title = "PVC Disk Capacity"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type = \"k8s_pod\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/pod/volume/total_bytes\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_NONE"
                      }
                    }
                  }
                  plotType = "LINE"
                },
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type = \"k8s_pod\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/pod/volume/used_bytes\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_NONE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = { scale = "LINEAR", label = "bytes" }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 22
          width  = 6
          height = 4
          widget = {
            title = "Network - Bytes Received"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"k8s_pod\" AND resource.labels.namespace_name = \"hermes\" AND metric.type = \"kubernetes.io/pod/network/received_bytes_count\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR", label = "bytes/s" }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.monitoring_api]
}
