# ---------- CloudWatch Dashboard ----------
resource "aws_cloudwatch_dashboard" "ysweet_dashboard" {
  dashboard_name = "${var.app_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ECS CPU & Memory
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.this.name, "ClusterName", aws_ecs_cluster.this.name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ECS Service - CPU & Memory Utilization"
          period  = 300
          stat    = "Average"
        }
      },
      # ALB Request Metrics
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ALB - Request Count & Response Times"
          period  = 300
          stat    = "Sum"
        }
      },
      # Target Group Health
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.this.arn_suffix],
            [".", "UnHealthyHostCount", ".", "."],
            [".", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Target Group - Health Status & Requests"
          period  = 60
          stat    = "Maximum"
        }
      },
      # ALB Connection Metrics
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", aws_lb.this.arn_suffix],
            [".", "NewConnectionCount", ".", "."],
            [".", "RejectedConnectionCount", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ALB - Connection Metrics"
          period  = 300
          stat    = "Sum"
        }
      },
      # Log Volume by Level (Production)
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["YSweet/Logs", "InfoLogCount"],
            [".", "WarnLogCount"],
            [".", "ErrorLogCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Production - Log Volume by Level (per 5min)"
          period  = 300
          stat    = "Sum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Dev Server Log Volume by Level
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["YSweet/Logs", "DevInfoLogCount"],
            [".", "DevWarnLogCount"],
            [".", "DevErrorLogCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Dev Server - Log Volume by Level (per 5min)"
          period  = 300
          stat    = "Sum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Recent Errors (Production)
      {
        type   = "log"
        x      = 0
        y      = 30
        width  = 12
        height = 4

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app.name}'
| fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 25
EOT
          region  = var.region
          title   = "Recent Errors (Production)"
          view    = "table"
        }
      },
      # Recent Warnings (Production)
      {
        type   = "log"
        x      = 12
        y      = 30
        width  = 12
        height = 4

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app.name}'
| fields @timestamp, @message
| filter @message like /WARN/
| sort @timestamp desc
| limit 25
EOT
          region  = var.region
          title   = "Recent Warnings (Production)"
          view    = "table"
        }
      },
      # Recent Errors (Dev Server)
      {
        type   = "log"
        x      = 0
        y      = 34
        width  = 12
        height = 4

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app_dev.name}'
| fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 25
EOT
          region  = var.region
          title   = "Recent Errors (Dev Server)"
          view    = "table"
        }
      },
      # Recent Warnings (Dev Server)
      {
        type   = "log"
        x      = 12
        y      = 34
        width  = 12
        height = 4

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app_dev.name}'
| fields @timestamp, @message
| filter @message like /WARN/
| sort @timestamp desc
| limit 25
EOT
          region  = var.region
          title   = "Recent Warnings (Dev Server)"
          view    = "table"
        }
      },
      # S3 Request Metrics
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = concat([
            ["AWS/S3", "4xxErrors", "BucketName", var.bucket_name],
            [".", "5xxErrors", ".", "."],
            [".", "AllRequests", ".", "."],
            [".", "GetRequests", ".", "."],
            [".", "PutRequests", ".", "."]
          ], var.enable_dev_server && var.dev_bucket_name != "" ? [
            ["AWS/S3", "4xxErrors", "BucketName", var.dev_bucket_name],
            [".", "5xxErrors", ".", "."],
            [".", "AllRequests", ".", "."],
            [".", "GetRequests", ".", "."],
            [".", "PutRequests", ".", "."]
          ] : [])
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = var.enable_dev_server && var.dev_bucket_name != "" ? "S3 Request Metrics (Production vs Dev)" : "S3 Request Metrics"
          period  = 300
        }
      },
      # S3 Latency Metrics
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = concat([
            ["AWS/S3", "FirstByteLatency", "BucketName", var.bucket_name],
            [".", "TotalRequestLatency", ".", "."]
          ], var.enable_dev_server && var.dev_bucket_name != "" ? [
            ["AWS/S3", "FirstByteLatency", "BucketName", var.dev_bucket_name],
            [".", "TotalRequestLatency", ".", "."]
          ] : [])
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = var.enable_dev_server && var.dev_bucket_name != "" ? "S3 Latency Metrics (Production vs Dev)" : "S3 Latency Metrics"
          period  = 300
        }
      },
      # S3 SlowDown Retry Metrics
      {
        type   = "metric"
        x      = 0
        y      = 38
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["YSweet/S3", "S3SlowDownRetries"],
            [".", "DevS3SlowDownRetries"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "S3 SlowDown Retries (Production vs Dev)"
          period  = 300
          stat    = "Sum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Document Persistence Metrics
      {
        type   = "metric"
        x      = 0
        y      = 44
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["YSweet/Documents", "DocPersistenceCount"],
            [".", "DevDocPersistenceCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Document Persistence Activity (Production vs Dev)"
          period  = 300
          stat    = "Sum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Persistence Events Per Minute (Production)
      {
        type   = "log"
        x      = 0
        y      = 50
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app.name}' | filter @message like /Done persisting./ | stats count(*) as count by bin(1m) | sort @timestamp asc
EOT
          region  = var.region
          title   = "Persistence Events Per Minute (Production)"
          view    = "line"
        }
      },
      # Persistence Events Per Minute (Dev)
      {
        type   = "log"
        x      = 12
        y      = 50
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app_dev.name}' | filter @message like /Done persisting./ | stats count(*) as count by bin(1m) | sort @timestamp asc
EOT
          region  = var.region
          title   = "Persistence Events Per Minute (Dev)"
          view    = "line"
        }
      },
      # Recent Document Persistence (Production)
      {
        type   = "log"
        x      = 0
        y      = 56
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app.name}'
| filter @message like /Done persisting./
| parse @message "doc_id=\"*\"" as doc_id
| sort @timestamp desc
| limit 25
EOT
          region  = var.region
          title   = "Recent Document Persistence (Production)"
          view    = "table"
        }
      },
      # Recent Document Persistence (Dev)
      {
        type   = "log"
        x      = 12
        y      = 56
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app_dev.name}'
| filter @message like /Done persisting./
| parse @message "doc_id=\"*\"" as doc_id
| sort @timestamp desc
| limit 25
EOT
          region  = var.region
          title   = "Recent Document Persistence (Dev)"
          view    = "table"
        }
      },
      # Recent Document Persistence Activity (Production)
      {
        type   = "log"
        x      = 0
        y      = 62
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app.name}'
| filter @message like /Done persisting./
| parse @message "doc_id=\"*\"" as doc_id
| stats count() by doc_id, bin(10s)
| sort @timestamp desc
EOT
          region  = var.region
          title   = "Document Persistence Timeline (Production) - 10s bins"
          view    = "table"
        }
      },
      # Document Persistence Summary (Production)
      {
        type   = "log"
        x      = 12
        y      = 62
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app.name}'
| filter @message like /Done persisting./
| parse @message "doc_id=\"*\"" as doc_id
| stats count() as persistence_count by doc_id
| sort persistence_count desc
| limit 20
EOT
          region  = var.region
          title   = "Top Persisted Documents (Production) - Last 1h"
          view    = "table"
        }
      },
      # Recent Document Persistence Activity (Dev)
      {
        type   = "log"
        x      = 0
        y      = 68
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app_dev.name}'
| filter @message like /Done persisting./
| parse @message "doc_id=\"*\"" as doc_id
| stats count() by doc_id, bin(10s)
| sort @timestamp desc
EOT
          region  = var.region
          title   = "Document Persistence Timeline (Dev) - 10s bins"
          view    = "table"
        }
      },
      # Document Persistence Summary (Dev)
      {
        type   = "log"
        x      = 12
        y      = 68
        width  = 12
        height = 6

        properties = {
          query = <<EOT
SOURCE '${aws_cloudwatch_log_group.app_dev.name}'
| filter @message like /Done persisting./
| parse @message "doc_id=\"*\"" as doc_id
| stats count() as persistence_count by doc_id
| sort persistence_count desc
| limit 20
EOT
          region  = var.region
          title   = "Top Persisted Documents (Dev) - Last 1h"
          view    = "table"
        }
      },
    ]
  })
}
