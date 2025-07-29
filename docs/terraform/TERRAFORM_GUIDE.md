# Terraform 基础设施管理综合指南

## 目录

1. [概述](#概述)
2. [模块架构](#模块架构)
3. [迁移指南](#迁移指南)
4. [架构改进](#架构改进)
5. [业务映射](#业务映射)
6. [模块说明](#模块说明)
7. [最佳实践](#最佳实践)

## 概述

本项目使用 Terraform 管理所有 AWS 基础设施资源。采用模块化设计，支持多环境部署和可扩展架构。

### 目录结构

```
infrastructure/terraform/
├── main.tf                 # 主配置文件
├── variables.tf           # 变量定义
├── outputs.tf            # 输出定义
├── versions.tf           # 版本约束
├── terraform.tfvars      # 变量值（不提交到版本控制）
├── environments/         # 环境特定配置
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
└── modules/              # 可重用模块
    ├── api_gateway/      # API Gateway 模块
    ├── bedrock/         # Bedrock 集成模块
    ├── cognito/         # 认证模块
    ├── common/          # 共享资源模块
    ├── frontend/        # 前端托管模块
    ├── lambda/          # Lambda 函数模块
    ├── monitoring/      # 监控和日志模块
    ├── networking/      # 网络配置模块
    ├── s3/             # 存储模块
    └── storage-optimization/ # 存储优化模块
```

## 模块架构

### 核心模块

#### 1. Common 模块
提供共享资源和基础配置：
- IAM 角色和策略
- 共享标签
- 通用安全组
- KMS 密钥

#### 2. Networking 模块
管理网络基础设施：
- VPC 配置
- 子网（公有/私有）
- NAT 网关
- 路由表
- VPC 端点

#### 3. Storage 模块
管理数据存储：
- S3 存储桶
- 生命周期策略
- 版本控制
- 加密配置
- 访问策略

#### 4. Lambda 模块
管理无服务器计算：
- Lambda 函数
- 层（Layers）
- 环境变量
- 权限策略
- 事件触发器

#### 5. API Gateway 模块
管理 API 接口：
- REST API 定义
- 资源和方法
- 集成配置
- CORS 设置
- 使用计划

#### 6. Frontend 模块
管理前端托管：
- S3 静态网站托管
- CloudFront 分发
- 域名配置
- SSL 证书
- 缓存策略

#### 7. Cognito 模块
管理用户认证：
- 用户池
- 应用客户端
- 联合身份
- 触发器
- 自定义域

#### 8. Bedrock 模块
管理 AI/ML 集成：
- Knowledge Base
- 数据源
- 向量数据库
- 模型权限
- RAG 配置

#### 9. Monitoring 模块
管理监控和日志：
- CloudWatch 日志组
- 指标和告警
- 仪表板
- 日志保留
- 成本追踪

#### 10. Storage Optimization 模块
优化存储成本和性能：
- 智能分层
- 生命周期管理
- 访问分析
- 成本优化
- 性能监控

## 迁移指南

### 从 CloudFormation 迁移到 Terraform

#### 准备阶段

1. **资源清单**
   ```bash
   # 导出现有资源
   aws cloudformation describe-stack-resources \
     --stack-name your-stack-name > resources.json
   ```

2. **状态备份**
   ```bash
   # 备份 CloudFormation 堆栈
   aws cloudformation create-change-set \
     --stack-name your-stack-name \
     --change-set-name backup-$(date +%Y%m%d%H%M%S)
   ```

#### 迁移步骤

1. **创建 Terraform 配置**
   ```hcl
   # 导入现有资源示例
   resource "aws_s3_bucket" "existing" {
     bucket = "your-existing-bucket"
   }
   ```

2. **导入资源**
   ```bash
   terraform import aws_s3_bucket.existing your-existing-bucket
   terraform import aws_lambda_function.existing your-function-name
   ```

3. **验证配置**
   ```bash
   terraform plan
   # 确保没有资源会被销毁
   ```

4. **逐步迁移**
   - 先迁移无状态资源（S3、IAM）
   - 再迁移计算资源（Lambda、API Gateway）
   - 最后迁移有状态资源（RDS、DynamoDB）

## 架构改进

### 改进报告摘要

基于架构分析，以下是主要改进建议：

#### 1. 模块化改进
- **问题**: 模块间耦合度高
- **解决方案**: 
  - 定义清晰的模块接口
  - 使用输出变量传递数据
  - 避免模块间直接引用

#### 2. 环境隔离
- **问题**: 环境配置混合
- **解决方案**:
  - 使用 Terraform 工作空间
  - 环境特定的变量文件
  - 独立的状态后端

#### 3. 安全加固
- **问题**: 权限过于宽松
- **解决方案**:
  - 实施最小权限原则
  - 使用 IAM 条件
  - 启用日志和审计

#### 4. 成本优化
- **问题**: 资源利用率低
- **解决方案**:
  - 实施自动扩展
  - 使用预留实例
  - 配置生命周期策略

### 实施路线图

1. **第一阶段**（1-2 周）
   - 重构模块结构
   - 实施环境隔离
   - 更新文档

2. **第二阶段**（2-3 周）
   - 安全加固
   - 性能优化
   - 监控增强

3. **第三阶段**（3-4 周）
   - 成本优化
   - 自动化测试
   - CI/CD 集成

## 业务映射

### 技术组件到业务功能映射

#### 1. 用户管理系统
- **Cognito 用户池**: 用户注册/登录
- **Lambda 授权器**: API 访问控制
- **DynamoDB**: 用户配置存储

#### 2. 文档处理系统
- **S3 存储桶**: 文档存储
- **Lambda 处理器**: 文档解析
- **Bedrock**: 向量化处理

#### 3. 查询系统
- **API Gateway**: 查询接口
- **Lambda 查询处理器**: 业务逻辑
- **Knowledge Base**: RAG 检索

#### 4. 前端系统
- **S3 + CloudFront**: 应用托管
- **Route 53**: 域名解析
- **ACM**: SSL 证书

### 成本分配

| 业务功能 | 主要成本组件 | 优化建议 |
|---------|------------|---------|
| 用户认证 | Cognito | 使用联合身份减少 MAU 成本 |
| 文档存储 | S3 | 实施智能分层和生命周期 |
| API 调用 | Lambda + API Gateway | 使用缓存和批处理 |
| 内容分发 | CloudFront | 优化缓存策略 |

## 模块说明

### Common 模块

提供跨模块共享的基础资源：

```hcl
module "common" {
  source = "./modules/common"
  
  project_name = var.project_name
  environment  = var.environment
  tags         = var.tags
}
```

**输出**:
- `lambda_execution_role_arn`: Lambda 执行角色
- `kms_key_id`: 加密密钥
- `common_tags`: 标准标签

### Storage Optimization 模块

实施存储成本和性能优化：

```hcl
module "storage_optimization" {
  source = "./modules/storage-optimization"
  
  bucket_name = module.s3.bucket_name
  enable_intelligent_tiering = true
  enable_lifecycle_rules = true
}
```

**功能**:
- 自动数据分层
- 过期数据清理
- 访问模式分析
- 成本报告

### Cognito 模块分离

认证系统已从 API Gateway 模块分离：

```hcl
module "cognito" {
  source = "./modules/cognito"
  
  project_name = var.project_name
  environment  = var.environment
  
  # 可选配置
  enable_mfa = var.enable_mfa
  password_policy = var.password_policy
}
```

**优势**:
- 独立管理认证系统
- 支持多应用共享
- 灵活的安全策略
- 简化的权限管理

## 最佳实践

### 1. 状态管理

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket = "terraform-state-bucket"
    key    = "rag-system/terraform.tfstate"
    region = "us-east-1"
    
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

### 2. 变量组织

```hcl
# 按类型组织变量
variable "networking_config" {
  type = object({
    vpc_cidr             = string
    public_subnet_cidrs  = list(string)
    private_subnet_cidrs = list(string)
    enable_nat_gateway   = bool
  })
}

variable "application_config" {
  type = object({
    lambda_memory_size = number
    lambda_timeout     = number
    api_throttle_limit = number
  })
}
```

### 3. 输出标准化

```hcl
# 使用一致的输出格式
output "api_endpoints" {
  value = {
    base_url     = module.api_gateway.base_url
    health_check = "${module.api_gateway.base_url}/health"
    docs         = "${module.api_gateway.base_url}/docs"
  }
}

output "frontend_urls" {
  value = {
    cloudfront = module.frontend.cloudfront_url
    s3_website = module.frontend.s3_website_url
  }
}
```

### 4. 标签策略

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CostCenter  = var.cost_center
    Owner       = var.owner_email
  }
}
```

### 5. 安全最佳实践

- 使用 AWS Secrets Manager 存储敏感信息
- 实施资源级 IAM 策略
- 启用所有日志记录
- 使用 VPC 端点避免公网暴露
- 定期审计权限

### 6. 成本优化

- 使用 `terraform plan` 预估成本变化
- 实施资源标签以追踪成本
- 配置预算告警
- 定期审查未使用资源
- 使用 Spot 实例（适用时）

### 7. 维护建议

1. **版本控制**
   - 锁定 Terraform 和提供者版本
   - 使用语义化版本管理
   - 记录重大变更

2. **代码审查**
   - 所有变更需要审查
   - 运行 `terraform fmt` 和 `terraform validate`
   - 使用 `tflint` 进行静态分析

3. **文档维护**
   - 保持 README 更新
   - 记录所有自定义模块
   - 维护架构图

4. **灾难恢复**
   - 定期备份状态文件
   - 测试恢复流程
   - 维护回滚计划

---

**文档版本**: v1.0  
**最后更新**: 2025-07-28  
**维护团队**: infrastructure@example.com