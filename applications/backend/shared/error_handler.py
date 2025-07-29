"""
统一错误处理模块
提供标准化的错误处理、日志记录和监控集成
"""
import logging
import json
import traceback
from typing import Dict, Any, Optional, Union
from dataclasses import dataclass, asdict
from enum import Enum
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

class ErrorLevel(Enum):
    """错误级别枚举"""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"

class ErrorCategory(Enum):
    """错误分类"""
    VALIDATION = "VALIDATION"
    AUTHENTICATION = "AUTHENTICATION"
    AUTHORIZATION = "AUTHORIZATION"
    NOT_FOUND = "NOT_FOUND"
    CONFLICT = "CONFLICT"
    RATE_LIMIT = "RATE_LIMIT"
    EXTERNAL_SERVICE = "EXTERNAL_SERVICE"
    INTERNAL = "INTERNAL"
    CONFIGURATION = "CONFIGURATION"

@dataclass
class ErrorContext:
    """错误上下文信息"""
    service: str
    operation: str
    user_id: Optional[str] = None
    request_id: Optional[str] = None
    trace_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {k: v for k, v in asdict(self).items() if v is not None}

@dataclass
class ErrorResponse:
    """标准错误响应"""
    error_code: str
    message: str
    details: Optional[Dict[str, Any]] = None
    request_id: Optional[str] = None
    timestamp: str = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.utcnow().isoformat() + 'Z'

class BaseError(Exception):
    """基础错误类"""
    def __init__(
        self,
        message: str,
        error_code: str = None,
        category: ErrorCategory = ErrorCategory.INTERNAL,
        status_code: int = 500,
        details: Dict[str, Any] = None
    ):
        super().__init__(message)
        self.message = message
        self.error_code = error_code or self.__class__.__name__
        self.category = category
        self.status_code = status_code
        self.details = details or {}

# 具体错误类
class ValidationError(BaseError):
    """验证错误"""
    def __init__(self, message: str, field: str = None, **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.VALIDATION,
            status_code=400,
            **kwargs
        )
        if field:
            self.details['field'] = field

class AuthenticationError(BaseError):
    """认证错误"""
    def __init__(self, message: str = "未授权访问", **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.AUTHENTICATION,
            status_code=401,
            **kwargs
        )

class AuthorizationError(BaseError):
    """授权错误"""
    def __init__(self, message: str = "禁止访问", **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.AUTHORIZATION,
            status_code=403,
            **kwargs
        )

class NotFoundError(BaseError):
    """资源未找到错误"""
    def __init__(self, resource: str, identifier: str = None, **kwargs):
        message = f"{resource}未找到"
        if identifier:
            message += f": {identifier}"
        super().__init__(
            message,
            category=ErrorCategory.NOT_FOUND,
            status_code=404,
            **kwargs
        )
        self.details['resource'] = resource
        if identifier:
            self.details['identifier'] = identifier

class ConflictError(BaseError):
    """资源冲突错误"""
    def __init__(self, message: str = "资源冲突", **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.CONFLICT,
            status_code=409,
            **kwargs
        )

class RateLimitError(BaseError):
    """速率限制错误"""
    def __init__(self, message: str = "请求过于频繁", retry_after: int = None, **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.RATE_LIMIT,
            status_code=429,
            **kwargs
        )
        if retry_after:
            self.details['retry_after'] = retry_after

class ExternalServiceError(BaseError):
    """外部服务错误"""
    def __init__(self, service: str, message: str = None, **kwargs):
        message = message or f"{service}服务暂时不可用"
        super().__init__(
            message,
            category=ErrorCategory.EXTERNAL_SERVICE,
            status_code=503,
            **kwargs
        )
        self.details['service'] = service

class ConfigurationError(BaseError):
    """配置错误"""
    def __init__(self, message: str, config_key: str = None, **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.CONFIGURATION,
            status_code=500,
            **kwargs
        )
        if config_key:
            self.details['config_key'] = config_key

class ErrorHandler:
    """统一错误处理器"""
    
    def __init__(
        self,
        service_name: str,
        cloudwatch_client=None,
        sns_client=None,
        enable_cloudwatch_metrics: bool = True,
        enable_sns_alerts: bool = False,
        sns_topic_arn: str = None
    ):
        self.service_name = service_name
        self.cloudwatch = cloudwatch_client or boto3.client('cloudwatch')
        self.sns = sns_client or boto3.client('sns')
        self.enable_cloudwatch_metrics = enable_cloudwatch_metrics
        self.enable_sns_alerts = enable_sns_alerts
        self.sns_topic_arn = sns_topic_arn
    
    def handle_error(
        self,
        error: Exception,
        context: ErrorContext,
        level: ErrorLevel = None
    ) -> Dict[str, Any]:
        """处理错误并返回标准响应"""
        
        # 确定错误级别
        if level is None:
            if isinstance(error, BaseError):
                level = self._get_error_level(error.category)
            else:
                level = ErrorLevel.ERROR
        
        # 记录错误
        self._log_error(error, context, level)
        
        # 发送指标
        if self.enable_cloudwatch_metrics:
            self._send_metrics(error, context, level)
        
        # 发送告警（仅针对严重错误）
        if self.enable_sns_alerts and level in [ErrorLevel.ERROR, ErrorLevel.CRITICAL]:
            self._send_alert(error, context)
        
        # 创建错误响应
        return self._create_error_response(error, context)
    
    def _get_error_level(self, category: ErrorCategory) -> ErrorLevel:
        """根据错误分类确定错误级别"""
        level_mapping = {
            ErrorCategory.VALIDATION: ErrorLevel.WARNING,
            ErrorCategory.AUTHENTICATION: ErrorLevel.WARNING,
            ErrorCategory.AUTHORIZATION: ErrorLevel.WARNING,
            ErrorCategory.NOT_FOUND: ErrorLevel.INFO,
            ErrorCategory.CONFLICT: ErrorLevel.WARNING,
            ErrorCategory.RATE_LIMIT: ErrorLevel.WARNING,
            ErrorCategory.EXTERNAL_SERVICE: ErrorLevel.ERROR,
            ErrorCategory.INTERNAL: ErrorLevel.ERROR,
            ErrorCategory.CONFIGURATION: ErrorLevel.CRITICAL,
        }
        return level_mapping.get(category, ErrorLevel.ERROR)
    
    def _log_error(
        self,
        error: Exception,
        context: ErrorContext,
        level: ErrorLevel
    ):
        """记录错误日志"""
        log_data = {
            "error_type": type(error).__name__,
            "error_message": str(error),
            "service": self.service_name,
            "context": context.to_dict(),
            "stack_trace": traceback.format_exc() if level.value in ["ERROR", "CRITICAL"] else None
        }
        
        # 如果是BaseError，添加额外信息
        if isinstance(error, BaseError):
            log_data.update({
                "error_code": error.error_code,
                "category": error.category.value,
                "status_code": error.status_code,
                "details": error.details
            })
        
        # 记录日志
        log_message = json.dumps(log_data, ensure_ascii=False)
        
        if level == ErrorLevel.DEBUG:
            logger.debug(log_message)
        elif level == ErrorLevel.INFO:
            logger.info(log_message)
        elif level == ErrorLevel.WARNING:
            logger.warning(log_message)
        elif level == ErrorLevel.ERROR:
            logger.error(log_message)
        elif level == ErrorLevel.CRITICAL:
            logger.critical(log_message)
    
    def _send_metrics(
        self,
        error: Exception,
        context: ErrorContext,
        level: ErrorLevel
    ):
        """发送CloudWatch指标"""
        try:
            namespace = f'RAG-System/{self.service_name}'
            
            # 基础指标
            metric_data = [
                {
                    'MetricName': 'Errors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ErrorType', 'Value': type(error).__name__},
                        {'Name': 'Operation', 'Value': context.operation},
                        {'Name': 'Level', 'Value': level.value}
                    ]
                }
            ]
            
            # 如果是BaseError，添加分类指标
            if isinstance(error, BaseError):
                metric_data.append({
                    'MetricName': 'ErrorsByCategory',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Category', 'Value': error.category.value},
                        {'Name': 'StatusCode', 'Value': str(error.status_code)}
                    ]
                })
            
            self.cloudwatch.put_metric_data(
                Namespace=namespace,
                MetricData=metric_data
            )
        except Exception as e:
            logger.error(f"发送指标失败: {e}")
    
    def _send_alert(self, error: Exception, context: ErrorContext):
        """发送SNS告警"""
        if not self.sns_topic_arn:
            return
        
        try:
            # 构建告警消息
            alert_message = {
                "service": self.service_name,
                "environment": context.metadata.get('environment', 'unknown') if context.metadata else 'unknown',
                "error_type": type(error).__name__,
                "error_message": str(error),
                "operation": context.operation,
                "request_id": context.request_id,
                "timestamp": datetime.utcnow().isoformat() + 'Z'
            }
            
            if isinstance(error, BaseError):
                alert_message.update({
                    "error_code": error.error_code,
                    "category": error.category.value,
                    "details": error.details
                })
            
            # 发送SNS消息
            self.sns.publish(
                TopicArn=self.sns_topic_arn,
                Subject=f"[{self.service_name}] {type(error).__name__}: {context.operation}",
                Message=json.dumps(alert_message, ensure_ascii=False, indent=2)
            )
        except Exception as e:
            logger.error(f"发送告警失败: {e}")
    
    def _create_error_response(
        self,
        error: Exception,
        context: ErrorContext
    ) -> Dict[str, Any]:
        """创建标准错误响应"""
        if isinstance(error, BaseError):
            # 处理自定义错误
            error_response = ErrorResponse(
                error_code=error.error_code,
                message=error.message,
                details=error.details,
                request_id=context.request_id
            )
            status_code = error.status_code
        else:
            # 处理未知错误
            error_response = ErrorResponse(
                error_code="INTERNAL_ERROR",
                message="服务暂时不可用，请稍后重试",
                request_id=context.request_id
            )
            status_code = 500
        
        return {
            "statusCode": status_code,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "X-Request-Id": context.request_id or "",
                "X-Trace-Id": context.trace_id or ""
            },
            "body": json.dumps(asdict(error_response), ensure_ascii=False)
        }

# 装饰器：自动错误处理
def handle_errors(
    service_name: str = None,
    operation: str = None,
    error_handler: ErrorHandler = None
):
    """
    装饰器：自动处理函数错误
    
    使用示例:
    @handle_errors(service_name="query-handler", operation="query")
    def lambda_handler(event, context):
        # 函数逻辑
        pass
    """
    def decorator(func):
        def wrapper(*args, **kwargs):
            # 获取Lambda context（如果存在）
            lambda_context = args[1] if len(args) > 1 else None
            request_id = getattr(lambda_context, 'aws_request_id', None) if lambda_context else None
            
            # 创建错误上下文
            error_context = ErrorContext(
                service=service_name or func.__module__,
                operation=operation or func.__name__,
                request_id=request_id
            )
            
            # 创建错误处理器
            handler = error_handler or ErrorHandler(service_name or func.__module__)
            
            try:
                return func(*args, **kwargs)
            except BaseError as e:
                # 处理已知错误
                return handler.handle_error(e, error_context)
            except ClientError as e:
                # 处理AWS客户端错误
                error_code = e.response['Error']['Code']
                error_message = e.response['Error']['Message']
                
                # 映射AWS错误到自定义错误
                if error_code in ['ResourceNotFoundException', 'NoSuchKey']:
                    custom_error = NotFoundError("AWS资源", error_code)
                elif error_code in ['AccessDeniedException', 'UnauthorizedOperation']:
                    custom_error = AuthorizationError(error_message)
                elif error_code == 'ThrottlingException':
                    custom_error = RateLimitError(error_message)
                else:
                    custom_error = ExternalServiceError("AWS", error_message)
                
                return handler.handle_error(custom_error, error_context)
            except Exception as e:
                # 处理未知错误
                return handler.handle_error(e, error_context, ErrorLevel.ERROR)
        
        return wrapper
    return decorator