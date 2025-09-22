# Y-Sweet Multi-Document Server on AWS Fargate

[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7C3AED?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Fargate-FF9900?logo=amazon-aws)](https://aws.amazon.com/fargate/)
[![Y-Sweet](https://img.shields.io/badge/Y--Sweet-Real--time_Collaboration-4F46E5)](https://github.com/jamsocket/y-sweet)

Production-ready Terraform infrastructure for deploying [Y-Sweet](https://github.com/jamsocket/y-sweet), a high-performance collaborative document server built on Yjs. Optimized for real-time collaborative editing (think Google Docs-style live collaboration) with enterprise-grade monitoring and security.

## 🚀 Quick Start

```bash
# 1. Setup remote state (recommended)
./setup-remote-state.sh

# 2. Configure your deployment
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Deploy
terraform init
terraform apply

# 4. Access your application
terraform output application_url
```

## 🏗️ Architecture

### **High-Level Overview**
```
Internet → ALB (HTTP/HTTPS) → ECS Fargate → Y-Sweet Server
                                    ↓
                         S3 Bucket (Document Storage)
                                    ↓
                       CloudWatch (Monitoring & Logs)
```

### **Infrastructure Components**

| Component | Purpose | Specifications |
|-----------|---------|----------------|
| **ECS Fargate** | Container orchestration | 4 vCPU + 8GB RAM ("beast mode") |
| **Application Load Balancer** | Traffic routing & SSL | WebSocket optimized (1h timeout) |
| **S3 Storage** | Document persistence | Versioned, encrypted, metrics enabled |
| **CloudWatch** | Monitoring & logging | Comprehensive dashboards + cost tracking |
| **ACM Certificate** | SSL/TLS termination | Optional, DNS validated |
| **Security Groups** | Network security | Minimal access (ALB → ECS only) |

### **Key Features**
- ✅ **High Concurrency**: Handles significant concurrent WebSocket connections
- ✅ **Real-time Sync**: Optimized for collaborative document editing
- ✅ **Production Ready**: SSL/TLS, monitoring, security best practices
- ✅ **Cost Monitoring**: Real-time AWS cost tracking
- ✅ **Auto-scaling Ready**: Easy to extend with auto-scaling groups
- ✅ **Fault Tolerant**: Health checks and graceful degradation

## 📁 Project Structure

This project follows Terraform best practices with modular file organization:

```
├── main.tf           # Documentation & architecture overview
├── versions.tf       # Terraform & provider configuration  
├── variables.tf      # Input variables with descriptions
├── outputs.tf        # Output values & dashboard links
├── storage.tf        # S3 bucket & metrics configuration
├── networking.tf     # VPC, ALB, security groups, SSL
├── compute.tf        # ECS cluster, tasks, IAM roles
├── monitoring.tf     # CloudWatch logs, metrics, queries
├── dashboard.tf      # CloudWatch dashboard widgets
├── terraform.tfvars # Your configuration values
└── setup-remote-state.sh # S3 backend setup script
```

Each file has a single responsibility, making the infrastructure easy to understand, maintain, and collaborate on.

## ⚙️ Configuration

### **Required Variables**

Create `terraform.tfvars` with these required values:

```hcl
# Required
image       = "your-account.dkr.ecr.region.amazonaws.com/y-sweet:latest"
bucket_name = "your-ysweet-storage-bucket"
auth_key    = "your-secure-authentication-key"

# Optional SSL setup
create_ssl_cert = true
domain_name     = "ysweet.yourdomain.com"

# Optional customization
region          = "us-east-1"
app_name        = "ysweet"
container_port  = 8080
```

### **All Available Variables**

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | `us-east-1` | AWS region for deployment |
| `app_name` | string | `ysweet` | Application name prefix |
| `container_port` | number | `8080` | Container port for Y-Sweet |
| `image` | string | **required** | Y-Sweet Docker image URI |
| `bucket_name` | string | **required** | S3 bucket for document storage |
| `auth_key` | string | **required** | Y-Sweet authentication key |
| `domain_name` | string | `""` | Domain for SSL certificate |
| `create_ssl_cert` | bool | `false` | Whether to create SSL certificate |

## 📊 Monitoring & Observability

### **CloudWatch Dashboard**
Comprehensive real-time monitoring automatically deployed:

```bash
terraform output dashboard_url
```

**Includes:**
- ECS performance (CPU, memory, task health)
- ALB metrics (requests, response times, connections)
- S3 storage tracking (size, object count)
- Cost monitoring (total + per-service breakdown)
- Error analysis and log insights

### **CloudWatch Logs Insights**
Pre-configured saved queries for advanced log analysis:

```bash
terraform output cloudwatch_insights_url
```

**Available Queries:**
- `ysweet-websocket-connections` - WebSocket activity patterns
- `ysweet-document-operations` - Document save/load tracking  
- `ysweet-error-analysis` - Error pattern analysis
- `ysweet-performance-monitoring` - Timing and performance metrics

### **Cost Monitoring Setup**
Enable real-time cost tracking (one-time setup):

1. Visit: `terraform output billing_dashboard_setup`
2. Enable "Receive Billing Alerts"
3. Cost widgets will populate within 24 hours

## 🔒 SSL/HTTPS Setup

### **1. Domain Configuration**
Set up your domain to point to the load balancer:

```bash
# Get your ALB DNS name
terraform output alb_dns_name

# Add CNAME record:
# Host: ysweet
# Value: your-alb-dns-name.region.elb.amazonaws.com
```

### **2. Enable SSL**
Update `terraform.tfvars`:

```hcl
create_ssl_cert = true
domain_name     = "ysweet.yourdomain.com"
```

```bash
terraform apply
```

### **3. DNS Validation**
Add the CNAME validation record shown in Terraform output to your DNS. Certificate validation typically takes 5-10 minutes.

**Benefits:**
- Secure WebSocket connections (`wss://`)
- Automatic HTTP → HTTPS redirect
- Modern TLS 1.2+ security

## 🔧 Usage

### **Document Operations**

Y-Sweet automatically creates documents when clients connect:

```javascript
// WebSocket connection
const ws = new WebSocket('wss://ysweet.yourdomain.com/doc/my-document-id');

// Authentication required
const headers = { 'Authorization': 'Bearer your-auth-key' };
```

### **Document Storage**

Documents are stored in S3 with this structure:
```
s3://your-bucket/
├── {document-uuid-1}/data.ysweet
├── {document-uuid-2}/data.ysweet
└── ...
```

**Inspect documents:**
```bash
# List all documents
aws s3 ls s3://$(terraform output -raw s3_bucket_name) --recursive --human-readable

# Watch for new documents
watch -n 5 'aws s3 ls s3://$(terraform output -raw s3_bucket_name) --recursive'
```

## 🔍 Troubleshooting

### **Common Issues**

**Container not starting:**
```bash
# Check ECS service status
aws ecs describe-services --cluster ysweet-cluster --services ysweet-svc

# View logs
aws logs tail /ecs/ysweet --follow
```

**SSL certificate issues:**
```bash
# Check certificate status
aws acm describe-certificate --certificate-arn $(terraform output ssl_certificate_arn)
```

**S3 metrics not showing:**
- Metrics appear 24-48 hours after bucket has data
- Verify metrics are enabled: `aws s3api get-bucket-metrics-configuration --bucket $(terraform output -raw s3_bucket_name) --id EntireBucket`

**Cost monitoring not working:**
- Enable billing alerts in AWS Console (see Cost Monitoring section)
- Metrics update once daily

### **Useful Commands**

```bash
# Force service restart
aws ecs update-service --cluster ysweet-cluster --service ysweet-svc --force-new-deployment

# Get current logs
TASK_ID=$(aws ecs list-tasks --cluster ysweet-cluster --service-name ysweet-svc --query 'taskArns[0]' --output text | cut -d'/' -f3)
aws logs get-log-events --log-group-name "/ecs/ysweet" --log-stream-name "ecs/ysweet/$TASK_ID"

# Check domain resolution
dig ysweet.yourdomain.com
```

## 🔗 Quick Access Links

Get all important URLs with Terraform outputs:

```bash
# Application & monitoring
terraform output application_url          # Your Y-Sweet application
terraform output dashboard_url            # CloudWatch monitoring dashboard
terraform output cloudwatch_insights_url  # Advanced log analysis

# Setup & configuration  
terraform output billing_dashboard_setup  # Enable cost monitoring
terraform output s3_bucket_name          # Your document storage bucket
```

## 🏗️ Infrastructure Management

### **Remote State (Recommended)**

Use S3 backend for production deployments:

```bash
./setup-remote-state.sh
terraform init  # Migrate existing state when prompted
```

**Benefits:**
- Team collaboration
- State locking
- Backup and versioning
- No single point of failure

### **Scaling Considerations**

This infrastructure can be extended with:
- **Auto Scaling Groups** for automatic scaling
- **Multiple AZs** for higher availability  
- **CloudFront CDN** for global performance
- **RDS** for session/metadata storage
- **ElastiCache** for caching layer

### **Security Best Practices**

- ✅ IAM roles with least privilege
- ✅ Security groups with minimal access
- ✅ S3 encryption at rest
- ✅ HTTPS/TLS in transit
- ✅ VPC network isolation
- ✅ Authentication required for all operations

## 🧹 Cleanup

Remove all infrastructure:

```bash
terraform destroy
```

**Note:** This will permanently delete all documents in S3. Export any important data first.

## 📄 License

This infrastructure code is provided as-is under the MIT license. Y-Sweet itself is licensed under its own terms.