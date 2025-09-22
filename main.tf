terraform {
  backend "s3" {
    bucket         = "ysweet-terraform-state"
    key            = "ysweet-fargate/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.1" }
  }
}

provider "aws" {
  region = var.region
}


# ---------- Inputs ----------
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app_name" {
  type    = string
  default = "ysweet"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "image" {
  type = string # e.g. ACCOUNT.dkr.ecr.REGION.amazonaws.com/hello-fargate:v1
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

# ---------- VPC (use default) ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------- Security Groups ----------
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg"
  description = "ALB SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tasks" {
  name        = "${var.app_name}-tasks-sg"
  description = "ECS tasks SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- ALB + Target Group + Listener ----------
resource "aws_lb" "this" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  # Increase idle timeout for WebSocket connections
  idle_timeout               = 3600  # 1 hour for long-lived WebSocket connections
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "this" {
  name        = "${var.app_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/ready"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  # Optimize for WebSocket connections
  deregistration_delay = 30
}

# SSL Certificate (optional)
resource "aws_acm_certificate" "this" {
  count                     = var.create_ssl_cert ? 1 : 0
  domain_name               = var.domain_name
  validation_method         = "DNS"
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "this" {
  count           = var.create_ssl_cert ? 1 : 0
  certificate_arn = aws_acm_certificate.this[0].arn
  
  timeouts {
    create = "5m"
  }
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.create_ssl_cert ? "redirect" : "forward"
    
    dynamic "redirect" {
      for_each = var.create_ssl_cert ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    dynamic "forward" {
      for_each = var.create_ssl_cert ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.this.arn
        }
      }
    }
  }
}

# HTTPS Listener (optional)
resource "aws_lb_listener" "https" {
  count             = var.create_ssl_cert ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate_validation.this[0].certificate_arn

  default_action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.this.arn
      }
      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }
}

# ---------- ECS ----------
resource "aws_ecs_cluster" "this" {
  name = "${var.app_name}-cluster"
}

data "aws_iam_policy" "ecs_exec_managed" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_exec" {
  name = "${var.app_name}-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_attach" {
  role       = aws_iam_role.task_exec.name
  policy_arn = data.aws_iam_policy.ecs_exec_managed.arn
}

# Task role for S3 access
resource "aws_iam_role" "task_role" {
  name = "${var.app_name}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_access" {
  name = "${var.app_name}-s3-access"
  role = aws_iam_role.task_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      Resource = [
        aws_s3_bucket.ysweet_storage.arn,
        "${aws_s3_bucket.ysweet_storage.arn}/*"
      ]
    }]
  })
}

# IAM User for programmatic S3 access
resource "aws_iam_user" "ysweet_s3_user" {
  name = "${var.app_name}-s3-user"
}

resource "aws_iam_access_key" "ysweet_s3_access_key" {
  user = aws_iam_user.ysweet_s3_user.name
}

resource "aws_iam_user_policy" "ysweet_s3_user_policy" {
  name = "${var.app_name}-s3-user-policy"
  user = aws_iam_user.ysweet_s3_user.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      Resource = [
        aws_s3_bucket.ysweet_storage.arn,
        "${aws_s3_bucket.ysweet_storage.arn}/*"
      ]
    }]
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7
}

# CloudWatch metric filters for log monitoring
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

resource "aws_ecs_task_definition" "this" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "4096"  # 4 vCPU (beast mode!)
  memory                   = "8192"  # 8 GB RAM
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn           = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.app_name
      image     = var.image
      essential = true
      command   = ["sh", "-c", "y-sweet serve --url-prefix=${var.create_ssl_cert ? "https" : "http"}://${var.create_ssl_cert ? var.domain_name : aws_lb.this.dns_name}/ --host=0.0.0.0 --auth=$AUTH_KEY s3://$STORAGE_BUCKET"]
      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]
      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "STORAGE_BUCKET", value = aws_s3_bucket.ysweet_storage.bucket },
        { name = "AUTH_KEY", value = var.auth_key },
        { name = "AWS_ACCESS_KEY_ID", value = aws_iam_access_key.ysweet_s3_access_key.id },
        { name = "AWS_SECRET_ACCESS_KEY", value = aws_iam_access_key.ysweet_s3_access_key.secret },
        { name = "AWS_DEFAULT_REGION", value = var.region },
        { name = "CORS_ALLOW_ORIGIN", value = "*" },
        { name = "CORS_ALLOW_METHODS", value = "GET,POST,PUT,DELETE,OPTIONS" },
        { name = "CORS_ALLOW_HEADERS", value = "Content-Type,Authorization,X-Requested-With,Origin,Connection,Upgrade,Sec-WebSocket-Key,Sec-WebSocket-Version,Sec-WebSocket-Protocol" }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name,
          awslogs-region        = var.region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = "${var.app_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Wait for steady state after deployment
  wait_for_steady_state = true

  # Health check grace period for container startup
  health_check_grace_period_seconds = 300

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  # Ensure ALB target group is created first
  depends_on = [aws_lb_listener.http]
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.ysweet_storage.bucket
}

output "ssl_certificate_arn" {
  value = var.create_ssl_cert ? aws_acm_certificate.this[0].arn : null
}

output "application_url" {
  value = var.create_ssl_cert ? "https://${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}

# ---------- CloudWatch Dashboard ----------
resource "aws_cloudwatch_dashboard" "ysweet_dashboard" {
  dashboard_name = "${var.app_name}-dashboard"

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
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.ysweet_storage.bucket, "StorageType", "StandardStorage"],
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
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 4

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}'\n| fields @timestamp, @message\n| filter @message like /Persisting snapshot size/\n| parse @message \"size=* \" as doc_size\n| stats count() as saves, avg(doc_size) as avg_size by bin(5m)\n| sort @timestamp desc\n| limit 100"
          region  = var.region
          title   = "Y-Sweet Document Saves (Real-time S3 Activity)"
          view    = "table"
        }
      },
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
      }
    ]
  })
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.ysweet_dashboard.dashboard_name}"
}

