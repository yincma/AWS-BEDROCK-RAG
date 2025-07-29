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
  
  // Check authentication status
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
    
    // Check if user is logged in
    try {
      const session = await authService.getAuthSession();
      if (!session || !session.tokens?.idToken) {
        setError('Please log in to use the Q&A feature');
        errorService.showWarningNotification(
          'Login Required',
          'Please log in to your account to use the Smart Q&A feature'
        );
        return;
      }
    } catch (error) {
      console.error('Failed to check auth status:', error);
      setError('Authentication check failed, please refresh the page and try again');
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
          content: answer || 'Sorry, I cannot generate an answer for your question.',
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
            'Knowledge Base Empty',
            'Please upload documents before querying'
          );
        } else if (sources.length > 0) {
          errorService.showInfoNotification(
            'Found relevant documents',
            `Answer generated based on ${sources.length} document sources`
          );
        }
      } else {
        // Parse detailed error message
        let errorMessage = 'Query failed';
        if (response.error?.message) {
          try {
            // Try to parse detailed error message from backend
            if (response.error.message.includes('Internal server error:') || response.error.message.includes('Query processing failed:')) {
              const jsonPart = response.error.message.replace(/^[^:]+:\s*/, '');
              const errorDetails = JSON.parse(jsonPart);
              if (errorDetails.environment?.KNOWLEDGE_BASE_ID === 'NOT_SET' || errorDetails.environment?.KNOWLEDGE_BASE_ID === '') {
                errorMessage = 'Knowledge Base not configured. Please run ./scripts/get-knowledge-base-info.sh for configuration info.';
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

      // Provide more specific user messages based on error type
      let userMessage = 'An error occurred while processing your question, please try again';
      
      if (error.status === 502 || error.status === 503) {
        userMessage = 'Smart Q&A service is temporarily unavailable, please ensure backend services are properly deployed';
      } else if (error.status === 401) {
        userMessage = 'Your login has expired, please log in again';
      } else if (error.status === 403) {
        userMessage = 'You do not have permission to use this feature';
      } else if (error.status === 404) {
        userMessage = 'API service not found, please check backend configuration';
      } else if (error.status === 500) {
        // 检查是否是Knowledge Base配置问题
        if (error.message && (
          error.message.includes('Knowledge Base未配置') ||
          error.message.includes('KNOWLEDGE_BASE_ID') ||
          error.message.includes('NOT_SET')
        )) {
          userMessage = 'Knowledge Base not properly configured. Please contact administrator to check AWS resource deployment.';
        } else {
          userMessage = 'Server error processing request, please try again later';
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

      setError(errorMessage.user_message || 'An unknown error occurred');
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
                <Typography variant="body1" sx={{ fontWeight: 500 }}>Thinking...</Typography>
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
                      📖 Reference Sources ({message.sources?.length || 0})
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
                              label={`Relevance: ${(source.confidence * 100).toFixed(1)}%`}
                              variant="filled"
                              color={source.confidence > 0.8 ? 'success' : source.confidence > 0.6 ? 'warning' : 'default'}
                              sx={{ fontWeight: 500 }}
                            />
                            {source.page && (
                              <Chip
                                size="small"
                                label={`Page ${source.page}`}
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
          💬 Smart Q&A
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          AI-powered Q&A assistant based on knowledge base
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
              You need to log in to use the Smart Q&A feature. Please log in to your account.
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
                  🧠 Enterprise RAG Knowledge Assistant
                </Typography>
                <Typography variant="body1" textAlign="center" sx={{ mb: 3, color: 'text.secondary' }}>
                  I'm your AI knowledge assistant. I can answer any questions based on your document library. Please enter your question and I'll search for relevant information to provide accurate answers.
                </Typography>
                
                <Box sx={{ mt: 4 }}>
                  <Typography variant="subtitle1" gutterBottom sx={{ fontWeight: 600, color: 'text.primary' }}>
                    💡 Try these questions:
                  </Typography>
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, justifyContent: 'center' }}>
                    {[
                      "What is the company's remote work policy?",
                      "How do I submit expense reimbursements?",
                      "What are the project management processes?",
                      "What are the features of AWS Bedrock?",
                      "What are the best practices for Lambda functions?"
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
                placeholder={isAuthenticated ? "Ask me anything about your document library..." : "Please log in to use the Q&A feature"}
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
                  🗑️ Clear conversation history
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