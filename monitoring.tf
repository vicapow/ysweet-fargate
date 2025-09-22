# ---------- CloudWatch Logs ----------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7
}

# ---------- CloudWatch Metric Filters ----------
resource "aws_cloudwatch_log_metric_filter" "info_logs" {
  name           = "${var.app_name}-info-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, request_id, level=\"INFO\", ...]"

  metric_transformation {
    name      = "InfoLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  name           = "${var.app_name}-error-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, request_id, level=\"ERROR\", ...]"

  metric_transformation {
    name      = "ErrorLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "warn_logs" {
  name           = "${var.app_name}-warn-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, request_id, level=\"WARN\", ...]"

  metric_transformation {
    name      = "WarnLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "total_logs" {
  name           = "${var.app_name}-total-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, request_id, level, ...]"

  metric_transformation {
    name      = "TotalLogCount"
    namespace = "YSweet/Logs"
    value     = "1"
  }
}

# ---------- CloudWatch Insights Saved Queries ----------
resource "aws_cloudwatch_query_definition" "websocket_connections" {
  name = "${var.app_name}-websocket-connections"
  
  log_group_names = [
    aws_cloudwatch_log_group.app.name
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /WebSocket/
| stats count() as connections by bin(5m)
| sort @timestamp desc
EOF
}

resource "aws_cloudwatch_query_definition" "document_operations" {
  name = "${var.app_name}-document-operations"
  
  log_group_names = [
    aws_cloudwatch_log_group.app.name
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /Persisting snapshot/ or @message like /Loading document/
| parse @message "size=* " as doc_size
| stats count() as operations, avg(doc_size) as avg_size by bin(5m)
| sort @timestamp desc
EOF
}

resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.app_name}-error-analysis"
  
  log_group_names = [
    aws_cloudwatch_log_group.app.name
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/ or @message like /WARN/ or @message like /Failed/
| stats count() as error_count by @message
| sort error_count desc
| limit 20
EOF
}

resource "aws_cloudwatch_query_definition" "performance_monitoring" {
  name = "${var.app_name}-performance-monitoring"
  
  log_group_names = [
    aws_cloudwatch_log_group.app.name
  ]
  
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ms/ or @message like /seconds/
| parse @message /(?<duration>\d+)(ms|seconds)/
| stats avg(duration) as avg_duration, max(duration) as max_duration by bin(5m)
| sort @timestamp desc
EOF
}
