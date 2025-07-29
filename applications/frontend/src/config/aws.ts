// ================================
// AWS配置文件
// Enterprise RAG System Frontend AWS Configuration
// ================================

import { AWSConfig } from '@/types';

// 从环境变量或构建时注入的配置中获取AWS设置
const getAWSConfig = (): AWSConfig => {
  // 调试信息：打印所有环境变量
  console.log('Environment variables:', {
    REACT_APP_AWS_REGION: process.env.REACT_APP_AWS_REGION,
    REACT_APP_USER_POOL_ID: process.env.REACT_APP_USER_POOL_ID,
    REACT_APP_USER_POOL_CLIENT_ID: process.env.REACT_APP_USER_POOL_CLIENT_ID,
    REACT_APP_API_GATEWAY_URL: process.env.REACT_APP_API_GATEWAY_URL,
    NODE_ENV: process.env.NODE_ENV,
  });
  
  // 这些值将在构建时由Terraform注入
  const config: AWSConfig = {
    region: process.env.REACT_APP_AWS_REGION || 'us-east-1',
    userPoolId: process.env.REACT_APP_USER_POOL_ID || '',
    userPoolWebClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID || '',
    apiGatewayUrl: process.env.REACT_APP_API_GATEWAY_URL || '',
    identityPoolId: process.env.REACT_APP_IDENTITY_POOL_ID || undefined,
  };

  // 验证必需的配置
  const requiredFields = ['userPoolId', 'userPoolWebClientId', 'apiGatewayUrl'];
  const missingFields = requiredFields.filter(field => !config[field as keyof AWSConfig]);
  
  if (missingFields.length > 0) {
    console.warn('Missing AWS configuration fields:', missingFields);
    
    // 在开发环境中提供默认值
    if (process.env.NODE_ENV === 'development') {
      console.warn('Using development defaults for missing AWS config');
      return {
        ...config,
        userPoolId: config.userPoolId || 'us-east-1_XXXXXXXXX',
        userPoolWebClientId: config.userPoolWebClientId || 'xxxxxxxxxxxxxxxxxxxxxxxxxx',
        apiGatewayUrl: config.apiGatewayUrl || 'https://api.example.com/dev',
      };
    }
  }

  return config;
};

export const awsConfig = getAWSConfig();

// Amplify配置 (v6格式)
export const amplifyConfig = {
  Auth: {
    Cognito: {
      userPoolId: awsConfig.userPoolId,
      userPoolClientId: awsConfig.userPoolWebClientId,
      loginWith: {
        oauth: {
          domain: process.env.REACT_APP_OAUTH_DOMAIN || '',
          scopes: ['openid', 'profile', 'email'],
          redirectSignIn: [window.location.origin + '/callback'],
          redirectSignOut: [window.location.origin + '/logout'],
          responseType: 'code' as const,
        },
        username: true,
        email: true,
      },
    },
  },
  API: {
    REST: {
      ragApi: {
        endpoint: awsConfig.apiGatewayUrl,
        region: awsConfig.region,
      },
    },
  },
  Storage: {
    S3: {
      bucket: process.env.REACT_APP_S3_BUCKET || '',
      region: awsConfig.region,
    },
  },
};

// API配置
export const apiConfig = {
  baseURL: awsConfig.apiGatewayUrl,
  timeout: 30000, // 30秒超时
  retries: 3,
  endpoints: {
    query: '/query',
    chat: '/chat',
    upload: '/upload',
    documents: '/documents',
    health: '/health',
    auth: '/auth',
    stats: '/stats',
  },
};

// 应用配置
export const appConfig = {
  name: 'Enterprise RAG',
  version: process.env.REACT_APP_VERSION || '1.0.0',
  environment: process.env.NODE_ENV || 'development',
  enableAnalytics: process.env.REACT_APP_ENABLE_ANALYTICS === 'true',
  enableDebug: process.env.NODE_ENV === 'development',
  
  // 功能开关
  features: {
    chat: true,
    documentUpload: true,
    userSettings: true,
    analytics: process.env.REACT_APP_ENABLE_ANALYTICS === 'true',
    darkMode: true,
    multiLanguage: true,
  },
  
  // 默认设置
  defaults: {
    theme: 'light' as const,
    language: 'auto' as const,
    topK: 5,
    includeSources: true,
    autoSave: true,
    notifications: true,
  },
  
  // 限制和约束
  limits: {
    maxFileSize: 100 * 1024 * 1024, // 100MB
    maxQueryLength: 1000,
    maxSessionMessages: 100,
    supportedFileTypes: [
      '.pdf',
      '.docx',
      '.txt',
      '.md',
      '.csv',
      '.json',
    ],
    maxConcurrentUploads: 3,
  },
  
  // 用户界面配置
  ui: {
    sidebarWidth: 280,
    headerHeight: 64,
    chatMessageMaxWidth: 800,
    animationDuration: 300,
    debounceDelay: 500,
  },
  
  // 错误重试配置
  retry: {
    maxAttempts: 3,
    baseDelay: 1000,
    maxDelay: 10000,
    backoffFactor: 2,
  },
  
  // 缓存配置
  cache: {
    enabled: true,
    ttl: 5 * 60 * 1000, // 5分钟
    maxEntries: 100,
  },
};

// 导出配置验证函数
export const validateConfig = (): boolean => {
  try {
    // 检查AWS配置
    if (!awsConfig.userPoolId || !awsConfig.userPoolWebClientId) {
      console.error('AWS Cognito configuration is missing');
      return false;
    }
    
    if (!awsConfig.apiGatewayUrl) {
      console.error('API Gateway URL is missing');
      return false;
    }
    
    // 检查URL格式
    try {
      new URL(awsConfig.apiGatewayUrl);
    } catch {
      console.error('Invalid API Gateway URL format');
      return false;
    }
    
    return true;
  } catch (error) {
    console.error('Configuration validation failed:', error);
    return false;
  }
};

// 开发环境配置检查
if (process.env.NODE_ENV === 'development') {
  console.log('AWS Configuration:', {
    region: awsConfig.region,
    userPoolId: awsConfig.userPoolId,
    apiGatewayUrl: awsConfig.apiGatewayUrl,
    hasIdentityPool: !!awsConfig.identityPoolId,
  });
  
  if (!validateConfig()) {
    console.warn('Configuration validation failed. Some features may not work correctly.');
  }
}

export default awsConfig;