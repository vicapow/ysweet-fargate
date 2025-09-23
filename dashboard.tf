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
        y      = 22
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
        y      = 28
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
        y      = 34
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
        y      = 34
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
        y      = 38
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
        y      = 38
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
      # S3 SlowDown Retry Metrics
      {
        type   = "metric"
        x      = 0
        y      = 42
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
    ]
  })
}
