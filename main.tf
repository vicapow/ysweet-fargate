# Y-Sweet Multi-Document Server on AWS Fargate
# 
# This infrastructure deploys Y-Sweet, a collaborative document server built on Yjs 
# for real-time collaborative editing (think Google Docs-style live collaboration).
# The setup is optimized for WebSocket connections and high-throughput document synchronization.
#
# Architecture:
# - ECS Fargate: Runs Y-Sweet container with 4 vCPU + 8GB RAM
# - Application Load Balancer: WebSocket-optimized with 1-hour idle timeout
# - S3 Storage: Document persistence with versioning and encryption
# - CloudWatch: Comprehensive monitoring with cost tracking
# - Optional SSL: ACM certificate with automatic HTTP->HTTPS redirect
#
# File Structure:
# - versions.tf: Terraform and provider configuration
# - variables.tf: Input variables
# - outputs.tf: Output values
# - storage.tf: S3 bucket configuration
# - networking.tf: VPC, ALB, security groups, SSL
# - compute.tf: ECS cluster, task definition, IAM roles
# - monitoring.tf: CloudWatch logs, metric filters, saved queries
# - dashboard.tf: CloudWatch dashboard with all monitoring widgets
#
# Quick Start:
# 1. ./setup-remote-state.sh (configure S3 backend)
# 2. terraform init
# 3. terraform apply
# 4. Visit billing console to enable cost monitoring (optional)
#
# Monitoring Access:
# - terraform output dashboard_url          # Main monitoring dashboard
# - terraform output cloudwatch_insights_url # Advanced log analysis
# - terraform output application_url        # Y-Sweet application