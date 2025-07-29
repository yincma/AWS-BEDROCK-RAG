# AWS Bedrock RAG 系统综合部署指南

## 目录

1. [概述](#概述)
2. [前置要求](#前置要求)
3. [快速部署](#快速部署)
4. [详细部署步骤](#详细部署步骤)
5. [环境配置](#环境配置)
6. [Cognito 认证配置](#cognito-认证配置)
7. [前端配置管理](#前端配置管理)
8. [高级选项](#高级选项)
9. [部署验证](#部署验证)
10. [故障排查](#故障排查)
11. [最佳实践](#最佳实践)

## 概述

AWS RAG System 是一个基于 AWS 服务构建的检索增强生成（RAG）系统。本指南将帮助您完成系统的完整部署和配置。

### 系统架构

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Frontend  │────▶│ API Gateway  │────▶│    Lambda    │
│  (S3 + CF)  │     │              │     │  Functions   │
└─────────────┘     └──────────────┘     └──────────────┘
                                                 │
                                        ┌────────▼────────┐
                                        │   S3 Storage    │
                                        │  (Documents)    │
                                        └─────────────────┘
                                                 │
                                        ┌────────▼────────┐
                                        │  Knowledge Base │
                                        │   (Bedrock)     │
                                        └─────────────────┘
```

### 主要组件

- **前端应用**: React 应用托管在 S3 + CloudFront
- **API 层**: API Gateway 提供 RESTful API
- **处理层**: Lambda 函数处理业务逻辑
- **存储层**: S3 存储文档和向量数据
- **知识库**: Bedrock Knowledge Base 提供 RAG 功能
- **认证**: Cognito 用户池（可选）

## 前置要求

### 必需工具

1. **AWS CLI** (v2.0+)
   ```bash
   # macOS
   brew install awscli
   
   # Linux
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

2. **Terraform** (v1.0+)
   ```bash
   # macOS
   brew tap hashicorp/tap
   brew install hashicorp/tap/terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
   unzip terraform_1.5.7_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Node.js** (v14+) 和 npm
   ```bash
   # 使用 nvm 安装
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
   nvm install 18
   nvm use 18
   ```

4. **Python** (v3.8+)
   ```bash
   # macOS
   brew install python@3.9
   
   # Linux
   sudo apt-get update
   sudo apt-get install python3.9 python3-pip
   ```

5. **其他工具**
   ```bash
   # jq - JSON 处理工具
   brew install jq  # macOS
   sudo apt-get install jq  # Linux
   
   # zip - 打包工具（通常已预装）
   ```

### AWS 配置

1. **配置 AWS 凭证**
   ```bash
   aws configure
   # 输入 AWS Access Key ID
   # 输入 AWS Secret Access Key
   # 输入默认区域 (建议: us-east-1)
   # 输入默认输出格式 (建议: json)
   ```

2. **验证配置**
   ```bash
   aws sts get-caller-identity
   ```

3. **必需的 AWS 权限**
   - IAM 管理权限
   - S3 完全访问
   - Lambda 管理权限
   - API Gateway 管理权限
   - CloudFront 管理权限
   - Cognito 管理权限
   - Bedrock 访问权限

## 快速部署

### 1. 克隆或解压部署包

```bash
# 如果是从 Git 克隆
git clone <repository-url>
cd AWS-Bedrock-RAG

# 如果是部署包
unzip AWS-Bedrock-RAG-Deployment.zip
cd AWS-Bedrock-RAG-Deployment
```

### 2. 安装依赖

```bash
# Python 依赖
pip install -r requirements.txt
pip install -r requirements-compatible.txt

# 前端依赖
cd applications/frontend
npm install
cd ../..
```

### 3. 快速部署脚本

```bash
# 创建快速部署脚本
cat > quick-deploy.sh << 'EOF'
#!/bin/bash
set -e

echo "开始部署 AWS Bedrock RAG 系统..."

# 1. 部署基础设施
echo "步骤 1: 部署 Terraform 基础设施..."
cd infrastructure/terraform
terraform init
terraform apply -auto-approve

# 2. 获取输出值
echo "步骤 2: 获取基础设施配置..."
terraform output -json > ../../terraform-outputs.json

# 3. 配置前端
echo "步骤 3: 配置前端应用..."
cd ../../applications/frontend
node scripts/setup-env-from-terraform.js

# 4. 构建和部署前端
echo "步骤 4: 构建和部署前端..."
npm run build
npm run deploy

echo "部署完成！"
EOF

chmod +x quick-deploy.sh
./quick-deploy.sh
```

## 详细部署步骤

### 步骤 1: 配置 Terraform 变量

```bash
cd infrastructure/terraform

# 创建 terraform.tfvars 文件
cat > terraform.tfvars << EOF
project_name = "aws-bedrock-rag"
environment = "dev"
aws_region = "us-east-1"

# Cognito 配置（可选）
enable_authentication = true

# 标签
tags = {
  Project = "AWS-Bedrock-RAG"
  Environment = "Development"
  ManagedBy = "Terraform"
}
EOF
```

### 步骤 2: 初始化并部署 Terraform

```bash
# 初始化 Terraform
terraform init

# 检查部署计划
terraform plan

# 执行部署
terraform apply
```

### 步骤 3: 保存 Terraform 输出

```bash
# 保存所有输出
terraform output -json > ../../terraform-outputs.json

# 查看特定输出
terraform output api_gateway_url
terraform output frontend_bucket_name
terraform output cloudfront_distribution_url
```

### 步骤 4: 配置前端环境变量

```bash
cd ../../applications/frontend

# 创建 .env 文件
cat > .env << EOF
REACT_APP_API_GATEWAY_URL=$(cd ../../infrastructure/terraform && terraform output -raw api_gateway_url)
REACT_APP_AWS_REGION=us-east-1
REACT_APP_USER_POOL_ID=$(cd ../../infrastructure/terraform && terraform output -json authentication | jq -r .user_pool_id)
REACT_APP_USER_POOL_CLIENT_ID=$(cd ../../infrastructure/terraform && terraform output -json authentication | jq -r .user_pool_client_id)
EOF

# 创建生产环境配置
cp .env .env.production
```

### 步骤 5: 构建和部署前端

```bash
# 生成配置文件
npm run generate-config

# 构建前端
npm run build

# 部署到 S3
export S3_BUCKET=$(cd ../../infrastructure/terraform && terraform output -raw frontend_bucket_name)
./scripts/deploy.sh
```

### 步骤 6: 配置 CloudFront 缓存失效

```bash
# 获取 CloudFront 分发 ID
DISTRIBUTION_ID=$(cd ../../infrastructure/terraform && terraform output -raw cloudfront_distribution_id)

# 创建缓存失效
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"
```

## 环境配置

### 开发环境

```bash
# applications/frontend/.env
REACT_APP_API_GATEWAY_URL=https://your-api-id.execute-api.us-east-1.amazonaws.com/dev
REACT_APP_AWS_REGION=us-east-1
REACT_APP_USER_POOL_ID=us-east-1_xxxxxxxxx
REACT_APP_USER_POOL_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 生产环境

```bash
# applications/frontend/.env.production
REACT_APP_API_GATEWAY_URL=https://your-api-id.execute-api.us-east-1.amazonaws.com/prod
REACT_APP_AWS_REGION=us-east-1
REACT_APP_USER_POOL_ID=us-east-1_xxxxxxxxx
REACT_APP_USER_POOL_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 环境特定配置

```hcl
# infrastructure/terraform/environments/dev.tfvars
environment = "dev"
enable_authentication = true
lambda_memory_size = 512
lambda_timeout = 300

# infrastructure/terraform/environments/prod.tfvars
environment = "prod"
enable_authentication = true
lambda_memory_size = 1024
lambda_timeout = 900
enable_monitoring = true
```

## Cognito 认证配置

### 1. 部署 Cognito 资源

Cognito 用户池会在 Terraform 部署时自动创建。如果遇到错误：

```
ResourceNotFoundException: User pool client xxx does not exist.
```

请确保：

1. Terraform 部署已成功完成
2. 在正确的 AWS 区域中操作
3. 使用正确的 Cognito 配置

### 2. 获取 Cognito 配置

```bash
cd infrastructure/terraform
terraform output -json authentication
```

输出示例：
```json
{
  "user_pool_id": "us-east-1_xxxxxxxxx",
  "user_pool_client_id": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
  "user_pool_domain": "enterprise-rag-dev",
  "user_pool_endpoint": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxxxxxxxx"
}
```

### 3. 配置回调 URL

```bash
# 获取 CloudFront URL
CLOUDFRONT_URL=$(terraform output -raw cloudfront_distribution_url)

# 更新 Cognito 客户端
aws cognito-idp update-user-pool-client \
  --user-pool-id $(terraform output -json authentication | jq -r .user_pool_id) \
  --client-id $(terraform output -json authentication | jq -r .user_pool_client_id) \
  --callback-urls "https://${CLOUDFRONT_URL}/callback" "http://localhost:3000/callback" \
  --logout-urls "https://${CLOUDFRONT_URL}/logout" "http://localhost:3000/logout"
```

### 4. 创建测试用户

```bash
# 创建用户
aws cognito-idp admin-create-user \
  --user-pool-id $(terraform output -json authentication | jq -r .user_pool_id) \
  --username testuser \
  --user-attributes Name=email,Value=test@example.com \
  --temporary-password TempPass123!

# 设置永久密码
aws cognito-idp admin-set-user-password \
  --user-pool-id $(terraform output -json authentication | jq -r .user_pool_id) \
  --username testuser \
  --password YourSecurePassword123! \
  --permanent
```

## 前端配置管理

### 配置文件说明

前端配置通过 `public/config.json` 管理，在不同环境下处理方式不同：

#### 本地开发
```
.env → generate-config.js → public/config.json → 应用加载
```

#### 生产部署
```
Terraform 变量 → aws_s3_object.frontend_config → S3/config.json → 应用加载
```

### 本地开发配置

```bash
# 从 .env 生成配置
npm run generate-config

# 开发服务器会自动生成
npm start
```

### 生产环境配置

配置由 Terraform 管理，自动部署到 S3：

```hcl
# infrastructure/terraform/modules/frontend/main.tf
resource "aws_s3_object" "frontend_config" {
  bucket = aws_s3_bucket.frontend_bucket.id
  key    = "config.json"
  content = jsonencode({
    apiGatewayUrl = var.api_gateway_url
    region        = var.aws_region
    userPoolId    = var.user_pool_id
    userPoolClientId = var.user_pool_client_id
  })
  content_type = "application/json"
}
```

### 更新配置

#### 本地环境
1. 修改 `.env` 文件
2. 运行 `npm run generate-config`
3. 重启开发服务器

#### 生产环境
1. 修改 Terraform 变量
2. 运行 `terraform apply`
3. CloudFront 缓存会自动失效

## 高级选项

### 自定义域名

```hcl
# terraform.tfvars
custom_domain_name = "rag.example.com"
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."
```

### VPC 配置

```hcl
# terraform.tfvars
enable_vpc = true
vpc_cidr = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
```

### 监控和告警

```hcl
# terraform.tfvars
enable_monitoring = true
alarm_email = "ops-team@example.com"
```

### 多环境部署

```bash
# 开发环境
terraform workspace new dev
terraform apply -var-file=environments/dev.tfvars

# 生产环境
terraform workspace new prod
terraform apply -var-file=environments/prod.tfvars
```

## 部署验证

### 1. 验证基础设施

```bash
# 运行验证脚本
./scripts/validate-deployment.sh

# 手动检查
aws s3 ls s3://$(terraform output -raw frontend_bucket_name)
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `enterprise-rag`)].FunctionName'
aws apigateway get-rest-apis --query 'items[?name==`enterprise-rag-api-dev`].id'
```

### 2. 验证前端部署

```bash
# 检查 CloudFront 状态
aws cloudfront get-distribution \
  --id $(terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.Status'

# 访问应用
echo "应用 URL: https://$(terraform output -raw cloudfront_distribution_url)"
```

### 3. 验证 API

```bash
# 测试健康检查
curl https://$(terraform output -raw api_gateway_url)/health

# 测试认证（如果启用）
curl -H "Authorization: Bearer <token>" \
  https://$(terraform output -raw api_gateway_url)/api/test
```

### 4. 验证 Knowledge Base

```bash
# 检查 Knowledge Base 状态
./scripts/get-knowledge-base-info.sh
```

## 故障排查

### 常见问题

1. **Terraform 初始化失败**
   ```bash
   # 清理并重新初始化
   rm -rf .terraform
   terraform init -upgrade
   ```

2. **Lambda 函数部署失败**
   ```bash
   # 检查 IAM 权限
   aws iam get-role --role-name enterprise-rag-lambda-role-dev
   ```

3. **前端部署失败**
   ```bash
   # 检查 S3 桶权限
   aws s3api get-bucket-policy --bucket $(terraform output -raw frontend_bucket_name)
   ```

4. **Cognito 配置错误**
   ```bash
   # 重新获取配置
   terraform output -json authentication
   ```

### 日志查看

```bash
# Lambda 日志
aws logs tail /aws/lambda/enterprise-rag-query-handler-dev --follow

# API Gateway 日志
aws logs tail /aws/api-gateway/enterprise-rag-api-dev --follow
```

## 最佳实践

### 1. 安全性
- 使用 IAM 角色而非访问密钥
- 启用 S3 桶版本控制
- 使用 HTTPS 进行所有通信
- 定期轮换密钥和密码

### 2. 成本优化
- 使用 Lambda 预留并发
- 配置 CloudFront 缓存策略
- 设置 S3 生命周期策略
- 监控和优化 Lambda 内存配置

### 3. 性能优化
- 使用 CloudFront 进行全球分发
- 优化 Lambda 冷启动
- 实施 API 缓存
- 使用 S3 Transfer Acceleration

### 4. 运维
- 实施自动化部署流程
- 配置监控和告警
- 定期备份重要数据
- 维护详细的部署文档

### 5. 开发流程
- 使用 Git 进行版本控制
- 实施 CI/CD 流程
- 进行代码审查
- 维护测试覆盖率

## 清理资源

当不再需要系统时，清理所有资源：

```bash
# 清理前端资源
aws s3 rm s3://$(terraform output -raw frontend_bucket_name) --recursive

# 销毁 Terraform 资源
cd infrastructure/terraform
terraform destroy

# 验证清理
aws s3 ls | grep enterprise-rag
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `enterprise-rag`)]'
```

---

**文档版本**: v2.0  
**最后更新**: 2025-07-28  
**联系方式**: support@example.com