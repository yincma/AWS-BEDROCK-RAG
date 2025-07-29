/**
 * DocumentsPage组件的单元测试
 */
import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import '@testing-library/jest-dom';
import DocumentsPage from '../../applications/frontend/src/pages/DocumentsPage';
import { apiService } from '../../applications/frontend/src/services/api';

// 模拟API服务
jest.mock('../../applications/frontend/src/services/api', () => ({
  apiService: {
    uploadDocument: jest.fn(),
    listDocuments: jest.fn(),
    deleteDocument: jest.fn(),
    getUploadUrl: jest.fn(),
  }
}));

// 模拟通知hook
jest.mock('../../applications/frontend/src/hooks/useNotification', () => ({
  useNotification: () => ({
    showSuccess: jest.fn(),
    showError: jest.fn(),
    showWarning: jest.fn(),
    showInfo: jest.fn(),
  })
}));

describe('DocumentsPage Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('渲染文档管理界面的基本元素', () => {
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ documents: [] });
    
    render(<DocumentsPage />);
    
    expect(screen.getByText('文档管理')).toBeInTheDocument();
    expect(screen.getByText('上传文档')).toBeInTheDocument();
    expect(screen.getByText(/支持的文件格式/)).toBeInTheDocument();
  });

  it('加载并显示文档列表', async () => {
    const mockDocuments = [
      {
        id: 'doc1',
        name: '测试文档1.pdf',
        size: 1024000,
        uploadDate: '2024-01-01T00:00:00Z',
        status: 'processed'
      },
      {
        id: 'doc2',
        name: '测试文档2.docx',
        size: 2048000,
        uploadDate: '2024-01-02T00:00:00Z',
        status: 'processing'
      }
    ];
    
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ 
      documents: mockDocuments 
    });
    
    await act(async () => {
      render(<DocumentsPage />);
    });
    
    await waitFor(() => {
      expect(screen.getByText('测试文档1.pdf')).toBeInTheDocument();
      expect(screen.getByText('测试文档2.docx')).toBeInTheDocument();
      expect(screen.getByText('已处理')).toBeInTheDocument();
      expect(screen.getByText('处理中')).toBeInTheDocument();
    });
  });

  it('处理文件上传', async () => {
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ documents: [] });
    (apiService.getUploadUrl as jest.Mock).mockResolvedValueOnce({
      uploadUrl: 'https://s3.amazonaws.com/upload',
      documentId: 'new-doc-id'
    });
    (apiService.uploadDocument as jest.Mock).mockResolvedValueOnce({ success: true });
    
    render(<DocumentsPage />);
    
    // 创建测试文件
    const file = new File(['test content'], 'test.pdf', { type: 'application/pdf' });
    const fileInput = screen.getByLabelText(/选择文件/);
    
    // 模拟文件选择
    await act(async () => {
      fireEvent.change(fileInput, { target: { files: [file] } });
    });
    
    // 等待文件显示在列表中
    await waitFor(() => {
      expect(screen.getByText('test.pdf')).toBeInTheDocument();
    });
    
    // 点击上传按钮
    const uploadButton = screen.getByRole('button', { name: /开始上传/ });
    await act(async () => {
      fireEvent.click(uploadButton);
    });
    
    // 验证上传流程
    await waitFor(() => {
      expect(apiService.getUploadUrl).toHaveBeenCalled();
      expect(apiService.uploadDocument).toHaveBeenCalledWith(
        'new-doc-id',
        file,
        'https://s3.amazonaws.com/upload'
      );
    });
  });

  it('验证文件类型限制', async () => {
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ documents: [] });
    
    render(<DocumentsPage />);
    
    // 创建不支持的文件类型
    const file = new File(['test'], 'test.exe', { type: 'application/x-exe' });
    const fileInput = screen.getByLabelText(/选择文件/);
    
    await act(async () => {
      fireEvent.change(fileInput, { target: { files: [file] } });
    });
    
    // 应该显示错误消息
    await waitFor(() => {
      expect(screen.getByText(/不支持的文件类型/)).toBeInTheDocument();
    });
  });

  it('验证文件大小限制', async () => {
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ documents: [] });
    
    render(<DocumentsPage />);
    
    // 创建超大文件（模拟101MB）
    const largeContent = new Array(101 * 1024 * 1024).fill('a').join('');
    const file = new File([largeContent], 'large.pdf', { type: 'application/pdf' });
    Object.defineProperty(file, 'size', { value: 101 * 1024 * 1024 });
    
    const fileInput = screen.getByLabelText(/选择文件/);
    
    await act(async () => {
      fireEvent.change(fileInput, { target: { files: [file] } });
    });
    
    // 应该显示错误消息
    await waitFor(() => {
      expect(screen.getByText(/文件大小超过限制/)).toBeInTheDocument();
    });
  });

  it('删除文档', async () => {
    const mockDocuments = [
      {
        id: 'doc1',
        name: '要删除的文档.pdf',
        size: 1024000,
        uploadDate: '2024-01-01T00:00:00Z',
        status: 'processed'
      }
    ];
    
    (apiService.listDocuments as jest.Mock)
      .mockResolvedValueOnce({ documents: mockDocuments })
      .mockResolvedValueOnce({ documents: [] });
    
    (apiService.deleteDocument as jest.Mock).mockResolvedValueOnce({ success: true });
    
    await act(async () => {
      render(<DocumentsPage />);
    });
    
    // 等待文档加载
    await waitFor(() => {
      expect(screen.getByText('要删除的文档.pdf')).toBeInTheDocument();
    });
    
    // 点击删除按钮
    const deleteButton = screen.getByRole('button', { name: /删除/ });
    await act(async () => {
      fireEvent.click(deleteButton);
    });
    
    // 确认删除对话框
    const confirmButton = screen.getByRole('button', { name: /确认删除/ });
    await act(async () => {
      fireEvent.click(confirmButton);
    });
    
    // 验证删除API被调用
    expect(apiService.deleteDocument).toHaveBeenCalledWith('doc1');
    
    // 文档应该从列表中消失
    await waitFor(() => {
      expect(screen.queryByText('要删除的文档.pdf')).not.toBeInTheDocument();
    });
  });

  it('处理多文件上传', async () => {
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ documents: [] });
    
    render(<DocumentsPage />);
    
    // 创建多个测试文件
    const files = [
      new File(['content1'], 'file1.pdf', { type: 'application/pdf' }),
      new File(['content2'], 'file2.docx', { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }),
      new File(['content3'], 'file3.txt', { type: 'text/plain' })
    ];
    
    const fileInput = screen.getByLabelText(/选择文件/);
    
    await act(async () => {
      fireEvent.change(fileInput, { target: { files } });
    });
    
    // 所有文件都应该显示在待上传列表中
    await waitFor(() => {
      expect(screen.getByText('file1.pdf')).toBeInTheDocument();
      expect(screen.getByText('file2.docx')).toBeInTheDocument();
      expect(screen.getByText('file3.txt')).toBeInTheDocument();
    });
  });

  it('显示上传进度', async () => {
    (apiService.listDocuments as jest.Mock).mockResolvedValueOnce({ documents: [] });
    (apiService.getUploadUrl as jest.Mock).mockResolvedValueOnce({
      uploadUrl: 'https://s3.amazonaws.com/upload',
      documentId: 'new-doc-id'
    });
    
    // 模拟延迟上传
    (apiService.uploadDocument as jest.Mock).mockImplementation(() => 
      new Promise(resolve => setTimeout(() => resolve({ success: true }), 100))
    );
    
    render(<DocumentsPage />);
    
    const file = new File(['test'], 'test.pdf', { type: 'application/pdf' });
    const fileInput = screen.getByLabelText(/选择文件/);
    
    await act(async () => {
      fireEvent.change(fileInput, { target: { files: [file] } });
    });
    
    const uploadButton = screen.getByRole('button', { name: /开始上传/ });
    await act(async () => {
      fireEvent.click(uploadButton);
    });
    
    // 应该显示上传进度
    expect(screen.getByRole('progressbar')).toBeInTheDocument();
    
    // 等待上传完成
    await waitFor(() => {
      expect(screen.queryByRole('progressbar')).not.toBeInTheDocument();
    });
  });

  it('刷新文档列表', async () => {
    const initialDocs = [{ id: 'doc1', name: '初始文档.pdf', size: 1024, uploadDate: '2024-01-01', status: 'processed' }];
    const updatedDocs = [
      ...initialDocs,
      { id: 'doc2', name: '新文档.pdf', size: 2048, uploadDate: '2024-01-02', status: 'processed' }
    ];
    
    (apiService.listDocuments as jest.Mock)
      .mockResolvedValueOnce({ documents: initialDocs })
      .mockResolvedValueOnce({ documents: updatedDocs });
    
    await act(async () => {
      render(<DocumentsPage />);
    });
    
    // 初始只有一个文档
    expect(screen.getByText('初始文档.pdf')).toBeInTheDocument();
    expect(screen.queryByText('新文档.pdf')).not.toBeInTheDocument();
    
    // 点击刷新按钮
    const refreshButton = screen.getByRole('button', { name: /刷新/ });
    await act(async () => {
      fireEvent.click(refreshButton);
    });
    
    // 应该显示新文档
    await waitFor(() => {
      expect(screen.getByText('新文档.pdf')).toBeInTheDocument();
    });
  });
});