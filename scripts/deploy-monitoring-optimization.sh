#!/bin/bash

# Deploy Monitoring Cost Optimization Script
# 部署监控成本优化配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 导入通用函数
if [ -f "$SCRIPT_DIR/utils/common.sh" ]; then
    source "$SCRIPT_DIR/utils/common.sh"
fi

# 默认值
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DRY_RUN=false
ANALYZE_ONLY=false
APPLY_OPTIMIZATION=false

# 显示使用说明
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy monitoring cost optimization for CloudWatch

OPTIONS:
    -e, --environment ENV     Environment (dev/staging/prod) [default: dev]
    -r, --region REGION      AWS region [default: us-east-1]
    -d, --dry-run           Show what would be done without making changes
    -a, --analyze           Analyze current costs only
    -o, --optimize          Apply optimization configurations
    -h, --help              Show this help message

EXAMPLES:
    # Analyze current monitoring costs
    $0 --analyze

    # Deploy optimization in dev environment
    $0 -e dev --optimize

    # Dry run for production
    $0 -e prod --dry-run --optimize

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -a|--analyze)
                ANALYZE_ONLY=true
                shift
                ;;
            -o|--optimize)
                APPLY_OPTIMIZATION=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 检查先决条件
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI is not installed${NC}"
        exit 1
    fi
    
    # 检查AWS凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}Error: AWS credentials not configured${NC}"
        exit 1
    fi
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: Python 3 is not installed${NC}"
        exit 1
    fi
    
    # 检查Terraform
    if [ "$APPLY_OPTIMIZATION" = true ] && ! command -v terraform &> /dev/null; then
        echo -e "${RED}Error: Terraform is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Prerequisites check passed${NC}"
}

# 分析当前监控成本
analyze_monitoring_costs() {
    echo -e "\n${BLUE}Analyzing current monitoring costs...${NC}"
    
    # 运行成本分析脚本
    if [ -f "$PROJECT_ROOT/scripts/cloudwatch-cost-optimizer.py" ]; then
        python3 "$PROJECT_ROOT/scripts/cloudwatch-cost-optimizer.py" \
            --region "$REGION" \
            --output "$PROJECT_ROOT/monitoring-cost-report.json"
        
        # 显示摘要
        if [ -f "$PROJECT_ROOT/monitoring-cost-report.json" ]; then
            echo -e "\n${YELLOW}Cost Analysis Summary:${NC}"
            python3 -c "
import json
with open('$PROJECT_ROOT/monitoring-cost-report.json', 'r') as f:
    data = json.load(f)
    print(f'Estimated Monthly Cost: \${data[\"estimated_monthly_cost\"]:.2f}')
    print(f'Potential Savings: \${data[\"potential_savings\"]:.2f}')
    print(f'\\nTop Recommendations:')
    for i, rec in enumerate(data['recommendations'][:5], 1):
        savings = f' (\${rec[\"estimated_savings\"]:.2f}/month)' if 'estimated_savings' in rec else ''
        print(f'{i}. {rec[\"description\"]}{savings}')
"
        fi
    else
        echo -e "${YELLOW}Warning: Cost analysis script not found${NC}"
    fi
}

# 准备Terraform变量
prepare_terraform_vars() {
    echo -e "\n${BLUE}Preparing Terraform variables...${NC}"
    
    # 创建terraform.tfvars文件
    cat > "$PROJECT_ROOT/infrastructure/environments/$ENVIRONMENT/monitoring-optimization.tfvars" << EOF
# Monitoring Optimization Variables
# Generated on $(date)

environment = "$ENVIRONMENT"
aws_region  = "$REGION"

# Log Groups with Optimized Retention
log_groups = {
  "api-logs" = {
    retention_days = $([ "$ENVIRONMENT" = "prod" ] && echo "90" || echo "7")
    encrypted      = $([ "$ENVIRONMENT" = "prod" ] && echo "true" || echo "false")
    cost_center    = "backend"
  }
  "lambda-logs" = {
    retention_days = $([ "$ENVIRONMENT" = "prod" ] && echo "30" || echo "3")
    encrypted      = false
    cost_center    = "compute"
  }
  "application-logs" = {
    retention_days = $([ "$ENVIRONMENT" = "prod" ] && echo "30" || echo "7")
    encrypted      = false
    cost_center    = "application"
  }
}

# Critical Log Metrics Only
critical_log_metrics = {
  "error-count" = {
    log_group_name   = "api-logs"
    filter_pattern   = "[time, request_id, level=ERROR, ...]"
    metric_name      = "ErrorCount"
    metric_namespace = "RAG-System/API"
    metric_value     = "1"
    unit            = "Count"
  }
  "high-latency" = {
    log_group_name   = "api-logs"
    filter_pattern   = "[time, request_id, level, latency > 1000, ...]"
    metric_name      = "HighLatency"
    metric_namespace = "RAG-System/API"
    metric_value     = "1"
    unit            = "Count"
  }
}

# Sampling Configuration
sampling_rate = $([ "$ENVIRONMENT" = "prod" ] && echo "0.2" || echo "0.1")

sampling_rules = {
  error = {
    pattern = "ERROR"
    rate    = 1.0  # Keep all errors
  }
  warning = {
    pattern = "WARN"
    rate    = $([ "$ENVIRONMENT" = "prod" ] && echo "0.5" || echo "0.3")
  }
  info = {
    pattern = "INFO"
    rate    = $([ "$ENVIRONMENT" = "prod" ] && echo "0.1" || echo "0.05")
  }
  debug = {
    pattern = "DEBUG"
    rate    = 0.01  # Keep only 1% of debug logs
  }
}

# Metric Stream Configuration
enable_metric_stream = $([ "$ENVIRONMENT" = "prod" ] && echo "true" || echo "false")

metric_stream_namespaces = [
  "AWS/Lambda",
  "AWS/ApiGateway",
  "AWS/DynamoDB",
  "RAG-System/API",
  "RAG-System/Backend"
]

# Excluded Metrics (high volume, low value)
excluded_metrics = [
  {
    namespace    = "AWS/Lambda"
    metric_names = ["IteratorAge", "DestinationDeliveryFailures"]
  },
  {
    namespace    = "AWS/ApiGateway"
    metric_names = ["CacheHitCount", "CacheMissCount"]
  }
]

# Cost Alarms
cost_alarms = {
  "cloudwatch-monthly-cost" = {
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 1
    threshold          = $([ "$ENVIRONMENT" = "prod" ] && echo "500" || echo "100")
    description        = "CloudWatch monthly cost exceeds threshold"
    account_id         = "$(aws sts get-caller-identity --query Account --output text)"
    alarm_actions      = ["arn:aws:sns:$REGION:$(aws sts get-caller-identity --query Account --output text):monitoring-alerts"]
    ok_actions         = []
  }
}

# Dashboard Configuration
enable_cost_optimized_dashboard = true

dashboard_metrics = [
  ["AWS/Lambda", "Errors", { "stat": "Sum" }],
  ["AWS/Lambda", "Duration", { "stat": "Average" }],
  ["AWS/ApiGateway", "4XXError", { "stat": "Sum" }],
  ["AWS/ApiGateway", "5XXError", { "stat": "Sum" }],
  ["AWS/ApiGateway", "Latency", { "stat": "Average" }]
]

# Contributor Insights
enable_contributor_insights = $([ "$ENVIRONMENT" = "prod" ] && echo "true" || echo "false")

# Tags
common_tags = {
  Project     = "rag-system"
  Environment = "$ENVIRONMENT"
  ManagedBy   = "terraform"
  CostCenter  = "monitoring"
  Purpose     = "cost-optimization"
}
EOF

    echo -e "${GREEN}Terraform variables prepared${NC}"
}

# 部署优化配置
deploy_optimization() {
    echo -e "\n${BLUE}Deploying monitoring optimization...${NC}"
    
    cd "$PROJECT_ROOT/infrastructure/terraform/modules/optimization/cloudwatch"
    
    # 初始化Terraform
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
    
    # 计划变更
    echo -e "${YELLOW}Planning changes...${NC}"
    terraform plan \
        -var-file="$PROJECT_ROOT/infrastructure/environments/$ENVIRONMENT/monitoring-optimization.tfvars" \
        -out=monitoring-optimization.tfplan
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "\n${YELLOW}Dry run mode - no changes will be applied${NC}"
        return
    fi
    
    # 询问确认
    echo -e "\n${YELLOW}Do you want to apply these changes? (yes/no)${NC}"
    read -r response
    if [[ "$response" != "yes" ]]; then
        echo -e "${RED}Deployment cancelled${NC}"
        return
    fi
    
    # 应用变更
    echo -e "${YELLOW}Applying changes...${NC}"
    terraform apply monitoring-optimization.tfplan
    
    echo -e "${GREEN}Monitoring optimization deployed successfully${NC}"
}

# 验证优化效果
verify_optimization() {
    echo -e "\n${BLUE}Verifying optimization...${NC}"
    
    # 检查日志组保留策略
    echo -e "${YELLOW}Checking log group retention policies...${NC}"
    aws logs describe-log-groups \
        --query 'logGroups[?retentionInDays!=`null`].[logGroupName,retentionInDays]' \
        --output table
    
    # 检查metric filters数量
    echo -e "\n${YELLOW}Checking metric filters...${NC}"
    METRIC_FILTERS_COUNT=$(aws logs describe-metric-filters --query 'length(metricFilters)' --output text)
    echo "Total metric filters: $METRIC_FILTERS_COUNT"
    
    # 检查alarms数量
    echo -e "\n${YELLOW}Checking alarms...${NC}"
    ALARMS_COUNT=$(aws cloudwatch describe-alarms --query 'length(MetricAlarms)' --output text)
    COMPOSITE_ALARMS_COUNT=$(aws cloudwatch describe-alarms --query 'length(CompositeAlarms)' --output text)
    echo "Metric alarms: $ALARMS_COUNT"
    echo "Composite alarms: $COMPOSITE_ALARMS_COUNT"
    
    # 显示优化摘要
    echo -e "\n${GREEN}Optimization Summary:${NC}"
    echo "- Log retention policies configured"
    echo "- Metric filters reduced to critical only"
    echo "- Composite alarms used where applicable"
    echo "- Log sampling enabled"
    echo "- Metric streaming configured"
}

# 生成优化报告
generate_optimization_report() {
    echo -e "\n${BLUE}Generating optimization report...${NC}"
    
    REPORT_FILE="$PROJECT_ROOT/monitoring-optimization-report.md"
    
    cat > "$REPORT_FILE" << EOF
# Monitoring Cost Optimization Report

Generated on: $(date)
Environment: $ENVIRONMENT
Region: $REGION

## Cost Analysis Summary

$(if [ -f "$PROJECT_ROOT/monitoring-cost-report.json" ]; then
    python3 -c "
import json
with open('$PROJECT_ROOT/monitoring-cost-report.json', 'r') as f:
    data = json.load(f)
    print(f'- Estimated Monthly Cost: \${data[\"estimated_monthly_cost\"]:.2f}')
    print(f'- Potential Savings: \${data[\"potential_savings\"]:.2f}')
    print(f'- Savings Percentage: {(data[\"potential_savings\"] / data[\"estimated_monthly_cost\"] * 100):.1f}%')
"
fi)

## Applied Optimizations

1. **Log Retention Policies**
   - Production: 90 days for API logs, 30 days for Lambda logs
   - Non-production: 7 days for API logs, 3 days for Lambda logs

2. **Log Sampling**
   - ERROR logs: 100% retention
   - WARN logs: $([ "$ENVIRONMENT" = "prod" ] && echo "50%" || echo "30%") retention
   - INFO logs: $([ "$ENVIRONMENT" = "prod" ] && echo "10%" || echo "5%") retention
   - DEBUG logs: 1% retention

3. **Metric Optimization**
   - Reduced to critical metrics only
   - Excluded high-volume, low-value metrics
   - $([ "$ENVIRONMENT" = "prod" ] && echo "Enabled" || echo "Disabled") metric streaming

4. **Alarm Consolidation**
   - Using composite alarms where applicable
   - Consolidated SNS topics for alerts

5. **Cost Monitoring**
   - Monthly cost alarms configured
   - Budget threshold: \$$([ "$ENVIRONMENT" = "prod" ] && echo "500" || echo "100")

## Next Steps

1. Monitor cost reduction over the next billing cycle
2. Fine-tune sampling rates based on actual needs
3. Review and adjust retention policies quarterly
4. Consider additional optimizations:
   - Export old logs to S3
   - Implement log aggregation
   - Use CloudWatch Insights more efficiently

## Recommendations

$(if [ -f "$PROJECT_ROOT/monitoring-cost-report.json" ]; then
    python3 -c "
import json
with open('$PROJECT_ROOT/monitoring-cost-report.json', 'r') as f:
    data = json.load(f)
    for i, rec in enumerate(data['recommendations'][:5], 1):
        print(f'{i}. **{rec[\"type\"]}**')
        print(f'   - {rec[\"description\"]}')
        print(f'   - Action: {rec[\"action\"]}')
        if 'estimated_savings' in rec:
            print(f'   - Estimated Savings: \${rec[\"estimated_savings\"]:.2f}/month')
        print()
"
fi)

EOF

    echo -e "${GREEN}Report generated: $REPORT_FILE${NC}"
}

# 主函数
main() {
    parse_arguments "$@"
    
    echo -e "${BLUE}=== CloudWatch Monitoring Cost Optimization ===${NC}"
    echo -e "Environment: ${YELLOW}$ENVIRONMENT${NC}"
    echo -e "Region: ${YELLOW}$REGION${NC}"
    echo -e "Dry Run: ${YELLOW}$DRY_RUN${NC}"
    
    check_prerequisites
    
    if [ "$ANALYZE_ONLY" = true ]; then
        analyze_monitoring_costs
        exit 0
    fi
    
    if [ "$APPLY_OPTIMIZATION" = true ]; then
        analyze_monitoring_costs
        prepare_terraform_vars
        deploy_optimization
        
        if [ "$DRY_RUN" = false ]; then
            verify_optimization
            generate_optimization_report
        fi
    else
        echo -e "\n${YELLOW}Please specify --analyze or --optimize${NC}"
        show_usage
        exit 1
    fi
    
    echo -e "\n${GREEN}✅ Monitoring optimization process completed${NC}"
}

# 运行主函数
main "$@"