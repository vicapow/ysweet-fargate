variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for deployment"
}

variable "app_name" {
  type        = string
  default     = "ysweet"
  description = "Application name prefix for resource naming"
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Container port for Y-Sweet service"
}

variable "image" {
  type        = string
  description = "Y-Sweet Docker image (e.g. ACCOUNT.dkr.ecr.REGION.amazonaws.com/hello-fargate:v1)"
}

variable "bucket_name" {
  type        = string
  description = "S3 bucket name for Y-Sweet storage (must be created manually - see README)"
}

variable "ysweet_auth_key_secret_arn" {
  type        = string
  description = "ARN of Secrets Manager secret containing AUTH_KEY"
}

variable "domain_name" {
  type        = string
  description = "Domain name for SSL certificate (e.g., ysweet.yourdomain.com)"
  default     = ""
}

variable "create_ssl_cert" {
  type        = bool
  description = "Whether to create an SSL certificate and HTTPS listener"
  default     = false
}
