#!/bin/bash
set -e

# Deploy frontend application to S3
# Ensure configuration is consistent with Terraform

echo "🚀 Starting frontend deployment..."

# Check required environment variables
if [ -z "$S3_BUCKET" ]; then
    echo "❌ Error: S3_BUCKET environment variable not set"
    echo "Please set: export S3_BUCKET=your-bucket-name"
    exit 1
fi

# Generate configuration file
echo "📋 Generating configuration file..."
npm run generate-config

# Build application
echo "🔨 Building application..."
npm run build

# Upload to S3
echo "☁️  Uploading to S3..."
aws s3 sync build/ s3://$S3_BUCKET/ --delete --exclude "config.json"

# Note: config.json is excluded as it's managed by Terraform
echo "⚠️  Note: config.json is managed by Terraform, local version not uploaded"

# Invalidate CloudFront cache (if CLOUDFRONT_DISTRIBUTION_ID is set)
if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
    echo "🔄 Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
        --distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
        --paths "/*"
fi

echo "✅ Deployment complete!"
echo ""
echo "📝 Reminder:"
echo "   - config.json is managed by Terraform"
echo "   - To update configuration, modify Terraform variables and run terraform apply"