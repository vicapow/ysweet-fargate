terraform {
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

  idle_timeout               = 1200
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

  deregistration_delay = 60
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
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

resource "aws_ecs_task_definition" "this" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn           = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.app_name
      image     = var.image
      essential = true
      command   = ["sh", "-c", "y-sweet serve --host=0.0.0.0 --auth=$AUTH_KEY s3://$STORAGE_BUCKET"]
      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]
      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "STORAGE_BUCKET", value = aws_s3_bucket.ysweet_storage.bucket },
        { name = "AUTH_KEY", value = var.auth_key },
        { name = "AWS_ACCESS_KEY_ID", value = aws_iam_access_key.ysweet_s3_access_key.id },
        { name = "AWS_SECRET_ACCESS_KEY", value = aws_iam_access_key.ysweet_s3_access_key.secret },
        { name = "AWS_DEFAULT_REGION", value = var.region }
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
