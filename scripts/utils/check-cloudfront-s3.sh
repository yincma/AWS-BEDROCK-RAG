#!/bin/bash

# CloudFront and S3 Configuration Check Script

set -e

echo "=== CloudFront and S3 Configuration Check ==="
echo

# Get CloudFront distribution details
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment,'enterprise-rag') && contains(Comment,'dev')].Id" --output text)

if [ -z "$DISTRIBUTION_ID" ]; then
    echo "❌ CloudFront distribution not found"
    exit 1
fi

echo "✅ Found CloudFront distribution: $DISTRIBUTION_ID"

# Get distribution config
DISTRIBUTION_CONFIG=$(aws cloudfront get-distribution-config --id $DISTRIBUTION_ID --query "DistributionConfig" --output json)

# Extract S3 bucket name
BUCKET_NAME=$(echo $DISTRIBUTION_CONFIG | jq -r '.Origins.Items[0].DomainName' | sed 's/.s3.amazonaws.com//')
echo "✅ S3 bucket: $BUCKET_NAME"

# Check OAI
OAI_PATH=$(echo $DISTRIBUTION_CONFIG | jq -r '.Origins.Items[0].S3OriginConfig.OriginAccessIdentity')
if [ "$OAI_PATH" != "null" ] && [ -n "$OAI_PATH" ]; then
    echo "✅ Origin Access Identity configured: $OAI_PATH"
else
    echo "❌ Origin Access Identity not configured"
fi

# Check S3 bucket policy
echo
echo "=== S3 Bucket Policy ==="
BUCKET_POLICY=$(aws s3api get-bucket-policy --bucket $BUCKET_NAME --query Policy --output text 2>/dev/null || echo "NO_POLICY")

if [ "$BUCKET_POLICY" = "NO_POLICY" ]; then
    echo "❌ No bucket policy found"
else
    echo "$BUCKET_POLICY" | jq .
    
    # Check if OAI is in the policy
    if echo "$BUCKET_POLICY" | grep -q "cloudfront:user"; then
        echo "✅ CloudFront OAI found in bucket policy"
    else
        echo "❌ CloudFront OAI not found in bucket policy"
    fi
fi

# Check public access block
echo
echo "=== S3 Public Access Block ==="
aws s3api get-public-access-block --bucket $BUCKET_NAME 2>/dev/null || echo "❌ Could not get public access block settings"

# Test file access
echo
echo "=== Testing File Access ==="

# Test direct S3 access (should fail)
echo -n "Testing direct S3 access: "
if curl -s -o /dev/null -w "%{http_code}" "https://${BUCKET_NAME}.s3.amazonaws.com/index.html" | grep -q "403"; then
    echo "✅ Direct access blocked (403)"
else
    echo "❌ Direct access not properly blocked"
fi

# Test CloudFront access (should succeed)
CLOUDFRONT_URL=$(echo $DISTRIBUTION_CONFIG | jq -r '.DomainName')
echo -n "Testing CloudFront access: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${CLOUDFRONT_URL}/")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ CloudFront access successful (200)"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ CloudFront access forbidden (403) - Check OAI configuration"
else
    echo "❌ CloudFront returned unexpected status: $HTTP_CODE"
fi

echo
echo "=== CloudFront Error Pages ==="
echo $DISTRIBUTION_CONFIG | jq '.CustomErrorResponses'

echo
echo "=== Recommendations ==="
if [ "$HTTP_CODE" = "403" ]; then
    echo "1. Run: terraform apply -target=module.frontend"
    echo "2. Ensure S3 bucket policy includes the CloudFront OAI"
    echo "3. Check if index.html exists in the S3 bucket"
    echo "4. Verify CloudFront distribution is using the correct OAI"
fi

echo
echo "To manually update bucket policy, use:"
echo "aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json"