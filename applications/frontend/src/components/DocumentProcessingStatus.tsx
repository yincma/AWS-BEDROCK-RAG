import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  LinearProgress,
  Chip,
  IconButton,
  Collapse,
  Alert,
  Button,
  List,
  ListItem,
  ListItemText,
  Divider,
  CircularProgress
} from '@mui/material';
import {
  ExpandMore as ExpandMoreIcon,
  ExpandLess as ExpandLessIcon,
  Refresh as RefreshIcon,
  CheckCircle as CheckIcon,
  Error as ErrorIcon,
  HourglassEmpty as ProcessingIcon,
  CloudSync as SyncIcon
} from '@mui/icons-material';
import { apiService } from '../services';

interface ProcessingStatusProps {
  onStatusChange?: (ready: boolean) => void;
  autoRefresh?: boolean;
  refreshInterval?: number;
}

interface KnowledgeBaseStatus {
  knowledgeBase: {
    id: string;
    name: string;
    status: string;
    dataSourceId: string;
  };
  systemReady: boolean;
  readyMessage: string;
  ingestionJobs: Array<{
    id: string;
    status: string;
    startedAt: string;
    completedAt?: string;
    documentsScanned: number;
    documentsFailed: number;
    documentsIndexed: number;
  }>;
  summary: {
    latestJobStatus: string;
    documentsProcessed: number;
    totalJobs: number;
  };
}

const DocumentProcessingStatus: React.FC<ProcessingStatusProps> = ({
  onStatusChange,
  autoRefresh = true,
  refreshInterval = 5000
}) => {
  const [status, setStatus] = useState<KnowledgeBaseStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchStatus = async () => {
    try {
      setRefreshing(true);
      const response = await apiService.getKnowledgeBaseStatus();
      
      if (response.success && response.data) {
        setStatus(response.data);
        setError(null);
        
        // Notify parent component about status change
        if (onStatusChange) {
          onStatusChange(response.data.systemReady);
        }
      } else {
        throw new Error(response.error?.message || '获取状态失败');
      }
    } catch (err: any) {
      setError(err.message || '无法获取处理状态');
      console.error('Failed to fetch status:', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    // Initial fetch
    fetchStatus();

    // Set up auto refresh
    if (autoRefresh && !status?.systemReady) {
      const interval = setInterval(fetchStatus, refreshInterval);
      return () => clearInterval(interval);
    }
  }, [autoRefresh, refreshInterval, status?.systemReady]);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'COMPLETE':
        return <CheckIcon color="success" />;
      case 'IN_PROGRESS':
        return <ProcessingIcon color="warning" />;
      case 'FAILED':
        return <ErrorIcon color="error" />;
      default:
        return <SyncIcon color="disabled" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'COMPLETE':
        return 'success';
      case 'IN_PROGRESS':
        return 'warning';
      case 'FAILED':
        return 'error';
      default:
        return 'default';
    }
  };

  const getAlertSeverity = (ready: boolean, latestStatus?: string) => {
    if (ready) return 'success';
    if (latestStatus === 'FAILED') return 'error';
    if (latestStatus === 'IN_PROGRESS') return 'info';
    return 'warning';
  };

  if (loading && !status) {
    return (
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Box display="flex" alignItems="center" justifyContent="center" py={2}>
            <CircularProgress size={24} sx={{ mr: 2 }} />
            <Typography>加载处理状态...</Typography>
          </Box>
        </CardContent>
      </Card>
    );
  }

  if (error && !status) {
    return (
      <Alert severity="error" sx={{ mb: 3 }}>
        {error}
        <Button onClick={fetchStatus} size="small" sx={{ ml: 2 }}>
          重试
        </Button>
      </Alert>
    );
  }

  if (!status) return null;

  return (
    <Card sx={{ mb: 3 }}>
      <CardContent>
        <Box display="flex" alignItems="center" justifyContent="space-between" mb={2}>
          <Box display="flex" alignItems="center">
            <Typography variant="h6" component="div">
              文档处理状态
            </Typography>
            {refreshing && <CircularProgress size={20} sx={{ ml: 2 }} />}
          </Box>
          <Box>
            <IconButton onClick={fetchStatus} disabled={refreshing} size="small">
              <RefreshIcon />
            </IconButton>
            <IconButton onClick={() => setExpanded(!expanded)} size="small">
              {expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
            </IconButton>
          </Box>
        </Box>

        {/* Main Status Alert */}
        <Alert 
          severity={getAlertSeverity(status.systemReady, status.summary.latestJobStatus)}
          sx={{ mb: 2 }}
          icon={getStatusIcon(status.summary.latestJobStatus || 'UNKNOWN')}
        >
          <Typography variant="body1" fontWeight="medium">
            {status.readyMessage}
          </Typography>
        </Alert>

        {/* Progress Bar for Active Processing */}
        {status.summary.latestJobStatus === 'IN_PROGRESS' && (
          <Box sx={{ mb: 2 }}>
            <LinearProgress variant="indeterminate" />
            <Typography variant="caption" color="text.secondary" sx={{ mt: 1 }}>
              正在处理文档，请稍候...
            </Typography>
          </Box>
        )}

        {/* Summary Stats */}
        <Box display="flex" gap={2} mb={2}>
          <Chip 
            label={`Knowledge Base: ${status.knowledgeBase.status}`}
            color={status.knowledgeBase.status === 'ACTIVE' ? 'success' : 'warning'}
            size="small"
          />
          <Chip 
            label={`已处理文档: ${status.summary.documentsProcessed}`}
            size="small"
          />
          <Chip 
            label={`总任务数: ${status.summary.totalJobs}`}
            size="small"
          />
        </Box>

        {/* Expandable Details */}
        <Collapse in={expanded}>
          <Divider sx={{ my: 2 }} />
          
          <Typography variant="subtitle2" gutterBottom>
            最近的处理任务
          </Typography>
          
          <List dense>
            {status.ingestionJobs.slice(0, 3).map((job, index) => (
              <ListItem key={job.id} disableGutters>
                <ListItemText
                  primary={
                    <Box display="flex" alignItems="center" gap={1}>
                      {getStatusIcon(job.status)}
                      <Typography variant="body2">
                        任务 {job.id.slice(-8)}
                      </Typography>
                      <Chip 
                        label={job.status} 
                        size="small" 
                        color={getStatusColor(job.status) as any}
                      />
                    </Box>
                  }
                  secondary={
                    <Typography variant="caption" color="text.secondary">
                      扫描: {job.documentsScanned} | 
                      索引: {job.documentsIndexed} | 
                      失败: {job.documentsFailed} | 
                      开始时间: {new Date(job.startedAt).toLocaleTimeString()}
                    </Typography>
                  }
                />
              </ListItem>
            ))}
          </List>

          {status.ingestionJobs.length === 0 && (
            <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
              暂无处理任务记录
            </Typography>
          )}
        </Collapse>
      </CardContent>
    </Card>
  );
};

export default DocumentProcessingStatus;