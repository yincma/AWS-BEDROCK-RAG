export const config = {
  aws: {
    region: process.env.REACT_APP_AWS_REGION || 'us-east-1',
    userPoolId: process.env.REACT_APP_USER_POOL_ID || '',
    userPoolClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID || '',
    apiGatewayUrl: process.env.REACT_APP_API_GATEWAY_URL || '',
    s3Bucket: process.env.REACT_APP_S3_BUCKET || '',
    knowledgeBaseId: process.env.REACT_APP_KNOWLEDGE_BASE_ID || ''
  },
  app: {
    version: process.env.REACT_APP_VERSION || '1.0.0',
    environment: process.env.REACT_APP_ENVIRONMENT || 'dev',
    enableAnalytics: process.env.REACT_APP_ENABLE_ANALYTICS === 'true'
  }
};