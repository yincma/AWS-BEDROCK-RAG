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
          description: 'AWS API Gateway running normally',
          response_time: 45,
          last_check: new Date().toISOString()
        },
        {
          name: 'Lambda Functions',
          status: 'healthy',
          description: 'Query handler function running normally',
          response_time: 230,
          last_check: new Date().toISOString()
        },
        {
          name: 'Amazon Bedrock',
          status: 'healthy',
          description: 'Amazon Nova model service normal',
          response_time: 850,
          last_check: new Date().toISOString()
        },
        {
          name: 'Document Store',
          status: 'healthy',
          description: 'S3 document storage normal',
          response_time: 35,
          last_check: new Date().toISOString()
        },
        {
          name: 'Vector Database',
          status: 'warning',
          description: 'OpenSearch load is high',
          response_time: 450,
          last_check: new Date().toISOString()
        },
        {
          name: 'Authentication',
          status: 'healthy',
          description: 'Cognito user authentication normal',
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
      setError('Failed to refresh monitoring data: ' + error.message);
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
          📈 System Monitoring
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          Real-time monitoring of system performance and component status
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
          Refresh Data
        </Button>
      </Box>

      <Grid container spacing={3}>
        {/* System Resources */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <ComputerIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">💻 System Resources</Typography>
              </Box>
              
              {systemMetrics ? (
                <Box>
                  {/* CPU */}
                  <Box mb={3}>
                    <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
                      <Typography variant="body2" color="text.secondary">CPU Usage</Typography>
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
                      <Typography variant="body2" color="text.secondary">Memory Usage</Typography>
                      <Typography variant="body2" fontWeight={500}>
                        {systemMetrics.memory_percent.toFixed(1)}% (Available: {systemMetrics.memory_available.toFixed(1)} GB)
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
                      <Typography variant="body2" color="text.secondary">Disk Usage</Typography>
                      <Typography variant="body2" fontWeight={500}>
                        {systemMetrics.disk_usage.percent.toFixed(1)}% (Available: {formatBytes(systemMetrics.disk_usage.free * 1024 * 1024 * 1024)})
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
                <Typography variant="h6">🔧 Component Status</Typography>
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
                            label={component.status === 'healthy' ? 'Normal' : 
                                   component.status === 'warning' ? 'Warning' : 'Error'}
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
                              Response time: {component.response_time}ms
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
                📊 Performance Trends (24 hours)
              </Typography>
              
              <Grid container spacing={3}>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>Response Time (ms)</Typography>
                  <ResponsiveContainer width="100%" height={200}>
                    <AreaChart data={performanceData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis 
                        dataKey="timestamp" 
                        tickFormatter={(value) => new Date(value).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
                      />
                      <YAxis />
                      <Tooltip 
                        labelFormatter={(value) => new Date(value).toLocaleString('en-US')}
                        formatter={(value: number) => [`${value.toFixed(0)}ms`, 'Response Time']}
                      />
                      <Area type="monotone" dataKey="response_time" stroke="#667eea" fill="#667eea" fillOpacity={0.3} />
                    </AreaChart>
                  </ResponsiveContainer>
                </Grid>
                
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>Throughput (requests/minute)</Typography>
                  <ResponsiveContainer width="100%" height={200}>
                    <LineChart data={performanceData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis 
                        dataKey="timestamp" 
                        tickFormatter={(value) => new Date(value).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
                      />
                      <YAxis />
                      <Tooltip 
                        labelFormatter={(value) => new Date(value).toLocaleString('en-US')}
                        formatter={(value: number) => [`${value.toFixed(1)}`, 'requests/minute']}
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
                <Typography variant="h6">⚙️ System Configuration</Typography>
              </Box>
              
              <Grid container spacing={3}>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>Model Configuration</Typography>
                  <Table size="small">
                    <TableBody>
                      <TableRow>
                        <TableCell>LLM Model</TableCell>
                        <TableCell>Amazon Nova Pro</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Embedding Model</TableCell>
                        <TableCell>Amazon Titan Embeddings</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Vector Database</TableCell>
                        <TableCell>Amazon OpenSearch</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Document Storage</TableCell>
                        <TableCell>Amazon S3</TableCell>
                      </TableRow>
                    </TableBody>
                  </Table>
                </Grid>
                
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" gutterBottom>Runtime Configuration</Typography>
                  <Table size="small">
                    <TableBody>
                      <TableRow>
                        <TableCell>AWS Region</TableCell>
                        <TableCell>us-east-1</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Lambda Memory</TableCell>
                        <TableCell>1024 MB</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Timeout</TableCell>
                        <TableCell>30s</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>Concurrency Limit</TableCell>
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