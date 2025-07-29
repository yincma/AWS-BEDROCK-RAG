// ================================
// AWS Configuration File
// Enterprise RAG System Frontend AWS Configuration
// ================================

import { AWSConfig } from '@/types';

// Get AWS settings from environment variables or build-time injected configuration
const getAWSConfig = (): AWSConfig => {
  // Debug info: print all environment variables
  console.log('Environment variables:', {
    REACT_APP_AWS_REGION: process.env.REACT_APP_AWS_REGION,
    REACT_APP_USER_POOL_ID: process.env.REACT_APP_USER_POOL_ID,
    REACT_APP_USER_POOL_CLIENT_ID: process.env.REACT_APP_USER_POOL_CLIENT_ID,
    REACT_APP_API_GATEWAY_URL: process.env.REACT_APP_API_GATEWAY_URL,
    NODE_ENV: process.env.NODE_ENV,
  });
  
  // These values will be injected by Terraform at build time
  const config: AWSConfig = {
    region: process.env.REACT_APP_AWS_REGION || 'us-east-1',
    userPoolId: process.env.REACT_APP_USER_POOL_ID || '',
    userPoolWebClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID || '',
    apiGatewayUrl: process.env.REACT_APP_API_GATEWAY_URL || '',
    identityPoolId: process.env.REACT_APP_IDENTITY_POOL_ID || undefined,
  };

  // Validate required configuration
  const requiredFields = ['userPoolId', 'userPoolWebClientId', 'apiGatewayUrl'];
  const missingFields = requiredFields.filter(field => !config[field as keyof AWSConfig]);
  
  if (missingFields.length > 0) {
    console.warn('Missing AWS configuration fields:', missingFields);
    
    // Provide default values in development environment
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

// Amplify configuration (v6 format)
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

// API configuration
export const apiConfig = {
  baseURL: awsConfig.apiGatewayUrl,
  timeout: 30000, // 30 seconds timeout
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

// Application configuration
export const appConfig = {
  name: 'Enterprise RAG',
  version: process.env.REACT_APP_VERSION || '1.0.0',
  environment: process.env.NODE_ENV || 'development',
  enableAnalytics: process.env.REACT_APP_ENABLE_ANALYTICS === 'true',
  enableDebug: process.env.NODE_ENV === 'development',
  
  // Feature toggles
  features: {
    chat: true,
    documentUpload: true,
    userSettings: true,
    analytics: process.env.REACT_APP_ENABLE_ANALYTICS === 'true',
    darkMode: true,
    multiLanguage: true,
  },
  
  // Default settings
  defaults: {
    theme: 'light' as const,
    language: 'auto' as const,
    topK: 5,
    includeSources: true,
    autoSave: true,
    notifications: true,
  },
  
  // Limits and constraints
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
  
  // User interface configuration
  ui: {
    sidebarWidth: 280,
    headerHeight: 64,
    chatMessageMaxWidth: 800,
    animationDuration: 300,
    debounceDelay: 500,
  },
  
  // Error retry configuration
  retry: {
    maxAttempts: 3,
    baseDelay: 1000,
    maxDelay: 10000,
    backoffFactor: 2,
  },
  
  // Cache configuration
  cache: {
    enabled: true,
    ttl: 5 * 60 * 1000, // 5 minutes
    maxEntries: 100,
  },
};

// Export configuration validation function
export const validateConfig = (): boolean => {
  try {
    // Check AWS configuration
    if (!awsConfig.userPoolId || !awsConfig.userPoolWebClientId) {
      console.error('AWS Cognito configuration is missing');
      return false;
    }
    
    if (!awsConfig.apiGatewayUrl) {
      console.error('API Gateway URL is missing');
      return false;
    }
    
    // Check URL format
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

// Development environment configuration check
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