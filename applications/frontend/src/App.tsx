import React, { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import { CssBaseline, Box, CircularProgress, Alert } from '@mui/material';
import { Amplify } from 'aws-amplify';
import './App.css';

// Components
import LoginPage from './pages/LoginPage';
import ChatPage from './pages/ChatPage';
import DocumentsPage from './pages/DocumentsPage';
import SystemMonitorPage from './pages/SystemMonitorPage';
import SettingsPage from './pages/SettingsPage';
import AuthTestPage from './pages/AuthTestPage';
import MainLayout from './components/MainLayout';
import NotificationProvider from './components/NotificationProvider';
import { User } from './types';
import { authService, errorService } from './services';

// Import configuration
import { amplifyConfig } from './config/aws';
import { apiService } from './services/api';

// 动态加载配置
const initializeApp = async () => {
  try {
    // 尝试从 config.json 加载配置
    const response = await fetch('/config.json');
    if (response.ok) {
      const config = await response.json();
      console.log('Loaded config from server:', config);
      
      // 使用服务器配置更新 Amplify 配置
      const updatedConfig = {
        Auth: {
          Cognito: {
            userPoolId: config.userPoolId,
            userPoolClientId: config.userPoolClientId,
            region: config.region,
            loginWith: {
              username: true,
              email: true,
            },
          },
        },
        API: {
          REST: {
            ragApi: {
              endpoint: config.apiEndpoint,
              region: config.region,
            },
          },
        },
      };
      
      Amplify.configure(updatedConfig);
      console.log('Amplify configured with server config');
      
      // 同时更新 API Service 的配置
      apiService.updateConfig({ apiEndpoint: config.apiEndpoint });
    } else {
      console.warn('Could not load config.json, using default configuration');
      Amplify.configure(amplifyConfig);
    }
  } catch (error) {
    console.error('Error loading config:', error);
    // 使用默认配置
    Amplify.configure(amplifyConfig);
  }
};

// 初始化应用将在组件加载时进行

// Initialize error service
errorService.onError((error) => {
  console.error('[App Error]', error);
});

const theme = createTheme({
  palette: {
    primary: {
      main: '#667eea',
      light: '#9ba5f2',
      dark: '#4c63d7',
    },
    secondary: {
      main: '#764ba2',
      light: '#a16fd0',
      dark: '#5d3a7f',
    },
    background: {
      default: '#f5f6fa',
      paper: '#ffffff',
    },
    text: {
      primary: '#2c2c54',
      secondary: '#6c7293',
    }
  },
  typography: {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    h4: {
      fontWeight: 600,
      color: '#2c2c54',
    },
    h5: {
      fontWeight: 600,
      color: '#2c2c54',
    },
    h6: {
      fontWeight: 600,
      color: '#2c2c54',
    },
  },
  components: {
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
        },
      },
    },
    MuiButton: {
      styleOverrides: {
        root: {
          borderRadius: 8,
          textTransform: 'none',
          fontWeight: 500,
        },
      },
    },
  },
});

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // 统一的初始化流程：先加载配置，然后检查认证状态
    const initialize = async () => {
      try {
        // 加载配置
        await initializeApp();
        
        // 检查认证状态
        try {
          const currentUser = await authService.getCurrentUser();
          setUser(currentUser);
          setError(null);
        } catch (authError: any) {
          console.log('User not authenticated:', authError);
          setUser(null);
          // Provide better error handling for unauthenticated users
          if (authError.message && authError.message.includes('UserPool')) {
            setError('Authentication service is being configured. Please contact your administrator or try again later.');
          }
        }
      } catch (error) {
        console.error('Failed to initialize app:', error);
        setError('Failed to initialize application');
      } finally {
        setLoading(false);
      }
    };
    
    initialize();
  }, []);


  const handleLogin = (userData: User) => {
    setUser(userData);
    setError(null);
  };

  const handleLogout = async () => {
    try {
      await authService.signOut();
      setUser(null);
      setError(null);
    } catch (error) {
      errorService.handleError(
        error,
        'logout',
        { 
          showNotification: true,
          userMessage: 'Failed to log out'
        }
      );
    }
  };

  if (loading) {
    return (
      <ThemeProvider theme={theme}>
        <CssBaseline />
        <Box 
          display="flex" 
          justifyContent="center" 
          alignItems="center" 
          minHeight="100vh"
          bgcolor="#f5f5f5"
        >
          <CircularProgress size={60} />
        </Box>
      </ThemeProvider>
    );
  }

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <NotificationProvider>
        <Router>
          <Box sx={{ minHeight: '100vh', bgcolor: '#f5f5f5' }}>
            {error && (
              <Alert severity="error" onClose={() => setError(null)}>
                {error}
              </Alert>
            )}
            
            {user ? (
              <MainLayout user={user} onLogout={handleLogout}>
                <Routes>
                  <Route path="/" element={<Navigate to="/chat" />} />
                  <Route path="/chat" element={<ChatPage />} />
                  <Route path="/documents" element={<DocumentsPage />} />
                  <Route path="/monitor" element={<SystemMonitorPage />} />
                  <Route path="/settings" element={<SettingsPage />} />
                  <Route path="/auth-test" element={<AuthTestPage />} />
                  <Route path="*" element={<Navigate to="/chat" />} />
                </Routes>
              </MainLayout>
            ) : (
              <Routes>
                <Route path="/login" element={<LoginPage onLogin={handleLogin} />} />
                <Route path="*" element={<Navigate to="/login" />} />
              </Routes>
            )}
          </Box>
        </Router>
      </NotificationProvider>
    </ThemeProvider>
  );
}

export default App;