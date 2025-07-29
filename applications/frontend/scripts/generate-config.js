#!/usr/bin/env node

/**
 * Generate config.json file from environment variables
 * Avoid hardcoding configuration values
 */

const fs = require('fs');
const path = require('path');

// Read configuration from environment variables or .env file
require('dotenv').config();

const config = {
  apiEndpoint: process.env.REACT_APP_API_GATEWAY_URL || '',
  region: process.env.REACT_APP_AWS_REGION || 'us-east-1',
  environment: process.env.NODE_ENV || 'development',
  userPoolId: process.env.REACT_APP_USER_POOL_ID || '',
  userPoolClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID || ''
};

// Validate required configuration
const requiredFields = ['apiEndpoint', 'userPoolId', 'userPoolClientId'];
const missingFields = requiredFields.filter(field => !config[field]);

if (missingFields.length > 0) {
  console.error('Error: Missing required environment variables:');
  missingFields.forEach(field => {
    console.error(`  - REACT_APP_${field.replace(/([A-Z])/g, '_$1').toUpperCase()}`);
  });
  process.exit(1);
}

// Write config.json
const configPath = path.join(__dirname, '..', 'public', 'config.json');
fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');

console.log('✅ Generated config.json:');
console.log(JSON.stringify(config, null, 2));