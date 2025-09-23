# ---------- CloudWatch Logs ----------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7
}

# ---------- S3 Performance Monitoring ----------
resource "aws_cloudwatch_dashboard" "s3_performance" {
  dashboard_name = "${var.app_name}-s3-performance"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "4xxErrors", "BucketName", var.bucket_name],
            [".", "5xxErrors", ".", "."],
            [".", "AllRequests", ".", "."],
            [".", "GetRequests", ".", "."],
            [".", "PutRequests", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "S3 Request Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "FirstByteLatency", "BucketName", var.bucket_name],
            [".", "TotalRequestLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "S3 Latency Metrics"
          period  = 300
        }
      }
    ]
  })
}

# Separate log group for dev server
resource "aws_cloudwatch_log_group" "app_dev" {
  name              = "/ecs/${var.app_name}-dev"
  retention_in_days = 7
}

# ---------- CloudWatch Metric Filters ----------
resource "aws_cloudwatch_log_metric_filter" "info_logs" {
  name           = "${var.app_name}-info-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "INFO"

  metric_transformation {
    name      = "InfoLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  name           = "${var.app_name}-error-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "ErrorLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "warn_logs" {
  name           = "${var.app_name}-warn-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "WARN"

  metric_transformation {
    name      = "WarnLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "total_logs" {
  name           = "${var.app_name}-total-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = ""

  metric_transformation {
    name      = "TotalLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

# ---------- Dev Server Metric Filters ----------
resource "aws_cloudwatch_log_metric_filter" "dev_info_logs" {
  name           = "${var.app_name}-dev-info-logs"
  log_group_name = aws_cloudwatch_log_group.app_dev.name
  pattern        = "INFO"

  metric_transformation {
    name      = "DevInfoLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "dev_error_logs" {
  name           = "${var.app_name}-dev-error-logs"
  log_group_name = aws_cloudwatch_log_group.app_dev.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "DevErrorLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "dev_warn_logs" {
  name           = "${var.app_name}-dev-warn-logs"
  log_group_name = aws_cloudwatch_log_group.app_dev.name
  pattern        = "WARN"

  metric_transformation {
    name      = "DevWarnLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "dev_total_logs" {
  name           = "${var.app_name}-dev-total-logs"
  log_group_name = aws_cloudwatch_log_group.app_dev.name
  pattern        = ""

  metric_transformation {
    name      = "DevTotalLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

# ---------- S3 SlowDown Metric Filters ----------
resource "aws_cloudwatch_log_metric_filter" "s3_slowdown_retries" {
  name           = "${var.app_name}-s3-slowdown-retries"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "SlowDown"

  metric_transformation {
    name      = "S3SlowDownRetries"
    namespace = "YSweet/S3"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "dev_s3_slowdown_retries" {
  name           = "${var.app_name}-dev-s3-slowdown-retries"
  log_group_name = aws_cloudwatch_log_group.app_dev.name
  pattern        = "SlowDown"

  metric_transformation {
    name      = "DevS3SlowDownRetries"
    namespace = "YSweet/S3"
    value     = "1"
  }
}

# ---------- CloudWatch Insights Saved Queries ----------


resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.app_name}-error-analysis"
  
  log_group_names = [
    aws_cloudwatch_log_group.app.name,
    aws_cloudwatch_log_group.app_dev.name
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/ or @message like /WARN/
| stats count() as error_count by @message
| sort error_count desc
| limit 20
EOF
}

resource "aws_cloudwatch_query_definition" "s3_slowdown_analysis" {
  name = "${var.app_name}-s3-slowdown-analysis"
  
  log_group_names = [
    aws_cloudwatch_log_group.app.name,
    aws_cloudwatch_log_group.app_dev.name
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /SlowDown error - retrying/
| parse @message "method=* attempt=* delay_ms=*" as method, attempt, delay_ms
| stats count() as retry_count, avg(delay_ms) as avg_delay_ms, max(attempt) as max_attempts by method, bin(5m)
| sort @timestamp desc
EOF
}



