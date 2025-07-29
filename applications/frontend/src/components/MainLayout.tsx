import React, { useState, useEffect } from 'react';
import {
  Box,
  Drawer,
  AppBar,
  Toolbar,
  Typography,
  Divider,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  ListItemButton,
  Avatar,
  Button,
  Card,
  CardContent,
  Chip,
  IconButton,
  Badge,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  CircularProgress,
  Alert,
} from '@mui/material';
import {
  Chat as ChatIcon,
  Description as DocumentIcon,
  Monitor as MonitorIcon,
  Settings as SettingsIcon,
  Menu as MenuIcon,
  Logout as LogoutIcon,
  Refresh as RefreshIcon,
  ExpandMore as ExpandMoreIcon,
  CheckCircle as CheckCircleIcon,
  Warning as WarningIcon,
  Error as ErrorIcon,
  Analytics as AnalyticsIcon,
  Storage as StorageIcon,
  Speed as SpeedIcon,
} from '@mui/icons-material';
import { useLocation, useNavigate } from 'react-router-dom';
import { User } from '../types';
import { apiService } from '../services';

const drawerWidth = 320;

interface MainLayoutProps {
  user: User;
  onLogout: () => void;
  children: React.ReactNode;
}

interface SystemHealth {
  overall: 'healthy' | 'degraded' | 'error';
  components: {
    [key: string]: {
      status: 'healthy' | 'error';
      error?: string;
    };
  };
}

interface KnowledgeBaseStats {
  total_chunks: number;
  unique_documents: number;
  collection_name: string;
  file_types: { [key: string]: number };
}

const MainLayout: React.FC<MainLayoutProps> = ({ user, onLogout, children }) => {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [systemHealth, setSystemHealth] = useState<SystemHealth | null>(null);
  const [kbStats, setKbStats] = useState<KnowledgeBaseStats | null>(null);
  const [loading, setLoading] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  const menuItems = [
    { text: '💬 智能问答', path: '/chat', icon: <ChatIcon /> },
    { text: '📚 文档管理', path: '/documents', icon: <DocumentIcon /> },
    { text: '📈 系统监控', path: '/monitor', icon: <MonitorIcon /> },
    { text: '⚙️ 系统设置', path: '/settings', icon: <SettingsIcon /> },
  ];

  const handleDrawerToggle = () => {
    setMobileOpen(!mobileOpen);
  };

  const refreshSystemHealth = async () => {
    setLoading(true);
    try {
      // Mock system health check - replace with actual API call
      const mockHealth: SystemHealth = {
        overall: 'healthy',
        components: {
          'API Gateway': { status: 'healthy' },
          'Lambda Functions': { status: 'healthy' },
          'Document Store': { status: 'healthy' },
          'Vector Database': { status: 'healthy' },
          'LLM Service': { status: 'healthy' },
        }
      };
      setSystemHealth(mockHealth);
    } catch (error) {
      console.error('Health check failed:', error);
      setSystemHealth({
        overall: 'error',
        components: {
          'System': { status: 'error', error: '健康检查失败' }
        }
      });
    } finally {
      setLoading(false);
    }
  };

  const refreshKbStats = async () => {
    try {
      // 获取文档列表
      const documentsResponse = await apiService.getDocuments();
      
      // 获取知识库状态
      const statusResponse = await apiService.getKnowledgeBaseStatus();
      
      if (documentsResponse.success && documentsResponse.data && statusResponse.success && statusResponse.data) {
        const documents = documentsResponse.data;
        const statusData = statusResponse.data;
        
        // 计算文件类型分布
        const fileTypes: Record<string, number> = {};
        documents.forEach(doc => {
          // 从文件名或类型中提取扩展名
          let extension = '';
          if (doc.name) {
            const match = doc.name.match(/\.([^.]+)$/);
            if (match) {
              extension = match[1].toLowerCase();
            }
          }
          
          // 如果无法从文件名获取，尝试从content-type推断
          if (!extension && doc.type) {
            const typeMapping: Record<string, string> = {
              'application/pdf': 'pdf',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
              'text/plain': 'txt',
              'text/markdown': 'md',
              'text/csv': 'csv',
              'application/json': 'json'
            };
            extension = typeMapping[doc.type] || 'other';
          }
          
          if (extension) {
            fileTypes[extension] = (fileTypes[extension] || 0) + 1;
          }
        });
        
        // 计算文档块数量 - 使用status中的信息或估算
        const totalChunks = statusData.summary?.totalDocumentsIndexed || documents.length * 5; // 假设每个文档平均5个块
        
        const stats: KnowledgeBaseStats = {
          total_chunks: totalChunks,
          unique_documents: documents.length,
          collection_name: statusData.knowledgeBase?.name || 'enterprise-knowledge-base',
          file_types: fileTypes
        };
        
        setKbStats(stats);
      }
    } catch (error) {
      console.error('Failed to fetch KB stats:', error);
      // 如果API调用失败，设置空统计
      setKbStats({
        total_chunks: 0,
        unique_documents: 0,
        collection_name: 'enterprise-knowledge-base',
        file_types: {}
      });
    }
  };

  useEffect(() => {
    refreshSystemHealth();
    refreshKbStats();
  }, []);

  const getHealthIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircleIcon color="success" fontSize="small" />;
      case 'degraded':
        return <WarningIcon color="warning" fontSize="small" />;
      case 'error':
        return <ErrorIcon color="error" fontSize="small" />;
      default:
        return <CircularProgress size={16} />;
    }
  };

  const getHealthColor = (status: string) => {
    switch (status) {
      case 'healthy': return 'success';
      case 'degraded': return 'warning';
      case 'error': return 'error';
      default: return 'default';
    }
  };

  const drawer = (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      {/* Header */}
      <Box sx={{ 
        p: 3, 
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        color: 'white',
        textAlign: 'center'
      }}>
        <Typography variant="h6" sx={{ fontWeight: 600, mb: 1 }}>
          🧠 企业RAG系统
        </Typography>
        <Typography variant="body2" sx={{ opacity: 0.9 }}>
          基于AWS Bedrock的智能知识问答
        </Typography>
      </Box>

      <Divider />

      {/* Navigation */}
      <List sx={{ py: 2 }}>
        {menuItems.map((item) => (
          <ListItemButton
            key={item.path}
            selected={location.pathname === item.path}
            onClick={() => navigate(item.path)}
            sx={{
              mx: 1,
              borderRadius: 2,
              mb: 0.5,
              '&.Mui-selected': {
                backgroundColor: 'primary.light',
                color: 'primary.contrastText',
                '& .MuiListItemIcon-root': {
                  color: 'primary.contrastText',
                },
              },
            }}
          >
            <ListItemIcon>{item.icon}</ListItemIcon>
            <ListItemText primary={item.text} />
          </ListItemButton>
        ))}
      </List>

      <Divider />

      {/* System Status */}
      <Box sx={{ p: 2, flex: 1 }}>
        <Box display="flex" alignItems="center" justifyContent="space-between" mb={2}>
          <Typography variant="subtitle2" color="text.primary">
            🔧 系统状态
          </Typography>
          <IconButton size="small" onClick={refreshSystemHealth} disabled={loading}>
            <RefreshIcon fontSize="small" />
          </IconButton>
        </Box>

        {systemHealth && (
          <Card variant="outlined" sx={{ mb: 2 }}>
            <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
              <Box display="flex" alignItems="center" gap={1} mb={2}>
                {getHealthIcon(systemHealth.overall)}
                <Typography variant="body2" fontWeight={500}>
                  {systemHealth.overall === 'healthy' ? '🟢 系统正常' : 
                   systemHealth.overall === 'degraded' ? '🟡 部分异常' : '🔴 系统异常'}
                </Typography>
              </Box>
              
              <Accordion>
                <AccordionSummary
                  expandIcon={<ExpandMoreIcon />}
                  sx={{ minHeight: 'auto', '& .MuiAccordionSummary-content': { margin: '8px 0' } }}
                >
                  <Typography variant="caption">组件详情</Typography>
                </AccordionSummary>
                <AccordionDetails sx={{ pt: 0 }}>
                  {Object.entries(systemHealth.components).map(([name, status]) => (
                    <Box key={name} display="flex" alignItems="center" gap={1} mb={1}>
                      {getHealthIcon(status.status)}
                      <Typography variant="caption" sx={{ fontSize: 11 }}>
                        {name}: {status.status === 'healthy' ? '正常' : status.error || '异常'}
                      </Typography>
                    </Box>
                  ))}
                </AccordionDetails>
              </Accordion>
            </CardContent>
          </Card>
        )}

        {/* Knowledge Base Stats */}
        <Box display="flex" alignItems="center" justifyContent="space-between" mb={2}>
          <Typography variant="subtitle2" color="text.primary">
            📊 知识库统计
          </Typography>
          <IconButton size="small" onClick={refreshKbStats}>
            <RefreshIcon fontSize="small" />
          </IconButton>
        </Box>

        {kbStats && (
          <Card variant="outlined" sx={{ mb: 2 }}>
            <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
              <Box display="flex" alignItems="center" gap={1} mb={1}>
                <StorageIcon fontSize="small" color="primary" />
                <Typography variant="body2">{kbStats.unique_documents} 个文档</Typography>
              </Box>
              <Box display="flex" alignItems="center" gap={1} mb={1}>
                <AnalyticsIcon fontSize="small" color="secondary" />
                <Typography variant="body2">{kbStats.total_chunks} 个文档块</Typography>
              </Box>
              
              <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                文件类型分布:
              </Typography>
              <Box display="flex" flexWrap="wrap" gap={0.5} mt={1}>
                {Object.entries(kbStats.file_types).map(([type, count]) => (
                  <Chip
                    key={type}
                    label={`${type.toUpperCase()}: ${count}`}
                    size="small"
                    variant="outlined"
                    sx={{ fontSize: 10, height: 20 }}
                  />
                ))}
              </Box>
            </CardContent>
          </Card>
        )}
      </Box>

      <Divider />

      {/* User Info */}
      <Box sx={{ p: 2 }}>
        <Box display="flex" alignItems="center" gap={2} mb={2}>
          <Avatar sx={{ width: 32, height: 32, bgcolor: 'primary.main' }}>
            {user.name?.charAt(0).toUpperCase() || user.email?.charAt(0).toUpperCase()}
          </Avatar>
          <Box flex={1} minWidth={0}>
            <Typography variant="body2" fontWeight={500} noWrap>
              {user.name || user.email}
            </Typography>
            <Typography variant="caption" color="text.secondary" noWrap>
              {user.email}
            </Typography>
          </Box>
        </Box>
        <Button
          fullWidth
          variant="outlined"
          startIcon={<LogoutIcon />}
          onClick={onLogout}
          size="small"
        >
          登出
        </Button>
      </Box>
    </Box>
  );

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <AppBar
        position="fixed"
        sx={{
          width: { md: `calc(100% - ${drawerWidth}px)` },
          ml: { md: `${drawerWidth}px` },
          display: { md: 'none' },
        }}
      >
        <Toolbar>
          <IconButton
            color="inherit"
            aria-label="open drawer"
            edge="start"
            onClick={handleDrawerToggle}
            sx={{ mr: 2, display: { md: 'none' } }}
          >
            <MenuIcon />
          </IconButton>
          <Typography variant="h6" noWrap component="div">
            企业RAG知识问答系统
          </Typography>
        </Toolbar>
      </AppBar>

      <Box
        component="nav"
        sx={{ width: { md: drawerWidth }, flexShrink: { md: 0 } }}
      >
        <Drawer
          variant="temporary"
          open={mobileOpen}
          onClose={handleDrawerToggle}
          ModalProps={{
            keepMounted: true,
          }}
          sx={{
            display: { xs: 'block', md: 'none' },
            '& .MuiDrawer-paper': { boxSizing: 'border-box', width: drawerWidth },
          }}
        >
          {drawer}
        </Drawer>
        <Drawer
          variant="permanent"
          sx={{
            display: { xs: 'none', md: 'block' },
            '& .MuiDrawer-paper': { 
              boxSizing: 'border-box', 
              width: drawerWidth,
              borderRight: '1px solid rgba(0, 0, 0, 0.08)',
            },
          }}
          open
        >
          {drawer}
        </Drawer>
      </Box>

      <Box
        component="main"
        sx={{
          flexGrow: 1,
          width: { md: `calc(100% - ${drawerWidth}px)` },
          minHeight: '100vh',
          bgcolor: 'background.default',
          pt: { xs: 8, md: 0 },
        }}
      >
        {children}
      </Box>
    </Box>
  );
};

export default MainLayout;