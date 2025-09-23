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

# ---------- S3 VPC Endpoint for Performance ----------
# This eliminates 503 errors by keeping S3 traffic within AWS network
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = data.aws_route_tables.default.ids
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "s3:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-s3-endpoint"
  }
}

# Get route tables for VPC endpoint
data "aws_route_tables" "default" {
  vpc_id = data.aws_vpc.default.id
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

  # Enable connection stickiness for WebSocket sessions
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 86400
  }
}

# ---------- SSL Certificate (optional) ----------
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

# ---------- Dev Server Resources ----------
# Dev ALB Security Group
resource "aws_security_group" "dev_alb" {
  count       = var.enable_dev_server ? 1 : 0
  name        = "${var.app_name}-dev-alb-sg"
  description = "Dev ALB SG"
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

# Dev Tasks Security Group
resource "aws_security_group" "dev_tasks" {
  count       = var.enable_dev_server ? 1 : 0
  name        = "${var.app_name}-dev-tasks-sg"
  description = "Dev ECS tasks SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Dev ALB
resource "aws_lb" "dev" {
  count              = var.enable_dev_server ? 1 : 0
  name               = "${var.app_name}-dev-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.dev_alb[0].id]
  subnets            = data.aws_subnets.public.ids

  # Standard timeout for dev server
  idle_timeout               = 60
  enable_deletion_protection = false
}

# Dev Target Group
resource "aws_lb_target_group" "dev" {
  count       = var.enable_dev_server ? 1 : 0
  name        = "${var.app_name}-dev-tg"
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

  deregistration_delay = 30
}

# Dev HTTP Listener (no SSL)
resource "aws_lb_listener" "dev_http" {
  count             = var.enable_dev_server ? 1 : 0
  load_balancer_arn = aws_lb.dev[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn = aws_lb_target_group.dev[0].arn
      }
    }
  }
}

# ---------- Production Listeners ----------
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
