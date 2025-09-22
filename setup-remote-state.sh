#!/bin/bash

# Simple script to set up S3 backend for Terraform state
# This follows AWS 2024 best practices
# Safe to run multiple times (idempotent)

set -e

# Configuration
BUCKET_NAME="ysweet-terraform-state"
REGION="us-east-1"  # Change this to match your region
KEY="ysweet-fargate/terraform.tfstate"

echo "Setting up Terraform remote state in S3..."
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo "Key: $KEY"
echo ""

# Check if bucket already exists
echo "Checking if S3 bucket exists..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "✅ S3 bucket '$BUCKET_NAME' already exists, skipping creation."
else
    echo "Creating S3 bucket..."
    aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
    echo "✅ S3 bucket created successfully!"
fi

# Enable versioning (safe to run multiple times)
echo "Ensuring versioning is enabled..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
echo "✅ Versioning enabled"

# Enable encryption (safe to run multiple times)
echo "Ensuring encryption is enabled..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'
echo "✅ Encryption enabled"

# Block public access (safe to run multiple times)
echo "Ensuring public access is blocked..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "✅ Public access blocked"

echo ""
echo "🔧 Updating main.tf with backend configuration..."

# Check if backend is already configured
if grep -q "backend \"s3\"" main.tf; then
    echo "⚠️  Backend configuration already exists in main.tf, skipping update."
else
    # Add backend configuration to terraform block
    # First, check if terraform block exists
    if grep -q "terraform {" main.tf; then
        # Insert backend config after terraform { line
        sed -i '/terraform {/a\
  backend "s3" {\
    bucket         = "'"$BUCKET_NAME"'"\
    key            = "'"$KEY"'"\
    region         = "'"$REGION"'"\
    use_lockfile   = true\
  }\
' main.tf
        echo "✅ Backend configuration added to main.tf"
    else
        echo "❌ Error: No terraform block found in main.tf"
        exit 1
    fi
fi

echo ""
echo "🚀 Setup complete! Next steps:"
echo ""
echo "1. Run: terraform init"
echo "   This will initialize the S3 backend and offer to migrate your existing state."
echo ""
echo "2. Choose 'yes' when prompted to copy existing state to the new backend."
echo ""
echo "3. Your state will now be stored in: s3://$BUCKET_NAME/$KEY"
echo ""
echo "🔒 Your Terraform state is now:"
echo "   • Stored remotely in S3"
echo "   • Encrypted at rest"
echo "   • Versioned for safety"
echo "   • Locked to prevent conflicts"
