import React, { createContext, useContext, useState, useEffect } from 'react';
import { 
  Snackbar, 
  Alert, 
  AlertColor, 
  IconButton, 
  Box,
  Slide,
  SlideProps
} from '@mui/material';
import { Close as CloseIcon } from '@mui/icons-material';
import { Notification } from '../types';
import { errorService } from '../services';

interface NotificationContextType {
  showNotification: (type: AlertColor, title: string, message: string) => void;
  showSuccess: (title: string, message: string) => void;
  showError: (title: string, message: string) => void;
  showWarning: (title: string, message: string) => void;
  showInfo: (title: string, message: string) => void;
}

const NotificationContext = createContext<NotificationContextType | undefined>(undefined);

function SlideTransition(props: SlideProps) {
  return <Slide {...props} direction="down" />;
}

interface NotificationProviderProps {
  children: React.ReactNode;
}

export const NotificationProvider: React.FC<NotificationProviderProps> = ({ children }) => {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [currentNotification, setCurrentNotification] = useState<Notification | null>(null);

  useEffect(() => {
    // Subscribe to error service notifications
    const unsubscribe = errorService.onNotification((notification: Notification) => {
      setNotifications(prev => [...prev, notification]);
    });

    return unsubscribe;
  }, []);

  useEffect(() => {
    // Process notification queue
    if (!currentNotification && notifications.length > 0) {
      const nextNotification = notifications[0];
      setCurrentNotification(nextNotification);
      setNotifications(prev => prev.slice(1));
    }
  }, [notifications, currentNotification]);

  const showNotification = (type: AlertColor, title: string, message: string) => {
    const notification: Notification = {
      id: `notification_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: type as 'info' | 'success' | 'warning' | 'error',
      title,
      message,
      timestamp: new Date(),
      read: false
    };

    setNotifications(prev => [...prev, notification]);
  };

  const showSuccess = (title: string, message: string) => {
    showNotification('success', title, message);
  };

  const showError = (title: string, message: string) => {
    showNotification('error', title, message);
  };

  const showWarning = (title: string, message: string) => {
    showNotification('warning', title, message);
  };

  const showInfo = (title: string, message: string) => {
    showNotification('info', title, message);
  };

  const handleClose = (event?: React.SyntheticEvent | Event, reason?: string) => {
    if (reason === 'clickaway') {
      return;
    }
    setCurrentNotification(null);
  };

  const contextValue: NotificationContextType = {
    showNotification,
    showSuccess,
    showError,
    showWarning,
    showInfo
  };

  return (
    <NotificationContext.Provider value={contextValue}>
      {children}
      
      <Snackbar
        open={!!currentNotification}
        autoHideDuration={
          currentNotification?.type === 'error' ? 8000 : 
          currentNotification?.type === 'warning' ? 6000 : 
          4000
        }
        onClose={handleClose}
        anchorOrigin={{ vertical: 'top', horizontal: 'right' }}
        TransitionComponent={SlideTransition}
        sx={{ mt: 8 }} // Account for navigation bar height
      >
        {currentNotification ? (
          <Alert
            severity={currentNotification.type}
            variant="filled"
            action={
              <IconButton
                size="small"
                aria-label="close"
                color="inherit"
                onClick={handleClose}
              >
                <CloseIcon fontSize="small" />
              </IconButton>
            }
            sx={{ 
              minWidth: 300,
              maxWidth: 500,
              '& .MuiAlert-message': {
                width: '100%'
              }
            }}
          >
            <Box>
              <Box sx={{ fontWeight: 'bold', mb: 0.5 }}>
                {currentNotification.title}
              </Box>
              <Box sx={{ fontSize: '0.875rem' }}>
                {currentNotification.message}
              </Box>
            </Box>
          </Alert>
        ) : (
          <div />
        )}
      </Snackbar>
    </NotificationContext.Provider>
  );
};

export const useNotification = (): NotificationContextType => {
  const context = useContext(NotificationContext);
  if (context === undefined) {
    throw new Error('useNotification must be used within a NotificationProvider');
  }
  return context;
};

export default NotificationProvider;