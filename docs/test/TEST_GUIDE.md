# AWS Bedrock RAG 系统测试指南

## 目录

1. [测试概述](#测试概述)
2. [测试环境设置](#测试环境设置)
3. [单元测试](#单元测试)
4. [集成测试](#集成测试)
5. [端到端测试](#端到端测试)
6. [手动测试](#手动测试)
7. [测试报告](#测试报告)
8. [最佳实践](#最佳实践)

## 测试概述

本项目采用多层次的测试策略，确保系统的稳定性和可靠性。

### 测试金字塔

```
        /\
       /E2E\      <- 端到端测试（少量）
      /------\
     /  集成  \    <- 集成测试（中等）
    /----------\
   /   单元测试   \  <- 单元测试（大量）
  /--------------\
```

### 测试覆盖率目标

- 单元测试：80%+
- 集成测试：60%+
- 端到端测试：关键路径 100%

## 测试环境设置

### 1. Python 测试环境

```bash
# 安装测试依赖
pip install pytest pytest-cov pytest-mock boto3-stubs

# 创建测试配置
cat > pytest.ini << EOF
[pytest]
testpaths = test
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = --cov=src --cov-report=html --cov-report=term-missing
EOF
```

### 2. JavaScript 测试环境

```bash
# 前端测试依赖
cd applications/frontend
npm install --save-dev @testing-library/react @testing-library/jest-dom jest

# Jest 配置已包含在 package.json 中
```

### 3. 本地 AWS 模拟

```bash
# 安装 LocalStack
pip install localstack

# 启动 LocalStack
localstack start

# 配置环境变量
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
```

## 单元测试

### Lambda 函数测试

```python
# test/unit/test_query_handler.py
import pytest
from unittest.mock import Mock, patch
from lambda_functions.query_handler import handler

class TestQueryHandler:
    @pytest.fixture
    def mock_event(self):
        return {
            "body": '{"query": "What is RAG?"}',
            "headers": {"Content-Type": "application/json"}
        }
    
    @pytest.fixture
    def mock_context(self):
        return Mock()
    
    @patch('boto3.client')
    def test_successful_query(self, mock_boto_client, mock_event, mock_context):
        # 模拟 Bedrock 响应
        mock_bedrock = Mock()
        mock_bedrock.invoke_model.return_value = {
            'body': Mock(read=Mock(return_value=b'{"response": "RAG is..."}'))
        }
        mock_boto_client.return_value = mock_bedrock
        
        # 执行测试
        response = handler(mock_event, mock_context)
        
        # 验证结果
        assert response['statusCode'] == 200
        assert 'RAG is' in response['body']
    
    def test_invalid_request(self, mock_event, mock_context):
        mock_event['body'] = 'invalid json'
        
        response = handler(mock_event, mock_context)
        
        assert response['statusCode'] == 400
        assert 'error' in response['body']
```

### 前端组件测试

```javascript
// test/unit/Chat.test.js
import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import Chat from '../../src/components/Chat';

describe('Chat Component', () => {
  test('renders input and send button', () => {
    render(<Chat />);
    
    expect(screen.getByPlaceholderText('输入您的问题...')).toBeInTheDocument();
    expect(screen.getByText('发送')).toBeInTheDocument();
  });
  
  test('sends message on button click', async () => {
    const mockOnSend = jest.fn();
    render(<Chat onSend={mockOnSend} />);
    
    const input = screen.getByPlaceholderText('输入您的问题...');
    const button = screen.getByText('发送');
    
    fireEvent.change(input, { target: { value: 'Test message' } });
    fireEvent.click(button);
    
    expect(mockOnSend).toHaveBeenCalledWith('Test message');
  });
});
```

## 集成测试

### API 集成测试

```python
# test/integration/test_api_integration.py
import pytest
import requests
import os

class TestAPIIntegration:
    @pytest.fixture
    def api_url(self):
        return os.environ.get('API_GATEWAY_URL', 'http://localhost:3000')
    
    def test_health_check(self, api_url):
        response = requests.get(f"{api_url}/health")
        assert response.status_code == 200
        assert response.json()['status'] == 'healthy'
    
    def test_query_endpoint(self, api_url):
        payload = {"query": "Test query"}
        headers = {"Content-Type": "application/json"}
        
        response = requests.post(
            f"{api_url}/api/query",
            json=payload,
            headers=headers
        )
        
        assert response.status_code == 200
        assert 'response' in response.json()
```

### 数据库集成测试

```python
# test/integration/test_s3_integration.py
import boto3
import pytest
from moto import mock_s3

@mock_s3
class TestS3Integration:
    def setup_method(self):
        self.s3 = boto3.client('s3', region_name='us-east-1')
        self.bucket_name = 'test-rag-documents'
        self.s3.create_bucket(Bucket=self.bucket_name)
    
    def test_upload_document(self):
        # 上传文档
        self.s3.put_object(
            Bucket=self.bucket_name,
            Key='test-doc.txt',
            Body=b'Test content'
        )
        
        # 验证上传
        response = self.s3.get_object(
            Bucket=self.bucket_name,
            Key='test-doc.txt'
        )
        assert response['Body'].read() == b'Test content'
```

## 端到端测试

### Selenium 测试

```python
# test/e2e/test_user_flow.py
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import pytest

class TestUserFlow:
    @pytest.fixture
    def driver(self):
        driver = webdriver.Chrome()
        driver.implicitly_wait(10)
        yield driver
        driver.quit()
    
    def test_complete_query_flow(self, driver):
        # 访问应用
        driver.get("https://your-cloudfront-url.com")
        
        # 等待页面加载
        wait = WebDriverWait(driver, 10)
        chat_input = wait.until(
            EC.presence_of_element_located((By.ID, "chat-input"))
        )
        
        # 输入查询
        chat_input.send_keys("What is AWS Bedrock?")
        
        # 点击发送
        send_button = driver.find_element(By.ID, "send-button")
        send_button.click()
        
        # 等待响应
        response = wait.until(
            EC.presence_of_element_located((By.CLASS_NAME, "response"))
        )
        
        # 验证响应
        assert "Bedrock" in response.text
```

### API 端到端测试

```bash
#!/bin/bash
# test/e2e/api_e2e_test.sh

API_URL="https://your-api-gateway-url.com"

echo "测试 1: 健康检查"
curl -s "$API_URL/health" | jq .

echo "测试 2: 查询请求"
curl -s -X POST "$API_URL/api/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is RAG?"}' | jq .

echo "测试 3: 文档上传"
curl -s -X POST "$API_URL/api/documents" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@test-document.pdf" | jq .
```

## 手动测试

### 手动测试清单

#### 1. 前端功能测试
- [ ] 页面正常加载
- [ ] 聊天输入框可用
- [ ] 发送按钮响应点击
- [ ] 消息正确显示
- [ ] 错误处理正常
- [ ] 响应式设计正常

#### 2. API 功能测试
- [ ] 健康检查端点返回 200
- [ ] 查询端点正确处理请求
- [ ] 错误请求返回适当错误码
- [ ] CORS 头正确设置
- [ ] 认证（如果启用）正常工作

#### 3. 集成测试
- [ ] 前端到 API 的通信正常
- [ ] Lambda 函数正确调用
- [ ] S3 文档上传/下载正常
- [ ] Bedrock 集成正常工作
- [ ] CloudFront 缓存正常

### 手动测试报告模板

```markdown
## 手动测试报告

**测试日期**: 2025-07-28
**测试人员**: 测试工程师
**测试环境**: Development

### 测试结果摘要

| 测试项 | 通过 | 失败 | 跳过 | 备注 |
|-------|-----|------|-----|------|
| 前端功能 | 6 | 0 | 0 | 全部通过 |
| API 功能 | 5 | 0 | 0 | 全部通过 |
| 集成测试 | 4 | 1 | 0 | S3 上传有延迟 |

### 详细测试结果

#### 1. 前端功能测试
- ✅ 页面加载时间 < 3秒
- ✅ 聊天功能正常
- ✅ 错误提示清晰
- ✅ 移动端显示正常

#### 2. API 功能测试
- ✅ 健康检查响应时间 < 100ms
- ✅ 查询响应时间 < 5秒
- ✅ 错误处理返回正确状态码

#### 3. 问题和建议
1. S3 文档上传在大文件时有延迟
   - 建议：实施分片上传
2. 首次查询有冷启动延迟
   - 建议：配置 Lambda 预热

### 下一步行动
1. 修复 S3 上传延迟问题
2. 实施 Lambda 预热策略
3. 增加性能监控
```

## 测试报告

### 自动生成测试报告

```bash
# Python 测试报告
pytest --cov=src --cov-report=html --html=report.html

# JavaScript 测试报告
npm test -- --coverage --watchAll=false

# 合并测试报告
python scripts/merge_test_reports.py
```

### 测试覆盖率报告

```python
# scripts/coverage_report.py
import json
import os

def generate_coverage_report():
    # 读取各种覆盖率报告
    python_coverage = read_python_coverage()
    js_coverage = read_js_coverage()
    
    # 生成综合报告
    report = {
        "summary": {
            "python": python_coverage['totals']['percent_covered'],
            "javascript": js_coverage['total']['lines']['pct'],
            "overall": calculate_overall_coverage()
        },
        "details": {
            "python": python_coverage['files'],
            "javascript": js_coverage['files']
        }
    }
    
    # 生成 HTML 报告
    generate_html_report(report)
    
    return report
```

### CI/CD 集成

```yaml
# .github/workflows/test.yml
name: Run Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.9'
    
    - name: Install dependencies
      run: |
        pip install -r requirements.txt
        pip install -r requirements-test.txt
    
    - name: Run Python tests
      run: |
        pytest --cov=src --cov-report=xml
    
    - name: Set up Node.js
      uses: actions/setup-node@v2
      with:
        node-version: '18'
    
    - name: Run JavaScript tests
      run: |
        cd applications/frontend
        npm install
        npm test -- --coverage
    
    - name: Upload coverage
      uses: codecov/codecov-action@v1
```

## 最佳实践

### 1. 测试命名规范

```python
# Good
def test_query_handler_returns_200_for_valid_request():
    pass

def test_s3_upload_fails_with_invalid_bucket():
    pass

# Bad
def test1():
    pass

def test_handler():
    pass
```

### 2. 测试数据管理

```python
# test/fixtures/test_data.py
TEST_DOCUMENTS = {
    "valid_pdf": "test/fixtures/files/valid.pdf",
    "invalid_pdf": "test/fixtures/files/corrupted.pdf",
    "large_file": "test/fixtures/files/large_10mb.pdf"
}

TEST_QUERIES = [
    "What is AWS Bedrock?",
    "How does RAG work?",
    "Explain vector databases"
]
```

### 3. 模拟和存根

```python
# 使用 pytest fixtures
@pytest.fixture
def mock_bedrock_client():
    with patch('boto3.client') as mock:
        client = Mock()
        client.invoke_model.return_value = {
            'body': Mock(read=lambda: b'{"response": "test"}')
        }
        mock.return_value = client
        yield client

# 使用 fixture
def test_with_mock(mock_bedrock_client):
    # 测试代码
    pass
```

### 4. 测试隔离

```python
class TestIsolation:
    def setup_method(self):
        """每个测试方法前运行"""
        self.test_bucket = f"test-bucket-{uuid.uuid4()}"
        create_test_bucket(self.test_bucket)
    
    def teardown_method(self):
        """每个测试方法后运行"""
        delete_test_bucket(self.test_bucket)
```

### 5. 性能测试

```python
import time
import pytest

@pytest.mark.performance
def test_query_performance():
    start_time = time.time()
    
    # 执行操作
    response = make_query("test query")
    
    execution_time = time.time() - start_time
    
    # 验证性能
    assert execution_time < 5.0  # 应在5秒内完成
    assert response.status_code == 200
```

### 6. 测试文档

```python
def test_user_registration_flow():
    """
    测试用户注册完整流程
    
    步骤:
    1. 用户访问注册页面
    2. 填写注册表单
    3. 提交表单
    4. 验证邮箱
    5. 完成注册
    
    预期结果:
    - 用户成功创建
    - 收到欢迎邮件
    - 可以登录系统
    """
    # 测试实现
    pass
```

---

**文档版本**: v1.0  
**最后更新**: 2025-07-28  
**测试团队**: qa@example.com