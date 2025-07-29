import { AppError, AppErrorClass, Notification } from '../types';

export interface ErrorHandlerOptions {
  showNotification?: boolean;
  logError?: boolean;
  throwError?: boolean;
  userMessage?: string;
}

class ErrorService {
  private errorListeners: Array<(error: AppError) => void> = [];
  private notificationListeners: Array<(notification: Notification) => void> = [];

  onError(callback: (error: AppError) => void) {
    this.errorListeners.push(callback);
    
    return () => {
      const index = this.errorListeners.indexOf(callback);
      if (index > -1) {
        this.errorListeners.splice(index, 1);
      }
    };
  }

  onNotification(callback: (notification: Notification) => void) {
    this.notificationListeners.push(callback);
    
    return () => {
      const index = this.notificationListeners.indexOf(callback);
      if (index > -1) {
        this.notificationListeners.splice(index, 1);
      }
    };
  }

  private emitError(error: AppError) {
    this.errorListeners.forEach(listener => {
      try {
        listener(error);
      } catch (err) {
        console.error('Error listener failed:', err);
      }
    });
  }

  private emitNotification(notification: Notification) {
    this.notificationListeners.forEach(listener => {
      try {
        listener(notification);
      } catch (err) {
        console.error('Notification listener failed:', err);
      }
    });
  }

  handleError(
    error: any,
    context?: string,
    options: ErrorHandlerOptions = {}
  ): AppError {
    const {
      showNotification = true,
      logError = true,
      throwError = false,
      userMessage
    } = options;

    const appError = this.normalizeError(error, context, userMessage);

    if (logError) {
      console.error(`[${appError.code}] ${appError.message}`, {
        context,
        details: appError.details,
        timestamp: appError.timestamp
      });
    }

    this.emitError(appError);

    if (showNotification) {
      this.showErrorNotification(appError);
    }

    if (throwError) {
      throw appError;
    }

    return appError;
  }

  private normalizeError(
    error: any,
    context?: string,
    userMessage?: string
  ): AppError {
    const timestamp = new Date();
    
    if (error instanceof AppErrorClass) {
      return error;
    }

    let code = 'UNKNOWN_ERROR';
    let message = 'An unknown error occurred';
    let details = error;

    if (error instanceof Error) {
      message = error.message;
      code = error.name || 'ERROR';
      details = {
        name: error.name,
        message: error.message,
        stack: error.stack
      };
    } else if (typeof error === 'string') {
      message = error;
      code = 'STRING_ERROR';
    } else if (error?.message) {
      message = error.message;
      code = error.code || error.name || 'API_ERROR';
      details = error;
    }

    // Add context to the code if provided
    if (context) {
      code = `${context.toUpperCase()}_${code}`;
    }

    return {
      code,
      message,
      details,
      timestamp,
      user_message: userMessage || this.getUserFriendlyMessage(code, message)
    };
  }

  private getUserFriendlyMessage(code: string, originalMessage: string): string {
    const lowerCode = code.toLowerCase();
    
    if (lowerCode.includes('network') || lowerCode.includes('fetch')) {
      return 'Network connection issue, please check your network connection and try again';
    }
    
    if (lowerCode.includes('timeout')) {
      return 'Request timeout, please try again later';
    }
    
    if (lowerCode.includes('auth') || lowerCode.includes('unauthorized')) {
      return 'Authentication failed, please log in again';
    }
    
    if (lowerCode.includes('forbidden')) {
      return 'You do not have permission to perform this operation';
    }
    
    if (lowerCode.includes('not_found')) {
      return 'Requested resource not found';
    }
    
    if (lowerCode.includes('upload')) {
      return 'File upload failed, please check the file format and size and try again';
    }
    
    if (lowerCode.includes('chat') || lowerCode.includes('query')) {
      return 'There was a problem processing your request, please resend the message';
    }
    
    if (lowerCode.includes('server') || lowerCode.includes('500')) {
      return 'The server is experiencing temporary issues, please try again later';
    }
    
    if (lowerCode.includes('validation')) {
      return 'Invalid input data format, please check and try again';
    }
    
    // Return original message for development, generic message for production
    if (process.env.NODE_ENV === 'development') {
      return originalMessage;
    }
    
    return 'Operation failed, please try again later';
  }

  private showErrorNotification(error: AppError) {
    const notification: Notification = {
      id: `error_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'error',
      title: 'Operation Failed',
      message: error.user_message || error.message,
      timestamp: error.timestamp,
      read: false
    };

    this.emitNotification(notification);
  }

  showSuccessNotification(title: string, message: string) {
    const notification: Notification = {
      id: `success_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'success',
      title,
      message,
      timestamp: new Date(),
      read: false
    };

    this.emitNotification(notification);
  }

  showInfoNotification(title: string, message: string) {
    const notification: Notification = {
      id: `info_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'info',
      title,
      message,
      timestamp: new Date(),
      read: false
    };

    this.emitNotification(notification);
  }

  showWarningNotification(title: string, message: string) {
    const notification: Notification = {
      id: `warning_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'warning',
      title,
      message,
      timestamp: new Date(),
      read: false
    };

    this.emitNotification(notification);
  }
}

export const errorService = new ErrorService();
export default errorService;