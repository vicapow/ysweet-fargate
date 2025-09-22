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
      # ECS Task Counts
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ServiceName", aws_ecs_service.this.name, "ClusterName", aws_ecs_cluster.this.name],
            [".", "PendingTaskCount", ".", ".", ".", "."],
            [".", "DesiredCount", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ECS Service - Task Counts"
          period  = 300
          stat    = "Average"
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
      # Target Group Health
      {
        type   = "metric"
        x      = 0
        y      = 12
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
      # S3 Storage Metrics
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", var.bucket_name, "StorageType", "StandardStorage"],
            [".", "NumberOfObjects", ".", ".", ".", "AllStorageTypes"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "S3 Storage - Bucket Size & Object Count (Daily)"
          period  = 86400
          stat    = "Maximum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Document Save Activity
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 12
        height = 4

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}'\n| fields @timestamp, @message\n| filter @message like /Persisting snapshot size/\n| parse @message \"size=* \" as doc_size\n| stats count() as saves, avg(doc_size) as avg_size by bin(5m)\n| sort @timestamp desc\n| limit 100"
          region  = var.region
          title   = "Y-Sweet Document Saves (Real-time S3 Activity)"
          view    = "table"
        }
      },
      # WebSocket Connection Activity
      {
        type   = "log"
        x      = 12
        y      = 18
        width  = 12
        height = 4

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}'\n| fields @timestamp, @message\n| filter @message like /WebSocket/\n| stats count() as connections by bin(5m)\n| sort @timestamp desc\n| limit 100"
          region  = var.region
          title   = "WebSocket Connection Activity"
          view    = "table"
        }
      },
      # Log Volume by Level
      {
        type   = "metric"
        x      = 0
        y      = 22
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["YSweet/Logs", "TotalLogCount"],
            [".", "InfoLogCount"],
            [".", "WarnLogCount"],
            [".", "ErrorLogCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Log Volume by Level (Count per 5min)"
          period  = 300
          stat    = "Sum"
        }
      },
      # Error & Warning Rate
      {
        type   = "metric"
        x      = 12
        y      = 22
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["YSweet/Logs", "ErrorLogCount", { "stat": "Sum" }],
            [".", "WarnLogCount", { "stat": "Sum" }]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.region
          title   = "Error & Warning Rate (per 5min)"
          period  = 300
          stat    = "Sum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Recent Error Logs
      {
        type   = "log"
        x      = 0
        y      = 28
        width  = 12
        height = 6

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 100"
          region  = var.region
          title   = "Recent Error Logs"
          view    = "table"
        }
      },
      # Log Activity Over Time
      {
        type   = "log"
        x      = 12
        y      = 28
        width  = 12
        height = 6

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}'\n| fields @timestamp, @message\n| stats count() as log_count by bin(5m)\n| sort @timestamp desc"
          region  = var.region
          title   = "Log Activity Over Time"
          view    = "table"
        }
      },
      # Recent Errors and Warnings
      {
        type   = "log"
        x      = 0
        y      = 34
        width  = 24
        height = 4

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}'\n| fields @timestamp, @message\n| filter @message like /ERROR/ or @message like /WARN/ or @message like /Failed/\n| sort @timestamp desc\n| limit 50"
          region  = var.region
          title   = "Recent Errors and Warnings"
          view    = "table"
        }
      },
      # AWS Account - Estimated Monthly Charges
      {
        type   = "metric"
        x      = 0
        y      = 38
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "AWS Account - Estimated Monthly Charges"
          period  = 86400
          stat    = "Maximum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Service-Level Estimated Charges
      {
        type   = "metric"
        x      = 12
        y      = 38
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", "ServiceName", "AmazonECS"],
            [".", ".", ".", ".", ".", "AmazonS3"],
            [".", ".", ".", ".", ".", "AmazonEC2"],
            [".", ".", ".", ".", ".", "AmazonCloudWatch"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Service-Level Estimated Charges"
          period  = 86400
          stat    = "Maximum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}
