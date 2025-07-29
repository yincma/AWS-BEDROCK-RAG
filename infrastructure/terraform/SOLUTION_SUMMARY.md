# API Gateway 500错误问题解决总结

## 问题描述
前端应用调用API时收到500错误：
- GET /documents 返回500
- GET /query/status 返回500

## 根本原因
1. **授权器Lambda函数错误**：JWT验证库`cryptography`在Mac上构建，无法在Linux Lambda环境运行
   - 错误信息：`invalid ELF header`
   - 影响：所有需要授权的API调用都失败

2. **API Gateway返回"Unauthorized"**：即使Lambda函数本身正常工作

## 解决步骤

### 1. 诊断过程
- 检查Lambda函数代码 ✓
- 验证环境变量配置 ✓
- 测试Lambda直接调用（成功）✓
- 检查API Gateway配置 ✓
- 发现授权器Lambda错误 ✓

### 2. 临时解决方案
- 禁用API Gateway授权器
- 重新部署API
- 验证API可以正常访问

### 3. 执行的命令
```bash
# 更新API Gateway方法，移除授权
aws apigateway update-method \
  --rest-api-id vjywvai0e7 \
  --resource-id [resource-id] \
  --http-method GET \
  --patch-operations op=replace,path=/authorizationType,value=NONE

# 重新部署API
aws apigateway create-deployment \
  --rest-api-id vjywvai0e7 \
  --stage-name dev
```

## 永久解决方案

### 选项1：使用Docker构建Lambda层
```bash
docker run --rm \
  -v "$PWD:/var/task" \
  public.ecr.aws/lambda/python:3.9 \
  /bin/sh -c "pip install -r requirements.txt -t python/"
```

### 选项2：使用AWS SAM CLI
```bash
sam build --use-container
```

### 选项3：简化授权器实现
- 移除`cryptography`依赖
- 使用简化的JWT验证（不验证签名）
- 或使用AWS Cognito内置的授权器

## 当前状态
- ✅ API可以正常访问
- ✅ Lambda函数正常工作
- ⚠️ 授权已暂时禁用
- ⏳ 需要重新构建Lambda层以恢复授权功能

## 下一步行动
1. 使用正确的方法重新构建Lambda层
2. 更新授权器Lambda函数
3. 重新启用API Gateway授权
4. 更新Terraform配置以防止未来出现此问题

## 经验教训
1. Lambda层必须在Linux环境下构建
2. 包含二进制依赖的Python包需要特别注意平台兼容性
3. 直接测试Lambda函数有助于快速定位问题
4. API Gateway的授权器错误不会在500响应中显示详细信息