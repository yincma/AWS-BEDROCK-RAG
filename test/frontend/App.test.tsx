/**
 * App组件的单元测试
 */
import React from 'react';
import { render, screen, waitFor, act } from '@testing-library/react';
import '@testing-library/jest-dom';
import App from '../../applications/frontend/src/App';
import { authService } from '../../applications/frontend/src/services';

// 模拟依赖
jest.mock('../../applications/frontend/src/services', () => ({
  authService: {
    getCurrentUser: jest.fn(),
    signOut: jest.fn(),
  },
  errorService: {
    onError: jest.fn(),
    handleError: jest.fn(),
  },
  apiService: {
    updateConfig: jest.fn(),
  }
}));

jest.mock('aws-amplify', () => ({
  Amplify: {
    configure: jest.fn(),
  }
}));

// 模拟React Router
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  BrowserRouter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Navigate: ({ to }: { to: string }) => <div>Navigate to {to}</div>,
}));

// 模拟组件
jest.mock('../../applications/frontend/src/pages/LoginPage', () => {
  return function LoginPage({ onLogin }: { onLogin: Function }) {
    return (
      <div>
        Login Page
        <button onClick={() => onLogin({ username: 'testuser', email: 'test@example.com' })}>
          Login
        </button>
      </div>
    );
  };
});

jest.mock('../../applications/frontend/src/pages/ChatPage', () => {
  return function ChatPage() {
    return <div>Chat Page</div>;
  };
});

jest.mock('../../applications/frontend/src/components/MainLayout', () => {
  return function MainLayout({ children, onLogout }: { children: React.ReactNode; onLogout: Function }) {
    return (
      <div>
        Main Layout
        <button onClick={() => onLogout()}>Logout</button>
        {children}
      </div>
    );
  };
});

jest.mock('../../applications/frontend/src/components/NotificationProvider', () => {
  return function NotificationProvider({ children }: { children: React.ReactNode }) {
    return <div>{children}</div>;
  };
});

// 模拟fetch
global.fetch = jest.fn();

describe('App Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (global.fetch as jest.Mock).mockReset();
  });

  it('显示加载状态', () => {
    // 设置认证检查为pending状态
    (authService.getCurrentUser as jest.Mock).mockImplementation(() => 
      new Promise(() => {}) // 永不resolve的Promise
    );
    
    // 配置加载也设为pending
    (global.fetch as jest.Mock).mockImplementation(() => 
      new Promise(() => {})
    );

    render(<App />);
    
    expect(screen.getByRole('progressbar')).toBeInTheDocument();
  });

  it('成功加载配置并显示登录页面（未认证）', async () => {
    // 模拟配置加载成功
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        userPoolId: 'test-pool-id',
        userPoolClientId: 'test-client-id',
        region: 'us-east-1',
        apiEndpoint: 'https://api.test.com'
      })
    });

    // 模拟用户未认证
    (authService.getCurrentUser as jest.Mock).mockRejectedValueOnce(new Error('Not authenticated'));

    await act(async () => {
      render(<App />);
    });

    await waitFor(() => {
      expect(screen.getByText('Login Page')).toBeInTheDocument();
    });
  });

  it('成功加载配置并显示主页面（已认证）', async () => {
    // 模拟配置加载成功
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        userPoolId: 'test-pool-id',
        userPoolClientId: 'test-client-id',
        region: 'us-east-1',
        apiEndpoint: 'https://api.test.com'
      })
    });

    // 模拟用户已认证
    const mockUser = { username: 'testuser', email: 'test@example.com' };
    (authService.getCurrentUser as jest.Mock).mockResolvedValueOnce(mockUser);

    await act(async () => {
      render(<App />);
    });

    await waitFor(() => {
      expect(screen.getByText('Main Layout')).toBeInTheDocument();
      expect(screen.getByText('Navigate to /chat')).toBeInTheDocument();
    });
  });

  it('配置加载失败时使用默认配置', async () => {
    // 模拟配置加载失败
    (global.fetch as jest.Mock).mockRejectedValueOnce(new Error('Network error'));

    // 模拟用户未认证
    (authService.getCurrentUser as jest.Mock).mockRejectedValueOnce(new Error('Not authenticated'));

    const consoleSpy = jest.spyOn(console, 'error').mockImplementation();

    await act(async () => {
      render(<App />);
    });

    await waitFor(() => {
      expect(screen.getByText('Login Page')).toBeInTheDocument();
      expect(consoleSpy).toHaveBeenCalledWith('Error loading config:', expect.any(Error));
    });

    consoleSpy.mockRestore();
  });

  it('处理登录操作', async () => {
    // 模拟配置加载
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        userPoolId: 'test-pool-id',
        userPoolClientId: 'test-client-id',
        region: 'us-east-1',
        apiEndpoint: 'https://api.test.com'
      })
    });

    // 初始未认证
    (authService.getCurrentUser as jest.Mock).mockRejectedValueOnce(new Error('Not authenticated'));

    await act(async () => {
      render(<App />);
    });

    await waitFor(() => {
      expect(screen.getByText('Login Page')).toBeInTheDocument();
    });

    // 点击登录按钮
    await act(async () => {
      screen.getByText('Login').click();
    });

    // 应该显示主页面
    expect(screen.getByText('Main Layout')).toBeInTheDocument();
  });

  it('处理登出操作', async () => {
    // 模拟配置加载
    (global.fetch as jest.Mock).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        userPoolId: 'test-pool-id',
        userPoolClientId: 'test-client-id',
        region: 'us-east-1',
        apiEndpoint: 'https://api.test.com'
      })
    });

    // 模拟用户已认证
    const mockUser = { username: 'testuser', email: 'test@example.com' };
    (authService.getCurrentUser as jest.Mock).mockResolvedValueOnce(mockUser);
    (authService.signOut as jest.Mock).mockResolvedValueOnce(undefined);

    await act(async () => {
      render(<App />);
    });

    await waitFor(() => {
      expect(screen.getByText('Main Layout')).toBeInTheDocument();
    });

    // 点击登出按钮
    await act(async () => {
      screen.getByText('Logout').click();
    });

    // 应该调用signOut并显示登录页面
    expect(authService.signOut).toHaveBeenCalled();
    expect(screen.getByText('Login Page')).toBeInTheDocument();
  });

  it('初始化失败时显示错误信息', async () => {
    // 模拟fetch抛出异常
    (global.fetch as jest.Mock).mockImplementation(() => {
      throw new Error('Network failure');
    });

    const consoleSpy = jest.spyOn(console, 'error').mockImplementation();

    await act(async () => {
      render(<App />);
    });

    await waitFor(() => {
      expect(screen.getByText('应用初始化失败')).toBeInTheDocument();
    });

    consoleSpy.mockRestore();
  });
});