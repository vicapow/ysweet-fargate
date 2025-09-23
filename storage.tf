# ---------- S3 Storage Configuration ----------
# S3 bucket is managed manually - see README for setup instructions

# ---------- CloudTrail for S3 API Logging ----------
# TEMPORARILY DISABLED TO TEST 503 SLOWDOWN ISSUE
# resource "aws_cloudtrail" "s3_api_logging" {
#   name           = "${var.app_name}-s3-api-trail"
#   s3_bucket_name = aws_s3_bucket.cloudtrail_logs.bucket

#   event_selector {
#     read_write_type                 = "All"
#     include_management_events       = false
#     exclude_management_event_sources = []

#     data_resource {
#       type   = "AWS::S3::Object"
#       values = ["arn:aws:s3:::${var.bucket_name}/*"]
#     }
#   }

#   cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.s3_api_logs.arn}:*"
#   cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs_role.arn

#   depends_on = [aws_s3_bucket_policy.cloudtrail_logs_policy]
# }

# CloudWatch Log Group for S3 API calls
resource "aws_cloudwatch_log_group" "s3_api_logs" {
  name              = "/aws/cloudtrail/${var.app_name}-s3-api"
  retention_in_days = 7
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.app_name}-cloudtrail-logs-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# IAM role for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_logs_role" {
  name = "${var.app_name}-cloudtrail-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_logs_policy" {
  name = "${var.app_name}-cloudtrail-logs-policy"
  role = aws_iam_role.cloudtrail_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:*:*"
      }
    ]
  })
}

# Random suffix for unique bucket naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Note: Billing metrics must be enabled manually in the AWS Billing console
# Go to: AWS Billing Console > Billing Preferences > Receive Billing Alerts
# This is required for cost monitoring in the dashboard
