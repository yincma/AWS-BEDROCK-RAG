/**
 * ChatPage组件的单元测试
 */
import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import '@testing-library/jest-dom';
import ChatPage from '../../applications/frontend/src/pages/ChatPage';
import { apiService } from '../../applications/frontend/src/services/api';

// 模拟API服务
jest.mock('../../applications/frontend/src/services/api', () => ({
  apiService: {
    query: jest.fn(),
  }
}));

// 模拟通知context
jest.mock('../../applications/frontend/src/hooks/useNotification', () => ({
  useNotification: () => ({
    showSuccess: jest.fn(),
    showError: jest.fn(),
    showWarning: jest.fn(),
    showInfo: jest.fn(),
  })
}));

describe('ChatPage Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('渲染聊天界面的基本元素', () => {
    render(<ChatPage />);
    
    // 检查标题
    expect(screen.getByText('智能知识问答助手')).toBeInTheDocument();
    
    // 检查输入框
    expect(screen.getByPlaceholderText(/请输入您的问题/)).toBeInTheDocument();
    
    // 检查发送按钮
    expect(screen.getByRole('button', { name: /发送/ })).toBeInTheDocument();
  });

  it('显示欢迎消息', () => {
    render(<ChatPage />);
    
    expect(screen.getByText(/您好！我是您的智能助手/)).toBeInTheDocument();
  });

  it('处理用户输入', async () => {
    render(<ChatPage />);
    
    const input = screen.getByPlaceholderText(/请输入您的问题/);
    
    await act(async () => {
      fireEvent.change(input, { target: { value: '测试问题' } });
    });
    
    expect(input).toHaveValue('测试问题');
  });

  it('发送查询并显示响应', async () => {
    // 模拟API响应
    const mockResponse = {
      success: true,
      answer: '这是测试答案',
      sources: [
        {
          content: '相关内容',
          document: 's3://bucket/test.pdf',
          confidence: 0.95
        }
      ],
      metadata: {
        model_used: 'amazon.nova-pro-v1:0',
        processing_time: 1.5
      }
    };
    
    (apiService.query as jest.Mock).mockResolvedValueOnce(mockResponse);
    
    render(<ChatPage />);
    
    const input = screen.getByPlaceholderText(/请输入您的问题/);
    const sendButton = screen.getByRole('button', { name: /发送/ });
    
    // 输入问题
    await act(async () => {
      fireEvent.change(input, { target: { value: '测试问题' } });
    });
    
    // 点击发送
    await act(async () => {
      fireEvent.click(sendButton);
    });
    
    // 等待响应显示
    await waitFor(() => {
      expect(screen.getByText('测试问题')).toBeInTheDocument();
      expect(screen.getByText('这是测试答案')).toBeInTheDocument();
    });
    
    // 检查输入框已清空
    expect(input).toHaveValue('');
    
    // 检查API被正确调用
    expect(apiService.query).toHaveBeenCalledWith('测试问题', {
      top_k: 5,
      include_sources: true
    });
  });

  it('处理查询错误', async () => {
    // 模拟API错误
    (apiService.query as jest.Mock).mockRejectedValueOnce(new Error('网络错误'));
    
    render(<ChatPage />);
    
    const input = screen.getByPlaceholderText(/请输入您的问题/);
    const sendButton = screen.getByRole('button', { name: /发送/ });
    
    // 输入问题并发送
    await act(async () => {
      fireEvent.change(input, { target: { value: '测试问题' } });
      fireEvent.click(sendButton);
    });
    
    // 等待错误消息显示
    await waitFor(() => {
      expect(screen.getByText(/抱歉，我遇到了一些问题/)).toBeInTheDocument();
    });
  });

  it('在发送时禁用输入和按钮', async () => {
    // 模拟延迟响应
    (apiService.query as jest.Mock).mockImplementation(() => 
      new Promise(resolve => setTimeout(resolve, 1000))
    );
    
    render(<ChatPage />);
    
    const input = screen.getByPlaceholderText(/请输入您的问题/);
    const sendButton = screen.getByRole('button', { name: /发送/ });
    
    // 输入问题并发送
    await act(async () => {
      fireEvent.change(input, { target: { value: '测试问题' } });
      fireEvent.click(sendButton);
    });
    
    // 检查输入和按钮被禁用
    expect(input).toBeDisabled();
    expect(sendButton).toBeDisabled();
    
    // 显示加载状态
    expect(screen.getByText(/正在思考中/)).toBeInTheDocument();
  });

  it('使用Enter键发送消息', async () => {
    (apiService.query as jest.Mock).mockResolvedValueOnce({
      success: true,
      answer: '测试答案',
      sources: [],
      metadata: {}
    });
    
    render(<ChatPage />);
    
    const input = screen.getByPlaceholderText(/请输入您的问题/);
    
    // 输入问题
    await act(async () => {
      fireEvent.change(input, { target: { value: '测试问题' } });
    });
    
    // 按Enter键
    await act(async () => {
      fireEvent.keyPress(input, { key: 'Enter', code: 'Enter', charCode: 13 });
    });
    
    // 检查消息已发送
    await waitFor(() => {
      expect(apiService.query).toHaveBeenCalled();
      expect(screen.getByText('测试问题')).toBeInTheDocument();
    });
  });

  it('阻止发送空消息', async () => {
    render(<ChatPage />);
    
    const sendButton = screen.getByRole('button', { name: /发送/ });
    
    // 不输入任何内容直接点击发送
    await act(async () => {
      fireEvent.click(sendButton);
    });
    
    // 确保API没有被调用
    expect(apiService.query).not.toHaveBeenCalled();
  });

  it('显示消息来源信息', async () => {
    const mockResponse = {
      success: true,
      answer: '这是答案',
      sources: [
        {
          content: '参考内容1',
          document: 's3://bucket/doc1.pdf',
          confidence: 0.98
        },
        {
          content: '参考内容2',
          document: 's3://bucket/doc2.pdf',
          confidence: 0.85
        }
      ],
      metadata: {
        processing_time: 2.1
      }
    };
    
    (apiService.query as jest.Mock).mockResolvedValueOnce(mockResponse);
    
    render(<ChatPage />);
    
    // 发送查询
    await act(async () => {
      const input = screen.getByPlaceholderText(/请输入您的问题/);
      fireEvent.change(input, { target: { value: '测试' } });
      fireEvent.click(screen.getByRole('button', { name: /发送/ }));
    });
    
    // 等待响应
    await waitFor(() => {
      expect(screen.getByText('这是答案')).toBeInTheDocument();
    });
    
    // 检查来源信息显示
    expect(screen.getByText(/参考来源/)).toBeInTheDocument();
    expect(screen.getByText(/doc1.pdf/)).toBeInTheDocument();
    expect(screen.getByText(/98%/)).toBeInTheDocument();
  });

  it('清空对话历史', async () => {
    // 添加一些消息
    (apiService.query as jest.Mock).mockResolvedValueOnce({
      success: true,
      answer: '答案1',
      sources: [],
      metadata: {}
    });
    
    render(<ChatPage />);
    
    // 发送第一条消息
    await act(async () => {
      const input = screen.getByPlaceholderText(/请输入您的问题/);
      fireEvent.change(input, { target: { value: '问题1' } });
      fireEvent.click(screen.getByRole('button', { name: /发送/ }));
    });
    
    await waitFor(() => {
      expect(screen.getByText('问题1')).toBeInTheDocument();
      expect(screen.getByText('答案1')).toBeInTheDocument();
    });
    
    // 点击清空按钮
    const clearButton = screen.getByRole('button', { name: /清空对话/ });
    await act(async () => {
      fireEvent.click(clearButton);
    });
    
    // 确认对话已清空，只剩欢迎消息
    expect(screen.queryByText('问题1')).not.toBeInTheDocument();
    expect(screen.queryByText('答案1')).not.toBeInTheDocument();
    expect(screen.getByText(/您好！我是您的智能助手/)).toBeInTheDocument();
  });
});