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
      return '网络连接出现问题，请检查您的网络连接后重试';
    }
    
    if (lowerCode.includes('timeout')) {
      return '请求超时，请稍后重试';
    }
    
    if (lowerCode.includes('auth') || lowerCode.includes('unauthorized')) {
      return '身份验证失败，请重新登录';
    }
    
    if (lowerCode.includes('forbidden')) {
      return '您没有权限执行此操作';
    }
    
    if (lowerCode.includes('not_found')) {
      return '未找到请求的资源';
    }
    
    if (lowerCode.includes('upload')) {
      return '文件上传失败，请检查文件格式和大小后重试';
    }
    
    if (lowerCode.includes('chat') || lowerCode.includes('query')) {
      return '处理您的请求时出现问题，请重新发送消息';
    }
    
    if (lowerCode.includes('server') || lowerCode.includes('500')) {
      return '服务器出现临时问题，请稍后重试';
    }
    
    if (lowerCode.includes('validation')) {
      return '输入数据格式不正确，请检查后重试';
    }
    
    // Return original message for development, generic message for production
    if (process.env.NODE_ENV === 'development') {
      return originalMessage;
    }
    
    return '操作失败，请稍后重试';
  }

  private showErrorNotification(error: AppError) {
    const notification: Notification = {
      id: `error_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'error',
      title: '操作失败',
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