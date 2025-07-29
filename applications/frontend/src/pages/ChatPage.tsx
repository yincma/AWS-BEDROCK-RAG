import React, { useState, useEffect, useRef } from 'react';
import {
  Container,
  Paper,
  TextField,
  Button,
  Typography,
  Box,
  List,
  ListItem,
  Avatar,
  Chip,
  CircularProgress,
  Alert,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  IconButton
} from '@mui/material';
import {
  Send as SendIcon,
  Person as PersonIcon,
  SmartToy as BotIcon,
  ExpandMore as ExpandMoreIcon,
  ContentCopy as CopyIcon,
  Source as SourceIcon
} from '@mui/icons-material';
import { ChatMessage, DocumentSource, QueryRequest } from '../types';
import { apiService, errorService, authService } from '../services';
import { v4 as uuidv4 } from 'uuid';

const ChatPage: React.FC = () => {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputMessage, setInputMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  
  // 检查认证状态
  useEffect(() => {
    const checkAuth = async () => {
      try {
        const authenticated = await authService.isAuthenticated();
        setIsAuthenticated(authenticated);
      } catch (error) {
        console.error('Failed to check auth:', error);
        setIsAuthenticated(false);
      }
    };
    checkAuth();
  }, []);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!inputMessage.trim() || loading) return;
    
    // 检查用户是否已登录
    try {
      const session = await authService.getAuthSession();
      if (!session || !session.tokens?.idToken) {
        setError('请先登录后再使用问答功能');
        errorService.showWarningNotification(
          '需要登录',
          '请先登录您的账户才能使用智能问答功能'
        );
        return;
      }
    } catch (error) {
      console.error('Failed to check auth status:', error);
      setError('认证检查失败，请刷新页面后重试');
      return;
    }

    const questionText = inputMessage.trim();
    const userMessage: ChatMessage = {
      id: uuidv4(),
      role: 'user',
      content: questionText,
      timestamp: new Date()
    };

    // Add user message and create loading bot message
    const loadingBotMessage: ChatMessage = {
      id: uuidv4(),
      role: 'assistant',
      content: '',
      timestamp: new Date(),
      isLoading: true
    };

    setMessages(prev => [...prev, userMessage, loadingBotMessage]);
    setInputMessage('');
    setLoading(true);
    setError(null);

    try {
      // Prepare query request
      const queryRequest: QueryRequest = {
        question: questionText,
        top_k: 5,
        include_sources: true
      };

      // Call RAG API
      const response = await apiService.queryRAG(queryRequest);

      if (response.success && response.data) {
        const { answer, sources = [], no_documents } = response.data;
        
        // Update the loading message with the actual response
        const finalBotMessage: ChatMessage = {
          ...loadingBotMessage,
          content: answer || '抱歉，我无法为您的问题生成回答。',
          sources: sources,
          isLoading: false
        };

        setMessages(prev => 
          prev.map(msg => 
            msg.id === loadingBotMessage.id ? finalBotMessage : msg
          )
        );

        // Show appropriate notification
        if (no_documents) {
          errorService.showWarningNotification(
            '知识库为空',
            '请先上传文档后再进行查询'
          );
        } else if (sources.length > 0) {
          errorService.showInfoNotification(
            '找到相关文档',
            `基于 ${sources.length} 个文档源生成回答`
          );
        }
      } else {
        // 解析详细的错误信息
        let errorMessage = '查询失败';
        if (response.error?.message) {
          try {
            // 尝试解析后端返回的详细错误信息
            if (response.error.message.includes('内部服务器错误:') || response.error.message.includes('查询处理失败:')) {
              const jsonPart = response.error.message.replace(/^[^:]+:\s*/, '');
              const errorDetails = JSON.parse(jsonPart);
              if (errorDetails.environment?.KNOWLEDGE_BASE_ID === 'NOT_SET' || errorDetails.environment?.KNOWLEDGE_BASE_ID === '') {
                errorMessage = 'Knowledge Base未配置。请运行 ./scripts/get-knowledge-base-info.sh 获取配置信息。';
              } else if (errorDetails.error) {
                errorMessage = errorDetails.error;
              }
            } else {
              errorMessage = response.error.message;
            }
          } catch {
            errorMessage = response.error.message;
          }
        }
        console.error('Query failed with error:', errorMessage);
        throw new Error(errorMessage);
      }
    } catch (error: any) {
      // Handle error - remove loading message and show error
      setMessages(prev => 
        prev.filter(msg => msg.id !== loadingBotMessage.id)
      );

      // 根据错误类型提供更具体的用户提示
      let userMessage = '处理您的问题时出现错误，请重试';
      
      if (error.status === 502 || error.status === 503) {
        userMessage = '智能问答服务暂时不可用，请确保后端服务已正确部署';
      } else if (error.status === 401) {
        userMessage = '您的登录已过期，请重新登录';
      } else if (error.status === 403) {
        userMessage = '您没有使用此功能的权限';
      } else if (error.status === 404) {
        userMessage = 'API服务未找到，请检查后端配置';
      } else if (error.status === 500) {
        // 检查是否是Knowledge Base配置问题
        if (error.message && (
          error.message.includes('Knowledge Base未配置') ||
          error.message.includes('KNOWLEDGE_BASE_ID') ||
          error.message.includes('NOT_SET')
        )) {
          userMessage = 'Knowledge Base未正确配置。请联系管理员检查AWS资源部署。';
        } else {
          userMessage = '服务器处理请求时出错，请稍后重试';
        }
      } else if (error.message) {
        userMessage = error.message;
      }

      const errorMessage = errorService.handleError(
        error,
        'chat',
        { 
          showNotification: true,
          userMessage: userMessage
        }
      );

      setError(errorMessage.user_message || '发生未知错误');
    } finally {
      setLoading(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const renderMessage = (message: ChatMessage) => (
    <ListItem
      key={message.id}
      sx={{
        flexDirection: 'column',
        alignItems: message.role === 'user' ? 'flex-end' : 'flex-start',
        mb: 3,
        px: 0
      }}
    >
      <Box
        sx={{
          display: 'flex',
          flexDirection: message.role === 'user' ? 'row-reverse' : 'row',
          alignItems: 'flex-start',
          gap: 2,
          maxWidth: '85%',
          width: '100%'
        }}
      >
        <Avatar
          sx={{
            bgcolor: message.role === 'user' ? 'primary.main' : 'secondary.main',
            width: 40,
            height: 40,
            boxShadow: '0 2px 8px rgba(0,0,0,0.15)'
          }}
        >
          {message.role === 'user' ? <PersonIcon /> : <BotIcon />}
        </Avatar>
        
        <Box sx={{ flex: 1, maxWidth: '100%' }}>
          <Paper
            elevation={0}
            sx={{
              p: 3,
              bgcolor: message.role === 'user' ? '#e3f2fd' : 'white',
              color: message.role === 'user' ? '#1565c0' : 'text.primary',
              borderRadius: 3,
              position: 'relative',
              border: '1px solid',
              borderColor: message.role === 'user' ? '#2196f3' : '#e0e0e0',
              borderLeftWidth: message.role === 'user' ? 1 : 4,
              borderLeftColor: message.role === 'user' ? '#2196f3' : '#9c27b0',
              boxShadow: '0 2px 8px rgba(0,0,0,0.08)'
            }}
          >
            {message.isLoading ? (
              <Box display="flex" alignItems="center" gap={2}>
                <CircularProgress size={20} />
                <Typography variant="body1" sx={{ fontWeight: 500 }}>正在思考中...</Typography>
              </Box>
            ) : (
              <>
                <Typography variant="body1" sx={{ 
                  whiteSpace: 'pre-wrap',
                  lineHeight: 1.6,
                  fontSize: '1rem'
                }}>
                  {message.content}
                </Typography>
                
                {message.role === 'assistant' && (
                  <IconButton
                    size="small"
                    onClick={() => copyToClipboard(message.content)}
                    sx={{
                      position: 'absolute',
                      top: 8,
                      right: 8,
                      opacity: 0.6,
                      '&:hover': { opacity: 1, bgcolor: 'action.hover' }
                    }}
                  >
                    <CopyIcon fontSize="small" />
                  </IconButton>
                )}
              </>
            )}
          </Paper>
          
          {/* Show sources if available */}
          {message.sources && message.sources.length > 0 && (
            <Box sx={{ mt: 2 }}>
              <Accordion sx={{ 
                boxShadow: '0 2px 4px rgba(0,0,0,0.05)',
                borderRadius: 2,
                '&:before': { display: 'none' }
              }}>
                <AccordionSummary 
                  expandIcon={<ExpandMoreIcon />}
                  sx={{ 
                    bgcolor: '#f8f9fa',
                    borderRadius: '8px 8px 0 0',
                    minHeight: 48,
                    '&.Mui-expanded': { minHeight: 48 }
                  }}
                >
                  <Box display="flex" alignItems="center" gap={1}>
                    <SourceIcon fontSize="small" color="primary" />
                    <Typography variant="body2" color="text.primary" fontWeight={500}>
                      📖 参考来源 ({message.sources?.length || 0}个)
                    </Typography>
                  </Box>
                </AccordionSummary>
                <AccordionDetails sx={{ bgcolor: 'white', pt: 2 }}>
                  <List dense>
                    {message.sources?.map((source, index) => (
                      <ListItem key={index} sx={{ 
                        bgcolor: '#fafbfc', 
                        borderRadius: 2, 
                        mb: 1, 
                        border: '1px solid #e0e0e0'
                      }}>
                        <Box width="100%">
                          <Typography variant="subtitle2" color="primary" display="block" gutterBottom>
                            📄 {source.document}
                          </Typography>
                          <Typography variant="body2" sx={{ 
                            mt: 1, 
                            mb: 2,
                            lineHeight: 1.5,
                            color: 'text.secondary'
                          }}>
                            {source.content}
                          </Typography>
                          <Box display="flex" alignItems="center" gap={1}>
                            <Chip
                              size="small"
                              label={`相关度: ${(source.confidence * 100).toFixed(1)}%`}
                              variant="filled"
                              color={source.confidence > 0.8 ? 'success' : source.confidence > 0.6 ? 'warning' : 'default'}
                              sx={{ fontWeight: 500 }}
                            />
                            {source.page && (
                              <Chip
                                size="small"
                                label={`第 ${source.page} 页`}
                                variant="outlined"
                                color="info"
                              />
                            )}
                          </Box>
                        </Box>
                      </ListItem>
                    ))}
                  </List>
                </AccordionDetails>
              </Accordion>
            </Box>
          )}
        </Box>
      </Box>
      
      <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, alignSelf: message.role === 'user' ? 'flex-end' : 'flex-start' }}>
        {message.timestamp.toLocaleTimeString()}
      </Typography>
    </ListItem>
  );

  return (
    <Container maxWidth="xl" sx={{ py: 3, height: 'calc(100vh - 100px)' }}>
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
          💬 智能问答
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          基于知识库的AI智能问答助手
        </Typography>
      </Box>
      
      <Paper elevation={3} sx={{ height: 'calc(100% - 120px)', display: 'flex', flexDirection: 'column', borderRadius: 3 }}>

        {error && (
          <Alert severity="error" sx={{ m: 2 }}>
            {error}
          </Alert>
        )}
        
        {!isAuthenticated && (
          <Alert severity="warning" sx={{ m: 2 }}>
            <Typography variant="body2">
              您需要登录才能使用智能问答功能。请先登录您的账户。
            </Typography>
          </Alert>
        )}

        <Box sx={{ flex: 1, overflow: 'auto', p: 3, bgcolor: '#fafbfc' }}>
          {messages.length === 0 ? (
            <Box
              sx={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                height: '100%',
                color: 'text.secondary'
              }}
            >
              <Box sx={{ 
                p: 4, 
                borderRadius: 3, 
                bgcolor: 'white', 
                boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
                textAlign: 'center',
                maxWidth: 600
              }}>
                <BotIcon sx={{ fontSize: 80, mb: 2, opacity: 0.7, color: 'primary.main' }} />
                <Typography variant="h5" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
                  🧠 企业RAG知识助手
                </Typography>
                <Typography variant="body1" textAlign="center" sx={{ mb: 3, color: 'text.secondary' }}>
                  我是您的AI知识助手，可以基于您的文档库回答任何问题。请输入您的问题，我会为您搜索相关信息并提供准确的答案。
                </Typography>
                
                <Box sx={{ mt: 4 }}>
                  <Typography variant="subtitle1" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
                    💡 试试这些问题：
                  </Typography>
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, justifyContent: 'center' }}>
                    {[
                      "公司的远程工作政策是什么？",
                      "如何提交费用报销？",
                      "项目管理流程有哪些？",
                      "AWS Bedrock 有什么特点？",
                      "Lambda 函数的最佳实践？"
                    ].map((suggestion, index) => (
                      <Chip
                        key={index}
                        label={suggestion}
                        variant="outlined"
                        clickable
                        onClick={() => setInputMessage(suggestion)}
                        size="medium"
                        sx={{ 
                          m: 0.5,
                          '&:hover': { 
                            backgroundColor: 'primary.light', 
                            color: 'white',
                            borderColor: 'primary.main'
                          }
                        }}
                      />
                    ))}
                  </Box>
                </Box>
              </Box>
            </Box>
          ) : (
            <List sx={{ width: '100%', bgcolor: 'transparent' }}>
              {messages.map(renderMessage)}
              <div ref={messagesEndRef} />
            </List>
          )}
        </Box>

        <Box sx={{ 
          p: 3, 
          borderTop: '1px solid #e0e0e0', 
          bgcolor: 'white',
          borderRadius: '0 0 12px 12px'
        }}>
          <form onSubmit={handleSendMessage}>
            <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-end' }}>
              <TextField
                fullWidth
                multiline
                maxRows={4}
                placeholder={isAuthenticated ? "问我关于您文档库的任何问题..." : "请先登录后再使用问答功能"}
                value={inputMessage}
                onChange={(e) => setInputMessage(e.target.value)}
                disabled={loading || !isAuthenticated}
                onKeyPress={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    handleSendMessage(e);
                  }
                }}
                sx={{
                  '& .MuiOutlinedInput-root': {
                    borderRadius: 3,
                    bgcolor: '#f8f9fa',
                    '& fieldset': {
                      borderColor: '#e0e0e0',
                    },
                    '&:hover fieldset': {
                      borderColor: 'primary.main',
                    },
                    '&.Mui-focused fieldset': {
                      borderColor: 'primary.main',
                      borderWidth: 2,
                    }
                  },
                  '& .MuiInputBase-input': {
                    fontSize: '1rem',
                    padding: '12px 16px',
                  }
                }}
              />
              <Button
                type="submit"
                variant="contained"
                disabled={!inputMessage.trim() || loading || !isAuthenticated}
                sx={{ 
                  minWidth: 60, 
                  height: 60,
                  borderRadius: 3,
                  boxShadow: '0 4px 12px rgba(102, 126, 234, 0.3)',
                  '&:hover': {
                    boxShadow: '0 6px 16px rgba(102, 126, 234, 0.4)',
                  }
                }}
              >
                {loading ? <CircularProgress size={24} color="inherit" /> : <SendIcon />}
              </Button>
            </Box>
            
            {/* Clear conversation button */}
            <Box sx={{ mt: 2, textAlign: 'center' }}>
              {messages.length > 0 && (
                <Button
                  variant="text"
                  size="small"
                  onClick={() => {
                    setMessages([]);
                  }}
                  sx={{ 
                    color: 'text.secondary',
                    '&:hover': {
                      bgcolor: 'action.hover'
                    }
                  }}
                >
                  🗑️ 清空对话历史
                </Button>
              )}
            </Box>
          </form>
        </Box>
      </Paper>
    </Container>
  );
};

export default ChatPage;