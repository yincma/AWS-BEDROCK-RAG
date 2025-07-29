# AWS Bedrock RAG 系统架构指南

## 目录

1. [系统架构概览](#系统架构概览)
2. [核心组件](#核心组件)
3. [数据流](#数据流)
4. [技术栈](#技术栈)
5. [部署架构](#部署架构)
6. [扩展性设计](#扩展性设计)

## 系统架构概览

### 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            用户界面层                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  React 前端应用  │  CloudFront CDN  │  S3 静态托管  │  Route 53 DNS    │
└──────────────────┴───────────────────┴──────────────┴──────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             API 网关层                                   │
├─────────────────────────────────────────────────────────────────────────┤
│        API Gateway       │      WAF       │      CloudWatch             │
└─────────────────────────┴────────────────┴─────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           业务逻辑层                                     │
├─────────────────────────────────────────────────────────────────────────┤
│   Lambda Functions   │   Step Functions   │   EventBridge              │
│   ├─ Query Handler   │                    │                            │
│   ├─ Doc Processor   │                    │                            │
│   └─ Auth Handler    │                    │                            │
└──────────────────────┴────────────────────┴─────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            数据层                                        │
├─────────────────────────────────────────────────────────────────────────┤
│      S3 存储桶       │   DynamoDB    │   OpenSearch   │   RDS (可选)   │
│   ├─ 原始文档        │   会话存储     │   向量索引      │   元数据存储    │
│   └─ 处理后数据      │               │                │                │
└──────────────────────┴───────────────┴────────────────┴────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           AI/ML 服务层                                   │
├─────────────────────────────────────────────────────────────────────────┤
│    Bedrock Foundation Models    │    Knowledge Base    │   Embeddings   │
│    ├─ Claude                   │                      │                │
│    ├─ Titan                    │                      │                │
│    └─ Llama                    │                      │                │
└─────────────────────────────────┴──────────────────────┴───────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          安全和监控层                                    │
├─────────────────────────────────────────────────────────────────────────┤
│   Cognito   │   IAM   │   KMS   │   CloudTrail   │   X-Ray   │   SNS  │
└─────────────┴─────────┴─────────┴────────────────┴───────────┴─────────┘
```

### 系统特性

- **无服务器架构**: 完全基于 AWS 托管服务，无需管理服务器
- **高可用性**: 多可用区部署，自动故障转移
- **弹性伸缩**: 根据负载自动扩展
- **安全合规**: 端到端加密，细粒度访问控制
- **成本优化**: 按使用付费，无闲置资源

## 核心组件

### 1. 前端组件

#### React 应用
- **功能**: 用户界面，交互逻辑
- **技术**: React 18, TypeScript, Material-UI
- **特性**: 
  - 响应式设计
  - PWA 支持
  - 实时聊天界面
  - 文档上传管理

#### CloudFront 分发
- **功能**: 全球内容分发，缓存优化
- **配置**:
  - 多源站配置（S3 + API Gateway）
  - 自定义错误页面
  - HTTPS 强制
  - 压缩启用

### 2. API 层组件

#### API Gateway
- **类型**: REST API
- **功能**: 
  - 请求路由
  - 认证授权
  - 限流控制
  - 请求/响应转换

#### 主要端点
```
POST   /api/chat          - 聊天查询
POST   /api/documents     - 文档上传
GET    /api/documents     - 文档列表
DELETE /api/documents/:id - 文档删除
GET    /api/health        - 健康检查
```

### 3. 计算层组件

#### Lambda 函数

##### Query Handler
```python
# 主要职责
- 接收用户查询
- 调用 Knowledge Base
- 格式化响应
- 会话管理

# 配置
Memory: 1024 MB
Timeout: 60 seconds
Runtime: Python 3.11
Layers: 
  - Bedrock SDK
  - Common Utils
```

##### Document Processor
```python
# 主要职责
- 文档解析（PDF, DOCX, TXT）
- 文本分块
- 向量化处理
- 元数据提取

# 配置
Memory: 2048 MB
Timeout: 300 seconds
Runtime: Python 3.11
Layers:
  - Document Parser
  - Bedrock SDK
```

##### Auth Handler
```python
# 主要职责
- Token 验证
- 权限检查
- 会话管理
- 审计日志

# 配置
Memory: 512 MB
Timeout: 10 seconds
Runtime: Python 3.11
```

### 4. 存储层组件

#### S3 存储结构
```
rag-system-bucket/
├── documents/
│   ├── raw/              # 原始上传文档
│   ├── processed/        # 处理后的文档
│   └── embeddings/       # 向量数据
├── frontend/
│   ├── static/          # 静态资源
│   └── index.html       # 主页面
└── logs/                # 应用日志
```

#### DynamoDB 表设计
```
Sessions Table:
  - PK: session_id
  - SK: timestamp
  - Attributes: user_id, messages, context

Documents Table:
  - PK: document_id
  - SK: version
  - Attributes: metadata, status, owner

Users Table:
  - PK: user_id
  - Attributes: profile, preferences, quota
```

### 5. AI/ML 组件

#### Bedrock Knowledge Base
- **向量数据库**: OpenSearch Serverless
- **嵌入模型**: Titan Embeddings G1
- **分块策略**: 
  - 固定大小: 512 tokens
  - 重叠: 20%

#### 模型配置
```python
MODEL_CONFIGS = {
    "claude-3-sonnet": {
        "max_tokens": 4096,
        "temperature": 0.7,
        "top_p": 0.9
    },
    "titan-text-express": {
        "max_tokens": 2048,
        "temperature": 0.5,
        "top_p": 0.95
    }
}
```

## 数据流

### 1. 查询流程

```
用户输入 → CloudFront → API Gateway → Lambda Authorizer
    ↓
Lambda Query Handler → Knowledge Base Search
    ↓
向量检索 → 相关文档片段 → Bedrock LLM
    ↓
生成响应 → 格式化 → API Gateway → CloudFront → 用户
```

### 2. 文档处理流程

```
文档上传 → S3 原始存储 → EventBridge 触发
    ↓
Document Processor Lambda:
    1. 文档解析
    2. 文本提取
    3. 智能分块
    4. 向量化
    ↓
存储向量 → 更新 Knowledge Base → 发送通知
```

### 3. 认证流程

```
用户登录 → Cognito User Pool → JWT Token
    ↓
API 请求 (带 Token) → API Gateway → Lambda Authorizer
    ↓
验证 Token → 检查权限 → 允许/拒绝请求
```

## 技术栈

### 前端技术
- **框架**: React 18.2.0
- **语言**: TypeScript 5.0
- **UI 库**: Material-UI 5.x
- **状态管理**: Redux Toolkit
- **构建工具**: Webpack 5
- **测试**: Jest + React Testing Library

### 后端技术
- **运行时**: Python 3.11
- **框架**: AWS Lambda Powertools
- **SDK**: Boto3, AWS SDK for Bedrock
- **测试**: Pytest
- **部署**: AWS SAM / Terraform

### 基础设施
- **IaC**: Terraform 1.5+
- **CI/CD**: GitHub Actions
- **监控**: CloudWatch + X-Ray
- **安全扫描**: AWS Security Hub

## 部署架构

### 多环境策略

```
开发环境 (dev)
├── 独立 AWS 账户
├── 较小实例规格
├── 模拟数据
└── 开放 CORS

测试环境 (staging)
├── 独立 AWS 账户
├── 生产级配置
├── 真实数据副本
└── 性能测试

生产环境 (prod)
├── 独立 AWS 账户
├── 多区域部署
├── 自动扩展
└── 完整监控
```

### 区域部署

```
主区域 (us-east-1)
├── 所有核心服务
├── 主数据存储
└── 全球 CloudFront

灾备区域 (us-west-2)
├── 只读副本
├── 数据同步
└── 故障转移准备
```

### 网络架构

```
VPC 设计:
├── CIDR: 10.0.0.0/16
├── 公有子网: 
│   ├── 10.0.1.0/24 (AZ-1)
│   └── 10.0.2.0/24 (AZ-2)
├── 私有子网:
│   ├── 10.0.11.0/24 (AZ-1)
│   └── 10.0.12.0/24 (AZ-2)
└── NAT 网关: 每个 AZ 一个
```

## 扩展性设计

### 1. 水平扩展

#### Lambda 并发控制
```python
# 预留并发配置
CONCURRENCY_CONFIG = {
    "query_handler": {
        "reserved": 100,
        "max": 1000
    },
    "document_processor": {
        "reserved": 20,
        "max": 100
    }
}
```

#### API Gateway 限流
```json
{
  "throttle": {
    "burstLimit": 5000,
    "rateLimit": 2000
  },
  "quota": {
    "limit": 1000000,
    "period": "DAY"
  }
}
```

### 2. 性能优化

#### 缓存策略
- CloudFront: 静态资源缓存 1 年
- API Gateway: GET 请求缓存 5 分钟
- Lambda: 内存缓存热点数据
- ElastiCache: 会话和查询结果缓存

#### 异步处理
```python
# 大文件处理队列
SQS_QUEUES = {
    "document_processing": {
        "visibility_timeout": 900,
        "message_retention": 14,
        "dlq_enabled": True
    }
}
```

### 3. 容错设计

#### 重试策略
```python
RETRY_CONFIG = {
    "max_attempts": 3,
    "backoff": "exponential",
    "base_delay": 1,
    "max_delay": 20
}
```

#### 断路器模式
```python
class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout=60):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = "CLOSED"
```

### 4. 监控和告警

#### 关键指标
```yaml
业务指标:
  - 查询成功率: > 99.9%
  - 平均响应时间: < 2s
  - 文档处理时间: < 5min

技术指标:
  - Lambda 错误率: < 0.1%
  - API Gateway 4xx: < 1%
  - API Gateway 5xx: < 0.1%

成本指标:
  - 每请求成本: < $0.01
  - 月度预算使用率: < 80%
```

#### 告警配置
```python
ALARMS = {
    "high_error_rate": {
        "metric": "Errors",
        "threshold": 10,
        "period": 300,
        "severity": "HIGH"
    },
    "high_latency": {
        "metric": "Duration",
        "threshold": 5000,
        "period": 300,
        "severity": "MEDIUM"
    }
}
```

---

**文档版本**: v1.0  
**最后更新**: 2025-07-28  
**架构师**: architect@example.com