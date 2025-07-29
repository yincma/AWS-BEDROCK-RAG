/**
 * 前端性能优化工具集
 * 包含懒加载、缓存、防抖、节流等优化措施
 */

import React, { lazy, Suspense, ComponentType, useState, useEffect, useRef, useCallback } from 'react';
import { CircularProgress, Box } from '@mui/material';

// 路由懒加载包装器
export function lazyLoad<T extends ComponentType<any>>(
  importFunc: () => Promise<{ default: T }>,
  fallback: React.ReactNode = <LoadingFallback />
) {
  const LazyComponent = lazy(importFunc);
  
  return (props: any) => (
    <Suspense fallback={fallback}>
      <LazyComponent {...props} />
    </Suspense>
  );
}

// 加载占位组件
function LoadingFallback() {
  return (
    <Box 
      display="flex" 
      justifyContent="center" 
      alignItems="center" 
      minHeight="400px"
    >
      <CircularProgress />
    </Box>
  );
}

// 路由懒加载导出
export const LazyChat = lazyLoad(
  () => import(/* webpackChunkName: "chat" */ '../pages/ChatPage')
);

export const LazyDocuments = lazyLoad(
  () => import(/* webpackChunkName: "documents" */ '../pages/DocumentsPage')
);

export const LazyLogin = lazyLoad(
  () => import(/* webpackChunkName: "login" */ '../pages/LoginPage')
);

/**
 * API请求缓存类
 * 提供内存缓存和请求去重功能
 */
export class ApiCache {
  private cache: Map<string, { data: any; timestamp: number; etag?: string }>;
  private ttl: number;
  private maxSize: number;
  
  constructor(ttl: number = 5 * 60 * 1000, maxSize: number = 100) {
    this.cache = new Map();
    this.ttl = ttl;
    this.maxSize = maxSize;
  }
  
  get(key: string): any | null {
    const cached = this.cache.get(key);
    if (!cached) return null;
    
    // 检查是否过期
    if (Date.now() - cached.timestamp > this.ttl) {
      this.cache.delete(key);
      return null;
    }
    
    return cached.data;
  }
  
  set(key: string, data: any, etag?: string): void {
    // 实施LRU策略
    if (this.cache.size >= this.maxSize && !this.cache.has(key)) {
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
    }
    
    this.cache.set(key, {
      data,
      timestamp: Date.now(),
      etag
    });
  }
  
  getEtag(key: string): string | undefined {
    const cached = this.cache.get(key);
    return cached?.etag;
  }
  
  clear(): void {
    this.cache.clear();
  }
  
  delete(key: string): void {
    this.cache.delete(key);
  }
  
  // 根据模式清除缓存
  clearByPattern(pattern: RegExp): void {
    const keysToDelete: string[] = [];
    
    this.cache.forEach((_, key) => {
      if (pattern.test(key)) {
        keysToDelete.push(key);
      }
    });
    
    keysToDelete.forEach(key => this.cache.delete(key));
  }
}

// 全局缓存实例
export const apiCache = new ApiCache();

/**
 * 请求去重管理器
 * 防止同时发起多个相同请求
 */
class RequestDeduplicator {
  private pendingRequests: Map<string, Promise<any>> = new Map();
  
  async deduplicate<T>(
    key: string,
    requestFunc: () => Promise<T>
  ): Promise<T> {
    // 检查是否有相同的请求正在进行
    const pending = this.pendingRequests.get(key);
    if (pending) {
      return pending;
    }
    
    // 发起新请求
    const promise = requestFunc()
      .then(result => {
        this.pendingRequests.delete(key);
        return result;
      })
      .catch(error => {
        this.pendingRequests.delete(key);
        throw error;
      });
    
    this.pendingRequests.set(key, promise);
    return promise;
  }
}

const requestDeduplicator = new RequestDeduplicator();

/**
 * 增强的fetch函数
 * 包含缓存、去重、重试等功能
 */
export async function enhancedFetch(
  url: string,
  options: RequestInit = {}
): Promise<any> {
  const method = options.method || 'GET';
  const cacheKey = `${method}:${url}:${JSON.stringify(options.body || {})}`;
  
  // GET请求检查缓存
  if (method === 'GET') {
    const cached = apiCache.get(cacheKey);
    if (cached) {
      return Promise.resolve(cached);
    }
    
    // 添加ETag支持
    const etag = apiCache.getEtag(cacheKey);
    if (etag) {
      options.headers = {
        ...options.headers,
        'If-None-Match': etag
      };
    }
  }
  
  // 请求去重
  return requestDeduplicator.deduplicate(cacheKey, async () => {
    const response = await fetch(url, options);
    
    // 处理304 Not Modified
    if (response.status === 304) {
      const cached = apiCache.get(cacheKey);
      if (cached) {
        return cached;
      }
    }
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const data = await response.json();
    
    // 缓存GET请求结果
    if (method === 'GET') {
      const etag = response.headers.get('etag');
      apiCache.set(cacheKey, data, etag || undefined);
    }
    
    return data;
  });
}

/**
 * 防抖函数
 * 延迟执行，减少频繁调用
 */
export function debounce<F extends (...args: any[]) => any>(
  func: F,
  delay: number
): (...args: Parameters<F>) => void {
  let timeoutId: NodeJS.Timeout;
  
  return function debounced(...args: Parameters<F>) {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => func(...args), delay);
  };
}

/**
 * 节流函数
 * 限制执行频率
 */
export function throttle<F extends (...args: any[]) => any>(
  func: F,
  limit: number
): (...args: Parameters<F>) => void {
  let inThrottle: boolean;
  let lastResult: any;
  
  return function throttled(...args: Parameters<F>): any {
    if (!inThrottle) {
      inThrottle = true;
      lastResult = func(...args);
      
      setTimeout(() => {
        inThrottle = false;
      }, limit);
    }
    
    return lastResult;
  };
}

/**
 * 虚拟滚动Hook
 * 用于长列表性能优化
 */
export function useVirtualScroll<T>(
  items: T[],
  itemHeight: number,
  containerHeight: number,
  overscan: number = 3
) {
  const [scrollTop, setScrollTop] = useState(0);
  
  const startIndex = Math.max(0, Math.floor(scrollTop / itemHeight) - overscan);
  const endIndex = Math.min(
    items.length - 1,
    Math.ceil((scrollTop + containerHeight) / itemHeight) + overscan
  );
  
  const visibleItems = items.slice(startIndex, endIndex + 1);
  const totalHeight = items.length * itemHeight;
  const offsetY = startIndex * itemHeight;
  
  const handleScroll = useCallback((e: React.UIEvent<HTMLDivElement>) => {
    setScrollTop(e.currentTarget.scrollTop);
  }, []);
  
  return {
    visibleItems,
    totalHeight,
    offsetY,
    handleScroll
  };
}

/**
 * 图片懒加载Hook
 */
export function useImageLazyLoad(threshold: number = 0.1) {
  const [isIntersecting, setIsIntersecting] = useState(false);
  const ref = useRef<HTMLElement>(null);
  
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsIntersecting(true);
          observer.disconnect();
        }
      },
      { threshold }
    );
    
    observer.observe(element);
    
    return () => observer.disconnect();
  }, [threshold]);
  
  return { ref, isIntersecting };
}

/**
 * 性能监控类
 */
export class PerformanceMonitor {
  private marks: Map<string, number> = new Map();
  
  mark(name: string): void {
    this.marks.set(name, performance.now());
  }
  
  measure(name: string, startMark: string, endMark?: string): number {
    const start = this.marks.get(startMark);
    if (!start) {
      console.warn(`Mark ${startMark} not found`);
      return 0;
    }
    
    const end = endMark ? this.marks.get(endMark) : performance.now();
    if (!end) {
      console.warn(`Mark ${endMark} not found`);
      return 0;
    }
    
    const duration = end - start;
    
    // 发送性能数据（可以集成到分析服务）
    if (window.gtag) {
      window.gtag('event', 'timing_complete', {
        name,
        value: Math.round(duration)
      });
    }
    
    return duration;
  }
  
  // 监控组件渲染时间
  measureComponent(componentName: string): () => void {
    const startMark = `${componentName}_start`;
    this.mark(startMark);
    
    return () => {
      const duration = this.measure(`${componentName}_render`, startMark);
      if (duration > 100) {
        console.warn(`Slow component render: ${componentName} took ${duration.toFixed(2)}ms`);
      }
    };
  }
}

export const performanceMonitor = new PerformanceMonitor();

/**
 * Web Worker管理器
 * 用于将计算密集型任务移至后台线程
 */
export class WorkerManager {
  private workers: Map<string, Worker> = new Map();
  
  createWorker(name: string, workerScript: string): Worker {
    if (this.workers.has(name)) {
      return this.workers.get(name)!;
    }
    
    const worker = new Worker(workerScript);
    this.workers.set(name, worker);
    return worker;
  }
  
  async runTask<T, R>(
    workerName: string,
    task: T
  ): Promise<R> {
    const worker = this.workers.get(workerName);
    if (!worker) {
      throw new Error(`Worker ${workerName} not found`);
    }
    
    return new Promise((resolve, reject) => {
      const messageHandler = (event: MessageEvent) => {
        worker.removeEventListener('message', messageHandler);
        worker.removeEventListener('error', errorHandler);
        resolve(event.data);
      };
      
      const errorHandler = (error: ErrorEvent) => {
        worker.removeEventListener('message', messageHandler);
        worker.removeEventListener('error', errorHandler);
        reject(error);
      };
      
      worker.addEventListener('message', messageHandler);
      worker.addEventListener('error', errorHandler);
      worker.postMessage(task);
    });
  }
  
  terminateWorker(name: string): void {
    const worker = this.workers.get(name);
    if (worker) {
      worker.terminate();
      this.workers.delete(name);
    }
  }
  
  terminateAll(): void {
    this.workers.forEach(worker => worker.terminate());
    this.workers.clear();
  }
}


// 扩展window类型以支持gtag
declare global {
  interface Window {
    gtag?: (...args: any[]) => void;
  }
}