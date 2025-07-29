# AWS 资源孤立检测和自动导入指南

## 概述

本系统提供了自动检测和导入AWS中存在但不在Terraform状态管理中的"孤立"资源的功能。这解决了常见的Terraform状态漂移问题。

## 功能特性

1. **自动检测**: 扫描AWS账户中的资源，与Terraform状态进行比对
2. **智能导入**: 自动生成并执行Terraform导入命令
3. **交互式操作**: 提供友好的用户界面，支持手动确认每个资源
4. **批量处理**: 支持自动模式，一次性导入所有检测到的资源
5. **可扩展性**: 通过配置文件轻松添加新的资源类型支持

## 使用方法

### 1. 基础使用

在部署时，系统会自动运行资源检测：

```bash
./deploy.sh
```

### 2. 跳过资源检测

如果需要跳过资源检测步骤：

```bash
./deploy.sh --skip-resource-check
```

### 3. 手动运行资源检测

#### 交互式模式（推荐）
```bash
./scripts/detect-and-import-resources.sh --env dev
```

#### 自动模式
```bash
./scripts/detect-and-import-resources.sh --env dev --auto
```

#### 模拟运行
```bash
./scripts/detect-and-import-resources.sh --env dev --dry-run
```

### 4. 使用扩展版本（支持更多资源类型）

```bash
./scripts/detect-resources-extended.sh --env dev
```

## 支持的资源类型

### 基础版本支持
- XRay 采样规则
- S3 存储桶
- Lambda 函数
- CloudWatch 日志组

### 扩展版本额外支持
- API Gateway REST API
- DynamoDB 表
- IAM 角色
- OpenSearch Serverless 资源
- Bedrock 知识库
- EventBridge 规则
- SNS 主题
- SQS 队列
- 更多...（查看 resource-types.conf）

## 配置文件

### resource-types.conf

资源类型配置文件定义了如何检测和导入各种AWS资源。格式如下：

```
资源类型|AWS类型|Terraform类型|检测命令|导入模式
```

示例：
```
xray_sampling_rule|xray|aws_xray_sampling_rule|aws xray get-sampling-rules...|module.monitoring.aws_xray_sampling_rule.main[0]
```

## 工作原理

1. **检测阶段**
   - 扫描Terraform配置，获取应该存在的资源列表
   - 查询AWS API，获取实际存在的资源
   - 比对两个列表，找出孤立资源

2. **导入阶段**
   - 为每个孤立资源生成合适的Terraform地址
   - 执行 `terraform import` 命令
   - 更新Terraform状态文件

3. **验证阶段**
   - 运行 `terraform plan` 确认导入成功
   - 检查是否还有其他配置差异

## 常见问题解决

### 1. XRay采样规则冲突

错误信息：
```
InvalidRequestException: A resource with the same resourceName but a different internalId already exists
```

解决方法：
```bash
# 方案1：自动导入
./scripts/detect-and-import-resources.sh --env dev --auto

# 方案2：手动导入
cd infrastructure/terraform
terraform import module.monitoring.aws_xray_sampling_rule.main[0] ${PROJECT_NAME}-sampling-${ENVIRONMENT}
```

### 2. 资源名称不匹配

如果自动检测无法找到资源，可能是命名模式不匹配。检查：
- 项目名称是否正确设置
- 环境名称是否匹配
- 资源命名是否遵循约定

### 3. 权限问题

确保AWS凭证具有以下权限：
- 列出和描述各种资源的权限
- Terraform状态操作权限

## 扩展资源类型

要添加新的资源类型支持：

1. 编辑 `resource-types.conf`
2. 添加新的资源类型行
3. 测试检测和导入功能

示例：
```bash
# 添加新的资源类型
echo "my_resource|myservice|aws_myservice_resource|aws myservice list-resources...|module.mymodule.aws_myservice_resource.\${RESOURCE_NAME}" >> scripts/resource-types.conf

# 测试
./scripts/detect-resources-extended.sh --env dev --dry-run
```

## 最佳实践

1. **定期运行**: 在每次部署前运行资源检测
2. **使用CI/CD**: 将资源检测集成到CI/CD流程中
3. **监控状态**: 定期检查Terraform状态的一致性
4. **备份状态**: 在导入前备份Terraform状态文件
5. **测试环境**: 先在测试环境验证导入过程

## 故障排除

### 启用详细日志
```bash
./scripts/detect-and-import-resources.sh --env dev --log-level DEBUG
```

### 查看日志文件
日志文件位置会在脚本执行后显示，通常在：
```
scripts/resource-import-YYYYMMDD-HHMMSS.log
```

### 手动状态操作
如果自动导入失败，可以手动操作：
```bash
# 查看当前状态
terraform state list

# 手动导入资源
terraform import <资源地址> <资源ID>

# 验证导入
terraform plan
```

## 安全注意事项

1. **谨慎删除**: 删除AWS资源是不可逆的操作
2. **验证导入**: 导入后始终运行 `terraform plan` 验证
3. **权限最小化**: 使用最小必要权限运行脚本
4. **备份重要数据**: 在操作生产环境前备份数据

## 贡献指南

欢迎贡献新的资源类型支持！请：
1. Fork 项目
2. 添加资源类型到 `resource-types.conf`
3. 测试检测和导入功能
4. 提交 Pull Request

## 版本历史

- v1.0: 初始版本，支持基础资源类型
- v1.1: 添加扩展资源类型支持
- v1.2: 集成到 deploy.sh 主脚本

## 相关文档

- [Terraform Import文档](https://www.terraform.io/docs/cli/import/index.html)
- [AWS CLI参考](https://docs.aws.amazon.com/cli/latest/reference/)
- [项目部署指南](../README.md)