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
      language: 'en-US',
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
    { id: 'us.amazon.nova-micro-v1:0', name: 'Nova Micro (Text Only)' },
    { id: 'us.amazon.nova-lite-v1:0', name: 'Nova Lite (Multimodal Fast)' },
    { id: 'us.amazon.nova-pro-v1:0', name: 'Nova Pro (Multimodal Balanced)' },
    { id: 'us.amazon.nova-premier-v1:0', name: 'Nova Premier (Multimodal Powerful)' },
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
      setError('Failed to save settings: ' + error.message);
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
        language: 'en-US',
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
          ⚙️ System Settings
        </Typography>
        <Typography variant="body1" sx={{ opacity: 0.9 }}>
          Configure RAG system parameters and preferences
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
              label="Unsaved changes"
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
            Restore Defaults
          </Button>
          <Button
            variant="contained"
            startIcon={<SaveIcon />}
            onClick={handleSaveSettings}
            disabled={loading || !hasChanges}
          >
            {loading ? 'Saving...' : 'Save Settings'}
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
                <Typography variant="h6">🔍 Retrieval Settings</Typography>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>Number of Documents to Retrieve (top_k)</Typography>
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
                  Controls the number of most relevant documents returned per query
                </Typography>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>Similarity Threshold</Typography>
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
                  Only return documents with similarity higher than this threshold
                </Typography>
              </Box>

              <Box mb={3}>
                <Typography gutterBottom>Max Chunks per Document</Typography>
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
                  Limit the number of text chunks returned from a single document
                </Typography>
              </Box>

              <FormControlLabel
                control={
                  <Switch
                    checked={settings.retrieval.enable_reranking}
                    onChange={(e) => updateSettings('retrieval', 'enable_reranking', e.target.checked)}
                  />
                }
                label="Enable Reranking"
              />
              <Typography variant="caption" color="text.secondary" display="block">
                Use a more accurate model to rerank retrieval results
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
                <Typography variant="h6">🧠 Model Settings</Typography>
              </Box>

              <Box mb={3}>
                <FormControl fullWidth>
                  <InputLabel>Model Selection</InputLabel>
                  <Select
                    value={settings.model.model_id}
                    onChange={(e) => updateSettings('model', 'model_id', e.target.value)}
                    label="Model Selection"
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
                <Typography gutterBottom>Temperature (Creativity)</Typography>
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
                  Controls the randomness of responses, higher values are more creative
                </Typography>
              </Box>

              <Box mb={3}>
                <TextField
                  fullWidth
                  label="Max Output Length"
                  type="number"
                  value={settings.model.max_tokens}
                  onChange={(e) => updateSettings('model', 'max_tokens', parseInt(e.target.value))}
                  inputProps={{ min: 100, max: 4000 }}
                />
                <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                  Limit the maximum number of tokens generated by the model
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
                  Nucleus sampling parameter, controls output diversity
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
                <Typography variant="h6">🎨 UI Preferences</Typography>
              </Box>

              <Box mb={3}>
                <FormControl fullWidth>
                  <InputLabel>Theme</InputLabel>
                  <Select
                    value={settings.ui_preferences.theme}
                    onChange={(e) => updateSettings('ui_preferences', 'theme', e.target.value)}
                    label="Theme"
                  >
                    <MenuItem value="light">Light Theme</MenuItem>
                    <MenuItem value="dark">Dark Theme</MenuItem>
                    <MenuItem value="auto">Follow System</MenuItem>
                  </Select>
                </FormControl>
              </Box>

              <Box mb={3}>
                <FormControl fullWidth>
                  <InputLabel>Language</InputLabel>
                  <Select
                    value={settings.ui_preferences.language}
                    onChange={(e) => updateSettings('ui_preferences', 'language', e.target.value)}
                    label="Language"
                  >
                    <MenuItem value="zh-CN">Simplified Chinese</MenuItem>
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
                  label="Enable Notifications"
                />
                <FormControlLabel
                  control={
                    <Switch
                      checked={settings.ui_preferences.auto_refresh}
                      onChange={(e) => updateSettings('ui_preferences', 'auto_refresh', e.target.checked)}
                    />
                  }
                  label="Auto Refresh Data"
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
                <Typography variant="h6">🔒 Security Settings</Typography>
              </Box>

              <Box mb={3}>
                <TextField
                  fullWidth
                  label="Session Timeout (seconds)"
                  type="number"
                  value={settings.security.session_timeout}
                  onChange={(e) => updateSettings('security', 'session_timeout', parseInt(e.target.value))}
                  inputProps={{ min: 300, max: 86400 }}
                />
                <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                  Time before automatic logout after user inactivity
                </Typography>
              </Box>

              <Box mb={3}>
                <TextField
                  fullWidth
                  label="Max Concurrent Sessions"
                  type="number"
                  value={settings.security.max_concurrent_sessions}
                  onChange={(e) => updateSettings('security', 'max_concurrent_sessions', parseInt(e.target.value))}
                  inputProps={{ min: 1, max: 10 }}
                />
                <Typography variant="caption" color="text.secondary" display="block" mt={1}>
                  Maximum number of concurrent sessions allowed per user
                </Typography>
              </Box>

              <FormControlLabel
                control={
                  <Switch
                    checked={settings.security.require_mfa}
                    onChange={(e) => updateSettings('security', 'require_mfa', e.target.checked)}
                  />
                }
                label="Require Multi-Factor Authentication"
              />
              <Typography variant="caption" color="text.secondary" display="block">
                Enable multi-factor authentication for all users
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        {/* Advanced Settings */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                🔧 Advanced Settings
              </Typography>
              
              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography>API Configuration</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <Grid container spacing={2}>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="API Base URL"
                        value="https://3ulb7g7jof.execute-api.us-east-1.amazonaws.com/dev"
                        disabled
                      />
                    </Grid>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="AWS Region"
                        value="us-east-1"
                        disabled
                      />
                    </Grid>
                  </Grid>
                </AccordionDetails>
              </Accordion>

              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography>Cache Settings</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <Grid container spacing={2}>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="Query Cache Time (seconds)"
                        type="number"
                        defaultValue={300}
                      />
                    </Grid>
                    <Grid item xs={12} md={6}>
                      <TextField
                        fullWidth
                        label="Document Cache Time (seconds)"
                        type="number"
                        defaultValue={3600}
                      />
                    </Grid>
                  </Grid>
                </AccordionDetails>
              </Accordion>

              <Accordion>
                <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                  <Typography>Log Settings</Typography>
                </AccordionSummary>
                <AccordionDetails>
                  <FormControl fullWidth sx={{ mb: 2 }}>
                    <InputLabel>Log Level</InputLabel>
                    <Select defaultValue="INFO" label="Log Level">
                      <MenuItem value="DEBUG">DEBUG</MenuItem>
                      <MenuItem value="INFO">INFO</MenuItem>
                      <MenuItem value="WARNING">WARNING</MenuItem>
                      <MenuItem value="ERROR">ERROR</MenuItem>
                    </Select>
                  </FormControl>
                  <FormControlLabel
                    control={<Switch defaultChecked />}
                    label="Enable Performance Logging"
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
          Settings saved successfully!
        </Alert>
      </Snackbar>
    </Container>
  );
};

export default SettingsPage;