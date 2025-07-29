# AWS 资源清理指南

## 概述
本指南提供了彻底清理 AWS 资源的方法和工具。

## 统一管理脚本

### aws-cleanup.sh
**文件**: `aws-cleanup.sh`
**用途**: 统一的AWS资源管理脚本，支持检查和清理功能

#### 使用方法：
```bash
# 显示帮助信息
./aws-cleanup.sh --help

# 只检查资源（不清理）
./aws-cleanup.sh check

# 直接执行清理（不检查）
./aws-cleanup.sh clean
./aws-cleanup.sh clean --prefix enterprise-rag --env dev --yes

# 先检查后清理（默认）
./aws-cleanup.sh
./aws-cleanup.sh all
```

### 原始脚本（已整合）
- `check-aws-resources.sh` - 检查功能已整合到统一脚本
- `enhanced-cleanup-aws.sh` - 清理功能已整合到统一脚本
- `（del）force-cleanup-aws.sh` - 基础清理功能已整合

## 清理的资源类型

### 基础资源
- ✅ CloudFront 分发
- ✅ S3 存储桶（documents, frontend, lambda_deployments）
- ✅ Lambda 函数和层
- ✅ API Gateway
- ✅ Cognito User Pool
- ✅ CloudWatch 日志组
- ✅ IAM 角色和策略
- ✅ Bedrock Knowledge Base

### 增强清理资源
- ✅ OpenSearch Serverless（集合、访问策略、安全策略）
- ✅ VPC 及相关资源（子网、路由表、安全组、VPC Endpoints）
- ✅ CloudWatch 监控资源（仪表板、告警、指标过滤器）
- ✅ SNS 主题
- ✅ X-Ray 采样规则
- ✅ EventBridge 规则
- ✅ KMS 密钥和别名
- ✅ CloudFront OAI 和 Response Headers Policy
- ✅ 本地 Terraform state 文件

## 使用步骤

### 1. 检查当前资源
首先运行检查功能，了解当前有哪些资源需要清理：
```bash
./aws-cleanup.sh check
```

### 2. 执行清理
如果发现有遗留资源，可以选择：

#### 选项A：先检查后清理（推荐）
```bash
./aws-cleanup.sh
# 或
./aws-cleanup.sh all
```

#### 选项B：直接清理（如果您确定要清理）
```bash
./aws-cleanup.sh clean
```

输入 `DELETE` 确认删除操作。

### 3. 验证清理结果
清理完成后，再次运行检查功能验证：
```bash
./aws-cleanup.sh check
```

### 4. 手动检查
登录 AWS 控制台，手动检查以下服务：
- OpenSearch Service
- VPC 控制台
- CloudWatch
- KMS（密钥将在7天后删除）
- Cost Explorer

## 注意事项

1. **KMS 密钥**: 由于 AWS 的安全策略，KMS 密钥不能立即删除，将被安排在 7 天后删除。

2. **CloudFront 分发**: 如果分发处于启用状态，脚本会先禁用它。需要等待禁用完成后手动删除。

3. **多区域资源**: 脚本只清理当前配置区域的资源。如果在其他区域部署过资源，需要切换区域后再次运行。

4. **备份建议**: 在执行清理前，建议备份重要数据。

5. **权限要求**: 执行清理需要相应的 AWS IAM 权限。

## 故障排除

### 权限错误
如果遇到权限错误，确保您的 AWS 凭证具有删除相应资源的权限。

### 依赖关系错误
某些资源可能因为依赖关系无法删除。检查错误信息，手动处理依赖关系后重试。

### 区域问题
确保 AWS CLI 配置的默认区域是正确的：
```bash
aws configure get region
```

## 清理后的验证

1. 运行检查脚本确认没有遗留资源
2. 检查 AWS Cost Explorer 确认没有持续费用
3. 检查 CloudTrail 日志确认删除操作已执行

## Terraform State 清理

增强脚本会自动备份并清理 Terraform state 文件。备份文件保存在：
```
infrastructure/terraform/backup_states/
```

如需恢复，可以从备份目录复制文件。