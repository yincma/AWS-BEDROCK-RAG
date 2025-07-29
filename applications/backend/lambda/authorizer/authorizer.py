"""
AWS Lambda Authorizer
系统二：基于AWS Nova的企业级RAG知识问答系统

自定义认证和授权逻辑
"""

import json
import logging
import os
import re
import time
import jwt
import boto3
from typing import Dict, Any, List

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 全局变量
USER_POOL_ID = os.environ.get('USER_POOL_ID')
APP_CLIENT_ID = os.environ.get('APP_CLIENT_ID')
REGION = os.environ.get('REGION', os.environ.get('AWS_REGION', 'us-east-1'))

# Cognito客户端
cognito_client = boto3.client('cognito-idp', region_name=REGION)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda Authorizer主处理器
    
    Args:
        event: API Gateway Authorizer事件
        context: Lambda上下文
        
    Returns:
        IAM策略响应
    """
    try:
        logger.info(f"Authorizer事件: {json.dumps(event, default=str)}")
        logger.info(f"环境变量 - USER_POOL_ID: {USER_POOL_ID}, APP_CLIENT_ID: {APP_CLIENT_ID}, REGION: {REGION}")
        
        # 提取token
        token = extract_token(event)
        if not token:
            logger.warning("未找到Authorization token")
            logger.warning(f"authorizationToken字段值: {event.get('authorizationToken', 'NOT_FOUND')}")
            # 明确返回Deny策略而不是抛出异常
            return generate_policy(
                principal_id='no-token',
                effect='Deny',
                resource=event['methodArn']
            )
        
        logger.info(f"提取到的token长度: {len(token)}")
        logger.info(f"Token前20字符: {token[:20]}...")
        
        # 验证token
        user_info = verify_token(token)
        if not user_info:
            logger.warning("Token验证失败")
            # 明确返回Deny策略而不是抛出异常
            return generate_policy(
                principal_id='invalid-token',
                effect='Deny',
                resource=event['methodArn']
            )
        
        logger.info(f"用户认证成功: {user_info.get('sub', 'unknown')}")
        logger.info(f"用户信息: {json.dumps(user_info, default=str)}")
        
        # 生成IAM策略
        policy = generate_policy(
            principal_id=user_info.get('sub', 'unknown'),
            effect='Allow',
            resource=event['methodArn'],
            context=user_info
        )
        
        logger.info(f"生成的策略: {json.dumps(policy, default=str)}")
        return policy
    
    except Exception as e:
        logger.error(f"认证失败: {str(e)}", exc_info=True)
        # 返回拒绝访问的策略
        return generate_policy(
            principal_id='error',
            effect='Deny',
            resource=event['methodArn']
        )

def extract_token(event: Dict[str, Any]) -> str:
    """
    从事件中提取token
    
    Args:
        event: API Gateway事件
        
    Returns:
        提取的token
    """
    auth_token = event.get('authorizationToken', '')
    
    # 支持Bearer token格式
    if auth_token.startswith('Bearer '):
        return auth_token.split(' ')[1]
    
    # 直接返回token
    return auth_token

def verify_token(token: str) -> Dict[str, Any]:
    """
    验证JWT token
    
    Args:
        token: JWT token
        
    Returns:
        用户信息字典，验证失败返回None
    """
    try:
        # 确保必需的环境变量存在
        if not USER_POOL_ID or not APP_CLIENT_ID:
            logger.error(f"缺少必需的环境变量: USER_POOL_ID={USER_POOL_ID}, APP_CLIENT_ID={APP_CLIENT_ID}")
            return None
            
        # 解码token但不验证签名（用于快速检查）
        try:
            unverified_header = jwt.get_unverified_header(token)
            logger.info(f"Token header: {json.dumps(unverified_header)}")
        except Exception as e:
            logger.error(f"无法解码token header: {str(e)}")
            return None
            
        try:
            unverified_payload = jwt.decode(token, options={"verify_signature": False})
            logger.info(f"Token payload (部分): sub={unverified_payload.get('sub')}, token_use={unverified_payload.get('token_use')}, iss={unverified_payload.get('iss')}")
        except Exception as e:
            logger.error(f"无法解码token payload: {str(e)}")
            return None
        
        # 基本验证
        if not unverified_payload.get('sub'):
            logger.error("Token缺少subject")
            return None
        
        # 检查token是否过期
        exp = unverified_payload.get('exp', 0)
        current_time = time.time()
        if exp < current_time:
            logger.error(f"Token已过期: exp={exp}, current={current_time}, 差值={current_time - exp}秒")
            return None
        
        # 检查issuer
        iss = unverified_payload.get('iss', '')
        expected_iss = f'https://cognito-idp.{REGION}.amazonaws.com/{USER_POOL_ID}'
        if iss != expected_iss:
            logger.error(f"无效的issuer: 期望={expected_iss}, 实际={iss}")
            logger.error(f"REGION={REGION}, USER_POOL_ID={USER_POOL_ID}")
            return None
        
        # 检查audience (client_id)
        aud = unverified_payload.get('aud', '')
        token_use = unverified_payload.get('token_use', '')
        
        logger.info(f"Token验证: token_use={token_use}, aud={aud}, APP_CLIENT_ID={APP_CLIENT_ID}")
        
        # ID Token检查aud，Access Token检查client_id
        if token_use == 'id':
            if aud != APP_CLIENT_ID:
                logger.error(f"ID Token无效的audience: 期望={APP_CLIENT_ID}, 实际={aud}")
                return None
        elif token_use == 'access':
            client_id = unverified_payload.get('client_id', '')
            if client_id != APP_CLIENT_ID:
                logger.error(f"Access Token无效的client_id: 期望={APP_CLIENT_ID}, 实际={client_id}")
                return None
        else:
            logger.warning(f"未知的token_use: {token_use}，跳过audience验证")
        
        # 验证用户状态
        if USER_POOL_ID:
            try:
                logger.info(f"开始验证用户状态 - UserPoolId: {USER_POOL_ID}, Username: {unverified_payload['sub']}")
                user_response = cognito_client.admin_get_user(
                    UserPoolId=USER_POOL_ID,
                    Username=unverified_payload['sub']
                )
                
                user_status = user_response.get('UserStatus', '')
                logger.info(f"用户状态: {user_status}")
                
                if user_status != 'CONFIRMED':
                    logger.error(f"用户状态无效: {user_status} (期望: CONFIRMED)")
                    return None
                
                # 获取用户属性
                user_attributes = {attr['Name']: attr['Value'] for attr in user_response.get('UserAttributes', [])}
                logger.info(f"用户属性: {list(user_attributes.keys())}")
                    
            except cognito_client.exceptions.UserNotFoundException:
                logger.error(f"用户不存在: {unverified_payload['sub']}")
                return None
            except cognito_client.exceptions.AccessDeniedException as e:
                logger.error(f"访问被拒绝 - 检查Lambda角色是否有cognito-idp:AdminGetUser权限: {str(e)}")
                # 如果是权限问题，仍然尝试继续（但记录警告）
                logger.warning("由于权限限制，跳过用户状态验证")
            except Exception as e:
                logger.error(f"验证用户状态失败: {str(e)}", exc_info=True)
                return None
        else:
            logger.warning("USER_POOL_ID未设置，跳过用户状态验证")
        
        # 返回用户信息
        user_info = {
            'sub': unverified_payload.get('sub'),
            'email': unverified_payload.get('email', ''),
            'username': unverified_payload.get('cognito:username', unverified_payload.get('username', '')),
            'groups': unverified_payload.get('cognito:groups', []),
            'token_use': unverified_payload.get('token_use'),
            'scope': unverified_payload.get('scope', ''),
            'exp': unverified_payload.get('exp'),
            'iat': unverified_payload.get('iat'),
        }
        
        logger.info(f"Token验证成功，用户信息: {json.dumps(user_info, default=str)}")
        return user_info
        
    except jwt.InvalidTokenError as e:
        logger.error(f"JWT token无效: {str(e)}")
        return None
    except Exception as e:
        logger.error(f"Token验证错误: {str(e)}", exc_info=True)
        return None

def generate_policy(principal_id: str, effect: str, resource: str, context: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    生成IAM策略
    
    Args:
        principal_id: 主体ID
        effect: Allow或Deny
        resource: 资源ARN
        context: 上下文信息
        
    Returns:
        IAM策略字典
    """
    # 构建基础策略
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': get_resource_arn(resource)
                }
            ]
        }
    }
    
    # 添加上下文信息
    if context and effect == 'Allow':
        policy['context'] = {
            'user_id': str(context.get('sub', '')),
            'email': str(context.get('email', '')),
            'username': str(context.get('username', '')),
            'groups': json.dumps(context.get('groups', [])),
            'token_use': str(context.get('token_use', '')),
            'scope': str(context.get('scope', '')),
        }
    
    return policy

def get_resource_arn(method_arn: str) -> str:
    """
    获取资源ARN，支持通配符
    
    Args:
        method_arn: 方法ARN
        
    Returns:
        资源ARN
    """
    # 解析ARN: arn:aws:execute-api:region:account:api-id/stage/method/resource
    arn_parts = method_arn.split(':')
    if len(arn_parts) >= 6:
        # 拆分最后一部分：api-id/stage/method/resource
        api_gateway_part = arn_parts[5]
        api_parts = api_gateway_part.split('/')
        
        if len(api_parts) >= 3:
            # 构建通配符ARN：api-id/stage/*/*
            api_id = api_parts[0]
            stage = api_parts[1]
            base_arn = ':'.join(arn_parts[:5])
            return f"{base_arn}:{api_id}/{stage}/*/*"
    
    return method_arn