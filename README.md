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
# Create terraform.tfvars with your configuration (see Configuration section below)

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
- High-performance WebSocket handling for concurrent connections
- Real-time collaborative document synchronization
- SSL/TLS termination with automatic certificate validation
- Comprehensive monitoring and cost tracking
- Production-ready security and fault tolerance

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

## 🪣 S3 Bucket Setup

**Important:** The S3 bucket for Y-Sweet document storage is **not managed by Terraform**. You must create and configure it manually before running Terraform.

### **1. Create the S3 Bucket**

```bash
# Replace 'y-crixet' with your desired bucket name
export BUCKET_NAME="y-crixet"
export AWS_REGION="us-east-1"  # or your preferred region

# Create the bucket
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION
```

### **2. Configure Bucket Settings**

```bash
# Enable versioning (recommended for data protection)
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable server-side encryption (recommended for security)
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Enable CloudWatch metrics (required for dashboard monitoring)
aws s3api put-bucket-metrics-configuration \
  --bucket $BUCKET_NAME \
  --id EntireBucket \
  --metrics-configuration Id=EntireBucket
```

### **3. Verify Bucket Configuration**

After creating a new bucket OR to verify an existing bucket is properly configured:

```bash
# Replace with your actual bucket name
BUCKET_NAME="y-crixet"

# Check versioning
aws s3api get-bucket-versioning --bucket $BUCKET_NAME
# Expected output: {"Status": "Enabled"}

# Check encryption
aws s3api get-bucket-encryption --bucket $BUCKET_NAME
# Expected output: {"ServerSideEncryptionConfiguration": {"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}}

# Check metrics
aws s3api get-bucket-metrics-configuration --bucket $BUCKET_NAME --id EntireBucket
# Expected output: {"MetricsConfiguration": {"Id": "EntireBucket"}}
```

**Note:** Once created, update the `bucket_name` variable in your `terraform.tfvars` to match your bucket name.

## 🔐 Authentication Setup

The Y-Sweet authentication key is stored securely in AWS Secrets Manager instead of plaintext in your configuration.

### **Create the Auth Key Secret**

```bash
# Create a secure random auth key
AUTH_KEY=$(openssl rand -base64 32)

# Store it in Secrets Manager
aws secretsmanager create-secret \
  --name "ysweet-auth-key" \
  --description "Y-Sweet authentication key" \
  --secret-string "$AUTH_KEY" \
  --region us-east-1

# Get the ARN for your terraform.tfvars
aws secretsmanager describe-secret \
  --secret-id "ysweet-auth-key" \
  --region us-east-1 \
  --query 'ARN' \
  --output text
```

**Copy the ARN output** and use it as the `ysweet_auth_key_secret_arn` value in your `terraform.tfvars`.

## ⚙️ Configuration

### **Required Variables**

Create `terraform.tfvars` with these required values:

```hcl
# Required
image                      = "732560673613.dkr.ecr.us-east-1.amazonaws.com/y-sweet:latest"
bucket_name                = "y-crixet"
ysweet_auth_key_secret_arn = "arn:aws:secretsmanager:us-east-1:732560673613:secret:ysweet-auth-key-p4qg7y"

# Optional SSL setup
create_ssl_cert = true
domain_name     = "ysweet.crixet.com"

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
| `ysweet_auth_key_secret_arn` | string | **required** | ARN of Secrets Manager secret containing AUTH_KEY |
| `domain_name` | string | `""` | Domain for SSL certificate |
| `create_ssl_cert` | bool | `false` | Whether to create SSL certificate |
| `log_level` | string | `error` | Y-Sweet log level (error, warn, info, debug, trace) |
| `enable_dev_server` | bool | `false` | Whether to create a development server instance |
| `dev_image` | string | `""` | Y-Sweet Docker image for dev server (optional, uses main image if not specified) |
| `dev_bucket_name` | string | `""` | S3 bucket for dev storage (optional, uses main bucket if not specified) |
| `dev_domain_name` | string | `""` | Domain for dev server SSL certificate |
| `create_dev_ssl_cert` | bool | `false` | Whether to create SSL certificate for dev server |

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
- `ysweet-error-analysis` - Error and warning pattern analysis
- `ysweet-s3-slowdown-analysis` - S3 SlowDown retry analysis with method/attempt/delay breakdown

### **S3 API Monitoring**
S3 storage monitoring is handled through the standard ECS application logs and CloudWatch metrics.


## 🔒 SSL/HTTPS Setup

### **Overview**

Y-Sweet supports SSL/HTTPS for secure WebSocket connections. The infrastructure automatically creates and validates SSL certificates using AWS Certificate Manager (ACM) with DNS validation.

### **1. Basic SSL Setup (Production)**

#### **Step 1: Configure SSL in terraform.tfvars**
```hcl
create_ssl_cert = true
domain_name     = "ysweet.crixet.com"
```

#### **Step 2: Apply Configuration to Create Certificate**
```bash
# Create the certificate first (it will be in PENDING_VALIDATION status)
terraform apply -target=aws_acm_certificate.this
```

#### **Step 3: Get DNS Validation Records**
```bash
# Get the certificate ARN from output
CERT_ARN=$(terraform output -raw ssl_certificate_arn)

# Get DNS validation record in table format
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output table
```

#### **Step 4: Add DNS Validation Record**
Add the CNAME record from Step 3 to your DNS provider.

#### **Step 5: Complete Setup**
See **Section 3: Complete DNS Setup** below for certificate validation and application DNS records.

### **2. Development Server SSL Setup**

The development server can also have SSL configured with its own domain:

#### **Configure Dev SSL in terraform.tfvars**
```hcl
# Enable development server with SSL
enable_dev_server    = true
create_dev_ssl_cert  = true
dev_domain_name      = "ysweet.dev.crixet.com"
```

#### **Get Dev Certificate DNS Validation Records**
```bash
# Apply to create dev certificate
terraform apply -target=aws_acm_certificate.dev

# Get dev certificate validation record
DEV_CERT_ARN=$(terraform output -raw dev_ssl_certificate_arn)
aws acm describe-certificate \
  --certificate-arn $DEV_CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output table
```

### **3. Complete DNS Setup**

After creating certificates for both production and dev (if enabled), add the DNS validation records from steps 1 and 2 to your DNS provider, then:

```bash
# Wait 5-15 minutes for DNS propagation, then validate certificates
terraform apply -target=aws_acm_certificate_validation.this      # Production
terraform apply -target=aws_acm_certificate_validation.dev       # Dev (if enabled)

# Complete the full deployment
terraform apply
```

Add CNAME records pointing your domains to the load balancers:
- `ysweet.crixet.com` → `$(terraform output -raw alb_dns_name)`
- `ysweet.dev.crixet.com` → `$(terraform output -raw dev_alb_dns_name)` (if dev enabled)

### **4. Certificate Status Monitoring**

#### **Check Certificate Status**
```bash
# Production certificate
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw ssl_certificate_arn) \
  --query 'Certificate.Status' \
  --output text

# Development certificate (if enabled)
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw dev_ssl_certificate_arn) \
  --query 'Certificate.Status' \
  --output text
```

#### **Monitor Certificate Validation**
```bash
# Watch certificate status (runs every 30 seconds)
watch -n 30 'aws acm describe-certificate --certificate-arn $(terraform output -raw ssl_certificate_arn) --query "Certificate.Status" --output text'
```

### **5. Troubleshooting SSL Issues**

#### **Certificate Validation Timeout**
If certificate validation times out (5 minutes):

**Production Certificate:**
```bash
# 1. Destroy the failed certificate resources
terraform destroy -target=aws_acm_certificate_validation.this -target=aws_acm_certificate.this

# 2. Recreate the certificate
terraform apply -target=aws_acm_certificate.this

# 3. Get new validation records and add to DNS
aws acm describe-certificate --certificate-arn $(terraform output -raw ssl_certificate_arn) --query 'Certificate.DomainValidationOptions[0].ResourceRecord' --output table

# 4. Wait for DNS propagation (5-15 minutes) then validate
terraform apply -target=aws_acm_certificate_validation.this

# 5. Complete deployment
terraform apply
```

**Dev Certificate (if enabled):**
```bash
# 1. Destroy the failed dev certificate resources
terraform destroy -target=aws_acm_certificate_validation.dev -target=aws_acm_certificate.dev

# 2. Recreate the dev certificate
terraform apply -target=aws_acm_certificate.dev

# 3. Get new dev validation records and add to DNS
aws acm describe-certificate --certificate-arn $(terraform output -raw dev_ssl_certificate_arn) --query 'Certificate.DomainValidationOptions[0].ResourceRecord' --output table

# 4. Wait for DNS propagation (5-15 minutes) then validate
terraform apply -target=aws_acm_certificate_validation.dev

# 5. Complete deployment
terraform apply
```

#### **DNS Propagation Check**
```bash
# Check if DNS validation record is propagated (replace _VALIDATION_RECORD with actual record from ACM output)
dig _VALIDATION_RECORD.ysweet.crixet.com CNAME

# Check from multiple DNS servers
dig @8.8.8.8 _VALIDATION_RECORD.ysweet.crixet.com CNAME
dig @1.1.1.1 _VALIDATION_RECORD.ysweet.crixet.com CNAME
```




## 🚀 Development Server

Optional development server with smaller resources (0.5 vCPU, 1GB RAM), separate logging, and optional SSL.

### **Enable Dev Server**

Add to your `terraform.tfvars`:

```hcl
# Enable development server
enable_dev_server = true

# Optional: Use different image for dev
dev_image = "732560673613.dkr.ecr.us-east-1.amazonaws.com/y-sweet:dev"

# Optional: Use separate S3 bucket for dev
dev_bucket_name = "y-sweet-crixet-dev-storage"
```

```bash
terraform apply
```

### **Access Dev Server**

```bash
# Get dev server URL
terraform output dev_application_url

# Test dev server health
curl $(terraform output -raw dev_application_url)/ready
```

### **Dev Server Logging**

The dev server has its own separate CloudWatch log group: `/ecs/ysweet-dev`

```bash
# View dev server logs
aws logs tail "/ecs/ysweet-dev" --follow

# Get dev server connection string
aws logs filter-log-events --log-group-name "/ecs/ysweet-dev" --filter-pattern "CONNECTION_STRING"
```

## 🔧 Usage

### **Document Operations**

Y-Sweet automatically creates documents when clients connect:

```javascript
// WebSocket connection
const ws = new WebSocket('wss://ysweet.crixet.com/doc/my-document-id');

// Authentication required (get auth key from AWS Secrets Manager)
const headers = { 'Authorization': 'Bearer <YOUR_AUTH_KEY>' };
```

### **Accessing Your Y-Sweet Servers**

#### **Production Server**
```bash
# Get production connection string from logs
aws logs filter-log-events --log-group-name "/ecs/ysweet" --filter-pattern "CONNECTION_STRING" --query 'events[0].message' --output text

# View production logs
aws logs tail "/ecs/ysweet" --follow

# Get production server URL
terraform output application_url
```

#### **Development Server** (if enabled)
```bash
# Get dev connection string from logs
aws logs filter-log-events --log-group-name "/ecs/ysweet-dev" --filter-pattern "CONNECTION_STRING" --query 'events[0].message' --output text

# View dev logs
aws logs tail "/ecs/ysweet-dev" --follow

# Get dev server URL
terraform output dev_application_url
```

**Example connection strings:**
- Non-SSL: `ys://auth-token@$(terraform output -raw alb_dns_name):8080`
- SSL: `yss://auth-token@ysweet.crixet.com/`

The connection string format is: `ys[s]://[auth-token]@[host]/`

### **Document Storage**

Documents are stored in S3 with this structure:
```
s3://y-crixet/
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
dig ysweet.crixet.com
```

## 🔗 Quick Access Links

Get all important URLs with Terraform outputs:

```bash
# Application & monitoring
terraform output application_url          # Your Y-Sweet production application
terraform output dev_application_url      # Your Y-Sweet dev application (if enabled)
terraform output dashboard_url            # CloudWatch monitoring dashboard
terraform output cloudwatch_insights_url  # Advanced log analysis

# Setup & configuration  
terraform output s3_bucket_name          # Your document storage bucket
```

## 🏗️ Infrastructure Management

### **Remote State (Recommended)**

Use S3 backend for production deployments:

```bash
./setup-remote-state.sh
terraform init  # Migrate existing state when prompted
```
## 🧹 Cleanup

Remove all infrastructure:

```bash
terraform destroy
```

**Note:** This will permanently delete all documents in S3. Export any important data first.

## 🐳 Building and Deploying Custom Y-Sweet Image

If you want to build and deploy a custom Y-Sweet image from the included submodule:

### Prerequisites

- Docker installed and running
- AWS CLI configured with appropriate permissions
- Y-Sweet submodule initialized (`git submodule update --init --recursive`)

### Quick Build and Deploy

Use the included automated script:

```bash
# Build and push with auto-incrementing version
./build-and-push.sh v7

# Build and push as latest
./build-and-push.sh

# Build development version
./build-and-push.sh dev
```

## 📄 License

This infrastructure code is provided as-is under the MIT license. Y-Sweet itself is licensed under its own terms.