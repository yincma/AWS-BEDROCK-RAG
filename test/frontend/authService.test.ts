/**
 * authService的单元测试
 */
import { authService } from '../../applications/frontend/src/services/auth';
import { Auth } from 'aws-amplify';

// 模拟aws-amplify
jest.mock('aws-amplify', () => ({
  Auth: {
    signIn: jest.fn(),
    signOut: jest.fn(),
    currentAuthenticatedUser: jest.fn(),
    currentSession: jest.fn(),
    signUp: jest.fn(),
    confirmSignUp: jest.fn(),
    resendSignUp: jest.fn(),
    forgotPassword: jest.fn(),
    forgotPasswordSubmit: jest.fn(),
    changePassword: jest.fn(),
  }
}));

describe('authService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('signIn', () => {
    it('成功登录', async () => {
      const mockUser = {
        username: 'testuser',
        attributes: {
          email: 'test@example.com'
        }
      };
      
      (Auth.signIn as jest.Mock).mockResolvedValueOnce(mockUser);
      
      const result = await authService.signIn('testuser', 'password123');
      
      expect(Auth.signIn).toHaveBeenCalledWith('testuser', 'password123');
      expect(result).toEqual({
        username: 'testuser',
        email: 'test@example.com'
      });
    });

    it('处理登录错误', async () => {
      (Auth.signIn as jest.Mock).mockRejectedValueOnce(new Error('Invalid credentials'));
      
      await expect(authService.signIn('testuser', 'wrongpass')).rejects.toThrow('Invalid credentials');
    });
  });

  describe('signOut', () => {
    it('成功登出', async () => {
      (Auth.signOut as jest.Mock).mockResolvedValueOnce(undefined);
      
      await authService.signOut();
      
      expect(Auth.signOut).toHaveBeenCalled();
    });

    it('处理登出错误', async () => {
      (Auth.signOut as jest.Mock).mockRejectedValueOnce(new Error('Network error'));
      
      await expect(authService.signOut()).rejects.toThrow('Network error');
    });
  });

  describe('getCurrentUser', () => {
    it('获取当前认证用户', async () => {
      const mockUser = {
        username: 'currentuser',
        attributes: {
          email: 'current@example.com'
        }
      };
      
      (Auth.currentAuthenticatedUser as jest.Mock).mockResolvedValueOnce(mockUser);
      
      const result = await authService.getCurrentUser();
      
      expect(result).toEqual({
        username: 'currentuser',
        email: 'current@example.com'
      });
    });

    it('处理未认证状态', async () => {
      (Auth.currentAuthenticatedUser as jest.Mock).mockRejectedValueOnce(new Error('No authenticated user'));
      
      await expect(authService.getCurrentUser()).rejects.toThrow('No authenticated user');
    });
  });

  describe('getAccessToken', () => {
    it('获取访问令牌', async () => {
      const mockSession = {
        getIdToken: () => ({
          getJwtToken: () => 'mock-jwt-token'
        })
      };
      
      (Auth.currentSession as jest.Mock).mockResolvedValueOnce(mockSession);
      
      const token = await authService.getAccessToken();
      
      expect(token).toBe('mock-jwt-token');
    });

    it('处理会话过期', async () => {
      (Auth.currentSession as jest.Mock).mockRejectedValueOnce(new Error('Session expired'));
      
      await expect(authService.getAccessToken()).rejects.toThrow('Session expired');
    });
  });

  describe('signUp', () => {
    it('成功注册', async () => {
      const mockSignUpResult = {
        user: {},
        userConfirmed: false,
        userSub: 'user-sub-123'
      };
      
      (Auth.signUp as jest.Mock).mockResolvedValueOnce(mockSignUpResult);
      
      const result = await authService.signUp('newuser', 'password123', 'new@example.com');
      
      expect(Auth.signUp).toHaveBeenCalledWith({
        username: 'newuser',
        password: 'password123',
        attributes: {
          email: 'new@example.com'
        }
      });
      expect(result).toEqual(mockSignUpResult);
    });

    it('处理注册错误', async () => {
      (Auth.signUp as jest.Mock).mockRejectedValueOnce(new Error('Username already exists'));
      
      await expect(authService.signUp('existinguser', 'pass', 'email@test.com'))
        .rejects.toThrow('Username already exists');
    });
  });

  describe('confirmSignUp', () => {
    it('成功确认注册', async () => {
      (Auth.confirmSignUp as jest.Mock).mockResolvedValueOnce('SUCCESS');
      
      const result = await authService.confirmSignUp('testuser', '123456');
      
      expect(Auth.confirmSignUp).toHaveBeenCalledWith('testuser', '123456');
      expect(result).toBe('SUCCESS');
    });

    it('处理无效确认码', async () => {
      (Auth.confirmSignUp as jest.Mock).mockRejectedValueOnce(new Error('Invalid code'));
      
      await expect(authService.confirmSignUp('testuser', '000000'))
        .rejects.toThrow('Invalid code');
    });
  });

  describe('forgotPassword', () => {
    it('成功发送密码重置邮件', async () => {
      (Auth.forgotPassword as jest.Mock).mockResolvedValueOnce({ CodeDeliveryDetails: {} });
      
      await authService.forgotPassword('testuser');
      
      expect(Auth.forgotPassword).toHaveBeenCalledWith('testuser');
    });

    it('处理用户不存在', async () => {
      (Auth.forgotPassword as jest.Mock).mockRejectedValueOnce(new Error('User not found'));
      
      await expect(authService.forgotPassword('nonexistent'))
        .rejects.toThrow('User not found');
    });
  });

  describe('forgotPasswordSubmit', () => {
    it('成功重置密码', async () => {
      (Auth.forgotPasswordSubmit as jest.Mock).mockResolvedValueOnce('SUCCESS');
      
      const result = await authService.forgotPasswordSubmit('testuser', '123456', 'newpass123');
      
      expect(Auth.forgotPasswordSubmit).toHaveBeenCalledWith('testuser', '123456', 'newpass123');
      expect(result).toBe('SUCCESS');
    });

    it('处理密码重置失败', async () => {
      (Auth.forgotPasswordSubmit as jest.Mock).mockRejectedValueOnce(new Error('Invalid code'));
      
      await expect(authService.forgotPasswordSubmit('testuser', '000000', 'newpass'))
        .rejects.toThrow('Invalid code');
    });
  });

  describe('changePassword', () => {
    it('成功更改密码', async () => {
      const mockUser = { username: 'testuser' };
      (Auth.currentAuthenticatedUser as jest.Mock).mockResolvedValueOnce(mockUser);
      (Auth.changePassword as jest.Mock).mockResolvedValueOnce('SUCCESS');
      
      const result = await authService.changePassword('oldpass123', 'newpass123');
      
      expect(Auth.changePassword).toHaveBeenCalledWith(mockUser, 'oldpass123', 'newpass123');
      expect(result).toBe('SUCCESS');
    });

    it('处理密码更改失败', async () => {
      const mockUser = { username: 'testuser' };
      (Auth.currentAuthenticatedUser as jest.Mock).mockResolvedValueOnce(mockUser);
      (Auth.changePassword as jest.Mock).mockRejectedValueOnce(new Error('Incorrect password'));
      
      await expect(authService.changePassword('wrongpass', 'newpass'))
        .rejects.toThrow('Incorrect password');
    });
  });

  describe('resendSignUp', () => {
    it('成功重新发送确认码', async () => {
      (Auth.resendSignUp as jest.Mock).mockResolvedValueOnce({ CodeDeliveryDetails: {} });
      
      await authService.resendSignUp('testuser');
      
      expect(Auth.resendSignUp).toHaveBeenCalledWith('testuser');
    });

    it('处理重新发送失败', async () => {
      (Auth.resendSignUp as jest.Mock).mockRejectedValueOnce(new Error('User already confirmed'));
      
      await expect(authService.resendSignUp('confirmeduser'))
        .rejects.toThrow('User already confirmed');
    });
  });
});