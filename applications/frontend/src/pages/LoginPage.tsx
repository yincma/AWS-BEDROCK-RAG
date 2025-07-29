import React, { useState } from 'react';
import {
  Container,
  Paper,
  TextField,
  Button,
  Typography,
  Box,
  Alert,
  Card,
  CardContent,
  CircularProgress
} from '@mui/material';
import { signIn, signUp, confirmSignUp } from 'aws-amplify/auth';
import { User } from '../types';
import { authService } from '../services';
import { useNotification } from '../components/NotificationProvider';

interface LoginPageProps {
  onLogin: (user: User) => void;
}

const LoginPage: React.FC<LoginPageProps> = ({ onLogin }) => {
  const [mode, setMode] = useState<'signin' | 'signup' | 'confirm'>('signin');
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    confirmPassword: '',
    name: '',
    confirmationCode: ''
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { showSuccess, showInfo } = useNotification();

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
    setError(null);
  };

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const result = await signIn({
        username: formData.email,
        password: formData.password
      });

      if (result.isSignedIn) {
        onLogin({
          id: formData.email,
          email: formData.email,
          name: formData.name || formData.email,
          isAuthenticated: true
        });
      }
    } catch (err: any) {
      console.error('Sign in error:', err);
      setError(err.message || 'Failed to sign in. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (formData.password !== formData.confirmPassword) {
      setError('Passwords do not match');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const { isSignUpComplete, userId, nextStep } = await signUp({
        username: formData.email,
        password: formData.password,
        options: {
          userAttributes: {
            email: formData.email,
            name: formData.name
          }
        }
      });

      if (isSignUpComplete) {
        onLogin({
          id: formData.email,
          email: formData.email,
          name: formData.name,
          isAuthenticated: true
        });
      } else if (nextStep.signUpStep === 'CONFIRM_SIGN_UP') {
        setMode('confirm');
      }
    } catch (err: any) {
      console.error('Sign up error:', err);
      setError(err.message || 'Failed to create account. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleConfirmSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const { isSignUpComplete } = await confirmSignUp({
        username: formData.email,
        confirmationCode: formData.confirmationCode
      });

      if (isSignUpComplete) {
        // Now sign in the user
        const result = await signIn({
          username: formData.email,
          password: formData.password
        });

        if (result.isSignedIn) {
          onLogin({
            id: formData.email,
            email: formData.email,
            name: formData.name,
            isAuthenticated: true
          });
        }
      }
    } catch (err: any) {
      console.error('Confirm sign up error:', err);
      setError(err.message || 'Failed to confirm account. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const renderSignInForm = () => (
    <form onSubmit={handleSignIn}>
      <TextField
        fullWidth
        label="Email"
        name="email"
        type="email"
        value={formData.email}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
        autoComplete="off"
        inputProps={{
          autoComplete: 'new-password'
        }}
      />
      <TextField
        fullWidth
        label="Password"
        name="password"
        type="password"
        value={formData.password}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
        autoComplete="new-password"
        inputProps={{
          autoComplete: 'new-password'
        }}
      />
      <Button
        type="submit"
        fullWidth
        variant="contained"
        size="large"
        disabled={loading}
        sx={{ mt: 3, mb: 2 }}
      >
        {loading ? <CircularProgress size={24} /> : 'Sign In'}
      </Button>
      <Button
        fullWidth
        variant="text"
        onClick={() => setMode('signup')}
        disabled={loading}
      >
        Don't have an account? Sign Up
      </Button>
    </form>
  );

  const renderSignUpForm = () => (
    <form onSubmit={handleSignUp}>
      <TextField
        fullWidth
        label="Full Name"
        name="name"
        value={formData.name}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
      />
      <TextField
        fullWidth
        label="Email"
        name="email"
        type="email"
        value={formData.email}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
      />
      <TextField
        fullWidth
        label="Password"
        name="password"
        type="password"
        value={formData.password}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
        autoComplete="new-password"
        inputProps={{
          autoComplete: 'new-password'
        }}
      />
      <TextField
        fullWidth
        label="Confirm Password"
        name="confirmPassword"
        type="password"
        value={formData.confirmPassword}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
      />
      <Button
        type="submit"
        fullWidth
        variant="contained"
        size="large"
        disabled={loading}
        sx={{ mt: 3, mb: 2 }}
      >
        {loading ? <CircularProgress size={24} /> : 'Sign Up'}
      </Button>
      <Button
        fullWidth
        variant="text"
        onClick={() => setMode('signin')}
        disabled={loading}
      >
        Already have an account? Sign In
      </Button>
    </form>
  );

  const renderConfirmForm = () => (
    <form onSubmit={handleConfirmSignUp}>
      <Typography variant="body2" sx={{ mb: 2 }}>
        Please check your email for the confirmation code and enter it below.
      </Typography>
      <TextField
        fullWidth
        label="Confirmation Code"
        name="confirmationCode"
        value={formData.confirmationCode}
        onChange={handleInputChange}
        margin="normal"
        required
        disabled={loading}
      />
      <Button
        type="submit"
        fullWidth
        variant="contained"
        size="large"
        disabled={loading}
        sx={{ mt: 3, mb: 2 }}
      >
        {loading ? <CircularProgress size={24} /> : 'Confirm Account'}
      </Button>
      <Button
        fullWidth
        variant="text"
        onClick={() => setMode('signin')}
        disabled={loading}
      >
        Back to Sign In
      </Button>
    </form>
  );

  return (
    <Box
      sx={{
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 2
      }}
    >
      <Container maxWidth="sm">
        <Card elevation={8}>
          <CardContent sx={{ p: 4 }}>
            <Box textAlign="center" mb={3}>
              <Typography variant="h4" gutterBottom color="primary">
                Enterprise RAG System
              </Typography>
              <Typography variant="h6" color="text.secondary">
                {mode === 'signin' && 'Sign In to Your Account'}
                {mode === 'signup' && 'Create Your Account'}
                {mode === 'confirm' && 'Confirm Your Account'}
              </Typography>
            </Box>

            {error && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {error}
              </Alert>
            )}

            {/* Authentication Notice */}
            <Alert severity="info" sx={{ mb: 2 }}>
              <Typography variant="body2" sx={{ mb: 1 }}>
                <strong>Note:</strong> This system requires authentication to access.
              </Typography>
              <Typography variant="caption" display="block">
                Please use your organization credentials or contact your administrator for access.
              </Typography>
            </Alert>

            {mode === 'signin' && renderSignInForm()}
            {mode === 'signup' && renderSignUpForm()}
            {mode === 'confirm' && renderConfirmForm()}

            {/* Demo Features */}
            <Box sx={{ mt: 4, pt: 3, borderTop: '1px solid #e0e0e0' }}>
              <Typography variant="subtitle2" color="text.secondary" gutterBottom>
                System Features:
              </Typography>
              <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1, mt: 1 }}>
                <Box sx={{ fontSize: '0.85rem', color: 'text.secondary' }}>
                  🔍 Intelligent Search
                </Box>
                <Box sx={{ fontSize: '0.85rem', color: 'text.secondary' }}>
                  💬 AI Conversation
                </Box>
                <Box sx={{ fontSize: '0.85rem', color: 'text.secondary' }}>
                  📚 Document Management
                </Box>
                <Box sx={{ fontSize: '0.85rem', color: 'text.secondary' }}>
                  🔐 Secure Authentication
                </Box>
              </Box>
            </Box>
          </CardContent>
        </Card>
      </Container>
    </Box>
  );
};

export default LoginPage;