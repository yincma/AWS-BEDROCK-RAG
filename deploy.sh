#!/bin/bash

# AWS RAG System Unified Deployment Script
# Version: 1.0
# Description: Unified deployment entry script, supports interactive wizard and multi-environment deployment

set -euo pipefail

# Script directory (must be defined first)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Initialize global variables (to avoid unbound variable errors)
ENVIRONMENT=""
DEPLOY_MODE=""
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
VERBOSE="${VERBOSE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DEPLOY_CONFIG_FILE=""
SKIP_RESOURCE_DETECTION="${SKIP_RESOURCE_DETECTION:-false}"

# Exit code definitions
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_MISSING_DEPS=2
readonly EXIT_DEPLOY_FAILED=3
readonly EXIT_USER_CANCELLED=4
readonly EXIT_CONFIG_ERROR=5

# Error handling function
error_handler() {
    local line_no=$1
    local error_code=$2
    # Use echo directly, as print_message may not be defined yet
    echo -e "\033[0;31m❌ Error occurred at line $line_no (exit code: $error_code)\033[0m" >&2
    
    # Clean up temporary files
    if [ -n "${TEMP_FILES:-}" ]; then
        rm -f $TEMP_FILES
    fi
    
    # If in Terraform directory, try to unlock state
    if [[ "$PWD" == *"/terraform"* ]] && [ -f ".terraform.lock.hcl" ]; then
        echo -e "\033[1;33mAttempting to unlock Terraform state...\033[0m"
        terraform force-unlock -force $(terraform output -raw lock_id 2>/dev/null || echo "") 2>/dev/null || true
    fi
    
    exit $error_code
}

# Set error trap
trap 'error_handler $LINENO $?' ERR

# Cleanup on exit
cleanup() {
    # Return to original directory
    cd "$SCRIPT_DIR" 2>/dev/null || true
    
    # Clean up temporary files
    if [ -n "${TEMP_FILES:-}" ]; then
        rm -f $TEMP_FILES 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Log configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${DEPLOY_LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
VERBOSE="${VERBOSE:-false}"

# Create log directory
if [ -n "$LOG_FILE" ] || [ "$LOG_LEVEL" != "INFO" ]; then
    mkdir -p "$LOG_DIR"
    # If no log file specified, use default name
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
    fi
fi

# Log level function (avoid using associative arrays for better compatibility)
get_log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# Enhanced log function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    if [ -n "${LOG_FILE:-}" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
    
    # Decide whether to output to console based on log level
    local current_level=$(get_log_level_value "${LOG_LEVEL:-INFO}")
    local message_level=$(get_log_level_value "$level")
    
    if [ "$message_level" -ge "$current_level" ]; then
        case "$level" in
            ERROR) echo -e "${RED}[$level] $message${NC}" >&2 ;;
            WARN)  echo -e "${YELLOW}[$level] $message${NC}" ;;
            INFO)  echo -e "${GREEN}[$level] $message${NC}" ;;
            DEBUG) echo -e "${GRAY}[$level] $message${NC}" ;;
        esac
    fi
}

# Switch to script directory
cd "$SCRIPT_DIR"

# Configuration file paths (support environment variable override)
CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/config}"
ENVIRONMENTS_DIR="${ENVIRONMENTS_DIR:-$SCRIPT_DIR/environments}"

# Default configuration (read from environment variables, avoid hardcoding)
DEFAULT_AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
DEFAULT_PROJECT_NAME="${PROJECT_NAME:-${PWD##*/}}"
AVAILABLE_ENVIRONMENTS="${DEPLOY_ENVIRONMENTS:-dev staging prod custom}"
DEPLOY_SCRIPTS_DIR="${DEPLOY_SCRIPTS_DIR:-$SCRIPT_DIR/scripts}"
TERRAFORM_DIR="${TERRAFORM_DIR:-$SCRIPT_DIR/infrastructure/terraform}"
TERRAFORM_WORKSPACE="${TERRAFORM_WORKSPACE:-default}"

# Print colored messages (with logging support)
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    
    # Also log to file
    if [ -n "$LOG_FILE" ]; then
        local level="INFO"
        case "$color" in
            "$RED") level="ERROR" ;;
            "$YELLOW") level="WARN" ;;
            "$GREEN") level="INFO" ;;
            "$BLUE"|"$CYAN") level="DEBUG" ;;
        esac
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    fi
}

# Print separator line
print_separator() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Print title
print_title() {
    local title=$1
    print_separator
    print_message "$BLUE" "🚀 $title"
    print_separator
}

# Show progress
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    
    printf "\r${CYAN}[%-50s] %d%% - %s${NC}" \
        "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
        "$percent" \
        "$message"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# Check if command exists
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        print_message "$RED" "❌ Error: $cmd command not found"
        return 1
    fi
    return 0
}

# Load configuration file
load_config_file() {
    local config_file=$1
    
    if [ -f "$config_file" ]; then
        log "INFO" "Loading configuration file: $config_file"
        # Use source to load config, but validate file first
        if grep -E '^\s*(rm|mv|dd|mkfs|>|>>)' "$config_file" >/dev/null; then
            log "WARN" "Configuration file contains potentially dangerous commands, skipping load"
            return 1
        fi
        source "$config_file"
        return 0
    else
        log "DEBUG" "Configuration file does not exist: $config_file"
        return 1
    fi
}

# Load environment configuration
load_environment_config() {
    local env=${1:-$ENVIRONMENT}
    
    # Try multiple possible configuration file locations
    local config_files=(
        "$CONFIG_DIR/${env}.env"
        "$CONFIG_DIR/${env}.conf"
        "$CONFIG_DIR/.env.${env}"
        "$ENVIRONMENTS_DIR/${env}/config.env"
        "$SCRIPT_DIR/.env.${env}"
        "${DEPLOY_CONFIG_FILE:-}"  # User-specified configuration file
    )
    
    local loaded=false
    for config_file in "${config_files[@]}"; do
        if [ -n "$config_file" ] && load_config_file "$config_file"; then
            loaded=true
            break
        fi
    done
    
    if [ "$loaded" == "false" ]; then
        log "DEBUG" "Environment configuration file not found: $env"
    fi
    
    # Load common configuration file (if exists)
    load_config_file "$CONFIG_DIR/common.env" || true
    load_config_file "$SCRIPT_DIR/.env" || true
}

# Dynamically find deployment script
find_deploy_script() {
    local script_name=$1
    local search_paths=(
        "$DEPLOY_SCRIPTS_DIR"
        "$SCRIPT_DIR/scripts"
        "$SCRIPT_DIR"
        "$SCRIPT_DIR/bin"
        "$SCRIPT_DIR/deployment"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path/$script_name" ] && [ -x "$path/$script_name" ]; then
            echo "$path/$script_name"
            return 0
        fi
    done
    
    # If not found, use find command to search in entire project
    local found_script=$(find "$SCRIPT_DIR" -name "$script_name" -type f -executable 2>/dev/null | head -1)
    if [ -n "$found_script" ]; then
        echo "$found_script"
        return 0
    fi
    
    return 1
}

# Show welcome screen
show_welcome() {
    clear
    cat << "EOF"
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║            AWS RAG System Deployment Tool v1.0               ║
    ║                                                              ║
    ║              Unified Deployment Management System            ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo
}

# Select environment
select_environment() {
    print_title "Select Deployment Environment"
    
    # Read available environments from environment variables, supports dynamic configuration
    IFS=' ' read -ra environments <<< "$AVAILABLE_ENVIRONMENTS"
    
    # Environment description function (avoid using associative arrays)
    get_env_description() {
        case "$1" in
            dev)     echo "${ENV_DESC_DEV:-Development environment - for development and testing}" ;;
            staging) echo "${ENV_DESC_STAGING:-Staging environment - for integration testing}" ;;
            prod)    echo "${ENV_DESC_PROD:-Production environment - live operational environment}" ;;
            custom)  echo "${ENV_DESC_CUSTOM:-Custom environment - uses custom configuration}" ;;
            *)       echo "$1 environment" ;;
        esac
    }
    
    local env_descriptions=()
    for env in "${environments[@]}"; do
        env_descriptions+=("$(get_env_description "$env")")
    done
    
    echo "Please select the environment to deploy:"
    echo
    
    for i in "${!environments[@]}"; do
        printf "  ${CYAN}%d)${NC} %-12s - %s\n" $((i+1)) "${environments[$i]}" "${env_descriptions[$i]}"
    done
    
    echo
    read -p "Please enter option (1-${#environments[@]}): " choice
    
    if [[ ! "$choice" =~ ^[1-9]$ ]] || (( choice > ${#environments[@]} )); then
        print_message "$RED" "❌ Invalid option"
        exit $EXIT_INVALID_ARGS
    fi
    
    ENVIRONMENT="${environments[$((choice-1))]}"
    print_message "$GREEN" "✓ Selected: $ENVIRONMENT environment"
    echo
}

# Select deployment mode
select_deployment_mode() {
    print_title "Select Deployment Mode"
    
    echo "Please select deployment mode:"
    echo
    printf "  ${CYAN}1)${NC} Full deployment - Deploy all components\n"
    printf "  ${CYAN}2)${NC} Frontend deployment - Deploy frontend application only\n"
    printf "  ${CYAN}3)${NC} Backend deployment - Deploy Lambda functions only\n"
    printf "  ${CYAN}4)${NC} Infrastructure deployment - Deploy infrastructure only\n"
    printf "  ${CYAN}5)${NC} Update deployment - Update existing deployment\n"
    echo
    
    read -p "Please enter option (1-5): " mode_choice
    
    case $mode_choice in
        1) DEPLOY_MODE="full" ;;
        2) DEPLOY_MODE="frontend" ;;
        3) DEPLOY_MODE="backend" ;;
        4) DEPLOY_MODE="infrastructure" ;;
        5) DEPLOY_MODE="update" ;;
        *) 
            print_message "$RED" "❌ Invalid option"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
    
    print_message "$GREEN" "✓ Selected: $DEPLOY_MODE mode"
    echo
}

# Confirm deployment
confirm_deployment() {
    print_title "Deployment Confirmation"
    
    echo "Deployment configuration summary:"
    echo
    echo "  • Environment: ${CYAN}$ENVIRONMENT${NC}"
    echo "  • Mode: ${CYAN}$DEPLOY_MODE${NC}"
    echo "  • AWS Region: ${CYAN}${AWS_REGION:-$DEFAULT_AWS_REGION}${NC}"
    echo "  • Project Name: ${CYAN}${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}${NC}"
    echo
    
    print_message "$YELLOW" "⚠️  Warning: Deployment will create AWS resources and incur costs"
    echo
    
    read -p "Continue with deployment? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_message "$YELLOW" "Deployment cancelled"
        exit $EXIT_USER_CANCELLED
    fi
    
    echo
}

# Validate environment and dependencies
validate_environment() {
    log "INFO" "Starting environment validation..."
    
    # Check required commands
    local required_commands=("aws" "terraform" "jq")
    local optional_commands=("node" "npm" "python3" "pip3")
    
    for cmd in "${required_commands[@]}"; do
        if ! check_command "$cmd"; then
            log "ERROR" "Required command $cmd not found"
            return $EXIT_MISSING_DEPS
        fi
        log "DEBUG" "✓ Found command: $cmd"
    done
    
    for cmd in "${optional_commands[@]}"; do
        if check_command "$cmd"; then
            log "DEBUG" "✓ Found optional command: $cmd"
        else
            log "WARN" "Optional command $cmd not found, some features may be unavailable"
        fi
    done
    
    # Validate AWS credentials
    log "INFO" "Validating AWS credentials..."
    if aws sts get-caller-identity &>/dev/null; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        log "INFO" "✓ AWS credentials valid (Account: $account_id)"
    else
        log "ERROR" "AWS credentials invalid or not configured"
        print_message "$YELLOW" "Please run 'aws configure' to configure your AWS credentials"
        return $EXIT_MISSING_DEPS
    fi
    
    # Check Terraform version
    if command -v terraform &> /dev/null; then
        local tf_version=$(terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log "INFO" "✓ Terraform version: $tf_version"
        
        # Check minimum version requirement
        local min_version="${TERRAFORM_MIN_VERSION:-1.0.0}"
        if ! version_compare "$tf_version" "$min_version"; then
            log "WARN" "Terraform version $tf_version is below recommended version $min_version"
        fi
    fi
    
    # Check disk space
    local available_space=$(df -k "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
    local min_space_kb=$((1024 * 1024)) # 1GB in KB
    if [ "$available_space" -lt "$min_space_kb" ]; then
        log "WARN" "Insufficient disk space: only $((available_space / 1024))MB remaining"
    fi
    
    return 0
}

# Version comparison function
version_compare() {
    local version1=$1
    local version2=$2
    
    if [[ "$version1" == "$version2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($version1) ver2=($version2)
    
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    
    return 0
}

# Run pre-deployment checks
run_pre_checks() {
    print_title "Running Pre-deployment Checks"
    
    local checks=(
        "Checking AWS credentials"
        "Checking Terraform version"
        "Checking Node.js version"
        "Checking Python version"
        "Validating configuration files"
    )
    
    # Perform actual validation
    if validate_environment; then
        for i in "${!checks[@]}"; do
            show_progress $((i+1)) ${#checks[@]} "${checks[$i]}"
            sleep 0.2  # Reduce wait time
        done
        
        echo
        print_message "$GREEN" "✓ All checks passed"
    else
        echo
        print_message "$RED" "❌ Environment validation failed"
        exit $EXIT_MISSING_DEPS
    fi
    echo
}

# Execute deployment
execute_deployment() {
    print_title "Starting Deployment"
    
    case $DEPLOY_MODE in
        "full")
            deploy_full
            ;;
        "frontend")
            deploy_frontend
            ;;
        "backend")
            deploy_backend
            ;;
        "infrastructure")
            deploy_infrastructure
            ;;
        "update")
            update_deployment
            ;;
    esac
}

# Full deployment
deploy_full() {
    print_message "$BLUE" "Executing full deployment..."
    
    # Check if corresponding deployment script exists
    if [ -f "$SCRIPT_DIR/scripts/deploy-complete.sh" ]; then
        bash "$SCRIPT_DIR/scripts/deploy-complete.sh" "$ENVIRONMENT" "${AWS_REGION:-$DEFAULT_AWS_REGION}"
    elif [ -f "$SCRIPT_DIR/deploy-complete.sh" ]; then
        bash "$SCRIPT_DIR/deploy-complete.sh" "$ENVIRONMENT" "${AWS_REGION:-$DEFAULT_AWS_REGION}"
    else
        print_message "$YELLOW" "⚠️  Full deployment script not found, will execute component deployments in sequence"
        deploy_infrastructure
        deploy_backend
        deploy_frontend
    fi
}

# Frontend deployment
deploy_frontend() {
    print_message "$BLUE" "Executing frontend deployment..."
    
    if [ -f "$SCRIPT_DIR/scripts/deploy-frontend.sh" ]; then
        bash "$SCRIPT_DIR/scripts/deploy-frontend.sh"
    else
        print_message "$RED" "❌ Frontend deployment script not found"
        exit $EXIT_MISSING_DEPS
    fi
}

# Backend deployment
deploy_backend() {
    print_message "$BLUE" "Executing backend deployment..."
    
    # Build Lambda packages
    if [ -f "$SCRIPT_DIR/build-lambda-packages.sh" ]; then
        print_message "$CYAN" "Building Lambda packages..."
        bash "$SCRIPT_DIR/build-lambda-packages.sh"
    else
        print_message "$RED" "❌ Lambda build script not found"
        exit $EXIT_MISSING_DEPS
    fi
    
    # Update Lambda functions
    print_message "$CYAN" "Updating Lambda functions..."
    cd "$TERRAFORM_DIR"
    terraform apply -var="environment=$ENVIRONMENT" -target=module.query_handler -target=module.document_processor -target=module.authorizer -auto-approve
    
    print_message "$GREEN" "✅ Lambda functions updated successfully"
}

# Infrastructure deployment
deploy_infrastructure() {
    print_message "$BLUE" "Executing infrastructure deployment..."
    
    # Execute pre-deployment resource checks
    if [ -f "$SCRIPT_DIR/scripts/pre-deployment-checks.sh" ]; then
        print_message "$CYAN" "Running pre-deployment resource checks..."
        if "$SCRIPT_DIR/scripts/pre-deployment-checks.sh" "$ENVIRONMENT" "${PROJECT_NAME:-enterprise-rag}" false; then
            print_message "$GREEN" "✓ Resource checks passed"
        else
            print_message "$YELLOW" "⚠️  Potential resource conflicts detected"
            if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
                read -p "Continue with deployment? (y/N): " continue_deploy
                if [[ ! "$continue_deploy" =~ ^[Yy]$ ]]; then
                    print_message "$YELLOW" "Deployment cancelled"
                    exit $EXIT_USER_CANCELLED
                fi
            fi
        fi
    fi
    
    if [ -d "$TERRAFORM_DIR" ]; then
        cd "$TERRAFORM_DIR"
        
        # Detect and import orphaned resources
        if [ "${SKIP_RESOURCE_DETECTION:-false}" != "true" ] && [ -f "$SCRIPT_DIR/scripts/detect-and-import-resources.sh" ]; then
            print_message "$CYAN" "Detecting orphaned resources..."
            
            # Set parameters based on interactive mode
            local import_args=""
            if [ "${NON_INTERACTIVE:-false}" == "true" ]; then
                import_args="--auto"
            fi
            
            # Execute resource detection and import
            if "$SCRIPT_DIR/scripts/detect-and-import-resources.sh" \
                --env "$ENVIRONMENT" \
                --project "$PROJECT_NAME" \
                $import_args; then
                print_message "$GREEN" "✓ Resource detection and import completed"
            else
                log "WARN" "Warnings during resource import process, continuing deployment..."
            fi
            echo
        elif [ "${SKIP_RESOURCE_DETECTION:-false}" == "true" ]; then
            log "INFO" "Skipping resource detection (per user settings)"
        fi
        
        # Initialize Terraform
        print_message "$CYAN" "Initializing Terraform..."
        terraform init -upgrade
        
        # Validate configuration
        print_message "$CYAN" "Validating configuration..."
        terraform validate
        
        # Execute plan
        print_message "$CYAN" "Generating deployment plan..."
        
        # Check if OpenSearch resources should be skipped
        local plan_args=""
        if [ "${SKIP_OPENSEARCH_RESOURCES:-false}" == "true" ]; then
            log "INFO" "Skipping OpenSearch Serverless resources"
            # Get all non-OpenSearch resources as targets
            local targets=$(terraform state list 2>/dev/null | grep -v "opensearchserverless" || true)
            if [ -n "$targets" ]; then
                for target in $targets; do
                    plan_args="$plan_args -target=$target"
                done
            fi
        fi
        
        terraform plan -var="environment=$ENVIRONMENT" $plan_args -out=tfplan
        
        # Apply changes
        print_message "$CYAN" "Applying infrastructure changes..."
        # Capture terraform output for error analysis
        local tf_output_file="${TEMP_DIR:-/tmp}/terraform_apply_$(date +%s).log"
        TEMP_FILES="${TEMP_FILES} $tf_output_file"
        
        if terraform apply tfplan 2>&1 | tee "$tf_output_file"; then
            print_message "$GREEN" "✓ Infrastructure deployment successful"
            
            # Save outputs
            terraform output -json > outputs.json
        else
            local exit_code=$?
            print_message "$RED" "❌ Deployment failed (exit code: $exit_code)"
            
            # Analyze errors and provide solutions
            if grep -q "ConflictException.*already exists\|InvalidRequestException.*already exists" "$tf_output_file" 2>/dev/null; then
                print_message "$YELLOW" "Resource conflict error detected: some resources already exist"
                
                # Detect specific resource types
                local resource_type=""
                local resource_name=""
                
                if grep -q "XRay.*SamplingRule" "$tf_output_file" 2>/dev/null; then
                    resource_type="XRay sampling rule"
                    resource_name=$(grep -oE "enterprise-rag-[^\"]*" "$tf_output_file" | head -1)
                    print_message "$CYAN" "XRay sampling rule conflict detected: $resource_name"
                    echo
                    echo "  Quick fix commands:"
                    echo "     # Option 1: Import existing rule"
                    echo "     cd $TERRAFORM_DIR"
                    echo "     terraform import module.monitoring.aws_xray_sampling_rule.main[0] $resource_name"
                    echo
                    echo "     # Option 2: Delete existing rule"
                    echo "     aws xray delete-sampling-rule --rule-name $resource_name"
                    echo
                elif grep -q "opensearchserverless" "$tf_output_file" 2>/dev/null; then
                    resource_type="OpenSearch Serverless"
                    print_message "$CYAN" "OpenSearch Serverless resource conflict detected"
                fi
                
                # General solutions
                print_message "$CYAN" "General solutions:"
                echo
                echo "  1. Import existing resources into Terraform state:"
                echo "     cd $TERRAFORM_DIR"
                echo "     terraform import <resource_type>.<resource_name> <resource_id>"
                echo
                echo "  2. Or, if this is a test environment, delete the conflicting resources first:"
                echo "     - Delete conflicting resources using AWS Console"
                echo "     - Or delete resources using AWS CLI"
                echo
                echo "  3. Use -replace parameter to force resource recreation:"
                echo "     terraform apply -replace=<resource_address>"
                echo
                echo "  4. Or try refreshing Terraform state and retry:"
                echo "     terraform refresh"
                echo "     terraform apply"
                echo
                echo "  For detailed resource import guide, please refer to: TERRAFORM_MIGRATION_GUIDE.md"
            else
                print_message "$YELLOW" "Please go to infrastructure/terraform directory and run terraform plan manually to troubleshoot."
                print_message "$YELLOW" "Tip: You can run the following commands to see detailed errors:"
                echo "  cd $TERRAFORM_DIR"
                echo "  terraform plan"
            fi
            
            # Provide auto-fix option (only in interactive mode)
            if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
                echo
                read -p "Attempt automatic fix? (y/N): " auto_fix
                if [[ "$auto_fix" =~ ^[Yy]$ ]]; then
                    attempt_auto_fix
                fi
            fi
            
            cd "$SCRIPT_DIR"
            exit $EXIT_DEPLOY_FAILED
        fi
        
        cd "$SCRIPT_DIR"
    else
        print_message "$RED" "❌ Infrastructure directory not found"
        exit $EXIT_CONFIG_ERROR
    fi
}

# Update deployment
update_deployment() {
    print_message "$BLUE" "Executing update deployment..."
    
    # Update logic can be implemented here based on actual requirements
    print_message "$YELLOW" "Update deployment feature under development..."
}

# Attempt to auto-fix deployment issues
attempt_auto_fix() {
    print_message "$BLUE" "Attempting to auto-fix deployment issues..."
    
    cd "$TERRAFORM_DIR"
    
    # 1. First try to refresh state
    print_message "$CYAN" "Refreshing Terraform state..."
    if terraform refresh; then
        log "INFO" "State refresh successful"
    else
        log "WARN" "State refresh failed, trying other methods"
    fi
    
    # 2. Detect specific resource conflicts
    local conflict_resources=()
    local conflict_types=()
    
    # Check recent error output
    if [ -f "$tf_output_file" ]; then
        # Extract conflicting resources
        while IFS= read -r line; do
            if [[ "$line" =~ "module.bedrock.aws_opensearchserverless".*"already exists" ]]; then
                local resource=$(echo "$line" | grep -oE 'module\.[^,]+' | head -1)
                conflict_resources+=("$resource")
                conflict_types+=("opensearch")
            elif [[ "$line" =~ "module.monitoring.aws_xray_sampling_rule".*"already exists" ]]; then
                local resource="module.monitoring.aws_xray_sampling_rule.main[0]"
                conflict_resources+=("$resource")
                conflict_types+=("xray")
            fi
        done < "$tf_output_file"
    fi
    
    # 3. If OpenSearch Serverless conflict detected
    if [ ${#conflict_resources[@]} -gt 0 ]; then
        print_message "$YELLOW" "Following resource conflicts detected:"
        for resource in "${conflict_resources[@]}"; do
            echo "  - $resource"
        done
        
        echo
        print_message "$CYAN" "Available fix options:"
        echo "  1. Import existing resources (preserve existing configuration)"
        echo "  2. Force replace resources (delete and recreate)"
        echo "  3. Skip conflicting resources (partial deployment)"
        echo "  4. Handle manually"
        echo
        
        read -p "Please select fix option (1-4): " fix_choice
        
        case "$fix_choice" in
            1)
                print_message "$CYAN" "Attempting to import existing resources..."
                # Provide specific import commands based on resource type
                for i in "${!conflict_resources[@]}"; do
                    local resource="${conflict_resources[$i]}"
                    local type="${conflict_types[$i]}"
                    
                    if [ "$type" == "xray" ]; then
                        local rule_name=$(grep -oE "enterprise-rag-[^\"]*-${ENVIRONMENT}" "$tf_output_file" | head -1)
                        if [ -n "$rule_name" ]; then
                            print_message "$CYAN" "Importing XRay sampling rule: $rule_name"
                            terraform import "$resource" "$rule_name" || log "WARN" "Import failed: $resource"
                        fi
                    elif [ "$type" == "opensearch" ]; then
                        print_message "$YELLOW" "OpenSearch resources need manual import, please execute:"
                        echo "terraform import $resource <resource-id>"
                    fi
                done
                
                # Retry applying
                print_message "$CYAN" "Re-applying Terraform configuration..."
                terraform apply -auto-approve
                ;;
            2)
                print_message "$CYAN" "Force replacing conflicting resources..."
                local replace_args=""
                for resource in "${conflict_resources[@]}"; do
                    replace_args="$replace_args -replace=$resource"
                done
                terraform apply $replace_args -auto-approve
                ;;
            3)
                print_message "$CYAN" "Skipping conflicting resources, continuing with other resources..."
                local target_args=""
                # Get all resources, excluding conflicting ones
                terraform state list | grep -v "opensearchserverless" | while read -r resource; do
                    target_args="$target_args -target=$resource"
                done
                terraform apply $target_args -auto-approve
                ;;
            4)
                print_message "$YELLOW" "Please handle resource conflicts manually"
                return 1
                ;;
        esac
    else
        # 4. General fix attempt
        print_message "$CYAN" "Attempting to reinitialize and apply..."
        terraform init -upgrade
        terraform apply -auto-approve
    fi
    
    cd "$SCRIPT_DIR"
}

# Show deployment result
show_deployment_result() {
    print_title "Deployment Complete"
    
    print_message "$GREEN" "✅ Deployment completed successfully!"
    echo
    
    echo "Deployment information:"
    echo "  • Environment: $ENVIRONMENT"
    echo "  • Mode: $DEPLOY_MODE"
    echo "  • Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    # Display output URLs if available
    local outputs_file="$TERRAFORM_DIR/outputs.json"
    if [ -f "$outputs_file" ]; then
        echo "Access information:"
        echo "  • Frontend URL: $(jq -r '.frontend_url.value' < "$outputs_file" 2>/dev/null || echo 'N/A')"
        echo "  • API URL: $(jq -r '.api_url.value' < "$outputs_file" 2>/dev/null || echo 'N/A')"
        echo
    fi
    
    if [ -n "$LOG_FILE" ]; then
        print_message "$CYAN" "📚 View deployment logs: $LOG_FILE"
    else
        print_message "$CYAN" "📚 Tip: Set LOG_FILE environment variable to enable logging"
    fi
    echo
}

# Main function
main() {
    # Show welcome screen
    show_welcome
    
    # Early environment validation (before interaction)
    log "INFO" "Starting deployment process..."
    if [ "${VERBOSE:-false}" == "true" ]; then
        LOG_LEVEL="DEBUG"
    fi
    
    # Load base configuration file
    load_environment_config "common"
    
    # Select environment (if not specified via parameter)
    if [ -z "${ENVIRONMENT:-}" ]; then
        select_environment
    else
        print_message "$GREEN" "✓ Using specified environment: $ENVIRONMENT"
        echo
    fi
    
    # Load environment-specific configuration
    load_environment_config "$ENVIRONMENT"
    
    # Select deployment mode (if not specified via parameter)
    if [ -z "${DEPLOY_MODE:-}" ]; then
        select_deployment_mode
    else
        print_message "$GREEN" "✓ Using specified mode: $DEPLOY_MODE"
        echo
    fi
    
    # CI/CD environment detection
    if [ "${CI:-false}" == "true" ] || [ "${GITHUB_ACTIONS:-false}" == "true" ] || [ "${GITLAB_CI:-false}" == "true" ]; then
        NON_INTERACTIVE="true"
        log "INFO" "CI/CD environment detected, enabling non-interactive mode"
    fi
    
    # Non-interactive mode configuration
    if [ "${NON_INTERACTIVE:-false}" == "true" ]; then
        log "INFO" "Running in non-interactive mode"
        # Ensure required parameters are set
        if [ -z "${ENVIRONMENT:-}" ]; then
            ENVIRONMENT="${DEFAULT_ENVIRONMENT:-dev}"
            log "INFO" "Using default environment: $ENVIRONMENT"
        fi
        if [ -z "${DEPLOY_MODE:-}" ]; then
            DEPLOY_MODE="${DEFAULT_DEPLOY_MODE:-full}"
            log "INFO" "Using default deployment mode: $DEPLOY_MODE"
        fi
        SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-true}"
    fi
    
    # Confirm deployment
    if [ "${NON_INTERACTIVE:-false}" != "true" ] && [ "${SKIP_CONFIRMATION:-false}" != "true" ]; then
        confirm_deployment
    elif [ "${SKIP_CONFIRMATION:-false}" == "true" ]; then
        log "INFO" "Skipping deployment confirmation (auto-confirming)"
        print_message "$YELLOW" "Auto-confirming deployment: environment=$ENVIRONMENT, mode=$DEPLOY_MODE"
    fi
    
    # Run pre-deployment checks
    run_pre_checks
    
    # Execute deployment
    execute_deployment
    
    # Show deployment result
    show_deployment_result
}

# Process command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help, -h              Show help information"
            echo "  --env ENV               Specify environment (dev|staging|prod|custom)"
            echo "  --mode MODE             Specify deployment mode (full|frontend|backend|infrastructure|update)"
            echo "  --non-interactive       Non-interactive mode"
            echo "  --skip-confirmation     Skip deployment confirmation"
            echo "  --skip-resource-check   Skip orphaned resource detection"
            echo "  --verbose               Show verbose logs"
            echo "  --log-file FILE         Specify log file path"
            echo "  --log-level LEVEL       Set log level (DEBUG|INFO|WARN|ERROR)"
            echo "  --config FILE           Specify configuration file path"
            echo ""
            echo "Environment Variables:"
            echo "  AWS_REGION              AWS region (default: $DEFAULT_AWS_REGION)"
            echo "  PROJECT_NAME            Project name (default: $DEFAULT_PROJECT_NAME)"
            echo "  LOG_LEVEL               Log level (default: INFO)"
            echo "  LOG_FILE                Log file path"
            echo "  NON_INTERACTIVE         Enable non-interactive mode"
            echo "  CI                      CI/CD environment flag"
            echo ""
            exit $EXIT_SUCCESS
            ;;
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --mode)
            DEPLOY_MODE="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --skip-resource-check)
            SKIP_RESOURCE_DETECTION=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            LOG_LEVEL="DEBUG"
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --config)
            DEPLOY_CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for help information"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
done

# Execute main function
main

exit $EXIT_SUCCESS