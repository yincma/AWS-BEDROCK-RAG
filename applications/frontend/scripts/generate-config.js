#!/usr/bin/env node

/**
 * 从环境变量生成 config.json 文件
 * 避免硬编码配置值
 */

const fs = require('fs');
const path = require('path');

// 从环境变量或 .env 文件读取配置
require('dotenv').config();

const config = {
  apiEndpoint: process.env.REACT_APP_API_GATEWAY_URL || '',
  region: process.env.REACT_APP_AWS_REGION || 'us-east-1',
  environment: process.env.NODE_ENV || 'development',
  userPoolId: process.env.REACT_APP_USER_POOL_ID || '',
  userPoolClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID || ''
};

// 验证必需的配置
const requiredFields = ['apiEndpoint', 'userPoolId', 'userPoolClientId'];
const missingFields = requiredFields.filter(field => !config[field]);

if (missingFields.length > 0) {
  console.error('错误：缺少必需的环境变量：');
  missingFields.forEach(field => {
    console.error(`  - REACT_APP_${field.replace(/([A-Z])/g, '_$1').toUpperCase()}`);
  });
  process.exit(1);
}

// 写入 config.json
const configPath = path.join(__dirname, '..', 'public', 'config.json');
fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');

console.log('✅ 已生成 config.json：');
console.log(JSON.stringify(config, null, 2));