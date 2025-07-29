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
  TextField,
  Slider,
  Switch,
  FormControlLabel,
  FormGroup,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  Divider,
  Alert,
  Snackbar,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Chip,
  List,
  ListItem,
  ListItemText,
  ListItemSecondaryAction,
  IconButton,
} from '@mui/material';
import {
  Save as SaveIcon,
  Refresh as RefreshIcon,
  ExpandMore as ExpandMoreIcon,
  Tune as TuneIcon,
  Psychology as PsychologyIcon,
  Search as SearchIcon,
  Security as SecurityIcon,
  Notifications as NotificationsIcon,
  Storage as StorageIcon,
  Delete as DeleteIcon,
  Edit as EditIcon,
} from '@mui/icons-material';

interface RetrievalSettings {
  top_k: number;
  similarity_threshold: number;
  max_chunks_per_document: number;
  enable_reranking: boolean;
}

interface ModelSettings {
  temperature: number;
  max_tokens: number;
  top_p: number;
  frequency_penalty: number;
  presence_penalty: number;
  model_id: string;
}

interface SystemSettings {
  retrieval: RetrievalSettings;
  model: ModelSettings;
  ui_preferences: {
    theme: 'light' | 'dark' | 'auto';
    language: 'zh-CN' | 'en-US';
    notifications_enabled: boolean;
    auto_refresh: boolean;
  };
  security: {
    session_timeout: number;
    max_concurrent_sessions: number;
    require_mfa: boolean;
  };
}

const SettingsPage: React.FC = () => {
  const [settings, setSettings] = useState<SystemSettings>({
    retrieval: {
      top_k: 5,
      similarity_threshold: 0.7,
      max_chunks_per_document: 3,
      enable_reranking: true,
    },
    model: {
      temperature: 0.1,
      max_tokens: 2000,
      top_p: 0.9,
      frequency_penalty: 0.0,
      presence_penalty: 0.0,
      model_id: 'us.amazon.nova-pro-v1:0',
    },
    ui_preferences: {
      theme: 'light',
      language: 'zh-CN',
      notifications_enabled: true,
      auto_refresh: true,
    },
    security: {
      session_timeout: 3600,
      max_concurrent_sessions: 3,
      require_mfa: false,
    },
  });

  const [loading, setLoading] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasChanges, setHasChanges] = useState(false);

  const availableModels = [
    { id: 'us.amazon.nova-micro-v1:0', name: 'Nova Micro (文本专用)' },
    { id: 'us.amazon.nova-lite-v1:0', name: 'Nova Lite (多模态快速)' },
    { id: 'us.amazon.nova-pro-v1:0', name: 'Nova Pro (多模态平衡)' },
    { id: 'us.amazon.nova-premier-v1:0', name: 'Nova Premier (多模态最强)' },
  ];

  const updateSettings = (section: keyof SystemSettings, key: string, value: any) => {
    setSettings(prev => ({
      ...prev,
      [section]: {
        ...prev[section],
        [key]: value
      }
    }));
    setHasChanges(true);
  };

  const handleSaveSettings = async () => {
    setLoading(true);
    setError(null);
    
    try {
      // Mock API call to save settings
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      setSaveSuccess(true);
      setHasChanges(false);
      
      // Reset success message after 3 seconds
      setTimeout(() => setSaveSuccess(false), 3000);
    } catch (error: any) {
      setError('保存设置失败: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleResetToDefaults = () => {
    const defaultSettings: SystemSettings = {
      retrieval: {
        top_k: 5,
        similarity_threshold: 0.7,
        max_chunks_per_document: 3,
        enable_reranking: true,
      },
      model: {
        temperature: 0.1,
        max_tokens: 2000,
        top_p: 0.9,
        frequency_penalty: 0.0,
        presence_penalty: 0.0,
        model_id: 'us.amazon.nova-pro-v1:0',
      },
      ui_preferences: {
        theme: 'light',
        language: 'zh-CN',
        notifications_enabled: true,
        auto_refresh: true,
      },
      security: {
        session_timeout: 3600,
        max_concurrent_sessions: 3,
        require_mfa: false,
      },
    };
    
    setSettings(defaultSettings);
    setHasChanges(true);
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
          ⚙️ 系统设置
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          配置RAG系统的各项参数和偏好设置
        </Typography>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {/* Action Buttons */}
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Box>
          {hasChanges && (
            <Chip
              label="有未保存的更改"
              color="warning"
              variant="outlined"
              size="small"
            />
          )}
        </Box>
        <Box display="flex" gap={2}>
          <Button
            variant="outlined"
            startIcon={<RefreshIcon />}
            onClick={handleResetToDefaults}
          >
            恢复默认
          </Button>
          <Button
            variant="contained"
            startIcon={<SaveIcon />}
            onClick={handleSaveSettings}
            disabled={loading || !hasChanges}
          >
            {loading ? '保存中...' : '保存设置'}
          </Button>
        </Box>
      </Box>

      <Grid container spacing={3}>
        {/* Retrieval Settings */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <SearchIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">🔍 检索设置</Typography>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>检索文档数量 (top_k)</Typography>
                <Slider
                  value={settings.retrieval.top_k}
                  onChange={(_, value) => updateSettings('retrieval', 'top_k', value)}
                  min={1}
                  max={20}
                  step={1}
                  marks
                  valueLabelDisplay="on"
                />
                <Typography variant="caption" color="text.secondary">
                  控制每次查询返回的最相关文档数量
                </Typography>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>相似度阈值</Typography>
                <Slider
                  value={settings.retrieval.similarity_threshold}
                  onChange={(_, value) => updateSettings('retrieval', 'similarity_threshold', value)}
                  min={0}
                  max={1}
                  step={0.1}
                  marks
                  valueLabelDisplay="on"
                />
                <Typography variant="caption" color="text.secondary">
                  只返回相似度高于此阈值的文档
                </Typography>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>单文档最大块数</Typography>
                <Slider
                  value={settings.retrieval.max_chunks_per_document}
                  onChange={(_, value) => updateSettings('retrieval', 'max_chunks_per_document', value)}
                  min={1}
                  max={10}
                  step={1}
                  marks
                  valueLabelDisplay="on"
                />
                <Typography variant="caption" color="text.secondary">
                  限制从单个文档返回的文本块数量
                </Typography>
              </Box>

              <FormControlLabel
                control={
                  <Switch
                    checked={settings.retrieval.enable_reranking}
                    onChange={(e) => updateSettings('retrieval', 'enable_reranking', e.target.checked)}
                  />
                }
                label="启用重排序"
              />
              <Typography variant="caption" color="text.secondary" display="block">
                使用更精确的模型对检索结果重新排序
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        {/* Model Settings */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <PsychologyIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">🧠 模型设置</Typography>
              </Box>

              <Box mb={3}>
                <FormControl fullWidth>
                  <InputLabel>模型选择</InputLabel>
                  <Select
                    value={settings.model.model_id}
                    onChange={(e) => updateSettings('model', 'model_id', e.target.value)}
                    label="模型选择"
                  >
                    {availableModels.map((model) => (
                      <MenuItem key={model.id} value={model.id}>
                        {model.name}
                      </MenuItem>
                    ))}
                  </Select>
                </FormControl>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>Temperature (创造性)</Typography>
                <Slider
                  value={settings.model.temperature}
                  onChange={(_, value) => updateSettings('model', 'temperature', value)}
                  min={0}
                  max={2}
                  step={0.1}
                  marks
                  valueLabelDisplay="on"
                />
                <Typography variant="caption" color="text.secondary">
                  控制回答的随机性，值越高越有创造性
                </Typography>
              </Box>

              <Box mb={3}>
                <TextField
                  fullWidth
                  label="最大输出长度"
                  type="number"
                  value={settings.model.max_tokens}
                  onChange={(e) => updateSettings('model', 'max_tokens', parseInt(e.target.value))}
                  inputProps={{ min: 100, max: 4000 }}
                />
                <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                  限制模型生成的最大token数量
                </Typography>
              </Box>

              <Box mb={2}>
                <Typography gutterBottom>Top P</Typography>
                <Slider
                  value={settings.model.top_p}
                  onChange={(_, value) => updateSettings('model', 'top_p', value)}
                  min={0}
                  max={1}
                  step={0.1}
                  marks
                  valueLabelDisplay="on"
                />
                <Typography variant="caption" color="text.secondary">
                  核采样参数，控制输出的多样性
                </Typography>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* UI Preferences */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <TuneIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">🎨 界面偏好</Typography>
              </Box>

              <Box mb={3}>
                <FormControl fullWidth>
                  <InputLabel>主题</InputLabel>
                  <Select
                    value={settings.ui_preferences.theme}
                    onChange={(e) => updateSettings('ui_preferences', 'theme', e.target.value)}
                    label="主题"
                  >
                    <MenuItem value="light">浅色主题</MenuItem>
                    <MenuItem value="dark">深色主题</MenuItem>
                    <MenuItem value="auto">跟随系统</MenuItem>
                  </Select>
                </FormControl>
              </Box>

              <Box mb={3}>
                <FormControl fullWidth>
                  <InputLabel>语言</InputLabel>
                  <Select
                    value={settings.ui_preferences.language}
                    onChange={(e) => updateSettings('ui_preferences', 'language', e.target.value)}
                    label="语言"
                  >
                    <MenuItem value="zh-CN">简体中文</MenuItem>
                    <MenuItem value="en-US">English</MenuItem>
                  </Select>
                </FormControl>
              </Box>

              <FormGroup>
                <FormControlLabel
                  control={
                    <Switch
                      checked={settings.ui_preferences.notifications_enabled}
                      onChange={(e) => updateSettings('ui_preferences', 'notifications_enabled', e.target.checked)}
                    />
                  }
                  label="启用通知"
                />
                <FormControlLabel
                  control={
                    <Switch
                      checked={settings.ui_preferences.auto_refresh}
                      onChange={(e) => updateSettings('ui_preferences', 'auto_refresh', e.target.checked)}
                    />
                  }
                  label="自动刷新数据"
                />
              </FormGroup>
            </CardContent>
          </Card>
        </Grid>

        {/* Security Settings */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" mb={3}>
                <SecurityIcon color="primary" sx={{ mr: 2 }} />
                <Typography variant="h6">🔒 安全设置</Typography>
              </Box>

              <Box mb={3}>
                <TextField
                  fullWidth
                  label="会话超时时间 (秒)"
                  type="number"
                  value={settings.security.session_timeout}
                  onChange={(e) => updateSettings('security', 'session_timeout', parseInt(e.target.value))}
                  inputProps={{ min: 300, max: 86400 }}
                />
                <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                  用户无操作后自动登出的时间
                </Typography>
              </Box>

              <Box mb={3}>
                <TextField
                  fullWidth
                  label="最大并发会话数"
                  type="number"
                  value={settings.security.max_concurrent_sessions}
                  onChange={(e) => updateSettings('security', 'max_concurrent_sessions', parseInt(e.target.value))}
                  inputProps={{ min: 1, max: 10 }}
                />
                <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                  单个用户同时允许的最大会话数
                </Typography>
              </Box>

              <FormControlLabel
                control={
                  <Switch
                    checked={settings.security.require_mfa}
                    onChange={(e) => updateSettings('security', 'require_mfa', e.target.checked)}
                  />
                }
                label="要求多因素认证"
              />
              <Typography variant="caption" color="text.secondary" display="block">
                为所有用户启用多因素认证
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        {/* Advanced Settings */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                🔧 高级设置
              </Typography>
              
              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography>API 配置</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <Grid container spacing={2}>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="API 基础 URL"
                        value="https://3ulb7g7jof.execute-api.us-east-1.amazonaws.com/dev"
                        disabled
                      />
                    </Grid>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="AWS 区域"
                        value="us-east-1"
                        disabled
                      />
                    </Grid>
                  </Grid>
                </AccordionDetails>
              </Accordion>

              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography>缓存设置</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <Grid container spacing={2}>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="查询缓存时间 (秒)"
                        type="number"
                        defaultValue={300}
                      />
                    </Grid>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="文档缓存时间 (秒)"
                        type="number"
                        defaultValue={3600}
                      />
                    </Grid>
                  </Grid>
                </AccordionDetails>
              </Accordion>

              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography>日志设置</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <FormControl fullWidth sx={{ mb: 2 }}>
                    <InputLabel>日志级别</InputLabel>
                    <Select defaultValue="INFO" label="日志级别">
                      <MenuItem value="DEBUG">DEBUG</MenuItem>
                      <MenuItem value="INFO">INFO</MenuItem>
                      <MenuItem value="WARNING">WARNING</MenuItem>
                      <MenuItem value="ERROR">ERROR</MenuItem>
                    </Select>
                  </FormControl>
                  <FormControlLabel
                    control={<Switch defaultChecked />}
                    label="启用性能日志"
                  />
                </AccordionDetails>
              </Accordion>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Success Snackbar */}
      <Snackbar
        open={saveSuccess}
        autoHideDuration={3000}
        onClose={() => setSaveSuccess(false)}
      >
        <Alert severity="success" onClose={() => setSaveSuccess(false)}>
          设置保存成功！
        </Alert>
      </Snackbar>
    </Container>
  );
};

export default SettingsPage;