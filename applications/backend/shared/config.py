"""
Unified configuration management module
Centrally manage all environment variables and configuration items, avoiding hard coding
"""
import os
import yaml
import json
import boto3
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from pathlib import Path
from functools import lru_cache

@dataclass
class APIConfig:
    """API configuration"""
    endpoint: str
    timeout: int = 30000
    stage: str = "dev"
    # CORS configuration
    cors_allow_origin: str = "*"
    cors_allow_methods: str = "GET,POST,PUT,DELETE,OPTIONS"
    cors_allow_headers: str = "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
    cors_allow_credentials: bool = False

@dataclass
class CognitoConfig:
    """Cognito configuration"""
    user_pool_id: str
    client_id: str
    domain: str

@dataclass
class BedrockConfig:
    """Bedrock configuration"""
    model_id: str = "amazon.nova-pro-v1:0"
    embedding_model_id: str = "amazon.titan-embed-text-v1"
    knowledge_base_id: Optional[str] = None
    data_source_id: Optional[str] = None
    max_tokens: int = 1000
    temperature: float = 0.1

@dataclass
class S3Config:
    """S3 configuration"""
    document_bucket: str
    frontend_bucket: str
    document_prefix: str = "documents/"
    lifecycle_transition_days: int = 30
    lifecycle_expiration_days: int = 90

@dataclass
class DocumentConfig:
    """Document processing configuration"""
    allowed_file_extensions: List[str] = field(default_factory=lambda: ['.pdf', '.txt', '.docx', '.doc', '.md', '.csv', '.json'])
    max_file_size_mb: int = 100
    presigned_url_expiry_seconds: int = 900
    
    @property
    def max_file_size_bytes(self) -> int:
        """Get maximum file size (bytes)"""
        return self.max_file_size_mb * 1024 * 1024
    
    def validate_file_extension(self, filename: str) -> bool:
        """Validate file extension"""
        if not filename:
            return False
        return any(filename.lower().endswith(ext) for ext in self.allowed_file_extensions)

@dataclass
class FeaturesConfig:
    """Feature toggle configuration"""
    enable_waf: bool = False
    enable_xray: bool = True
    enable_shield: bool = False
    log_level: str = "INFO"
    log_retention_days: int = 7

@dataclass
class MonitoringConfig:
    """Monitoring configuration"""
    cloudwatch_namespace: str
    alarm_email: Optional[str] = None

@dataclass
class LambdaConfig:
    """Lambda configuration"""
    memory_size: int = 1024
    timeout: int = 300
    reserved_concurrent_executions: int = 5

@dataclass
class Config:
    """Unified configuration management"""
    environment: str
    region: str
    api: APIConfig
    cognito: CognitoConfig
    bedrock: BedrockConfig
    s3: S3Config
    document: DocumentConfig
    features: FeaturesConfig
    monitoring: MonitoringConfig
    lambda_config: LambdaConfig = field(default_factory=lambda: LambdaConfig())
    
    _instance: Optional['Config'] = None
    
    @classmethod
    def load(cls, env: str = None) -> 'Config':
        """Load environment configuration (singleton pattern)"""
        if cls._instance is not None:
            return cls._instance
            
        env = env or os.getenv('ENVIRONMENT', 'dev')
        
        # Find configuration file
        config_paths = [
            Path(f'config/environments/{env}.yaml'),
            Path(f'../config/environments/{env}.yaml'),
            Path(f'../../config/environments/{env}.yaml'),
            Path(f'/opt/config/{env}.yaml'),  # Lambda environment
        ]
        
        config_data = None
        for config_path in config_paths:
            if config_path.exists():
                with open(config_path, 'r') as f:
                    config_data = yaml.safe_load(f)
                break
        
        if config_data is None:
            # If configuration file not found, use environment variables
            config_data = cls._load_from_env()
        
        # Replace environment variables
        config_data = cls._substitute_env_vars(config_data)
        
        # Create configuration object
        config = cls._create_config(config_data)
        cls._instance = config
        
        return config
    
    @staticmethod
    def _load_from_env() -> Dict[str, Any]:
        """Load configuration from environment variables"""
        return {
            'environment': os.getenv('ENVIRONMENT', 'dev'),
            'region': os.getenv('AWS_REGION', 'us-east-1'),
            'api': {
                'endpoint': os.getenv('API_ENDPOINT', ''),
                'timeout': int(os.getenv('API_TIMEOUT', '30000')),
                'stage': os.getenv('API_STAGE', 'dev'),
                'cors_allow_origin': os.getenv('CORS_ALLOW_ORIGIN', '*'),
                'cors_allow_methods': os.getenv('CORS_ALLOW_METHODS', 'GET,POST,PUT,DELETE,OPTIONS'),
                'cors_allow_headers': os.getenv('CORS_ALLOW_HEADERS', 
                                              'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'),
                'cors_allow_credentials': os.getenv('CORS_ALLOW_CREDENTIALS', 'false').lower() == 'true'
            },
            'cognito': {
                'user_pool_id': os.getenv('COGNITO_USER_POOL_ID', ''),
                'client_id': os.getenv('COGNITO_CLIENT_ID', ''),
                'domain': os.getenv('COGNITO_DOMAIN', '')
            },
            'bedrock': {
                'model_id': os.getenv('BEDROCK_MODEL_ID', 'amazon.nova-pro-v1:0'),
                'embedding_model_id': os.getenv('BEDROCK_EMBEDDING_MODEL_ID', 'amazon.titan-embed-text-v1'),
                'knowledge_base_id': os.getenv('KNOWLEDGE_BASE_ID'),
                'data_source_id': os.getenv('DATA_SOURCE_ID'),
                'max_tokens': int(os.getenv('BEDROCK_MAX_TOKENS', '1000')),
                'temperature': float(os.getenv('BEDROCK_TEMPERATURE', '0.1'))
            },
            's3': {
                'document_bucket': os.getenv('S3_BUCKET', ''),
                'frontend_bucket': os.getenv('FRONTEND_BUCKET', ''),
                'document_prefix': os.getenv('DOCUMENT_PREFIX', 'documents/'),
                'lifecycle_transition_days': int(os.getenv('S3_LIFECYCLE_TRANSITION_DAYS', '30')),
                'lifecycle_expiration_days': int(os.getenv('S3_LIFECYCLE_EXPIRATION_DAYS', '90'))
            },
            'document': {
                'allowed_file_extensions': os.getenv('ALLOWED_FILE_EXTENSIONS', '.pdf,.txt,.docx,.doc,.md,.csv,.json').split(','),
                'max_file_size_mb': int(os.getenv('MAX_FILE_SIZE_MB', '100')),
                'presigned_url_expiry_seconds': int(os.getenv('PRESIGNED_URL_EXPIRY_SECONDS', '900'))
            },
            'features': {
                'enable_waf': os.getenv('ENABLE_WAF', 'false').lower() == 'true',
                'enable_xray': os.getenv('ENABLE_XRAY', 'true').lower() == 'true',
                'enable_shield': os.getenv('ENABLE_SHIELD', 'false').lower() == 'true',
                'log_level': os.getenv('LOG_LEVEL', 'INFO'),
                'log_retention_days': int(os.getenv('LOG_RETENTION_DAYS', '7'))
            },
            'monitoring': {
                'cloudwatch_namespace': os.getenv('CLOUDWATCH_NAMESPACE', 'enterprise-rag'),
                'alarm_email': os.getenv('ALARM_EMAIL')
            },
            'lambda': {
                'memory_size': int(os.getenv('LAMBDA_MEMORY_SIZE', '1024')),
                'timeout': int(os.getenv('LAMBDA_TIMEOUT', '300')),
                'reserved_concurrent_executions': int(os.getenv('LAMBDA_RESERVED_CONCURRENCY', '5'))
            }
        }
    
    @staticmethod
    def _substitute_env_vars(config: Dict[str, Any]) -> Dict[str, Any]:
        """Recursively replace environment variables in configuration"""
        def substitute(value):
            if isinstance(value, str):
                # Find ${VAR_NAME} pattern
                import re
                pattern = r'\$\{([^}]+)\}'
                
                def replacer(match):
                    var_name = match.group(1)
                    return os.getenv(var_name, match.group(0))
                
                return re.sub(pattern, replacer, value)
            elif isinstance(value, dict):
                return {k: substitute(v) for k, v in value.items()}
            elif isinstance(value, list):
                return [substitute(v) for v in value]
            else:
                return value
        
        return substitute(config)
    
    @classmethod
    def _create_config(cls, data: Dict[str, Any]) -> 'Config':
        """Create configuration object from dictionary"""
        return cls(
            environment=data['environment'],
            region=data['region'],
            api=APIConfig(**data['api']),
            cognito=CognitoConfig(**data['cognito']),
            bedrock=BedrockConfig(**data['bedrock']),
            s3=S3Config(**data['s3']),
            document=DocumentConfig(**data.get('document', {})),
            features=FeaturesConfig(**data['features']),
            monitoring=MonitoringConfig(**data['monitoring']),
            lambda_config=LambdaConfig(**data.get('lambda', {}))
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            'environment': self.environment,
            'region': self.region,
            'api': {
                'endpoint': self.api.endpoint,
                'timeout': self.api.timeout,
                'stage': self.api.stage
            },
            'cognito': {
                'user_pool_id': self.cognito.user_pool_id,
                'client_id': self.cognito.client_id,
                'domain': self.cognito.domain
            },
            'bedrock': {
                'model_id': self.bedrock.model_id,
                'embedding_model_id': self.bedrock.embedding_model_id,
                'knowledge_base_id': self.bedrock.knowledge_base_id,
                'data_source_id': self.bedrock.data_source_id,
                'max_tokens': self.bedrock.max_tokens,
                'temperature': self.bedrock.temperature
            },
            's3': {
                'document_bucket': self.s3.document_bucket,
                'frontend_bucket': self.s3.frontend_bucket
            },
            'features': {
                'enable_waf': self.features.enable_waf,
                'enable_xray': self.features.enable_xray,
                'enable_shield': self.features.enable_shield,
                'log_level': self.features.log_level,
                'log_retention_days': self.features.log_retention_days
            },
            'monitoring': {
                'cloudwatch_namespace': self.monitoring.cloudwatch_namespace,
                'alarm_email': self.monitoring.alarm_email
            },
            'lambda': {
                'memory_size': self.lambda_config.memory_size,
                'timeout': self.lambda_config.timeout,
                'reserved_concurrent_executions': self.lambda_config.reserved_concurrent_executions
            }
        }
    
    def get_lambda_environment_variables(self) -> Dict[str, str]:
        """Get Lambda function environment variables"""
        return {
            'ENVIRONMENT': self.environment,
            'REGION': self.region,
            # Note: Do not set AWS_REGION, it's a reserved Lambda environment variable
            'KNOWLEDGE_BASE_ID': self.bedrock.knowledge_base_id or '',
            'DATA_SOURCE_ID': self.bedrock.data_source_id or '',
            'BEDROCK_MODEL_ID': self.bedrock.model_id,
            'S3_BUCKET': self.s3.document_bucket,
            'LOG_LEVEL': self.features.log_level,
            'ENABLE_XRAY': str(self.features.enable_xray).lower(),
            # CORS configuration
            'CORS_ALLOW_ORIGIN': self.api.cors_allow_origin,
            'CORS_ALLOW_METHODS': self.api.cors_allow_methods,
            'CORS_ALLOW_HEADERS': self.api.cors_allow_headers,
            'CORS_ALLOW_CREDENTIALS': str(self.api.cors_allow_credentials).lower(),
            # Document processing configuration
            'ALLOWED_FILE_EXTENSIONS': ','.join(self.document.allowed_file_extensions),
            'MAX_FILE_SIZE_MB': str(self.document.max_file_size_mb),
            'DOCUMENT_PREFIX': self.s3.document_prefix,
            'PRESIGNED_URL_EXPIRY_SECONDS': str(self.document.presigned_url_expiry_seconds),
            # Lambda configuration
            'LAMBDA_MEMORY_SIZE': str(self.lambda_config.memory_size),
            'LAMBDA_TIMEOUT': str(self.lambda_config.timeout)
        }
    
    def get_cors_headers(self) -> Dict[str, str]:
        """Get CORS response headers"""
        headers = {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": self.api.cors_allow_origin,
            "Access-Control-Allow-Methods": self.api.cors_allow_methods,
            "Access-Control-Allow-Headers": self.api.cors_allow_headers
        }
        if self.api.cors_allow_credentials and self.api.cors_allow_origin != "*":
            headers["Access-Control-Allow-Credentials"] = "true"
        return headers
    
    def get_s3_key(self, file_id: str, file_extension: str) -> str:
        """Generate S3 object key"""
        return f"{self.s3.document_prefix}{file_id}{file_extension}"
    
    def validate_required_config(self) -> None:
        """Validate required configuration items"""
        required_configs = {
            'S3_BUCKET': self.s3.document_bucket,
            'AWS_REGION': self.region,
        }
        
        missing_configs = [key for key, value in required_configs.items() if not value]
        
        if missing_configs:
            raise ValueError(f"Missing required configuration items: {', '.join(missing_configs)}")
    
    def get_config_summary(self) -> Dict[str, Any]:
        """Get configuration summary (hide sensitive information)"""
        return {
            'project_name': self.environment,
            'environment': self.environment,
            'aws_region': self.region,
            's3_bucket': self.s3.document_bucket[:10] + '...' if self.s3.document_bucket else None,
            'knowledge_base_configured': bool(self.bedrock.knowledge_base_id),
            'allowed_file_extensions': self.document.allowed_file_extensions,
            'max_file_size_mb': self.document.max_file_size_mb,
            'cors_origin': self.api.cors_allow_origin,
            'enable_xray': self.features.enable_xray
        }

# Quick access
def get_config(env: str = None) -> Config:
    """Get configuration instance"""
    return Config.load(env)