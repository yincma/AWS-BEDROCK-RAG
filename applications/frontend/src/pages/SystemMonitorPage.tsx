import React, { useState, useEffect } from 'react';
import {
  Container,
  Paper,
  Typography,
  Box,
  Grid,
  Card,
  CardContent,
  Button,
  LinearProgress,
  Chip,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Alert,
  CircularProgress,
  Divider,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
} from '@mui/material';
import {
  Refresh as RefreshIcon,
  Memory as MemoryIcon,
  Storage as StorageIcon,
  Speed as SpeedIcon,
  Cloud as CloudIcon,
  DataUsage as DataIcon,
  Timeline as TimelineIcon,
  CheckCircle as CheckCircleIcon,
  Warning as WarningIcon,
  Error as ErrorIcon,
  Computer as ComputerIcon,
  Api as ApiIcon,
  Psychology as PsychologyIcon,
  Folder as FolderIcon,
} from '@mui/icons-material';
import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, AreaChart, Area } from 'recharts';

interface SystemMetrics {
  cpu_percent: number;
  memory_percent: number;
  memory_available: number;
  disk_usage: {
    percent: number;
    free: number;
    total: number;
  };
  timestamp: string;
}

interface ComponentStatus {
  name: string;
  status: 'healthy' | 'warning' | 'error';
  description: string;
  response_time?: number;
  last_check: string;
}

interface PerformanceData {
  timestamp: string;
  response_time: number;
  throughput: number;
  error_rate: number;
}

const SystemMonitorPage: React.FC = () => {
  const [systemMetrics, setSystemMetrics] = useState<SystemMetrics | null>(null);
  const [components, setComponents] = useState<ComponentStatus[]>([]);
  const [performanceData, setPerformanceData] = useState<PerformanceData[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchSystemMetrics = async () => {
    try {
      // Mock system metrics - replace with actual API call
      const mockMetrics: SystemMetrics = {
        cpu_percent: Math.random() * 100,
        memory_percent: 65.4 + Math.random() * 10,
        memory_available: 15.2,
        disk_usage: {
          percent: 42.8,
          free: 850.5,
          total: 1500.0
        },
        timestamp: new Date().toISOString()
      };
      setSystemMetrics(mockMetrics);
    } catch (error) {
      console.error('Failed to fetch system metrics:', error);
    }
  };

  const fetchComponentStatus = async () => {
    try {
      // Mock component status - replace with actual API calls
      const mockComponents: ComponentStatus[] = [
        {
          name: 'API Gateway',
          status: 'healthy',
          description: 'AWS API Gateway 运行正常',
          response_time: 45,
          last_check: new Date().toISOString()
        },
        {
          name: 'Lambda Functions',
          status: 'healthy',
          description: '查询处理函数运行正常',
          response_time: 230,
          last_check: new Date().toISOString()
        },
        {
          name: 'Amazon Bedrock',
          status: 'healthy',
          description: 'Amazon Nova 模型服务正常',
          response_time: 850,
          last_check: new Date().toISOString()
        },
        {
          name: 'Document Store',
          status: 'healthy',
          description: 'S3 文档存储正常',
          response_time: 35,
          last_check: new Date().toISOString()
        },
        {
          name: 'Vector Database',
          status: 'warning',
          description: 'OpenSearch 负载较高',
          response_time: 450,
          last_check: new Date().toISOString()
        },
        {
          name: 'Authentication',
          status: 'healthy',
          description: 'Cognito 用户认证正常',
          response_time: 120,
          last_check: new Date().toISOString()
        }
      ];
      setComponents(mockComponents);
    } catch (error) {
      console.error('Failed to fetch component status:', error);
    }
  };

  const fetchPerformanceData = async () => {
    try {
      // Mock performance data - replace with actual metrics
      const mockData: PerformanceData[] = Array.from({ length: 24 }, (_, i) => ({
        timestamp: new Date(Date.now() - (23 - i) * 3600000).toISOString(),
        response_time: 200 + Math.random() * 300,
        throughput: 10 + Math.random() * 20,
        error_rate: Math.random() * 2
      }));
      setPerformanceData(mockData);
    } catch (error) {
      console.error('Failed to fetch performance data:', error);
    }
  };

  const refreshAllData = async () => {
    setLoading(true);
    setError(null);
    try {
      await Promise.all([
        fetchSystemMetrics(),
        fetchComponentStatus(),
        fetchPerformanceData()
      ]);
    } catch (error: any) {
      setError('刷新监控数据失败: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refreshAllData();
  }, []);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircleIcon color="success" fontSize="small" />;
      case 'warning':
        return <WarningIcon color="warning" fontSize="small" />;
      case 'error':
        return <ErrorIcon color="error" fontSize="small" />;
      default:
        return <CircularProgress size={16} />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy': return 'success';
      case 'warning': return 'warning';
      case 'error': return 'error';
      default: return 'default';
    }
  };

  const formatBytes = (bytes: number): string => {
    if (bytes === 0) return '0 GB';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  return (
    <Container maxWidth="xl" sx={{ py: 3 }}>
      {/* Header */}
      <Box sx={{ 
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        color: 'white',
        borderRadius: 3,
        p: 4,
        mb: 3,
        textAlign: 'center'
      }}>
        <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
          📈 系统监控
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          实时监控系统性能和组件状态
        </Typography>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {/* Actions */}
      <Box display="flex" justifyContent="flex-end" mb={3}>
        <Button
          variant="contained"
          startIcon={loading ? <CircularProgress size={16} /> : <RefreshIcon />}
          onClick={refreshAllData}
          disabled={loading}
        >
          刷新数据
        </Button>
      </Box>

      <Grid container spacing={3}>
        {/* System Resources */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <ComputerIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">💻 系统资源</Typography>
              </Box>
              
              {systemMetrics ? (
                <Box>
                  {/* CPU */}
                  <Box mb={3}>
                    <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
                      <Typography variant="body2" color="text.secondary">CPU 使用率</Typography>
                      <Typography variant="body2" fontWeight={500}>
                        {systemMetrics.cpu_percent.toFixed(1)}%
                      </Typography>
                    </Box>
                    <LinearProgress 
                      variant="determinate" 
                      value={systemMetrics.cpu_percent} 
                      sx={{ height: 8, borderRadius: 4 }}
                      color={systemMetrics.cpu_percent > 80 ? 'error' : systemMetrics.cpu_percent > 60 ? 'warning' : 'primary'}
                    />
                  </Box>

                  {/* Memory */}
                  <Box mb={3}>
                    <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
                      <Typography variant="body2" color="text.secondary">内存使用率</Typography>
                      <Typography variant="body2" fontWeight={500}>
                        {systemMetrics.memory_percent.toFixed(1)}% (可用: {systemMetrics.memory_available.toFixed(1)} GB)
                      </Typography>
                    </Box>
                    <LinearProgress 
                      variant="determinate" 
                      value={systemMetrics.memory_percent} 
                      sx={{ height: 8, borderRadius: 4 }}
                      color={systemMetrics.memory_percent > 80 ? 'error' : systemMetrics.memory_percent > 60 ? 'warning' : 'primary'}
                    />
                  </Box>

                  {/* Disk */}
                  <Box>
                    <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
                      <Typography variant="body2" color="text.secondary">磁盘使用率</Typography>
                      <Typography variant="body2" fontWeight={500}>
                        {systemMetrics.disk_usage.percent.toFixed(1)}% (可用: {formatBytes(systemMetrics.disk_usage.free * 1024 * 1024 * 1024)})
                      </Typography>
                    </Box>
                    <LinearProgress 
                      variant="determinate" 
                      value={systemMetrics.disk_usage.percent} 
                      sx={{ height: 8, borderRadius: 4 }}
                      color={systemMetrics.disk_usage.percent > 80 ? 'error' : systemMetrics.disk_usage.percent > 60 ? 'warning' : 'primary'}
                    />
                  </Box>
                </Box>
              ) : (
                <Box display="flex" justifyContent="center" py={4}>
                  <CircularProgress />
                </Box>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Component Status */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <ApiIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">🔧 组件状态</Typography>
              </Box>
              
              <List dense>
                {components.map((component, index) => (
                  <ListItem key={index} divider={index < components.length - 1}>
                    <ListItemIcon>
                      {getStatusIcon(component.status)}
                    </ListItemIcon>
                    <ListItemText
                      primary={
                        <Box display="flex" alignItems="center" gap={1}>
                          <Typography variant="body2" fontWeight={500}>
                            {component.name}
                          </Typography>
                          <Chip
                            size="small"
                            label={component.status === 'healthy' ? '正常' : 
                                   component.status === 'warning' ? '警告' : '异常'}
                            color={getStatusColor(component.status) as any}
                            variant="outlined"
                          />
                        </Box>
                      }
                      secondary={
                        <Box>
                          <Typography variant="caption" color="text.secondary">
                            {component.description}
                          </Typography>
                          {component.response_time && (
                            <Typography variant="caption" color="text.secondary" display="block">
                              响应时间: {component.response_time}ms
                            </Typography>
                          )}
                        </Box>
                      }
                    />
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        </Grid>

        {/* Performance Charts */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                📊 性能趋势（24小时）
              </Typography>
              
              <Grid container spacing={3}>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>响应时间 (ms)</Typography>
                  <ResponsiveContainer width="100%" height={200}>
                    <AreaChart data={performanceData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis 
                        dataKey="timestamp" 
                        tickFormatter={(value) => new Date(value).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}
                      />
                      <YAxis />
                      <Tooltip 
                        labelFormatter={(value) => new Date(value).toLocaleString('zh-CN')}
                        formatter={(value: number) => [`${value.toFixed(0)}ms`, '响应时间']}
                      />
                      <Area type="monotone" dataKey="response_time" stroke="#667eea" fill="#667eea" fillOpacity={0.3} />
                    </AreaChart>
                  </ResponsiveContainer>
                </Grid>
                
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>吞吐量 (请求/分钟)</Typography>
                  <ResponsiveContainer width="100%" height={200}>
                    <LineChart data={performanceData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis 
                        dataKey="timestamp" 
                        tickFormatter={(value) => new Date(value).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}
                      />
                      <YAxis />
                      <Tooltip 
                        labelFormatter={(value) => new Date(value).toLocaleString('zh-CN')}
                        formatter={(value: number) => [`${value.toFixed(1)}`, '请求/分钟']}
                      />
                      <Line type="monotone" dataKey="throughput" stroke="#764ba2" strokeWidth={2} />
                    </LineChart>
                  </ResponsiveContainer>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Grid>

        {/* System Configuration */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <PsychologyIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">⚙️ 系统配置</Typography>
              </Box>
              
              <Grid container spacing={3}>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>模型配置</Typography>
                  <Table size="small">
                    <TableBody>
                      <TableRow>
                        <TableCell>LLM 模型</TableCell>
                        <TableCell>Amazon Nova Pro</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>嵌入模型</TableCell>
                        <TableCell>Amazon Titan Embeddings</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>向量数据库</TableCell>
                        <TableCell>Amazon OpenSearch</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>文档存储</TableCell>
                        <TableCell>Amazon S3</TableCell>
                      </TableRow>
                    </TableBody>
                  </Table>
                </Grid>
                
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>运行时配置</Typography>
                  <Table size="small">
                    <TableBody>
                      <TableRow>
                        <TableCell>AWS 区域</TableCell>
                        <TableCell>us-east-1</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Lambda 内存</TableCell>
                        <TableCell>1024 MB</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>超时时间</TableCell>
                        <TableCell>30s</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>并发限制</TableCell>
                        <TableCell>100</TableCell>
                      </TableRow>
                    </TableBody>
                  </Table>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Container>
  );
};

export default SystemMonitorPage;