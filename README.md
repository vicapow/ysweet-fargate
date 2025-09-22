# Y-Sweet Multi-Document Server on AWS Fargate

This repository contains Terraform configuration to deploy [Y-Sweet](https://github.com/jamsocket/y-sweet), a Yjs sync server for real-time collaborative applications, on AWS Fargate with S3 storage.

## Architecture

- **ECS Fargate**: Runs Y-Sweet in multi-document mode
- **Application Load Balancer**: Public HTTP/WebSocket access
- **S3 Storage**: Persistent document storage with encryption (human-readable bucket names)
- **CloudWatch Logs**: Container logging
- **IAM Roles**: Secure S3 access permissions

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed (>= 1.0)
- Docker (for local testing/debugging)

## Deployment

### 1. Initialize Terraform
```bash
terraform init
```

### 2. Review the deployment plan
```bash
terraform plan
```

### 3. Deploy the infrastructure
```bash
terraform apply
```

### 4. Get the application URL
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

## CloudWatch Dashboard

A comprehensive monitoring dashboard is automatically created for your Y-Sweet deployment. After deployment, you can access it at:

```
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=ysweet-dashboard
```

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

## License

This infrastructure code is provided as-is. Y-Sweet itself is licensed under its own terms.
