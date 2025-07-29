"""
Query Handler Lambda函数的单元测试
"""
import json
import pytest
from unittest.mock import Mock, patch, MagicMock
import sys
import os

# 添加源代码路径
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../applications/backend/lambda/query_handler')))

# 模拟AWS服务
@pytest.fixture
def mock_aws_services():
    with patch('boto3.client') as mock_client:
        # 创建模拟客户端
        mock_bedrock_runtime = Mock()
        mock_bedrock_agent_runtime = Mock()
        mock_s3_client = Mock()
        mock_bedrock_client = Mock()
        mock_bedrock_agent = Mock()
        
        # 配置client方法返回不同的模拟对象
        def client_side_effect(service_name, **kwargs):
            if service_name == 'bedrock-runtime':
                return mock_bedrock_runtime
            elif service_name == 'bedrock-agent-runtime':
                return mock_bedrock_agent_runtime
            elif service_name == 's3':
                return mock_s3_client
            elif service_name == 'bedrock':
                return mock_bedrock_client
            elif service_name == 'bedrock-agent':
                return mock_bedrock_agent
            
        mock_client.side_effect = client_side_effect
        
        yield {
            'bedrock_runtime': mock_bedrock_runtime,
            'bedrock_agent_runtime': mock_bedrock_agent_runtime,
            's3_client': mock_s3_client,
            'bedrock_client': mock_bedrock_client,
            'bedrock_agent': mock_bedrock_agent
        }

@pytest.fixture
def mock_env_vars():
    """设置测试环境变量"""
    env_vars = {
        'AWS_REGION': 'us-east-1',
        'KNOWLEDGE_BASE_ID': 'test-kb-id',
        'DATA_SOURCE_ID': 'test-ds-id',
        'S3_BUCKET': 'test-bucket',
        'BEDROCK_MODEL_ID': 'amazon.nova-pro-v1:0',
        'ENVIRONMENT': 'test'
    }
    with patch.dict(os.environ, env_vars):
        yield env_vars

class TestQueryHandler:
    
    def test_handle_options_request(self, mock_aws_services, mock_env_vars):
        """测试CORS预检请求处理"""
        from handler import lambda_handler
        
        event = {
            'httpMethod': 'OPTIONS',
            'path': '/query'
        }
        
        response = lambda_handler(event, None)
        
        assert response['statusCode'] == 200
        assert 'Access-Control-Allow-Origin' in response['headers']
        assert response['headers']['Access-Control-Allow-Origin'] == '*'
        assert 'Access-Control-Allow-Methods' in response['headers']
    
    def test_handle_health_check(self, mock_aws_services, mock_env_vars):
        """测试健康检查端点"""
        from handler import lambda_handler
        
        # 配置模拟响应
        mock_aws_services['bedrock_client'].list_foundation_models.return_value = {
            'modelSummaries': [{'modelId': 'test-model'}]
        }
        mock_aws_services['bedrock_agent'].get_knowledge_base.return_value = {
            'knowledgeBase': {'status': 'ACTIVE'}
        }
        mock_aws_services['s3_client'].head_bucket.return_value = {}
        
        event = {
            'httpMethod': 'GET',
            'path': '/query'
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 200
        assert response_body['status'] == 'healthy'
        assert response_body['service'] == 'RAG Query Handler'
        assert 'checks' in response_body
    
    def test_query_request_success(self, mock_aws_services, mock_env_vars):
        """测试成功的查询请求"""
        from handler import lambda_handler
        
        # 配置Knowledge Base响应
        mock_aws_services['bedrock_agent_runtime'].retrieve_and_generate.return_value = {
            'output': {
                'text': '这是测试答案'
            },
            'citations': [{
                'retrievedReferences': [{
                    'content': {'text': '参考内容'},
                    'location': {'s3Location': {'uri': 's3://bucket/doc.pdf'}},
                    'metadata': {'score': 0.95}
                }]
            }]
        }
        
        event = {
            'httpMethod': 'POST',
            'path': '/query',
            'body': json.dumps({
                'question': '测试问题',
                'top_k': 5,
                'include_sources': True
            })
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 200
        assert response_body['success'] is True
        assert response_body['question'] == '测试问题'
        assert response_body['answer'] == '这是测试答案'
        assert len(response_body['sources']) == 1
        assert response_body['sources'][0]['confidence'] == 0.95
    
    def test_query_request_empty_question(self, mock_aws_services, mock_env_vars):
        """测试空问题的错误处理"""
        from handler import lambda_handler
        
        event = {
            'httpMethod': 'POST',
            'path': '/query',
            'body': json.dumps({
                'question': ''
            })
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 400
        assert response_body['success'] is False
        assert '问题不能为空' in response_body['error']['message']
    
    def test_query_request_invalid_json(self, mock_aws_services, mock_env_vars):
        """测试无效JSON的错误处理"""
        from handler import lambda_handler
        
        event = {
            'httpMethod': 'POST',
            'path': '/query',
            'body': 'invalid json'
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 400
        assert response_body['success'] is False
        assert '无效的JSON格式' in response_body['error']['message']
    
    def test_query_fallback_mode(self, mock_aws_services, mock_env_vars):
        """测试Knowledge Base不可用时的回退模式"""
        from handler import lambda_handler
        
        # 让Knowledge Base调用失败
        mock_aws_services['bedrock_agent_runtime'].retrieve_and_generate.side_effect = Exception("KB不可用")
        
        # 配置直接模型调用的响应
        mock_aws_services['bedrock_runtime'].invoke_model.return_value = {
            'body': MagicMock(read=lambda: json.dumps({
                'results': [{'outputText': '这是回退模式的答案'}]
            }).encode())
        }
        
        event = {
            'httpMethod': 'POST',
            'path': '/query',
            'body': json.dumps({
                'question': '测试问题'
            })
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 200
        assert response_body['success'] is True
        assert '这是回退模式的答案' in response_body['answer']
        assert '注意：此回答基于模型的一般知识' in response_body['answer']
        assert len(response_body['sources']) == 0
    
    def test_knowledge_base_status(self, mock_aws_services, mock_env_vars):
        """测试知识库状态查询"""
        from handler import lambda_handler
        
        # 配置Knowledge Base状态响应
        mock_aws_services['bedrock_agent'].get_knowledge_base.return_value = {
            'knowledgeBase': {
                'status': 'ACTIVE',
                'name': 'Test KB'
            }
        }
        
        # 配置摄入任务响应
        mock_aws_services['bedrock_agent'].list_ingestion_jobs.return_value = {
            'ingestionJobSummaries': [{
                'ingestionJobId': 'job-123',
                'status': 'COMPLETE',
                'startedAt': '2024-01-01T00:00:00Z',
                'completedAt': '2024-01-01T00:05:00Z'
            }]
        }
        
        mock_aws_services['bedrock_agent'].get_ingestion_job.return_value = {
            'ingestionJob': {
                'statistics': {
                    'numberOfDocumentsScanned': 10,
                    'numberOfDocumentsFailed': 0,
                    'numberOfNewDocumentsIndexed': 8,
                    'numberOfModifiedDocumentsIndexed': 2
                }
            }
        }
        
        event = {
            'httpMethod': 'GET',
            'path': '/status'
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 200
        assert response_body['success'] is True
        assert response_body['systemReady'] is True
        assert response_body['knowledgeBase']['status'] == 'ACTIVE'
        assert len(response_body['ingestionJobs']) == 1
        assert response_body['summary']['documentsProcessed'] == 10
    
    def test_unsupported_http_method(self, mock_aws_services, mock_env_vars):
        """测试不支持的HTTP方法"""
        from handler import lambda_handler
        
        event = {
            'httpMethod': 'DELETE',
            'path': '/query'
        }
        
        response = lambda_handler(event, None)
        response_body = json.loads(response['body'])
        
        assert response['statusCode'] == 405
        assert response_body['success'] is False
        assert '不支持的HTTP方法' in response_body['error']['message']

if __name__ == '__main__':
    pytest.main([__file__, '-v'])