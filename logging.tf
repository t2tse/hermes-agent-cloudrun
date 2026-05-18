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

# Alert: Hermes container crash / restart
resource "google_logging_metric" "hermes_crash" {
  name    = "hermes-run/container_restart"
  project = var.project_id
  filter  = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name=~"hermes-agent-run-.*"
    severity>="ERROR"
    textPayload=~"process exited|container.*exit|SIGKILL|unhandledRejection"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "hermes_crash" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "Hermes Agent: Container Crash"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Hermes container exiting repeatedly"

    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.hermes_crash.name}\""
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
    content   = "A Hermes Agent container is crashing. Check logs with: gcloud logging read 'resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"hermes-agent-run-.*\"' --project=PROJECT_ID --limit=50. Common causes: Vertex AI proxy connection issues, config errors, or OOM."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring_api]
}

# Alert: Vertex AI proxy errors
resource "google_logging_metric" "vertex_proxy_error" {
  name    = "hermes-run/vertex_proxy_error"
  project = var.project_id
  filter  = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name=~"hermes-agent-run-.*"
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
      filter          = "resource.type = \"cloud_run_revision\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.vertex_proxy_error.name}\""
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
    content   = "High rate of Vertex AI proxy errors. Check IAM permissions (roles/aiplatform.user on the developer's SA), ADC availability, and Vertex AI API quota."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.monitoring_api]
}

# ──────────────────────────────────────────────────────────────────────────────
# Log Storage -- GCS Bucket Sink
# ──────────────────────────────────────────────────────────────────────────────

resource "google_storage_bucket" "hermes_logs" {
  name          = "${var.project_id}-hermes-run-logs"
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
  name        = "hermes-run-logs-to-gcs"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.hermes_logs.name}"

  filter = <<-EOT
    resource.type="cloud_run_revision" AND resource.labels.service_name=~"hermes-agent-run-.*"
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
              filter = "resource.type=\"cloud_run_revision\"\nresource.labels.service_name=~\"hermes-agent-run-.*\""
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
              filter = "resource.type=\"cloud_run_revision\"\nresource.labels.service_name=~\"hermes-agent-run-.*\"\ntextPayload=~\"\\[vertex-proxy\\]\""
            }
          }
        },
        {
          xPos   = 0
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Container Crash Events"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.hermes_crash.name}\""
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
                    filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.vertex_proxy_error.name}\""
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
              filter = "resource.type=\"cloud_run_revision\"\nresource.labels.service_name=~\"hermes-agent-run-.*\"\nseverity>=\"ERROR\""
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
            title = "Cloud Run CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = monitoring.regex.full_match(\"hermes-agent-run-.*\") AND metric.type = \"run.googleapis.com/container/cpu/utilizations\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_PERCENTILE_99"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR", label = "utilization" }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 14
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run Memory Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = monitoring.regex.full_match(\"hermes-agent-run-.*\") AND metric.type = \"run.googleapis.com/container/memory/utilizations\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_PERCENTILE_99"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR", label = "utilization" }
            }
          }
        },
        {
          xPos   = 0
          yPos   = 18
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = monitoring.regex.full_match(\"hermes-agent-run-.*\") AND metric.type = \"run.googleapis.com/request_count\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_SUM"
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
            title = "Cloud Run Instance Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = monitoring.regex.full_match(\"hermes-agent-run-.*\") AND metric.type = \"run.googleapis.com/container/instance_count\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_NONE"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.monitoring_api]
}
