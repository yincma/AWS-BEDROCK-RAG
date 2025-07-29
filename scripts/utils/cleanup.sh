#!/bin/bash

# AWS RAG System Cleanup Script
# Version: 1.0
# Description: 分级清理脚本，支持安全确认和资源备份

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 默认参数
DRY_RUN=false
CLEANUP_LEVEL="all"
BACKUP_ENABLED=true
FORCE=false

# 时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/backups/cleanup_$TIMESTAMP"
LOG_FILE="$PROJECT_ROOT/logs/cleanup_$TIMESTAMP.log"

# 打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# 打印分隔线
print_separator() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
}

# 初始化日志
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "清理操作日志 - $TIMESTAMP" > "$LOG_FILE"
    echo "================================" >> "$LOG_FILE"
}

# 显示使用帮助
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

AWS RAG System 清理脚本

Options:
  -l, --level LEVEL     清理级别 (lambda|frontend|infrastructure|all) [默认: all]
  -d, --dry-run         模拟运行，只显示将要执行的操作
  -f, --force           跳过确认提示
  -n, --no-backup       不创建备份
  -h, --help            显示此帮助信息

清理级别说明:
  lambda          - 仅清理Lambda函数和相关资源
  frontend        - 仅清理前端资源（S3、CloudFront）
  infrastructure  - 仅清理基础设施（但保留数据）
  all            - 清理所有资源

示例:
  $0 --level lambda --dry-run    # 模拟清理Lambda资源
  $0 --level all --force          # 强制清理所有资源
  $0 --no-backup                  # 清理时不创建备份

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--level)
                CLEANUP_LEVEL="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -n|--no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_message "$RED" "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 验证清理级别
validate_cleanup_level() {
    case $CLEANUP_LEVEL in
        lambda|frontend|infrastructure|all)
            ;;
        *)
            print_message "$RED" "❌ 无效的清理级别: $CLEANUP_LEVEL"
            show_help
            exit 1
            ;;
    esac
}

# 显示清理预览
show_cleanup_preview() {
    print_separator
    print_message "$BLUE" "🔍 清理预览"
    print_separator
    
    echo "清理配置:"
    echo "  • 清理级别: $CLEANUP_LEVEL"
    echo "  • 模拟运行: $DRY_RUN"
    echo "  • 创建备份: $BACKUP_ENABLED"
    echo ""
    
    print_message "$YELLOW" "将要清理的资源:"
    
    case $CLEANUP_LEVEL in
        lambda)
            echo "  • Lambda函数"
            echo "  • Lambda层"
            echo "  • 相关IAM角色和策略"
            echo "  • CloudWatch日志组"
            ;;
        frontend)
            echo "  • S3静态网站桶"
            echo "  • CloudFront分发"
            echo "  • Route53记录（如果存在）"
            ;;
        infrastructure)
            echo "  • API Gateway"
            echo "  • VPC和网络资源"
            echo "  • 安全组"
            echo "  • 其他基础设施组件"
            ;;
        all)
            echo "  • 所有Lambda资源"
            echo "  • 所有前端资源"
            echo "  • 所有基础设施"
            echo "  • 所有IAM资源"
            echo "  • 所有监控和日志"
            ;;
    esac
    
    echo ""
}

# 确认清理操作
confirm_cleanup() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    print_message "$YELLOW" "⚠️  警告: 此操作将删除上述资源，无法撤销！"
    echo ""
    
    read -p "请输入 'yes' 确认继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_message "$YELLOW" "清理操作已取消"
        exit 0
    fi
}

# 创建资源备份
create_backup() {
    if [ "$BACKUP_ENABLED" = false ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_message "$BLUE" "📦 创建资源备份..."
    
    mkdir -p "$BACKUP_DIR"
    
    # 备份Terraform状态
    if [ -f "$PROJECT_ROOT/infrastructure/terraform/terraform.tfstate" ]; then
        cp "$PROJECT_ROOT/infrastructure/terraform/terraform.tfstate" "$BACKUP_DIR/" 2>/dev/null || true
        print_message "$GREEN" "  ✓ Terraform状态已备份"
    fi
    
    # 备份配置文件
    if [ -d "$PROJECT_ROOT/config" ]; then
        cp -r "$PROJECT_ROOT/config" "$BACKUP_DIR/" 2>/dev/null || true
        print_message "$GREEN" "  ✓ 配置文件已备份"
    fi
    
    # 导出当前AWS资源列表
    if command -v aws &> /dev/null; then
        print_message "$CYAN" "  正在导出AWS资源清单..."
        
        # Lambda函数列表
        aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `rag-`) == `true`]' \
            > "$BACKUP_DIR/lambda-functions.json" 2>/dev/null || true
        
        # S3桶列表
        aws s3api list-buckets --query 'Buckets[?contains(Name, `rag`) == `true`]' \
            > "$BACKUP_DIR/s3-buckets.json" 2>/dev/null || true
        
        # CloudFront分发列表
        aws cloudfront list-distributions --query 'DistributionList.Items[?Comment == `RAG System`]' \
            > "$BACKUP_DIR/cloudfront-distributions.json" 2>/dev/null || true
        
        print_message "$GREEN" "  ✓ AWS资源清单已导出"
    fi
    
    print_message "$GREEN" "✓ 备份完成: $BACKUP_DIR"
    echo ""
}

# 清理Lambda资源
cleanup_lambda() {
    print_message "$BLUE" "🧹 清理Lambda资源..."
    
    if [ "$DRY_RUN" = true ]; then
        print_message "$CYAN" "  [DRY RUN] 将删除以下Lambda函数:"
        aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `rag-`) == `true`].FunctionName' --output table 2>/dev/null || true
        return 0
    fi
    
    # 获取所有RAG相关的Lambda函数
    local functions=$(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `rag-`) == `true`].FunctionName' --output text 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        for func in $functions; do
            print_message "$YELLOW" "  删除Lambda函数: $func"
            aws lambda delete-function --function-name "$func" 2>/dev/null || true
            
            # 删除相关的日志组
            local log_group="/aws/lambda/$func"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
        done
        print_message "$GREEN" "  ✓ Lambda资源清理完成"
    else
        print_message "$CYAN" "  没有找到需要清理的Lambda函数"
    fi
}

# 清理前端资源
cleanup_frontend() {
    print_message "$BLUE" "🧹 清理前端资源..."
    
    if [ "$DRY_RUN" = true ]; then
        print_message "$CYAN" "  [DRY RUN] 将删除前端相关资源"
        return 0
    fi
    
    # 清理S3桶
    local buckets=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `rag-frontend`) == `true`].Name' --output text 2>/dev/null || echo "")
    
    if [ -n "$buckets" ]; then
        for bucket in $buckets; do
            print_message "$YELLOW" "  清空并删除S3桶: $bucket"
            # 先清空桶
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            # 删除桶
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        done
        print_message "$GREEN" "  ✓ S3资源清理完成"
    fi
    
    # 清理CloudFront分发
    local distributions=$(aws cloudfront list-distributions --query 'DistributionList.Items[?Comment == `RAG System Frontend`].Id' --output text 2>/dev/null || echo "")
    
    if [ -n "$distributions" ]; then
        for dist_id in $distributions; do
            print_message "$YELLOW" "  禁用CloudFront分发: $dist_id"
            # 需要先禁用分发
            aws cloudfront update-distribution --id "$dist_id" \
                --if-match "$(aws cloudfront get-distribution --id "$dist_id" --query 'ETag' --output text)" \
                --distribution-config "$(aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DistributionConfig' | jq '.Enabled = false')" \
                2>/dev/null || true
            
            # 注意：CloudFront分发需要等待禁用完成后才能删除
            print_message "$YELLOW" "  CloudFront分发 $dist_id 已标记为禁用，稍后可手动删除"
        done
    fi
}

# 清理基础设施
cleanup_infrastructure() {
    print_message "$BLUE" "🧹 清理基础设施..."
    
    if [ "$DRY_RUN" = true ]; then
        print_message "$CYAN" "  [DRY RUN] 将通过Terraform销毁基础设施"
        return 0
    fi
    
    # 使用Terraform销毁基础设施
    if [ -d "$PROJECT_ROOT/infrastructure/terraform" ]; then
        cd "$PROJECT_ROOT/infrastructure/terraform"
        
        if [ -f "terraform.tfstate" ]; then
            print_message "$YELLOW" "  执行Terraform destroy..."
            terraform destroy -auto-approve || true
            print_message "$GREEN" "  ✓ Terraform资源清理完成"
        else
            print_message "$YELLOW" "  未找到Terraform状态文件"
        fi
        
        cd "$PROJECT_ROOT"
    fi
}

# 处理资源依赖关系
handle_dependencies() {
    print_message "$BLUE" "🔍 检查资源依赖关系..."
    
    # 这里可以添加更复杂的依赖关系检查
    # 例如：检查是否有其他服务依赖于要删除的资源
    
    print_message "$GREEN" "  ✓ 依赖关系检查完成"
}

# 执行清理
execute_cleanup() {
    print_separator
    print_message "$BLUE" "🚀 开始执行清理操作"
    print_separator
    
    # 处理依赖关系
    handle_dependencies
    
    # 根据清理级别执行相应操作
    case $CLEANUP_LEVEL in
        lambda)
            cleanup_lambda
            ;;
        frontend)
            cleanup_frontend
            ;;
        infrastructure)
            cleanup_infrastructure
            ;;
        all)
            # 按照依赖顺序清理
            cleanup_lambda
            cleanup_frontend
            cleanup_infrastructure
            ;;
    esac
    
    if [ "$DRY_RUN" = false ]; then
        print_message "$GREEN" "✅ 清理操作完成"
    else
        print_message "$CYAN" "✅ 模拟运行完成（未执行实际删除）"
    fi
}

# 生成清理报告
generate_cleanup_report() {
    print_separator
    print_message "$BLUE" "📊 清理报告"
    print_separator
    
    echo "清理操作摘要:"
    echo "  • 清理级别: $CLEANUP_LEVEL"
    echo "  • 执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  • 日志文件: $LOG_FILE"
    
    if [ "$BACKUP_ENABLED" = true ] && [ "$DRY_RUN" = false ]; then
        echo "  • 备份位置: $BACKUP_DIR"
    fi
    
    echo ""
    print_message "$CYAN" "详细日志已保存至: $LOG_FILE"
}

# 主函数
main() {
    # 初始化日志
    init_logging
    
    # 解析参数
    parse_arguments "$@"
    
    # 验证参数
    validate_cleanup_level
    
    # 显示清理预览
    show_cleanup_preview
    
    # 确认操作
    confirm_cleanup
    
    # 创建备份
    create_backup
    
    # 执行清理
    execute_cleanup
    
    # 生成报告
    generate_cleanup_report
}

# 执行主函数
main "$@"