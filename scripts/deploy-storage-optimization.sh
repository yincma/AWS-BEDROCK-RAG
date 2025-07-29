#!/bin/bash

# Deploy Storage Optimization Module
# This script deploys and manages the storage cost optimization configurations

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure/terraform"

# Functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not found. Please install Terraform."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Analyze current storage costs
analyze_current_costs() {
    print_header "Analyzing Current Storage Costs"
    
    # Run S3 cost analyzer
    if [ -f "$SCRIPT_DIR/s3-cost-analyzer.py" ]; then
        echo "Running S3 cost analysis..."
        python3 "$SCRIPT_DIR/s3-cost-analyzer.py" --output "$PROJECT_ROOT/s3-cost-analysis.json" --html
        
        if [ -f "$PROJECT_ROOT/s3-cost-analysis.html" ]; then
            print_success "S3 cost analysis report generated: s3-cost-analysis.html"
        fi
    fi
    
    # Run CloudWatch cost optimizer
    if [ -f "$SCRIPT_DIR/cloudwatch-cost-optimizer.py" ]; then
        echo "Running CloudWatch cost analysis..."
        python3 "$SCRIPT_DIR/cloudwatch-cost-optimizer.py" --output "$PROJECT_ROOT/cloudwatch-cost-report.json"
        print_success "CloudWatch cost analysis complete"
    fi
}

# Generate Terraform variables
generate_tfvars() {
    print_header "Generating Terraform Variables"
    
    local ENV="${1:-dev}"
    local TFVARS_FILE="$TERRAFORM_DIR/environments/$ENV/storage-optimization.tfvars"
    
    mkdir -p "$TERRAFORM_DIR/environments/$ENV"
    
    cat > "$TFVARS_FILE" << EOF
# Storage Optimization Configuration for $ENV
# Generated on $(date)

# S3 Buckets to optimize
s3_buckets = {
  documents = {
    bucket_name              = "\${var.project_name}-documents-\${var.environment}"
    enable_lifecycle         = true
    enable_intelligent_tiering = $([ "$ENV" = "prod" ] && echo "true" || echo "false")
    enable_inventory        = $([ "$ENV" = "prod" ] && echo "true" || echo "false")
    lifecycle_rules = {
      ia_transition_days      = $([ "$ENV" = "dev" ] && echo "7" || echo "30")
      glacier_transition_days = $([ "$ENV" = "dev" ] && echo "30" || echo "90")
      deep_archive_days      = $([ "$ENV" = "dev" ] && echo "90" || echo "180")
      expiration_days        = $([ "$ENV" = "dev" ] && echo "180" || echo "365")
    }
  }
}

# CloudWatch Log Groups
log_groups = {
  "/aws/lambda/\${var.project_name}-query-handler" = {
    retention_in_days  = $([ "$ENV" = "dev" ] && echo "7" || [ "$ENV" = "staging" ] && echo "30" || echo "90")
    enable_compression = true
  }
  "/aws/lambda/\${var.project_name}-document-processor" = {
    retention_in_days  = $([ "$ENV" = "dev" ] && echo "7" || [ "$ENV" = "staging" ] && echo "30" || echo "90")
    enable_compression = true
  }
}

# Budget configuration
storage_budget_amount = $([ "$ENV" = "dev" ] && echo "50" || [ "$ENV" = "staging" ] && echo "100" || echo "500")
logs_budget_amount    = $([ "$ENV" = "dev" ] && echo "25" || [ "$ENV" = "staging" ] && echo "50" || echo "200")

# Alert configuration
alert_email = "$ALERT_EMAIL"
EOF
    
    print_success "Generated Terraform variables file: $TFVARS_FILE"
}

# Deploy storage optimization
deploy_optimization() {
    print_header "Deploying Storage Optimization"
    
    local ENV="${1:-dev}"
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    echo "Initializing Terraform..."
    terraform init
    
    # Create workspace if it doesn't exist
    terraform workspace select $ENV 2>/dev/null || terraform workspace new $ENV
    
    # Plan deployment
    echo "Planning deployment..."
    terraform plan \
        -var="environment=$ENV" \
        -var-file="environments/$ENV/storage-optimization.tfvars" \
        -out="storage-optimization-$ENV.tfplan"
    
    # Ask for confirmation
    echo -e "\n${YELLOW}Review the plan above. Do you want to apply these changes? (yes/no)${NC}"
    read -r response
    
    if [[ "$response" == "yes" ]]; then
        echo "Applying changes..."
        terraform apply "storage-optimization-$ENV.tfplan"
        print_success "Storage optimization deployed successfully!"
    else
        print_warning "Deployment cancelled"
        exit 0
    fi
}

# Show optimization status
show_status() {
    print_header "Storage Optimization Status"
    
    # Get S3 lifecycle rules
    echo "S3 Lifecycle Rules:"
    aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read bucket; do
        if aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" 2>/dev/null; then
            print_success "$bucket - Lifecycle configured"
        else
            print_warning "$bucket - No lifecycle rules"
        fi
    done
    
    echo -e "\nCloudWatch Log Groups:"
    aws logs describe-log-groups --query 'logGroups[].[logGroupName, retentionInDays]' --output table
    
    # Show cost trends
    if [ -f "$PROJECT_ROOT/s3-cost-analysis.json" ]; then
        echo -e "\nEstimated Savings:"
        jq -r '.potential_monthly_savings' "$PROJECT_ROOT/s3-cost-analysis.json" | awk '{printf "S3: $%.2f/month\n", $1}'
    fi
}

# Enable monitoring
enable_monitoring() {
    print_header "Enabling Cost Monitoring"
    
    # Create CloudWatch dashboard
    cat > /tmp/storage-dashboard.json << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/S3", "BucketSizeBytes", {"stat": "Average"}],
                    [".", "NumberOfObjects", {"stat": "Average", "yAxis": "right"}]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "us-east-1",
                "title": "S3 Storage Overview"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "StorageOptimization" \
        --dashboard-body file:///tmp/storage-dashboard.json
    
    print_success "Monitoring dashboard created"
}

# Main menu
show_menu() {
    echo -e "\n${BLUE}Storage Cost Optimization Tool${NC}"
    echo "================================"
    echo "1. Analyze current storage costs"
    echo "2. Deploy optimization (dev)"
    echo "3. Deploy optimization (staging)"
    echo "4. Deploy optimization (prod)"
    echo "5. Show optimization status"
    echo "6. Enable monitoring"
    echo "7. Generate cost report"
    echo "8. Exit"
    echo
    read -p "Select an option: " choice
    
    case $choice in
        1) analyze_current_costs ;;
        2) generate_tfvars "dev" && deploy_optimization "dev" ;;
        3) generate_tfvars "staging" && deploy_optimization "staging" ;;
        4) generate_tfvars "prod" && deploy_optimization "prod" ;;
        5) show_status ;;
        6) enable_monitoring ;;
        7) 
            analyze_current_costs
            echo -e "\n${GREEN}Reports generated in project root${NC}"
            ;;
        8) exit 0 ;;
        *) 
            print_error "Invalid option"
            show_menu
            ;;
    esac
}

# Parse command line arguments
case "${1:-}" in
    analyze)
        check_prerequisites
        analyze_current_costs
        ;;
    deploy)
        check_prerequisites
        ENV="${2:-dev}"
        generate_tfvars "$ENV"
        deploy_optimization "$ENV"
        ;;
    status)
        show_status
        ;;
    monitor)
        enable_monitoring
        ;;
    *)
        check_prerequisites
        show_menu
        ;;
esac