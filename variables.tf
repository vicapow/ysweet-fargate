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
  description = "Human-readable S3 bucket name for Y-Sweet storage"
}

variable "auth_key" {
  type        = string
  description = "Y-Sweet authentication key for production use"
  sensitive   = true
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
