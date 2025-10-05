#!/bin/bash

# Enable S3 CloudWatch Request Metrics Script
# This enables the request metrics that appear in your CloudWatch dashboard

set -e

echo "🔧 Enabling S3 CloudWatch Request Metrics..."

# Get bucket names from Terraform outputs
MAIN_BUCKET=$(terraform output -raw bucket_name 2>/dev/null || echo "y-crixet")
DEV_BUCKET=$(terraform output -raw dev_bucket_name 2>/dev/null || echo "")

echo "📦 Main bucket: $MAIN_BUCKET"
if [ ! -z "$DEV_BUCKET" ]; then
    echo "📦 Dev bucket: $DEV_BUCKET"
fi

# Function to enable metrics for a bucket
enable_bucket_metrics() {
    local bucket=$1
    
    echo "🔍 Checking if bucket $bucket exists..."
    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        echo "✅ Bucket $bucket exists"
        
        echo "📊 Enabling CloudWatch request metrics for $bucket..."
        aws s3api put-bucket-metrics-configuration \
            --bucket "$bucket" \
            --id EntireBucket \
            --metrics-configuration 'Id=EntireBucket'
        
        echo "✅ CloudWatch request metrics enabled for $bucket"
    else
        echo "❌ Bucket $bucket does not exist or is not accessible"
        echo "💡 Please ensure the bucket exists and you have the necessary permissions"
    fi
}

# Enable metrics for main bucket
enable_bucket_metrics "$MAIN_BUCKET"

# Enable metrics for dev bucket if it exists
if [ ! -z "$DEV_BUCKET" ]; then
    enable_bucket_metrics "$DEV_BUCKET"
fi

echo ""
echo "🎉 S3 CloudWatch Request Metrics setup complete!"
echo ""
echo "📊 What this enables:"
echo "   • AllRequests, GetRequests, PutRequests metrics"
echo "   • 4xxErrors, 5xxErrors metrics"
echo "   • FirstByteLatency, TotalRequestLatency metrics"
echo ""
echo "🔍 View metrics:"
echo "   • CloudWatch Dashboard: terraform output dashboard_url"
echo "   • CloudWatch Console: https://console.aws.amazon.com/cloudwatch/home?region=$(terraform output -raw region)#metricsV2:graph=~();query=AWS%2FS3"
echo ""
echo "⏱️  Note: It may take up to 15 minutes for metrics to start appearing"


