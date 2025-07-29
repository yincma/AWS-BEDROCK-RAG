import React, { useState, useEffect } from 'react';
import { Box, Paper, Typography, Button, Alert, Divider, TextField } from '@mui/material';
import { fetchAuthSession, getCurrentUser } from 'aws-amplify/auth';
import { apiService } from '../services/api';

const AuthTestPage: React.FC = () => {
  const [authStatus, setAuthStatus] = useState<any>({});
  const [apiTestResult, setApiTestResult] = useState<any>({});
  const [loading, setLoading] = useState(false);

  const checkAuthStatus = async () => {
    setLoading(true);
    try {
      // 1. 检查当前用户
      const user = await getCurrentUser();
      const session = await fetchAuthSession();
      
      setAuthStatus({
        isAuthenticated: true,
        username: user.username,
        userId: user.userId,
        hasTokens: !!session.tokens,
        hasIdToken: !!session.tokens?.idToken,
        hasAccessToken: !!session.tokens?.accessToken,
        idTokenPreview: session.tokens?.idToken?.toString().substring(0, 50) + '...',
        accessTokenPreview: session.tokens?.accessToken?.toString().substring(0, 50) + '...',
      });
    } catch (error: any) {
      setAuthStatus({
        isAuthenticated: false,
        error: error.message,
      });
    }
    setLoading(false);
  };

  const testDocumentsAPI = async () => {
    setLoading(true);
    setApiTestResult({ loading: true });
    
    try {
      // 获取认证token
      const session = await fetchAuthSession();
      const idToken = session.tokens?.idToken?.toString();
      
      if (!idToken) {
        throw new Error('No ID token available');
      }

      // 直接测试API
      const startTime = Date.now();
      const response = await fetch('https://vjywvai0e7.execute-api.us-east-1.amazonaws.com/dev/documents', {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${idToken}`,
          'Content-Type': 'application/json',
        },
      });
      
      const responseTime = Date.now() - startTime;
      const responseText = await response.text();
      
      let parsedData = null;
      try {
        parsedData = JSON.parse(responseText);
      } catch (e) {
        console.error('Failed to parse response as JSON');
      }

      setApiTestResult({
        status: response.status,
        statusText: response.statusText,
        responseTime: `${responseTime}ms`,
        headers: Object.fromEntries(response.headers.entries()),
        rawResponse: responseText.substring(0, 500),
        parsedData: parsedData,
        success: response.ok,
      });

      // 同时测试通过apiService
      if (response.ok) {
        const apiServiceResult = await apiService.getDocuments();
        setApiTestResult((prev: any) => ({
          ...prev,
          apiServiceResult: apiServiceResult,
        }));
      }
    } catch (error: any) {
      setApiTestResult({
        error: error.message,
        stack: error.stack,
      });
    }
    setLoading(false);
  };

  const testStatusAPI = async () => {
    setLoading(true);
    try {
      const result = await apiService.getKnowledgeBaseStatus();
      setApiTestResult({
        endpoint: '/query/status',
        success: result.success,
        data: result.data,
        error: result.error,
      });
    } catch (error: any) {
      setApiTestResult({
        endpoint: '/query/status',
        error: error.message,
      });
    }
    setLoading(false);
  };

  useEffect(() => {
    checkAuthStatus();
  }, []);

  return (
    <Box p={3}>
      <Typography variant="h4" gutterBottom>
        认证和API测试页面
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h6" gutterBottom>
          认证状态
        </Typography>
        <Button onClick={checkAuthStatus} disabled={loading} variant="contained" sx={{ mb: 2 }}>
          刷新认证状态
        </Button>
        
        {authStatus.isAuthenticated ? (
          <Alert severity="success" sx={{ mb: 2 }}>
            ✓ 用户已登录
          </Alert>
        ) : (
          <Alert severity="error" sx={{ mb: 2 }}>
            ✗ 用户未登录: {authStatus.error}
          </Alert>
        )}
        
        <pre style={{ 
          backgroundColor: '#f5f5f5', 
          padding: '10px', 
          borderRadius: '4px',
          overflow: 'auto',
          fontSize: '12px' 
        }}>
          {JSON.stringify(authStatus, null, 2)}
        </pre>
      </Paper>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h6" gutterBottom>
          API测试
        </Typography>
        
        <Box sx={{ display: 'flex', gap: 2, mb: 2 }}>
          <Button 
            onClick={testDocumentsAPI} 
            disabled={loading || !authStatus.isAuthenticated} 
            variant="contained"
          >
            测试 /documents API
          </Button>
          
          <Button 
            onClick={testStatusAPI} 
            disabled={loading || !authStatus.isAuthenticated} 
            variant="contained"
            color="secondary"
          >
            测试 /status API
          </Button>
        </Box>

        {apiTestResult.error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            API调用失败: {apiTestResult.error}
          </Alert>
        )}

        {apiTestResult.success && (
          <Alert severity="success" sx={{ mb: 2 }}>
            API调用成功! 状态码: {apiTestResult.status}
          </Alert>
        )}

        <pre style={{ 
          backgroundColor: '#f5f5f5', 
          padding: '10px', 
          borderRadius: '4px',
          overflow: 'auto',
          fontSize: '12px',
          maxHeight: '400px'
        }}>
          {JSON.stringify(apiTestResult, null, 2)}
        </pre>
      </Paper>

      <Paper sx={{ p: 3 }}>
        <Typography variant="h6" gutterBottom>
          调试命令（在浏览器控制台运行）
        </Typography>
        
        <TextField
          multiline
          rows={10}
          fullWidth
          variant="outlined"
          value={`
// 检查Amplify配置
console.log('Amplify Config:', window.Amplify);

// 检查认证状态
import { fetchAuthSession, getCurrentUser } from 'aws-amplify/auth';
const user = await getCurrentUser();
console.log('Current User:', user);

const session = await fetchAuthSession();
console.log('Session:', session);
console.log('ID Token:', session.tokens?.idToken?.toString());

// 手动测试API
const idToken = session.tokens?.idToken?.toString();
const response = await fetch('https://vjywvai0e7.execute-api.us-east-1.amazonaws.com/dev/documents', {
  headers: {
    'Authorization': \`Bearer \${idToken}\`,
    'Content-Type': 'application/json'
  }
});
console.log('Response:', await response.json());
          `.trim()}
          InputProps={{ readOnly: true }}
        />
      </Paper>
    </Box>
  );
};

export default AuthTestPage;