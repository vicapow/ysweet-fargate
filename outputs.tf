output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "s3_bucket_name" {
  value       = var.bucket_name
  description = "Name of the S3 bucket for Y-Sweet storage"
}

output "ssl_certificate_arn" {
  value       = var.create_ssl_cert ? aws_acm_certificate.this[0].arn : null
  description = "ARN of the SSL certificate (if created)"
}

output "application_url" {
  value       = var.create_ssl_cert ? "https://${var.domain_name}" : "http://${aws_lb.this.dns_name}"
  description = "Application URL (HTTP or HTTPS depending on SSL configuration)"
}

output "dashboard_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.ysweet_dashboard.dashboard_name}"
  description = "CloudWatch dashboard URL for monitoring"
}

output "cloudwatch_insights_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logs:insights"
  description = "CloudWatch Logs Insights console with saved queries for log analysis"
}



# Dev Server Outputs
output "dev_alb_dns_name" {
  value       = var.enable_dev_server ? aws_lb.dev[0].dns_name : null
  description = "DNS name of the Dev Application Load Balancer"
}

output "dev_ssl_certificate_arn" {
  value       = var.create_dev_ssl_cert ? aws_acm_certificate.dev[0].arn : null
  description = "ARN of the dev SSL certificate (if created)"
}

output "dev_application_url" {
  value       = var.enable_dev_server ? (var.create_dev_ssl_cert ? "https://${var.dev_domain_name}" : "http://${aws_lb.dev[0].dns_name}") : null
  description = "Dev Application URL (HTTP or HTTPS depending on SSL configuration)"
}
