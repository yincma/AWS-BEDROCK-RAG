/**
 * Frontend performance optimization toolkit
 * Includes lazy loading, caching, debouncing, throttling and other optimization measures
 */

import React, { lazy, Suspense, ComponentType, useState, useEffect, useRef, useCallback } from 'react';
import { CircularProgress, Box } from '@mui/material';

// Route lazy loading wrapper
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

// Loading placeholder component
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

// Route lazy loading exports
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
 * API request cache class
 * Provides memory caching and request deduplication functionality
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
    
    // Check if expired
    if (Date.now() - cached.timestamp > this.ttl) {
      this.cache.delete(key);
      return null;
    }
    
    return cached.data;
  }
  
  set(key: string, data: any, etag?: string): void {
    // Implement LRU strategy
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
  
  // Clear cache by pattern
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

// Global cache instance
export const apiCache = new ApiCache();

/**
 * Request deduplicator manager
 * Prevents multiple identical requests from being made simultaneously
 */
class RequestDeduplicator {
  private pendingRequests: Map<string, Promise<any>> = new Map();
  
  async deduplicate<T>(
    key: string,
    requestFunc: () => Promise<T>
  ): Promise<T> {
    // Check if the same request is in progress
    const pending = this.pendingRequests.get(key);
    if (pending) {
      return pending;
    }
    
    // Initiate new request
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
 * Enhanced fetch function
 * Includes caching, deduplication, retry and other features
 */
export async function enhancedFetch(
  url: string,
  options: RequestInit = {}
): Promise<any> {
  const method = options.method || 'GET';
  const cacheKey = `${method}:${url}:${JSON.stringify(options.body || {})}`;
  
  // Check cache for GET requests
  if (method === 'GET') {
    const cached = apiCache.get(cacheKey);
    if (cached) {
      return Promise.resolve(cached);
    }
    
    // Add ETag support
    const etag = apiCache.getEtag(cacheKey);
    if (etag) {
      options.headers = {
        ...options.headers,
        'If-None-Match': etag
      };
    }
  }
  
  // Request deduplication
  return requestDeduplicator.deduplicate(cacheKey, async () => {
    const response = await fetch(url, options);
    
    // Handle 304 Not Modified
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
    
    // Cache GET request results
    if (method === 'GET') {
      const etag = response.headers.get('etag');
      apiCache.set(cacheKey, data, etag || undefined);
    }
    
    return data;
  });
}

/**
 * Debounce function
 * Delay execution to reduce frequent calls
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
 * Throttle function
 * Limit execution frequency
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
 * Virtual scroll hook
 * Used for long list performance optimization
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
 * Image lazy loading hook
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
 * Performance monitoring class
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
    
    // Send performance data (can be integrated with analytics service)
    if (window.gtag) {
      window.gtag('event', 'timing_complete', {
        name,
        value: Math.round(duration)
      });
    }
    
    return duration;
  }
  
  // Monitor component render time
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
 * Web Worker manager
 * Used to move compute-intensive tasks to background threads
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


// Extend window type to support gtag
declare global {
  interface Window {
    gtag?: (...args: any[]) => void;
  }
}