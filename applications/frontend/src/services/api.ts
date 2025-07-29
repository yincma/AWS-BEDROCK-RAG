import { fetchAuthSession } from 'aws-amplify/auth';
import { 
  QueryRequest, 
  QueryResponse, 
  ApiResponse, 
  Document, 
  DocumentUpload,
  HealthStatus 
} from '../types';
import { apiConfig } from '../config/aws';

interface RequestConfig extends RequestInit {
  timeout?: number;
  retries?: number;
}

interface ApiClient {
  get<T = any>(url: string, config?: RequestConfig): Promise<ApiResponse<T>>;
  post<T = any>(url: string, data?: any, config?: RequestConfig): Promise<ApiResponse<T>>;
  put<T = any>(url: string, data?: any, config?: RequestConfig): Promise<ApiResponse<T>>;
  delete<T = any>(url: string, config?: RequestConfig): Promise<ApiResponse<T>>;
}

class ApiService implements ApiClient {
  private baseURL: string;
  private defaultConfig: RequestConfig;

  constructor() {
    // 初始使用默认配置
    this.baseURL = apiConfig.baseURL;
    this.defaultConfig = {
      timeout: apiConfig.timeout,
      retries: apiConfig.retries,
      headers: {
        'Content-Type': 'application/json',
      },
    };
  }

  // 更新API配置
  updateConfig(config: { apiEndpoint?: string }) {
    if (config.apiEndpoint) {
      this.baseURL = config.apiEndpoint;
    }
  }

  private async getAuthHeaders(): Promise<Record<string, string>> {
    try {
      const session = await fetchAuthSession();
      console.log('Auth session:', {
        hasTokens: !!session.tokens,
        hasIdToken: !!session.tokens?.idToken,
        hasAccessToken: !!session.tokens?.accessToken,
      });
      
      // 使用 ID Token 用于 API Gateway 认证
      const token = session.tokens?.idToken?.toString();
      
      if (token) {
        console.log('Using ID token for authorization');
        // 调试：打印token的前20个字符
        console.log('Token preview:', token.substring(0, 20) + '...');
        return {
          'Authorization': `Bearer ${token}`,
        };
      }
      
      console.warn('No auth token available');
      return {};
    } catch (error) {
      console.warn('Failed to get auth token:', error);
      return {};
    }
  }

  private async makeRequest<T>(
    url: string, 
    config: RequestConfig
  ): Promise<ApiResponse<T>> {
    const { timeout = this.defaultConfig.timeout || 30000, retries = this.defaultConfig.retries || 3 } = config;
    
    let lastError: Error = new Error('Unknown error');
    
    for (let attempt = 0; attempt <= (retries || 0); attempt++) {
      try {
        const authHeaders = await this.getAuthHeaders();
        
        const finalConfig: RequestInit = {
          ...config,
          headers: {
            ...this.defaultConfig.headers,
            ...authHeaders,
            ...config.headers,
          },
        };

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), timeout);

        const response = await fetch(`${this.baseURL}${url}`, {
          ...finalConfig,
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          let errorData: any = {};
          let responseText = '';
          
          try {
            responseText = await response.text();
            errorData = JSON.parse(responseText);
          } catch (e) {
            console.error('Failed to parse error response:', e);
            errorData = { message: responseText || response.statusText };
          }
          
          console.error('API Error Response:', {
            url: `${this.baseURL}${url}`,
            method: config.method,
            status: response.status,
            statusText: response.statusText,
            errorData: errorData,
            responseText: responseText,
            headers: Object.fromEntries(response.headers.entries())
          });
          
          // 创建更详细的错误消息
          let errorMessage = `HTTP ${response.status}`;
          
          if (response.status === 401) {
            errorMessage = '认证失败：请重新登录';
          } else if (response.status === 403) {
            errorMessage = '权限不足：您没有访问此资源的权限';
          } else if (response.status === 404) {
            errorMessage = 'API端点未找到：请检查服务配置';
          } else if (response.status === 500) {
            errorMessage = '服务器内部错误：请稍后重试';
          } else if (response.status === 502 || response.status === 503) {
            errorMessage = '服务暂时不可用：后端服务可能未启动';
          } else if (errorData.message) {
            errorMessage = errorData.message;
          } else if (errorData.error) {
            errorMessage = errorData.error;
          } else {
            errorMessage = `请求失败 (${response.status}): ${response.statusText}`;
          }
          
          const error = new Error(errorMessage);
          (error as any).status = response.status;
          (error as any).details = errorData;
          throw error;
        }

        const responseText = await response.text();
        console.log('API Response:', {
          url: `${this.baseURL}${url}`,
          status: response.status,
          responseText: responseText.substring(0, 500) // Log first 500 chars
        });
        
        let data: any;
        try {
          data = JSON.parse(responseText);
        } catch (e) {
          console.error('Failed to parse response as JSON:', responseText);
          throw new Error('Invalid response format from server');
        }
        
        // Handle Lambda proxy integration response format
        if (data.statusCode && data.body) {
          console.log('[API] Detected Lambda proxy response format');
          // This is a Lambda proxy response, parse the actual body
          try {
            const actualData = typeof data.body === 'string' ? JSON.parse(data.body) : data.body;
            console.log('[API] Parsed Lambda body:', { 
              success: actualData.success, 
              hasData: !!actualData.data,
              dataType: typeof actualData.data,
              dataIsArray: Array.isArray(actualData.data),
              dataLength: actualData.data?.length 
            });
            
            // If statusCode indicates an error (not 2xx), treat as error
            if (data.statusCode >= 300) {
              return {
                success: false,
                data: undefined,
                error: actualData.error || { message: actualData.message || 'Request failed' },
                metadata: actualData.metadata
              };
            }
            
            // For successful responses, check the success field
            const result = {
              success: actualData.success !== false,
              data: actualData.success !== false ? (actualData.data !== undefined ? actualData.data : actualData) : undefined,
              error: actualData.success === false ? actualData.error : undefined,
              metadata: actualData.metadata
            };
            console.log('[API] Returning Lambda proxy result:', { 
              success: result.success, 
              hasData: !!result.data,
              dataType: typeof result.data,
              dataIsArray: Array.isArray(result.data),
              dataLength: result.data?.length 
            });
            return result;
          } catch (e) {
            console.error('Failed to parse Lambda proxy response body:', data.body);
            throw new Error('Invalid Lambda response format');
          }
        }
        
        // Direct response format (non-proxy)
        console.log('[API] Detected direct response format:', { 
          success: data.success, 
          hasData: !!data.data,
          dataType: typeof data.data,
          dataIsArray: Array.isArray(data.data),
          dataLength: data.data?.length 
        });
        
        const result = {
          success: data.success !== false,
          data: data.success !== false ? (data.data !== undefined ? data.data : data) : undefined,
          error: data.success === false ? data.error : undefined,
          metadata: data.metadata
        };
        
        console.log('[API] Returning direct result:', { 
          success: result.success, 
          hasData: !!result.data,
          dataType: typeof result.data,
          dataIsArray: Array.isArray(result.data),
          dataLength: result.data?.length 
        });
        
        return result;

      } catch (error) {
        lastError = error as Error;
        
        if (error instanceof Error && error.name === 'AbortError') {
          throw new Error('Request timeout');
        }
        
        // Don't retry on authentication errors or client errors
        if (error instanceof Error && error.message.includes('401')) {
          throw error;
        }
        
        if (attempt === (retries || 0)) {
          throw lastError;
        }
        
        // Exponential backoff
        await new Promise(resolve => 
          setTimeout(resolve, Math.pow(2, attempt) * 1000)
        );
      }
    }
    
    throw lastError;
  }

  async get<T = any>(url: string, config: RequestConfig = {}): Promise<ApiResponse<T>> {
    return this.makeRequest<T>(url, {
      ...config,
      method: 'GET',
    });
  }

  async post<T = any>(url: string, data?: any, config: RequestConfig = {}): Promise<ApiResponse<T>> {
    return this.makeRequest<T>(url, {
      ...config,
      method: 'POST',
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async put<T = any>(url: string, data?: any, config: RequestConfig = {}): Promise<ApiResponse<T>> {
    return this.makeRequest<T>(url, {
      ...config,
      method: 'PUT',
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async delete<T = any>(url: string, config: RequestConfig = {}): Promise<ApiResponse<T>> {
    return this.makeRequest<T>(url, {
      ...config,
      method: 'DELETE',
    });
  }

  // Specific API methods
  async queryRAG(request: QueryRequest): Promise<ApiResponse<QueryResponse>> {
    return this.post<QueryResponse>(apiConfig.endpoints.query, request);
  }

  async getHealthStatus(): Promise<ApiResponse<HealthStatus>> {
    return this.get<HealthStatus>(apiConfig.endpoints.health);
  }

  async uploadDocument(file: File, onProgress?: (progress: number) => void): Promise<ApiResponse<Document>> {
    try {
      // 第一阶段：获取预签名URL
      const uploadRequest = {
        filename: file.name,
        contentType: file.type,
        fileSize: file.size
      };

      const presignedResponse = await this.post<{
        uploadUrl: string;
        fileId: string;
        s3Key: string;
        bucket: string;
        expiresIn: number;
        message: string;
      }>(apiConfig.endpoints.upload, uploadRequest);

      console.log('预签名URL响应:', JSON.stringify(presignedResponse, null, 2));

      if (!presignedResponse.success || !presignedResponse.data) {
        throw new Error('获取上传URL失败');
      }

      const { uploadUrl, fileId, s3Key } = presignedResponse.data;
      
      if (!uploadUrl) {
        console.error('uploadUrl is undefined in response:', presignedResponse);
        throw new Error('预签名URL为空');
      }

      // 第二阶段：使用预签名URL上传文件到S3
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        
        if (onProgress) {
          xhr.upload.addEventListener('progress', (event) => {
            if (event.lengthComputable) {
              const progress = Math.round((event.loaded * 100) / event.total);
              onProgress(progress);
            }
          });
        }
        
        xhr.addEventListener('load', () => {
          console.log(`XHR加载完成 - Status: ${xhr.status}, StatusText: ${xhr.statusText}`);
          console.log(`Response Headers: ${xhr.getAllResponseHeaders()}`);
          console.log(`Response Text: ${xhr.responseText}`);
          
          if (xhr.status >= 200 && xhr.status < 300) {
            console.log(`文件上传到S3成功: ${file.name}, Status: ${xhr.status}`);
            
            // S3上传成功，返回文档信息
            const documentData: Document = {
              id: fileId,
              name: file.name,
              size: file.size,
              type: file.type,
              s3_key: s3Key,
              status: 'processing',
              upload_date: new Date(),
              processed_date: null,
              metadata: {
                original_filename: file.name,
                content_type: file.type,
                file_size: file.size
              }
            };

            resolve({
              success: true,
              data: documentData
            });
          } else {
            console.error(`S3上传失败: Status ${xhr.status}, Response: ${xhr.responseText}`);
            reject(new Error(`上传到S3失败 (${xhr.status}): ${xhr.statusText || '未知错误'}`));
          }
        });
        
        xhr.addEventListener('error', () => {
          console.error('文件上传网络错误');
          reject(new Error('文件上传失败：网络错误'));
        });
        
        xhr.addEventListener('timeout', () => {
          console.error('文件上传超时');
          reject(new Error('文件上传失败：请求超时'));
        });
        
        // 配置S3上传请求
        console.log(`准备上传文件到S3:
          - URL: ${uploadUrl}
          - 文件名: ${file.name}
          - 文件大小: ${file.size} bytes
          - 文件类型: ${file.type}
          - S3 Key: ${s3Key}
          - File ID: ${fileId}`);
        
        xhr.open('PUT', uploadUrl);
        xhr.setRequestHeader('Content-Type', file.type);
        xhr.timeout = 300000; // 5分钟超时
        
        console.log('开始发送文件到S3...');
        // 直接发送文件内容
        xhr.send(file);
      });

    } catch (error: any) {
      throw new Error(`文档上传失败: ${error.message || error}`);
    }
  }

  async getDocuments(): Promise<ApiResponse<Document[]>> {
    return this.get<Document[]>(apiConfig.endpoints.documents);
  }

  async deleteDocument(documentId: string): Promise<ApiResponse<void>> {
    return this.delete<void>(`${apiConfig.endpoints.documents}/${documentId}`);
  }

  async getDocumentStatus(documentId: string): Promise<ApiResponse<Document>> {
    return this.get<Document>(`${apiConfig.endpoints.documents}/${documentId}/status`);
  }

  async getKnowledgeBaseStatus(): Promise<ApiResponse<any>> {
    // Query handler now supports /status endpoint
    return this.get<any>('/query/status');
  }
}

export const apiService = new ApiService();
export default apiService;