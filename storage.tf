# ---------- S3 Storage Bucket ----------
resource "aws_s3_bucket" "ysweet_storage" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "ysweet_storage" {
  bucket = aws_s3_bucket.ysweet_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ysweet_storage" {
  bucket = aws_s3_bucket.ysweet_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_metric" "ysweet_storage_metrics" {
  bucket = aws_s3_bucket.ysweet_storage.id
  name   = "EntireBucket"
}

# Note: Billing metrics must be enabled manually in the AWS Billing console
# Go to: AWS Billing Console > Billing Preferences > Receive Billing Alerts
# This is required for cost monitoring in the dashboard
