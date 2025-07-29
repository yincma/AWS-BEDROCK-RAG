export { apiService } from './api';
export { authService } from './auth';  
export { errorService } from './error';

export type { AuthService } from './auth';

// Re-export types that might be needed
export type {
  QueryRequest,
  QueryResponse,
  ApiResponse,
  Document,
  DocumentUpload,
  HealthStatus,
  User
} from '../types';

// Re-export interfaces that are used by services
export type { AppError, Notification } from '../types';
export { AppErrorClass } from '../types';