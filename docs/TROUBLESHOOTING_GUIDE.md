# AWS RAG System 综合故障排查指南

## 目录

1. [快速诊断流程](#快速诊断流程)
2. [常见错误及解决方案](#常见错误及解决方案)
3. [组件级故障排查](#组件级故障排查)
4. [性能问题诊断](#性能问题诊断)
5. [日志分析指南](#日志分析指南)
6. [紧急恢复流程](#紧急恢复流程)
7. [预防措施](#预防措施)

## 快速诊断流程

### 系统健康检查清单

```bash
#!/bin/bash
# 快速健康检查脚本

echo "1. 检查 API Gateway 状态..."
curl -s -o /dev/null -w "%{http_code}" https://<api-gateway-url>/health

echo "2. 检查 Lambda 函数状态..."
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `rag-`)].{Name:FunctionName,State:State}'

echo "3. 检查 S3 桶访问..."
aws s3 ls s3://<bucket-name> --max-items 1

echo "4. 检查 CloudFront 分发..."
aws cloudfront list-distributions --query 'DistributionList.Items[?Comment==`RAG System`].{Id:Id,Status:Status}'

echo "5. 验证 Knowledge Base 配置..."
./scripts/get-knowledge-base-info.sh

echo "6. 完整部署验证..."
./scripts/validate-deployment.sh
```

## 常见错误及解决方案

### 1. 查询失败错误

#### 问题描述
在使用聊天功能时出现"查询失败"错误。

#### 根本原因
Knowledge Base ID环境变量未正确配置到Lambda函数中。

#### 诊断步骤

1. **运行诊断脚本**
   ```bash
   ./scripts/get-knowledge-base-info.sh
   ```
   此脚本将显示：
   - 当前的Knowledge Base ID和状态
   - Lambda函数的环境变量配置
   - 建议的修复方法

2. **验证部署状态**
   ```bash
   ./scripts/validate-deployment.sh
   ```

#### 解决方案

**方案1：完整重新部署（推荐）**
```bash
cd infrastructure/terraform
terraform apply
```

**方案2：仅更新Lambda函数**
```bash
cd infrastructure/terraform
terraform apply -target=module.query_handler
```

**方案3：手动更新环境变量**
```bash
# 获取Knowledge Base ID
./scripts/get-knowledge-base-info.sh

# 更新Lambda环境变量
aws lambda update-function-configuration \
  --function-name enterprise-rag-query-handler-dev \
  --environment Variables="{KNOWLEDGE_BASE_ID=<your-kb-id>,DATA_SOURCE_ID=<your-ds-id>}" \
  --region us-east-1
```

### 2. 部署错误

#### Terraform 初始化失败
```
Error: Failed to get existing workspaces: S3 bucket does not exist
```

**原因**: Terraform 后端 S3 桶不存在

**解决方案**:
```bash
# 创建后端桶
aws s3 mb s3://terraform-state-bucket-name

# 或使用本地后端
terraform init -backend=false
```

#### IAM 角色创建失败
```
Error: creating IAM Role: AccessDenied
```

**原因**: 没有创建 IAM 角色的权限

**解决方案**:
1. 确保部署用户有 `iam:CreateRole` 权限
2. 或使用已有角色：
   ```hcl
   # 在 terraform.tfvars 中
   use_existing_role = true
   existing_role_arn = "arn:aws:iam::123456789012:role/existing-role"
   ```

### 3. Lambda 函数错误

#### Lambda 超时
```
Task timed out after 300.00 seconds
```

**原因**: 处理时间超过配置的超时时间

**解决方案**:
```bash
# 增加超时时间
aws lambda update-function-configuration \
  --function-name rag-query-handler \
  --timeout 900

# 或优化代码性能
```

#### 内存不足
```
Runtime exited with error: signal: killed Runtime.ExitError
```

**原因**: Lambda 内存配置不足

**解决方案**:
```bash
# 增加内存配置
aws lambda update-function-configuration \
  --function-name rag-query-handler \
  --memory-size 1024
```

### 4. API Gateway 错误

#### 502 Bad Gateway
```json
{
  "message": "Internal server error"
}
```

**诊断步骤**:
1. 检查 Lambda 日志
2. 检查 API Gateway 日志
3. 验证集成配置

**解决方案**:
```bash
# 查看 Lambda 日志
aws logs tail /aws/lambda/rag-query-handler --follow

# 检查 API Gateway 配置
aws apigateway get-integration \
  --rest-api-id <api-id> \
  --resource-id <resource-id> \
  --http-method POST
```

#### CORS 错误
```
Access to fetch at 'https://api.example.com' from origin 'https://app.example.com' has been blocked by CORS policy
```

**解决方案**:
```bash
# 更新 CORS 配置
aws apigateway put-method-response \
  --rest-api-id <api-id> \
  --resource-id <resource-id> \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{"method.response.header.Access-Control-Allow-Origin":true}'
```

### 5. S3 和 CloudFront 错误

#### 403 Forbidden
```xml
<Error>
  <Code>AccessDenied</Code>
  <Message>Access Denied</Message>
</Error>
```

**原因**: S3 桶策略或 CloudFront OAI 配置错误

**解决方案**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity <OAI-ID>"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::bucket-name/*"
    }
  ]
}
```

### 6. Bedrock 相关错误

#### 模型访问错误
如果出现模型访问错误：
1. 确保在该区域启用了所需的Bedrock模型
2. 检查IAM角色是否有`bedrock:InvokeModel`权限
3. 验证模型ID是否正确

#### Knowledge Base 错误
1. 检查Knowledge Base状态是否为ACTIVE
2. 验证数据源同步状态
3. 确保向量数据库配置正确

## 组件级故障排查

### Lambda 函数诊断

```bash
# 1. 检查函数配置
aws lambda get-function-configuration --function-name rag-query-handler

# 2. 查看最近的调用
aws lambda list-function-event-invoke-configs --function-name rag-query-handler

# 3. 测试函数
aws lambda invoke \
  --function-name rag-query-handler \
  --payload '{"test": true}' \
  output.json

# 4. 查看并发执行
aws lambda get-function-concurrency --function-name rag-query-handler

# 5. 检查环境变量
aws lambda get-function-configuration \
  --function-name enterprise-rag-query-handler-dev \
  --query 'Environment.Variables'
```

### API Gateway 诊断

```bash
# 1. 获取 API 信息
aws apigateway get-rest-api --rest-api-id <api-id>

# 2. 查看部署历史
aws apigateway get-deployments --rest-api-id <api-id>

# 3. 测试 API
aws apigateway test-invoke-method \
  --rest-api-id <api-id> \
  --resource-id <resource-id> \
  --http-method POST \
  --body '{"query": "test"}'

# 4. 查看使用计划
aws apigateway get-usage-plans
```

### S3 诊断

```bash
# 1. 检查桶配置
aws s3api get-bucket-versioning --bucket <bucket-name>
aws s3api get-bucket-encryption --bucket <bucket-name>
aws s3api get-bucket-policy --bucket <bucket-name>

# 2. 检查对象
aws s3api head-object --bucket <bucket-name> --key <object-key>

# 3. 列出最近修改的对象
aws s3api list-objects-v2 \
  --bucket <bucket-name> \
  --query 'sort_by(Contents, &LastModified)[-10:]'
```

## 性能问题诊断

### Lambda 冷启动分析

```python
# CloudWatch Insights 查询
fields @timestamp, @type, @message
| filter @type = "REPORT"
| stats avg(@duration), max(@duration), min(@duration) by bin(5m)
```

### API 响应时间分析

```bash
# 启用详细监控
aws apigateway update-stage \
  --rest-api-id <api-id> \
  --stage-name prod \
  --patch-operations op=replace,path=/methodSettings/*/*/metricsEnabled,value=true
```

### 内存使用分析

```python
# Lambda 函数中添加内存监控
import psutil

def handler(event, context):
    memory_usage = psutil.Process().memory_info().rss / 1024 / 1024
    print(f"Memory usage: {memory_usage} MB")
    
    # 业务逻辑
    
    return response
```

## 日志分析指南

### CloudWatch Logs Insights 查询示例

#### 查找错误
```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

#### 分析延迟
```
fields @timestamp, @duration
| filter @type = "REPORT"
| stats avg(@duration), p99(@duration), max(@duration) by bin(5m)
```

#### 追踪特定请求
```
fields @timestamp, @requestId, @message
| filter @requestId = "specific-request-id"
| sort @timestamp asc
```

### 关键日志位置
- Lambda函数日志：`/aws/lambda/enterprise-rag-query-handler-dev`
- API Gateway日志：`/aws/api-gateway/enterprise-rag-api-dev`

### 日志聚合和告警

```bash
# 创建指标过滤器
aws logs put-metric-filter \
  --log-group-name /aws/lambda/rag-query-handler \
  --filter-name errors \
  --filter-pattern "[ERROR]" \
  --metric-transformations \
    metricName=Errors,metricNamespace=RAGSystem,metricValue=1

# 创建告警
aws cloudwatch put-metric-alarm \
  --alarm-name rag-high-error-rate \
  --alarm-description "High error rate in RAG system" \
  --metric-name Errors \
  --namespace RAGSystem \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

## 紧急恢复流程

### 1. 服务降级

```bash
# 切换到维护模式
aws s3 cp maintenance.html s3://frontend-bucket/index.html

# 限制 API 访问
aws apigateway update-usage-plan \
  --usage-plan-id <plan-id> \
  --patch-operations op=replace,path=/throttle/rateLimit,value=100
```

### 2. 快速回滚

```bash
# Lambda 函数回滚
aws lambda update-function-code \
  --function-name rag-query-handler \
  --s3-bucket deployment-bucket \
  --s3-key lambda/previous-version.zip

# Terraform 回滚
cd infrastructure/terraform
terraform apply -target=module.lambda -var="lambda_version=previous"
```

### 3. 数据恢复

```bash
# 从 S3 版本恢复
aws s3api list-object-versions \
  --bucket <bucket-name> \
  --prefix important-data/

# 恢复特定版本
aws s3api copy-object \
  --bucket <bucket-name> \
  --copy-source <bucket-name>/object-key?versionId=<version-id> \
  --key object-key
```

### 4. 紧急联系人

创建紧急响应清单：

```yaml
# emergency-contacts.yaml
on-call:
  primary: +1-xxx-xxx-xxxx
  secondary: +1-xxx-xxx-xxxx

escalation:
  level1: ops-team@example.com
  level2: engineering-lead@example.com
  level3: cto@example.com

external:
  aws-support: https://console.aws.amazon.com/support/
  vendor-support: support@vendor.com
```

## 预防措施

### 1. 监控设置

```bash
# 创建仪表板
aws cloudwatch put-dashboard \
  --dashboard-name RAGSystemHealth \
  --dashboard-body file://dashboard-config.json
```

### 2. 自动化测试

```bash
# 定期健康检查
*/5 * * * * /opt/scripts/health-check.sh || /opt/scripts/alert.sh
```

### 3. 备份策略

```bash
# 自动备份脚本
0 2 * * * aws s3 sync s3://prod-bucket s3://backup-bucket --delete
```

### 4. 部署后验证
- 始终在部署后运行验证脚本
- 检查Terraform输出确保所有资源ID都存在
- 记录所有环境变量要求
- 维护部署检查清单

## 网络连接问题

如果Lambda函数超时：
1. 检查VPC配置（如果使用）
2. 验证安全组规则
3. 确保NAT网关配置正确（对于私有子网中的Lambda）

## 获取帮助

如果问题仍然存在：

1. 收集诊断信息：
   ```bash
   ./scripts/validate-deployment.sh > deployment-diagnosis.txt
   ```

2. 检查CloudWatch日志并导出相关日志

3. 提供以下信息寻求帮助：
   - 错误消息截图
   - deployment-diagnosis.txt文件
   - 相关的CloudWatch日志
   - 系统架构图和配置详情

---

**文档版本**: v2.0  
**最后更新**: 2025-07-28  
**紧急联系**: ops-team@example.com