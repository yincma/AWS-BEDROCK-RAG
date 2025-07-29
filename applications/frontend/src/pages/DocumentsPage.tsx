import React, { useState, useEffect, useCallback } from 'react';
import {
  Container,
  Paper,
  Typography,
  Box,
  Button,
  List,
  ListItem,
  ListItemText,
  ListItemSecondaryAction,
  IconButton,
  Chip,
  Alert,
  LinearProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Fab,
  CircularProgress
} from '@mui/material';
import {
  CloudUpload as UploadIcon,
  Delete as DeleteIcon,
  Refresh as RefreshIcon,
  Description as DocumentIcon,
  Add as AddIcon,
  CheckCircle as SuccessIcon,
  Error as ErrorIcon
} from '@mui/icons-material';
import { useDropzone } from 'react-dropzone';
import { Document, DocumentUpload } from '../types';
import { apiService, errorService } from '../services';
import { v4 as uuidv4 } from 'uuid';
import DocumentProcessingStatus from '../components/DocumentProcessingStatus';

const DocumentsPage: React.FC = () => {
  const [documents, setDocuments] = useState<Document[]>([]);
  const [uploads, setUploads] = useState<DocumentUpload[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadDialogOpen, setUploadDialogOpen] = useState(false);
  const [systemReady, setSystemReady] = useState(false);

  useEffect(() => {
    fetchDocuments();
  }, []);

  const fetchDocuments = async (retries = 3) => {
    try {
      setLoading(true);
      let lastError: any = null;
      
      // 重试逻辑
      for (let attempt = 0; attempt < retries; attempt++) {
        try {
          console.log(`[DocumentsPage] Attempt ${attempt + 1}/${retries} - Calling apiService.getDocuments()`);
          const response = await apiService.getDocuments();
          
          // 调试日志 - 更详细
          console.log('[DocumentsPage] Full API Response:', response);
          console.log('[DocumentsPage] Response details:', {
            hasResponse: !!response,
            responseType: typeof response,
            success: response?.success,
            hasData: !!response?.data,
            dataType: typeof response?.data,
            dataIsArray: Array.isArray(response?.data),
            dataLength: response?.data?.length,
            firstItem: response?.data?.[0],
            hasError: !!response?.error,
            errorMessage: response?.error?.message
          });
          
          if (response && response.success && response.data !== undefined) {
            // 确保 response.data 是数组
            const documentsArray = Array.isArray(response.data) ? response.data : [];
            console.log(`[DocumentsPage] Setting ${documentsArray.length} documents to state`);
            setDocuments(documentsArray);
            console.log('[DocumentsPage] Documents successfully set to state');
            return; // 成功获取，退出函数
          } else {
            const errorMsg = response?.error?.message || 'Unknown error - response.success is false or data is undefined';
            console.error('[DocumentsPage] API call failed:', errorMsg);
            throw new Error(errorMsg);
          }
        } catch (error: any) {
          lastError = error;
          
          // 如果不是最后一次尝试，等待后重试
          if (attempt < retries - 1) {
            console.log(`Failed to get document list, retrying in ${1} second... (attempt ${attempt + 1}/${retries})`);
            await new Promise(resolve => setTimeout(resolve, 1000));
          }
        }
      }
      
      // All retries failed
      throw lastError || new Error('Failed to get document list');
      
    } catch (error: any) {
      // If API fails, show empty state (this is expected for new deployments)
      console.warn('Failed to fetch documents after retries:', error);
      setDocuments([]);
      
      // Only show error if it's not a 'not implemented' or network error
      if (!error.message?.includes('404') && !error.message?.includes('not found')) {
        errorService.handleError(
          error,
          'document-fetch',
          { 
            showNotification: false, // Don't show notification for initial load failure
            userMessage: 'Unable to load document list'
          }
        );
      }
    } finally {
      setLoading(false);
    }
  };

  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const getFileTypeIcon = (type: string) => {
    if (type.includes('pdf')) return '📄';
    if (type.includes('word') || type.includes('docx')) return '📝';
    if (type.includes('text')) return '📄';
    if (type.includes('csv')) return '📊';
    return '📄';
  };

  const onDrop = useCallback((acceptedFiles: File[]) => {
    acceptedFiles.forEach((file) => {
      const upload: DocumentUpload = {
        file,
        id: uuidv4(),
        name: file.name,
        size: file.size,
        type: file.type,
        status: 'pending',
        progress: 0
      };
      
      setUploads(prev => Array.isArray(prev) ? [...prev, upload] : [upload]);
      uploadDocument(upload);
    });
    setUploadDialogOpen(false);
  }, []);

  const uploadDocument = async (upload: DocumentUpload) => {
    try {
      // Update status to uploading
      setUploads(prev => Array.isArray(prev) ? prev.map(u => 
        u.id === upload.id ? { ...u, status: 'uploading' as const } : u
      ) : []);

      // Call upload API with progress tracking
      const response = await apiService.uploadDocument(
        upload.file,
        (progress: number) => {
          setUploads(prev => Array.isArray(prev) ? prev.map(u => 
            u.id === upload.id ? { ...u, progress } : u
          ) : []);
        }
      );

      if (response.success && response.data) {
        // Update upload status to completed
        setUploads(prev => Array.isArray(prev) ? prev.map(u => 
          u.id === upload.id ? { ...u, status: 'completed' as const, progress: 100 } : u
        ) : []);

        // Show success notification
        errorService.showSuccessNotification(
          'Upload Successful',
          `Document "${upload.name}" uploaded successfully, syncing document list...`
        );

        // Wait for S3 eventual consistency, then refresh document list
        setTimeout(async () => {
          try {
            // Re-fetch document list from server
            await fetchDocuments();
            
            // Confirm documents have been synced
            errorService.showInfoNotification(
              'Sync Complete',
              'Document list has been updated'
            );
          } catch (error) {
            console.error('Failed to refresh document list:', error);
            // If first attempt fails, try again
            setTimeout(() => {
              fetchDocuments();
            }, 2000);
          }
        }, 1500); // Wait 1.5 seconds to ensure S3 sync

        // Remove from uploads after a short delay
        setTimeout(() => {
          setUploads(prev => Array.isArray(prev) ? prev.filter(u => u.id !== upload.id) : []);
        }, 3000);

      } else {
        throw new Error(response.error?.message || 'Upload failed');
      }
    } catch (error: any) {
      // Update upload status to error
      setUploads(prev => Array.isArray(prev) ? prev.map(u => 
        u.id === upload.id ? { 
          ...u, 
          status: 'error' as const, 
          error: error.message || 'Upload failed'
        } : u
      ) : []);

      errorService.handleError(
        error,
        'document-upload',
        { 
          showNotification: true,
          userMessage: `Document "${upload.name}" upload failed`
        }
      );
    }
  };

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'application/pdf': ['.pdf'],
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ['.docx'],
      'text/plain': ['.txt'],
      'text/markdown': ['.md'],
      'text/csv': ['.csv'],
      'application/json': ['.json']
    },
    maxSize: 100 * 1024 * 1024,
    multiple: true
  });

  const handleDeleteDocument = async (documentId: string) => {
    try {
      const document = documents.find(doc => doc.id === documentId);
      if (!document) return;

      const response = await apiService.deleteDocument(documentId);
      
      if (response.success) {
        setDocuments(prev => Array.isArray(prev) ? prev.filter(doc => doc.id !== documentId) : []);
        
        errorService.showSuccessNotification(
          'Delete Successful',
          `Document "${document.name}" has been deleted`
        );
      } else {
        throw new Error(response.error?.message || 'Delete failed');
      }
    } catch (error: any) {
      errorService.handleError(
        error,
        'document-delete',
        { 
          showNotification: true,
          userMessage: 'Failed to delete document'
        }
      );
    }
  };

  const handleRefresh = async () => {
    try {
      errorService.showInfoNotification(
        'Refreshing',
        'Getting the latest document list...'
      );
      await fetchDocuments();
      errorService.showSuccessNotification(
        'Refresh Successful',
        'Document list has been updated'
      );
    } catch (error) {
      console.error('Failed to refresh document list:', error);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'success';
      case 'processing': return 'warning';
      case 'error': return 'error';
      default: return 'default';
    }
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
          📚 文档管理
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          上传和管理您的知识库文档
        </Typography>
      </Box>

      {/* Document Processing Status Card */}
      <DocumentProcessingStatus 
        onStatusChange={setSystemReady}
        autoRefresh={true}
        refreshInterval={5000}
      />
      
      <Paper elevation={3} sx={{ p: 4, borderRadius: 3, mt: 3 }}>
        <Box display="flex" justifyContent="space-between" alignItems="center" mb={4}>
          <Box>
            <Typography variant="h5" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
              📄 文档库管理
            </Typography>
            <Typography variant="body1" color="text.secondary">
              上传、查看和管理您的知识库文档
            </Typography>
          </Box>
          <Box display="flex" gap={2}>
            <Button
              variant="outlined"
              startIcon={<RefreshIcon />}
              onClick={handleRefresh}
              disabled={loading}
              sx={{ 
                borderRadius: 2,
                borderColor: 'primary.main',
                color: 'primary.main',
                '&:hover': {
                  borderColor: 'primary.dark',
                  bgcolor: 'primary.light',
                  color: 'white'
                }
              }}
            >
              🔄 刷新
            </Button>
            <Button
              variant="contained"
              startIcon={<UploadIcon />}
              onClick={() => setUploadDialogOpen(true)}
              sx={{ 
                borderRadius: 2,
                boxShadow: '0 4px 12px rgba(102, 126, 234, 0.3)',
                '&:hover': {
                  boxShadow: '0 6px 16px rgba(102, 126, 234, 0.4)',
                }
              }}
            >
              📁 上传文档
            </Button>
          </Box>
        </Box>

        {error && (
          <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>
            {error}
          </Alert>
        )}

        {loading && <LinearProgress sx={{ mb: 3 }} />}

        {uploads.length > 0 && (
          <Box mb={4}>
            <Typography variant="h6" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
              ⏳ 正在上传的文档
            </Typography>
            <Paper elevation={1} sx={{ p: 2, borderRadius: 2, bgcolor: '#f8f9fa' }}>
              <List>
                {uploads.map((upload) => (
                  <ListItem 
                    key={upload.id}
                    sx={{ 
                      bgcolor: 'white', 
                      borderRadius: 2, 
                      mb: 1, 
                      border: '1px solid #e0e0e0'
                    }}
                  >
                    <Box sx={{ mr: 2, fontSize: '24px' }}>
                      {getFileTypeIcon(upload.type)}
                    </Box>
                    <ListItemText
                      primary={
                        <Typography variant="subtitle1" fontWeight={500}>
                          {upload.name}
                        </Typography>
                      }
                      secondary={
                        <Box>
                          <Box display="flex" alignItems="center" gap={1} mb={1}>
                            <Typography variant="body2" color="text.secondary">
                              {formatFileSize(upload.size)} • 
                            </Typography>
                            {upload.status === 'uploading' && (
                              <>
                                <CircularProgress size={16} />
                                <Typography variant="body2" color="primary" fontWeight={500}>
                                  上传中...
                                </Typography>
                              </>
                            )}
                            {upload.status === 'completed' && (
                              <>
                                <SuccessIcon color="success" fontSize="small" />
                                <Typography variant="body2" color="success.main" fontWeight={500}>
                                  上传完成
                                </Typography>
                              </>
                            )}
                            {upload.status === 'error' && (
                              <>
                                <ErrorIcon color="error" fontSize="small" />
                                <Typography variant="body2" color="error.main" fontWeight={500}>
                                  上传失败
                                </Typography>
                              </>
                            )}
                          </Box>
                          {upload.status === 'error' && upload.error && (
                            <Alert severity="error" sx={{ mt: 1 }}>
                              {upload.error}
                            </Alert>
                          )}
                          {(upload.status === 'uploading' || upload.status === 'processing') && (
                            <LinearProgress 
                              variant="determinate" 
                              value={upload.progress} 
                              sx={{ mt: 2, height: 6, borderRadius: 3 }}
                            />
                          )}
                        </Box>
                      }
                    />
                  </ListItem>
                ))}
              </List>
            </Paper>
          </Box>
        )}

        <Box>
          <Typography variant="h6" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
            📊 知识库文档 ({documents.length})
          </Typography>
          
          {documents.length === 0 ? (
            <Box
              sx={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                py: 8,
                bgcolor: '#fafbfc',
                borderRadius: 3,
                border: '2px dashed #e0e0e0'
              }}
            >
              <DocumentIcon sx={{ fontSize: 80, mb: 3, opacity: 0.6, color: 'primary.main' }} />
              <Typography variant="h5" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
                📚 暂无文档
              </Typography>
              <Typography variant="body1" textAlign="center" sx={{ maxWidth: 500, mb: 4, color: 'text.secondary' }}>
                您的知识库还是空的。上传您的第一个文档，开始构建智能知识问答系统。
              </Typography>
              <Button
                variant="contained"
                startIcon={<UploadIcon />}
                onClick={() => setUploadDialogOpen(true)}
                size="large"
                sx={{ 
                  borderRadius: 2,
                  px: 4,
                  py: 1.5,
                  fontSize: '1.1rem',
                  boxShadow: '0 4px 12px rgba(102, 126, 234, 0.3)',
                  '&:hover': {
                    boxShadow: '0 6px 16px rgba(102, 126, 234, 0.4)',
                  }
                }}
              >
                📁 上传第一个文档
              </Button>
            </Box>
          ) : (
            <Paper elevation={1} sx={{ borderRadius: 2, overflow: 'hidden' }}>
              <List>
                {Array.isArray(documents) && documents.map((document, index) => (
                  <ListItem 
                    key={document.id} 
                    divider={index < documents.length - 1}
                    sx={{ 
                      py: 2.5,
                      '&:hover': {
                        bgcolor: '#f8f9fa'
                      }
                    }}
                  >
                    <Box sx={{ mr: 3, fontSize: '32px' }}>
                      {getFileTypeIcon(document.type)}
                    </Box>
                    <ListItemText
                      primary={
                        <Box display="flex" alignItems="center" gap={2} mb={1}>
                          <Typography variant="subtitle1" fontWeight={600} sx={{ color: 'text.primary' }}>
                            {document.name}
                          </Typography>
                          <Chip 
                            size="small" 
                            label={document.status === 'active' ? '✅ 活跃' : 
                                   document.status === 'processing' ? '⚙️ 处理中' : '❌ 错误'} 
                            color={getStatusColor(document.status) as any}
                            variant="filled"
                            sx={{ fontWeight: 500 }}
                          />
                        </Box>
                      }
                      secondary={
                        <Box>
                          <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                            📏 {formatFileSize(document.size)} • 📅 上传于 {new Date(document.upload_date).toLocaleDateString('zh-CN')}
                          </Typography>
                          {document.metadata && (
                            <Box display="flex" gap={1} flexWrap="wrap">
                              {document.metadata?.pages && (
                                <Chip 
                                  size="small" 
                                  label={`📄 ${document.metadata.pages} 页`} 
                                  variant="outlined" 
                                  color="info"
                                />
                              )}
                              {document.metadata?.words && (
                                <Chip 
                                  size="small" 
                                  label={`📝 ${document.metadata.words} 字`} 
                                  variant="outlined" 
                                  color="info"
                                />
                              )}
                            </Box>
                          )}
                        </Box>
                      }
                    />
                    <ListItemSecondaryAction>
                      <IconButton 
                        edge="end" 
                        onClick={() => handleDeleteDocument(document.id)}
                        color="error"
                        sx={{
                          '&:hover': {
                            bgcolor: 'error.light',
                            color: 'white'
                          }
                        }}
                      >
                        <DeleteIcon />
                      </IconButton>
                    </ListItemSecondaryAction>
                  </ListItem>
                ))}
              </List>
            </Paper>
          )}
        </Box>
      </Paper>

      <Dialog 
        open={uploadDialogOpen} 
        onClose={() => setUploadDialogOpen(false)}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>上传文档</DialogTitle>
        <DialogContent>
          <Box
            {...getRootProps()}
            sx={{
              border: '2px dashed',
              borderColor: isDragActive ? 'primary.main' : 'grey.300',
              borderRadius: 2,
              p: 6,
              textAlign: 'center',
              cursor: 'pointer',
              bgcolor: isDragActive ? 'action.hover' : 'background.paper',
              transition: 'all 0.2s ease'
            }}
          >
            <input {...getInputProps()} />
            <UploadIcon sx={{ fontSize: 60, mb: 2, color: 'text.secondary' }} />
            <Typography variant="h6" gutterBottom>
              {isDragActive ? 'Drop files here' : 'Drag and drop files here'}
            </Typography>
            <Typography variant="body2" color="text.secondary" gutterBottom>
              or click to browse files
            </Typography>
            <Typography variant="caption" display="block" color="text.secondary">
              Supports PDF, DOCX, TXT, MD, CSV, JSON formats (max 100MB per file)
            </Typography>
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setUploadDialogOpen(false)}>取消</Button>
        </DialogActions>
      </Dialog>

      <Fab
        color="primary"
        sx={{ position: 'fixed', bottom: 24, right: 24 }}
        onClick={() => setUploadDialogOpen(true)}
      >
        <AddIcon />
      </Fab>
    </Container>
  );
};

export default DocumentsPage;