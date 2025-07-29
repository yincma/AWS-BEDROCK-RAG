# 配置管理指南

## 概述

本文档描述了AWS Bedrock RAG系统的配置管理方法。我们已经将所有硬编码的值迁移到环境变量中，实现了配置的集中管理和灵活性。

## 配置架构

### 1. 环境变量层次

```
├── .env.example          # 环境变量模板
├── .env                  # 本地环境变量（不提交到Git）
├── applications/
│   └── backend/
│       └── shared/
│           └── config.py # Python配置管理模块
└── infrastructure/
    └── terraform/
        └── variables.tf  # Terraform变量定义
```

### 2. 配置优先级

1. **环境变量** - 最高优先级
2. **配置文件** - 中等优先级（.env文件）
3. **默认值** - 最低优先级

## 配置项说明

### 基础配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `PROJECT_NAME` | 项目名称 | enterprise-rag |
| `ENVIRONMENT` | 环境名称 | dev |
| `REGION` | AWS区域（注意：不使用AWS_REGION） | us-east-1 |
| `LOG_LEVEL` | 日志级别 | INFO |

> ⚠️ **重要提示**：Lambda运行时会自动设置`AWS_REGION`环境变量，这是一个保留的环境变量，不能被覆盖。在代码中，应该使用`os.environ['AWS_REGION']`来获取当前区域，或使用我们设置的`REGION`变量。

### CORS配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `CORS_ALLOW_ORIGIN` | 允许的源 | * |
| `CORS_ALLOW_METHODS` | 允许的HTTP方法 | GET,POST,PUT,DELETE,OPTIONS |
| `CORS_ALLOW_HEADERS` | 允许的请求头 | Content-Type,Authorization等 |
| `CORS_ALLOW_CREDENTIALS` | 是否允许凭证 | false |

### 文档处理配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `ALLOWED_FILE_EXTENSIONS` | 允许的文件扩展名 | .pdf,.txt,.docx,.doc,.md,.csv,.json |
| `MAX_FILE_SIZE_MB` | 最大文件大小(MB) | 100 |
| `DOCUMENT_PREFIX` | S3文档前缀 | documents/ |
| `PRESIGNED_URL_EXPIRY_SECONDS` | 预签名URL过期时间(秒) | 900 |

### Lambda配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `LAMBDA_MEMORY_SIZE` | Lambda内存大小(MB) | 1024 |
| `LAMBDA_TIMEOUT` | Lambda超时时间(秒) | 300 |
| `LAMBDA_RESERVED_CONCURRENCY` | 预留并发数 | -1 |

## 使用方法

### 1. 本地开发

1. 复制环境变量模板：
   ```bash
   cp .env.example .env
   ```

2. 编辑 `.env` 文件，设置必要的值：
   ```bash
   S3_BUCKET=your-bucket-name
   KNOWLEDGE_BASE_ID=your-kb-id
   DATA_SOURCE_ID=your-ds-id
   ```

3. 加载环境变量：
   ```bash
   source .env
   ```

### 2. Lambda函数中使用

#### 使用配置模块（推荐）

```python
from shared.config import get_config

# 获取配置实例
config = get_config()

# 使用配置
bucket_name = config.s3.document_bucket
allowed_extensions = config.document.allowed_file_extensions
cors_headers = config.get_cors_headers()
```

#### 直接使用环境变量（备用）

```python
import os

bucket_name = os.getenv('S3_BUCKET')
max_file_size = int(os.getenv('MAX_FILE_SIZE_MB', '100'))
```

### 3. Terraform部署

1. 在 `terraform.tfvars` 中设置变量：
   ```hcl
   cors_allow_origin = "https://example.com"
   max_file_size_mb = "200"
   ```

2. 或使用环境变量：
   ```bash
   export TF_VAR_cors_allow_origin="https://example.com"
   export TF_VAR_max_file_size_mb="200"
   ```

3. 应用配置：
   ```bash
   terraform apply
   ```

## 配置验证

### 1. 验证Lambda配置

运行验证脚本：
```bash
./test/verify_lambda_config.sh
```

### 2. 应急修复

如果需要快速更新Lambda环境变量：
```bash
./test/emergency_fix.sh
```

## 最佳实践

### 1. 环境隔离

- 为每个环境（dev, staging, prod）使用不同的配置文件
- 使用Terraform workspace管理多环境

### 2. 敏感信息管理

- 不要将敏感信息提交到Git
- 使用AWS Secrets Manager或Parameter Store存储敏感配置
- 在 `.gitignore` 中添加 `.env` 文件

### 3. 配置验证

- 在应用启动时验证必需的配置项
- 提供有意义的错误信息
- 使用配置摘要日志记录（隐藏敏感信息）

### 4. 配置更新

- 使用Terraform管理基础设施配置
- 通过CI/CD管道自动化配置部署
- 记录配置变更历史

## 配置迁移检查清单

- [x] 创建环境变量配置文件模板（.env.example）
- [x] 创建Python配置管理模块（config.py）
- [x] 重构Lambda函数使用配置模块
- [x] 更新Terraform配置添加新环境变量
- [x] 创建验证和修复脚本
- [x] 移除所有硬编码值

## 故障排查

### 问题：Lambda函数无法读取环境变量

**解决方案：**
1. 检查Terraform是否已应用：`terraform apply`
2. 验证Lambda配置：`./test/verify_lambda_config.sh`
3. 查看CloudWatch日志确认环境变量值

### 问题：CORS错误

**解决方案：**
1. 检查 `CORS_ALLOW_ORIGIN` 设置
2. 确保包含所有必要的请求头
3. 验证预检请求（OPTIONS）处理

### 问题：文件上传失败

**解决方案：**
1. 检查 `ALLOWED_FILE_EXTENSIONS` 包含文件类型
2. 验证 `MAX_FILE_SIZE_MB` 设置
3. 确认S3存储桶配置正确

## 配置参考

完整的配置项列表请参考：
- [.env.example](../.env.example) - 环境变量模板
- [config.py](../applications/backend/shared/config.py) - Python配置模块
- [variables.tf](../infrastructure/terraform/variables.tf) - Terraform变量定义

---

更新日期：2025-07-28