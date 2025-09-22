# Y-Sweet Multi-Document Server on AWS Fargate

This repository contains Terraform configuration to deploy [Y-Sweet](https://github.com/jamsocket/y-sweet), a Yjs sync server for real-time collaborative applications, on AWS Fargate with S3 storage.

## Architecture

This infrastructure deploys **Y-Sweet**, a collaborative document server built on Yjs for real-time collaborative editing (think Google Docs-style live collaboration). The setup is optimized for WebSocket connections and high-throughput document synchronization.

### 🏗️ **Infrastructure Components**

#### **1. Core Application (ECS Fargate)**
- **ECS Cluster**: Managed container orchestration
- **Fargate Task**: Single task with **4 vCPU + 8GB RAM** ("beast mode" for high concurrency)
- **Container**: Runs `y-sweet serve` with S3 backend storage
- **Networking**: Uses default VPC with public subnets and assigned public IPs

#### **2. Load Balancer & SSL**
- **Application Load Balancer (ALB)**: Internet-facing, handles HTTP/HTTPS traffic
- **Target Group**: Health checks on `/ready` endpoint with WebSocket optimizations
- **SSL Certificate**: Optional ACM certificate with DNS validation
- **Smart Routing**: 
  - SSL enabled: HTTP (80) → redirects to HTTPS (443)
  - SSL disabled: HTTP (80) → forwards directly to container
- **WebSocket Optimized**: 
  - 1-hour idle timeout for long-lived connections
  - 30-second deregistration delay for graceful shutdowns

#### **3. Storage Layer**
- **S3 Bucket**: Stores Y-Sweet documents with versioning and server-side encryption
- **Dual IAM Access Strategy**:
  - **ECS Task Role**: For container to access S3 via AWS SDK
  - **IAM User + Access Keys**: Programmatic access (passed as environment variables)

#### **4. Security**
- **ALB Security Group**: Allows HTTP (80) + HTTPS (443) from internet (0.0.0.0/0)
- **Task Security Group**: Restricts access to container port (8080) only from ALB
- **S3 Security**: Server-side encryption (AES256), public access blocked
- **Authentication**: Y-Sweet auth key required for all document operations

#### **5. Monitoring & Observability**
- **CloudWatch Logs**: Container logs with 7-day retention
- **Log Metric Filters**: Automatically tracks INFO/WARN/ERROR/TOTAL log counts
- **Comprehensive Dashboard**: Real-time monitoring of:
  - ECS metrics (CPU, memory, task health)
  - ALB performance (requests, response times, connections)
  - S3 storage metrics (bucket size, object count)
  - Document save activity and error tracking

### 🔄 **Data Flow**

```
Internet → ALB (HTTP/HTTPS) → ECS Fargate Task → Y-Sweet Server
                                       ↓
                              S3 Bucket (Document Storage)
                                       ↓
                            CloudWatch Logs (Monitoring)
```

### 🎯 **Use Case**

Perfect for hosting **collaborative document editing services** where:
- Multiple users edit documents simultaneously in real-time
- Changes sync instantly via WebSocket connections
- Document state persists reliably in S3 with versioning
- High availability with load balancing and health checks
- Secure SSL termination for production use
- Comprehensive monitoring for production operations

### ⚡ **Performance Characteristics**

- **High Concurrency**: 4 vCPU/8GB handles significant concurrent WebSocket connections
- **Low Latency**: Direct WebSocket upgrades through ALB
- **Scalable Storage**: S3 backend with versioning for document history
- **Fault Tolerant**: Health checks ensure service availability
- **Production Ready**: SSL/TLS, monitoring, and security best practices

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed (>= 1.0)
- Docker (for local testing/debugging)

## Deployment

### 1. Setup Remote State (Recommended)

For production use, configure Terraform to store state remotely in S3:

```bash
# Run the setup script to create S3 bucket and configure backend
./setup-remote-state.sh
```

This script will:
- Create an S3 bucket for Terraform state with encryption and versioning
- Automatically add the backend configuration to `main.tf`
- Set up state locking using S3's native capabilities (no DynamoDB needed)

### 2. Initialize Terraform
```bash
terraform init
```

If you ran the remote state setup, Terraform will offer to migrate your existing local state to S3. Choose "yes" when prompted.

### 3. Review the deployment plan
```bash
terraform plan
```

### 4. Deploy the infrastructure
```bash
terraform apply
```

### 5. Get the application URL
After deployment, the ALB DNS name will be output:
```bash
terraform output alb_dns_name
```

## Configuration

### Variables (terraform.tfvars)

- `region`: AWS region (default: us-east-1)
- `app_name`: Application name prefix (default: ysweet)
- `container_port`: Container port (default: 8080)
- `image`: Y-Sweet Docker image (default: ghcr.io/jamsocket/y-sweet)
- `bucket_name`: Human-readable S3 bucket name for document storage
- `auth_key`: Y-Sweet authentication key for production use
- `create_ssl_cert`: Enable HTTPS with SSL certificate (default: false)
- `domain_name`: Domain name for SSL certificate (required if create_ssl_cert = true)

### Environment Variables

The container runs with:
- `PORT`: Application port (8080)
- `STORAGE_BUCKET`: S3 bucket name for document storage
- `AUTH_KEY`: Authentication key for Y-Sweet
- `AWS_ACCESS_KEY_ID`: IAM user access key for S3
- `AWS_SECRET_ACCESS_KEY`: IAM user secret key for S3
- `AWS_DEFAULT_REGION`: AWS region for S3 operations
- `CORS_ALLOW_ORIGIN`: CORS origin policy (set to "*")
- `CORS_ALLOW_METHODS`: Allowed HTTP methods
- `CORS_ALLOW_HEADERS`: Allowed request headers

### Command Override

The container runs Y-Sweet in multi-document mode with authentication:
```bash
y-sweet serve --host=0.0.0.0 --auth=$AUTH_KEY s3://[BUCKET_NAME]
```

## Domain Setup

### Setting up Custom Domain (Required for SSL)

1. **Add CNAME record in your DNS provider**:
   - **Type**: CNAME
   - **Host**: `ysweet` (creates `ysweet.yourdomain.com`)
   - **Value**: `your-alb-dns-name.us-east-1.elb.amazonaws.com`
   - **TTL**: 300 seconds

2. **Verify DNS propagation**:
```bash
# Check against your DNS provider directly
dig @dns1.registrar-servers.com ysweet.yourdomain.com

# Test from your location
dig ysweet.yourdomain.com
```

3. **Test HTTP access**:
Once DNS propagates, test: `http://ysweet.yourdomain.com`

## SSL/HTTPS Setup (Optional)

### Enabling HTTPS

To enable HTTPS with SSL certificate:

1. **Ensure domain is working** (see Domain Setup above)

2. **Update terraform.tfvars**:
```hcl
create_ssl_cert = true
domain_name     = "ysweet.yourdomain.com"
```

3. **Deploy the changes**:
```bash
terraform apply
```

4. **Add DNS validation records**:
After deployment, add the CNAME record shown in Terraform output to your domain's DNS.

5. **Wait for validation**:
Certificate validation typically takes 5-10 minutes.

### HTTPS Benefits
- Secure WebSocket connections (`wss://`)
- Automatic HTTP to HTTPS redirect
- Better compatibility with strict CSP policies
- Modern TLS 1.2+ security

## Usage

### Creating Documents

Y-Sweet will automatically create new documents when clients connect to new document IDs:

```javascript
// HTTP connection
const ws = new WebSocket('ws://your-alb-dns-name/doc/my-document-id');

// HTTPS connection (if SSL enabled)
const wss = new WebSocket('wss://your-domain.com/doc/my-document-id');
```

### Authentication

All requests require authentication using the configured auth key:

```javascript
// Example with auth header
const headers = { 'Authorization': 'Bearer your-auth-key' };
```

### Health Checks

The ALB performs health checks on `/ready` endpoint.

## Document Storage

### Inspecting S3 Documents

View all stored documents:
```bash
aws s3 ls s3://your-bucket-name --recursive --human-readable --summarize
```

Basic listing:
```bash
aws s3 ls s3://your-bucket-name
```

Watch for new documents (refreshes every 5 seconds):
```bash
watch -n 5 'aws s3 ls s3://your-bucket-name --recursive --human-readable'
```

Get document metadata:
```bash
aws s3api head-object --bucket your-bucket-name --key document-id/data.ysweet
```

### Document Format
- Documents are stored as `.ysweet` files
- Each document gets its own UUID-based folder
- Format: `{document-uuid}/data.ysweet`

## Monitoring

- **CloudWatch Logs**: `/ecs/ysweet` log group
- **ECS Console**: Monitor service health and task status
- **ALB Target Groups**: Check target health status

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

## Security

- S3 bucket has server-side encryption enabled
- IAM roles follow least privilege principle
- ECS tasks only have necessary S3 permissions
- Security groups restrict traffic to required ports (80, 443)
- Y-Sweet authentication required for all operations
- Optional HTTPS/TLS encryption for secure connections
- CORS configured to accept connections from any origin

## Troubleshooting

### DNS Issues
Check if domain is resolving correctly:
```bash
# Test against authoritative name server
dig @dns1.registrar-servers.com ysweet.yourdomain.com

# Test from your location
nslookup ysweet.yourdomain.com
```

### Check container logs
```bash
aws logs get-log-events \
  --log-group-name "/ecs/ysweet" \
  --log-stream-name "ecs/ysweet/[TASK-ID]" \
  --region us-east-1
```

### Check ECS service status
```bash
aws ecs describe-services \
  --cluster ysweet-cluster \
  --services ysweet-svc \
  --region us-east-1
```

### Check S3 bucket contents
```bash
aws s3 ls s3://y-sweet-crixet-dev-storage --recursive --human-readable
```

### Check certificate status (if SSL enabled)
```bash
aws acm describe-certificate --certificate-arn [CERT-ARN] --region us-east-1
```

### Restart the service
To force a restart/redeploy of the Y-Sweet service:
```bash
aws ecs update-service \
  --cluster ysweet-cluster \
  --service ysweet-svc \
  --force-new-deployment \
  --region us-east-1
```

### Tail container logs in real-time
To follow the logs from the running container:
```bash
aws logs tail /ecs/ysweet --follow --region us-east-1
```

### View all logs for current container
Get current task ID and view all logs:
```bash
# Get current task ID
aws ecs list-tasks --cluster ysweet-cluster --service-name ysweet-svc --region us-east-1

# View all logs for specific task
aws logs get-log-events \
  --log-group-name "/ecs/ysweet" \
  --log-stream-name "ecs/ysweet/[TASK-ID]" \
  --region us-east-1
```

### Get recent logs (last hour)
```bash
aws logs get-log-events \
  --log-group-name "/ecs/ysweet" \
  --log-stream-name "ecs/ysweet/[TASK-ID]" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region us-east-1
```

### One-liner to get current logs
```bash
TASK_ID=$(aws ecs list-tasks --cluster ysweet-cluster --service-name ysweet-svc --region us-east-1 --query 'taskArns[0]' --output text | cut -d'/' -f3) && aws logs get-log-events --log-group-name "/ecs/ysweet" --log-stream-name "ecs/ysweet/$TASK_ID" --region us-east-1
```

### S3 Storage Metrics Not Showing in Dashboard

If the "S3 Storage - Bucket Size & Object Count (Daily)" dashboard widget shows no data:

1. **Check if metrics are enabled** (should be handled by Terraform):
```bash
aws s3api get-bucket-metrics-configuration --bucket $(terraform output -raw s3_bucket_name) --id EntireBucket
```

2. **Verify bucket has data**:
```bash
aws s3 ls s3://$(terraform output -raw s3_bucket_name) --recursive --human-readable --summarize
```

3. **Check if CloudWatch metrics exist**:
```bash
aws cloudwatch list-metrics --namespace AWS/S3 --metric-name BucketSizeBytes --dimensions Name=BucketName,Value=$(terraform output -raw s3_bucket_name)
```

**Note**: S3 storage metrics are updated **once daily** and may take 24-48 hours to appear after enabling metrics configuration. The metrics will only show data from the point when metrics were enabled forward.

## Observability & Monitoring

### 📊 **CloudWatch Dashboard**

A comprehensive monitoring dashboard is automatically created with your deployment:

```bash
# Access your main dashboard
terraform output dashboard_url
```

**Direct link:** `https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=ysweet-dashboard`

The dashboard includes the following monitoring widgets:

### 📊 **Performance Metrics**
- **CPU & Memory Utilization**: Track ECS service resource usage
- **Task Counts**: Monitor running, pending, and desired task counts
- **Request Metrics**: View ALB request count, response times, and HTTP status codes

### 🔗 **Connection Metrics**
- **ALB Connections**: Active, new, and rejected connection counts
- **Health Status**: Healthy vs unhealthy target counts
- **WebSocket Support**: Monitor long-lived connection performance

### 💾 **Storage Metrics**
- **S3 Bucket Size**: Track document storage growth
- **Object Count**: Monitor number of Y-Sweet documents

### 📋 **Error Monitoring**
- **Recent Error Logs**: Real-time view of application errors from CloudWatch logs

### 🎯 **Key Metrics to Watch**
- **CPU > 80%**: Consider scaling up if sustained
- **Memory > 80%**: Monitor for memory leaks or increase allocation
- **4XX/5XX Errors**: Investigate application or infrastructure issues
- **Unhealthy Targets**: Check container health and startup time
- **High Response Time**: Monitor WebSocket upgrade and document operations

The dashboard automatically refreshes and provides 5-minute granularity for most metrics, with S3 metrics updating daily.

### 🔍 **CloudWatch Logs Insights**

Advanced log analysis with pre-configured saved queries:

```bash
# Access CloudWatch Insights console
terraform output cloudwatch_insights_url
```

**Direct link:** `https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logs:insights`

#### **Pre-configured Saved Queries**

The following saved queries are automatically created for easy log analysis:

1. **`ysweet-websocket-connections`**
   ```sql
   fields @timestamp, @message
   | filter @message like /WebSocket/
   | stats count() as connections by bin(5m)
   | sort @timestamp desc
   ```
   *Monitors WebSocket connection patterns and volume*

2. **`ysweet-document-operations`**
   ```sql
   fields @timestamp, @message
   | filter @message like /Persisting snapshot/ or @message like /Loading document/
   | parse @message "size=* " as doc_size
   | stats count() as operations, avg(doc_size) as avg_size by bin(5m)
   | sort @timestamp desc
   ```
   *Tracks document save/load operations and sizes*

3. **`ysweet-error-analysis`**
   ```sql
   fields @timestamp, @message
   | filter @message like /ERROR/ or @message like /WARN/ or @message like /Failed/
   | stats count() as error_count by @message
   | sort error_count desc
   | limit 20
   ```
   *Analyzes error patterns and frequency*

4. **`ysweet-performance-monitoring`**
   ```sql
   fields @timestamp, @message
   | filter @message like /ms/ or @message like /seconds/
   | parse @message /(?<duration>\d+)(ms|seconds)/
   | stats avg(duration) as avg_duration, max(duration) as max_duration by bin(5m)
   | sort @timestamp desc
   ```
   *Monitors performance metrics and timing*

#### **Custom Log Analysis**

You can also run custom queries directly:

```bash
# Example: Find recent WebSocket activity
aws logs start-query \
  --log-group-name "/ecs/ysweet" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /WebSocket/ | sort @timestamp desc | limit 20'
```

### 💰 **Cost Monitoring**

Real-time AWS cost tracking integrated into your dashboard:

#### **Setup Required (One-time)**
```bash
# Get the setup link
terraform output billing_dashboard_setup
```

**Manual step:** Visit `https://console.aws.amazon.com/billing/home#/preferences` and enable:
- ✅ **Receive Billing Alerts**

This enables the cost monitoring widgets in your dashboard.

#### **Cost Dashboard Widgets**
- **Total Monthly Charges**: Account-wide estimated costs
- **Service Breakdown**: Costs by service (ECS, S3, EC2, CloudWatch)
- **Daily Tracking**: 24-hour cost accumulation

**Note**: Billing metrics update once daily and may take 24 hours to appear after enabling billing alerts.

## Manual Setup Requirements

Some AWS features require manual configuration outside of Terraform:

### 📊 **Billing Alerts (Required for Cost Monitoring)**

**Why manual?** AWS billing preferences can't be managed via Terraform for security reasons.

**Setup steps:**
1. Visit: `https://console.aws.amazon.com/billing/home#/preferences`
2. Enable: ✅ **Receive Billing Alerts**
3. Cost widgets will populate within 24 hours

**Alternative CLI approach** (may not work in all accounts):
```bash
# Attempt to enable via Budgets API (creates a minimal budget)
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName":"EnableBillingMetrics",
    "BudgetLimit":{"Amount":"1","Unit":"USD"},
    "TimeUnit":"MONTHLY",
    "BudgetType":"COST"
  }' \
  --notifications-with-subscribers '[]'
```

### 🔍 **S3 Metrics (Handled by Terraform)**

S3 storage metrics are automatically enabled via Terraform:
```hcl
resource "aws_s3_bucket_metric" "ysweet_storage_metrics" {
  bucket = aws_s3_bucket.ysweet_storage.id
  name   = "EntireBucket"
}
```

**No manual action required** - metrics will appear 24-48 hours after bucket has data.

## Quick Access Links

All monitoring dashboards and tools:

```bash
# Main CloudWatch Dashboard
terraform output dashboard_url

# CloudWatch Insights (log analysis)  
terraform output cloudwatch_insights_url

# Billing setup page
terraform output billing_dashboard_setup

# Application URL
terraform output application_url
```

## License

This infrastructure code is provided as-is. Y-Sweet itself is licensed under its own terms.
