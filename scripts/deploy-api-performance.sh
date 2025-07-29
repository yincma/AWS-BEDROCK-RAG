#!/bin/bash

# API Performance Optimization Deployment Script
# This script helps deploy and manage API Gateway and CloudFront performance optimizations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENVIRONMENT="${ENVIRONMENT:-dev}"
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure/terraform"
ENABLE_CACHE="${ENABLE_CACHE:-false}"
ENABLE_CDN="${ENABLE_CDN:-false}"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy and manage API performance optimizations for AWS RAG system.

OPTIONS:
    -e, --environment ENV     Environment to deploy to (dev|staging|prod) [default: dev]
    -c, --enable-cache       Enable API Gateway caching
    -d, --enable-cdn         Enable CloudFront CDN
    -p, --plan-only          Run terraform plan only
    -m, --metrics            Show current performance metrics
    -i, --invalidate-cache   Invalidate CloudFront cache
    -h, --help              Show this help message

EXAMPLES:
    # Deploy with caching and CDN for production
    $0 -e prod -c -d

    # Plan changes for staging
    $0 -e staging -c -p

    # Show performance metrics
    $0 -m

    # Invalidate CloudFront cache
    $0 -i
EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check for required tools
    for tool in aws terraform jq; do
        if ! command -v $tool &> /dev/null; then
            print_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    print_success "All prerequisites met."
}

# Function to get current configuration
get_current_config() {
    print_status "Getting current configuration..."
    
    # Get API Gateway info
    API_ID=$(aws apigateway get-rest-apis --query "items[?name=='rag-api-${ENVIRONMENT}'].id" --output text 2>/dev/null || echo "")
    
    if [ -n "$API_ID" ]; then
        STAGE_INFO=$(aws apigateway get-stage --rest-api-id "$API_ID" --stage-name "$ENVIRONMENT" 2>/dev/null || echo "{}")
        CACHE_ENABLED=$(echo "$STAGE_INFO" | jq -r '.cacheClusterEnabled // false')
        CACHE_SIZE=$(echo "$STAGE_INFO" | jq -r '.cacheClusterSize // "N/A"')
        
        print_status "API Gateway ID: $API_ID"
        print_status "Cache Enabled: $CACHE_ENABLED"
        print_status "Cache Size: $CACHE_SIZE"
    else
        print_warning "No API Gateway found for environment: $ENVIRONMENT"
    fi
    
    # Get CloudFront info
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='rag-api-${ENVIRONMENT} CloudFront distribution'].Id" --output text 2>/dev/null || echo "")
    
    if [ -n "$DISTRIBUTION_ID" ]; then
        print_status "CloudFront Distribution ID: $DISTRIBUTION_ID"
    else
        print_status "No CloudFront distribution found"
    fi
}

# Function to show performance metrics
show_metrics() {
    print_status "Fetching performance metrics..."
    
    if [ -z "$API_ID" ]; then
        print_error "No API Gateway found. Please deploy first."
        return 1
    fi
    
    # Get API Gateway metrics
    print_status "\nAPI Gateway Metrics (last 1 hour):"
    
    # Average latency
    LATENCY=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ApiGateway \
        --metric-name Latency \
        --dimensions Name=ApiName,Value="rag-api-${ENVIRONMENT}" Name=Stage,Value="$ENVIRONMENT" \
        --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 3600 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")
    
    print_status "Average Latency: ${LATENCY}ms"
    
    # Request count
    REQUESTS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ApiGateway \
        --metric-name Count \
        --dimensions Name=ApiName,Value="rag-api-${ENVIRONMENT}" Name=Stage,Value="$ENVIRONMENT" \
        --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "N/A")
    
    print_status "Total Requests: ${REQUESTS}"
    
    if [ "$CACHE_ENABLED" == "true" ]; then
        # Cache hit rate
        CACHE_HITS=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name CacheHitCount \
            --dimensions Name=ApiName,Value="rag-api-${ENVIRONMENT}" Name=Stage,Value="$ENVIRONMENT" \
            --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 3600 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        CACHE_MISSES=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/ApiGateway \
            --metric-name CacheMissCount \
            --dimensions Name=ApiName,Value="rag-api-${ENVIRONMENT}" Name=Stage,Value="$ENVIRONMENT" \
            --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 3600 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$CACHE_HITS" != "N/A" ] && [ "$CACHE_MISSES" != "N/A" ]; then
            TOTAL_CACHE=$((CACHE_HITS + CACHE_MISSES))
            if [ $TOTAL_CACHE -gt 0 ]; then
                HIT_RATE=$((CACHE_HITS * 100 / TOTAL_CACHE))
                print_status "Cache Hit Rate: ${HIT_RATE}%"
            fi
        fi
    fi
    
    # CloudFront metrics
    if [ -n "$DISTRIBUTION_ID" ]; then
        print_status "\nCloudFront Metrics (last 1 hour):"
        
        CF_REQUESTS=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/CloudFront \
            --metric-name Requests \
            --dimensions Name=DistributionId,Value="$DISTRIBUTION_ID" \
            --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 3600 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text \
            --region us-east-1 2>/dev/null || echo "N/A")
        
        print_status "CloudFront Requests: ${CF_REQUESTS}"
    fi
}

# Function to invalidate CloudFront cache
invalidate_cache() {
    if [ -z "$DISTRIBUTION_ID" ]; then
        print_error "No CloudFront distribution found."
        return 1
    fi
    
    print_status "Creating CloudFront invalidation..."
    
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    print_success "Invalidation created: $INVALIDATION_ID"
    print_status "Waiting for invalidation to complete..."
    
    aws cloudfront wait invalidation-completed \
        --distribution-id "$DISTRIBUTION_ID" \
        --id "$INVALIDATION_ID"
    
    print_success "Cache invalidation completed."
}

# Function to deploy performance optimizations
deploy_optimizations() {
    print_status "Deploying performance optimizations for environment: $ENVIRONMENT"
    
    cd "$TERRAFORM_DIR"
    
    # Set Terraform variables
    export TF_VAR_environment="$ENVIRONMENT"
    export TF_VAR_enable_caching="$ENABLE_CACHE"
    export TF_VAR_enable_cloudfront="$ENABLE_CDN"
    
    # Load environment-specific variables
    if [ -f "environments/${ENVIRONMENT}/api-performance.tfvars" ]; then
        TFVARS_FILE="-var-file=environments/${ENVIRONMENT}/api-performance.tfvars"
    else
        TFVARS_FILE=""
    fi
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init -upgrade
    
    # Plan changes
    print_status "Planning changes..."
    terraform plan $TFVARS_FILE -out=tfplan
    
    if [ "$PLAN_ONLY" == "true" ]; then
        print_success "Plan completed. Review the changes above."
        return 0
    fi
    
    # Apply changes
    print_warning "This will apply the changes shown above."
    read -p "Do you want to continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        print_warning "Deployment cancelled."
        return 0
    fi
    
    print_status "Applying changes..."
    terraform apply tfplan
    
    print_success "Performance optimizations deployed successfully!"
    
    # Show post-deployment information
    print_status "\nPost-deployment information:"
    
    if [ "$ENABLE_CDN" == "true" ]; then
        CDN_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null || echo "")
        if [ -n "$CDN_DOMAIN" ]; then
            print_success "CloudFront Domain: https://${CDN_DOMAIN}"
        fi
    fi
    
    DASHBOARD_URL=$(terraform output -raw performance_dashboard_url 2>/dev/null || echo "")
    if [ -n "$DASHBOARD_URL" ]; then
        print_success "Performance Dashboard: $DASHBOARD_URL"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -c|--enable-cache)
                ENABLE_CACHE="true"
                shift
                ;;
            -d|--enable-cdn)
                ENABLE_CDN="true"
                shift
                ;;
            -p|--plan-only)
                PLAN_ONLY="true"
                shift
                ;;
            -m|--metrics)
                SHOW_METRICS="true"
                shift
                ;;
            -i|--invalidate-cache)
                INVALIDATE_CACHE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        print_error "Invalid environment: $ENVIRONMENT"
        usage
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Get current configuration
    get_current_config
    
    # Execute requested action
    if [ "$SHOW_METRICS" == "true" ]; then
        show_metrics
    elif [ "$INVALIDATE_CACHE" == "true" ]; then
        invalidate_cache
    else
        deploy_optimizations
    fi
}

# Run main function
main "$@"