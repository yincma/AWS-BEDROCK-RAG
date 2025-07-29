// ================================
// 类型定义文件
// Enterprise RAG System Frontend Types
// ================================

// 用户认证相关类型
export interface User {
  id: string;
  email: string;
  name: string;
  groups?: string[];
  isAuthenticated: boolean;
}

// API响应基础类型
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: {
    code: number;
    message: string;
  };
  metadata?: {
    response_time: number;
    model_used: string;
    tokens_used?: number;
  };
}

// 查询请求类型
export interface QueryRequest {
  question: string;
  top_k?: number;
  include_sources?: boolean;
  conversation_id?: string;
}

// 文档来源类型
export interface DocumentSource {
  document: string;
  content: string;
  confidence: number;
  page?: number;
  section?: string;
}

// 查询响应类型
export interface QueryResponse {
  answer: string;
  sources: DocumentSource[];
  citations_count?: number;
  model_used?: string;
  fallback_mode?: boolean;
  no_documents?: boolean;
}

// 对话消息类型
export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
  sources?: DocumentSource[];
  isLoading?: boolean;
  error?: string;
}

// 对话会话类型
export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  created_at: Date;
  updated_at: Date;
}

// 文档上传类型
export interface DocumentUpload {
  file: File;
  id: string;
  name: string;
  size: number;
  type: string;
  status: 'pending' | 'uploading' | 'processing' | 'completed' | 'error';
  progress: number;
  error?: string;
  upload_url?: string;
}

// 文档列表项类型
export interface Document {
  id: string;
  name: string;
  size: number;
  type: string;
  upload_date: Date;
  processed_date?: Date | null;
  status: 'active' | 'processing' | 'error';
  url?: string;
  s3_key?: string;
  metadata?: {
    pages?: number;
    words?: number;
    language?: string;
    original_filename?: string;
    content_type?: string;
    file_size?: number;
  };
}

// 系统健康状态类型
export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  service: string;
  version: string;
  timestamp: string;
  environment: string;
  region: string;
  knowledge_base_id?: string;
  checks: {
    bedrock: ServiceCheck;
    knowledge_base?: ServiceCheck;
    s3: ServiceCheck;
  };
}

export interface ServiceCheck {
  status: 'ok' | 'warning' | 'error';
  message: string;
  response_time?: number;
}

// 用户设置类型
export interface UserSettings {
  theme: 'light' | 'dark' | 'auto';
  language: 'en' | 'zh' | 'auto';
  notifications: boolean;
  auto_save: boolean;
  default_top_k: number;
  include_sources_by_default: boolean;
}

// 统计数据类型
export interface SystemStats {
  total_queries: number;
  total_documents: number;
  average_response_time: number;
  active_users: number;
  uptime: string;
  version: string;
}

// 错误类型
export interface AppError {
  code: string;
  message: string;
  details?: any;
  timestamp: Date;
  user_message?: string;
}

// 错误类实现
export class AppErrorClass implements AppError {
  code: string;
  message: string;
  details?: any;
  timestamp: Date;
  user_message?: string;

  constructor(
    code: string,
    message: string,
    details?: any,
    user_message?: string
  ) {
    this.code = code;
    this.message = message;
    this.details = details;
    this.timestamp = new Date();
    this.user_message = user_message;
  }
}

// 通知类型
export interface Notification {
  id: string;
  type: 'info' | 'success' | 'warning' | 'error';
  title: string;
  message: string;
  timestamp: Date;
  read: boolean;
  action?: {
    label: string;
    onClick: () => void;
  };
}

// 应用状态类型
export interface AppState {
  user: User | null;
  isLoading: boolean;
  error: AppError | null;
  notifications: Notification[];
  settings: UserSettings;
  currentSession: ChatSession | null;
  sessions: ChatSession[];
  documents: Document[];
  uploads: DocumentUpload[];
  healthStatus: HealthStatus | null;
  stats: SystemStats | null;
}

// AWS配置类型
export interface AWSConfig {
  region: string;
  userPoolId: string;
  userPoolWebClientId: string;
  apiGatewayUrl: string;
  identityPoolId?: string;
}

// 主题配置类型
export interface ThemeConfig {
  mode: 'light' | 'dark';
  primaryColor: string;
  secondaryColor: string;
  backgroundColor: string;
  textColor: string;
}

// 搜索过滤器类型
export interface SearchFilters {
  query?: string;
  document_types?: string[];
  date_range?: {
    start: Date;
    end: Date;
  };
  min_confidence?: number;
  max_results?: number;
}

// API端点枚举
export enum ApiEndpoints {
  QUERY = '/query',
  CHAT = '/chat',
  UPLOAD = '/upload',
  DOCUMENTS = '/documents',
  HEALTH = '/health',
  AUTH = '/auth',
  STATS = '/stats'
}

// 事件类型
export type AppEvent = 
  | { type: 'USER_LOGIN'; payload: User }
  | { type: 'USER_LOGOUT' }
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_ERROR'; payload: AppError | null }
  | { type: 'ADD_NOTIFICATION'; payload: Notification }
  | { type: 'REMOVE_NOTIFICATION'; payload: string }
  | { type: 'UPDATE_SETTINGS'; payload: Partial<UserSettings> }
  | { type: 'SET_CURRENT_SESSION'; payload: ChatSession | null }
  | { type: 'ADD_MESSAGE'; payload: { sessionId: string; message: ChatMessage } }
  | { type: 'UPDATE_DOCUMENTS'; payload: Document[] }
  | { type: 'ADD_UPLOAD'; payload: DocumentUpload }
  | { type: 'UPDATE_UPLOAD'; payload: { id: string; updates: Partial<DocumentUpload> } }
  | { type: 'SET_HEALTH_STATUS'; payload: HealthStatus }
  | { type: 'SET_STATS'; payload: SystemStats };

// 组件Props类型
export interface BaseComponentProps {
  className?: string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}

// 路由配置类型
export interface RouteConfig {
  path: string;
  component: React.ComponentType<any>;
  exact?: boolean;
  private?: boolean;
  title?: string;
  icon?: string;
}

export default {};