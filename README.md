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

### Environment Variables

The container runs with:
- `PORT`: Application port (8080)
- `STORAGE_BUCKET`: S3 bucket name for document storage

### Command Override

The container runs Y-Sweet in multi-document mode:
```bash
y-sweet serve --host=0.0.0.0 s3://[BUCKET_NAME]
```

## Usage

### Creating Documents

Y-Sweet will automatically create new documents when clients connect to new document IDs:

```javascript
// WebSocket connection to create/join a document
const ws = new WebSocket('ws://your-alb-dns-name/doc/my-document-id');
```

### Health Checks

The ALB performs health checks on `/ready` endpoint.

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
- Security groups restrict traffic to required ports

## Troubleshooting

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
aws s3 ls s3://[BUCKET-NAME] --recursive
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

Or to get logs for a specific time period:
```bash
aws logs get-log-events \
  --log-group-name "/ecs/ysweet" \
  --log-stream-name "ecs/ysweet/[TASK-ID]" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region us-east-1
```

## License

This infrastructure code is provided as-is. Y-Sweet itself is licensed under its own terms.
