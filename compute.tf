# ---------- ECS Cluster ----------
resource "aws_ecs_cluster" "this" {
  name = "${var.app_name}-cluster"
}

# ---------- IAM Roles ----------
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

# ---------- ECS Task Definition ----------
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

# ---------- ECS Service ----------
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
