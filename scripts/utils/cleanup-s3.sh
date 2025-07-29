#!/bin/bash

# ================================
# 统一的S3清理脚本
# 支持普通清理、强制清理和失败资源清理
# ================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 使用说明
usage() {
    echo "使用方法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help       显示帮助信息"
    echo "  -f, --force      强制清理（暂停版本控制）"
    echo "  -b, --bucket     指定要清理的存储桶名称"
    echo "  -a, --all        清理所有已知的存储桶"
    echo "  --list-failed    列出失败的AWS资源"
    echo ""
    echo "示例:"
    echo "  $0 --all                    # 清理所有存储桶"
    echo "  $0 -b bucket-name           # 清理指定存储桶"
    echo "  $0 -f -b bucket-name        # 强制清理指定存储桶"
    exit 0
}

# 清理函数
cleanup_bucket() {
    local bucket_name="$1"
    local force_mode="${2:-false}"
    
    log_info "正在清理存储桶: $bucket_name"
    
    # 检查存储桶是否存在
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_warning "存储桶 $bucket_name 不存在或无法访问"
        return
    fi
    
    # 强制模式：暂停版本控制
    if [ "$force_mode" = "true" ]; then
        log_info "强制模式：暂停版本控制..."
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Suspended || true
    fi
    
    # 删除所有当前对象
    log_info "删除所有当前对象..."
    aws s3 rm "s3://$bucket_name" --recursive || true
    
    # 删除所有删除标记
    log_info "删除所有删除标记..."
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --query "DeleteMarkers[].{Key:Key,VersionId:VersionId}" \
        --output json | \
    jq -c '.[]' 2>/dev/null | \
    while read -r marker; do
        key=$(echo "$marker" | jq -r '.Key')
        version_id=$(echo "$marker" | jq -r '.VersionId')
        if [ "$version_id" != "null" ]; then
            aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
        fi
    done
    
    # 删除所有版本对象
    log_info "删除所有版本对象..."
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --query "Versions[].{Key:Key,VersionId:VersionId}" \
        --output json | \
    jq -c '.[]' 2>/dev/null | \
    while read -r version; do
        key=$(echo "$version" | jq -r '.Key')
        version_id=$(echo "$version" | jq -r '.VersionId')
        aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
    done
    
    log_success "存储桶 $bucket_name 清理完成"
}

# 列出失败的资源
list_failed_resources() {
    log_info "检查失败的AWS资源..."
    
    # 检查Lambda函数
    echo -e "\n${PURPLE}Lambda函数状态:${NC}"
    aws lambda list-functions --query "Functions[?contains(FunctionName, 'enterprise-rag')].{Name:FunctionName,State:State}" --output table || true
    
    # 检查S3存储桶
    echo -e "\n${PURPLE}S3存储桶:${NC}"
    aws s3api list-buckets --query "Buckets[?contains(Name, 'enterprise-rag')].Name" --output table || true
    
    # 检查API Gateway
    echo -e "\n${PURPLE}API Gateway:${NC}"
    aws apigateway get-rest-apis --query "items[?contains(name, 'enterprise-rag')].{Name:name,ID:id}" --output table || true
}

# 默认存储桶列表
DEFAULT_BUCKETS=(
    "enterprise-rag-frontend-dev-6590e6cb"
    "enterprise-rag-documents-dev-a8c14028"
)

# 解析命令行参数
FORCE_MODE=false
BUCKET_NAME=""
CLEAN_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -b|--bucket)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -a|--all)
            CLEAN_ALL=true
            shift
            ;;
        --list-failed)
            list_failed_resources
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            usage
            ;;
    esac
done

# 主逻辑
echo "🧹 S3存储桶清理工具"

if [ -n "$BUCKET_NAME" ]; then
    # 清理指定的存储桶
    cleanup_bucket "$BUCKET_NAME" "$FORCE_MODE"
elif [ "$CLEAN_ALL" = true ]; then
    # 清理所有默认存储桶
    for bucket in "${DEFAULT_BUCKETS[@]}"; do
        cleanup_bucket "$bucket" "$FORCE_MODE"
    done
else
    log_error "请指定要清理的存储桶 (-b) 或使用 -a 清理所有存储桶"
    usage
fi

echo "🎉 清理完成！"