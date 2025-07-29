import { 
  signIn, 
  signUp, 
  signOut, 
  getCurrentUser, 
  confirmSignUp,
  resendSignUpCode,
  fetchAuthSession 
} from 'aws-amplify/auth';
import { User } from '../types';

interface SignUpParams {
  username: string;
  password: string;
  email: string;
  name?: string;
}

interface SignInParams {
  username: string;
  password: string;
}

interface ConfirmSignUpParams {
  username: string;
  confirmationCode: string;
}

export class AuthService {
  async signUp({ username, password, email, name }: SignUpParams) {
    try {
      const { nextStep } = await signUp({
        username,
        password,
        options: {
          userAttributes: {
            email,
            name: name || username,
          }
        }
      });

      return {
        success: true,
        nextStep,
      };
    } catch (error) {
      console.error('Sign up failed:', error);
      throw new Error(this.getErrorMessage(error));
    }
  }

  async confirmSignUp({ username, confirmationCode }: ConfirmSignUpParams) {
    try {
      const { nextStep } = await confirmSignUp({
        username,
        confirmationCode,
      });

      return {
        success: true,
        nextStep,
      };
    } catch (error) {
      console.error('Confirm sign up failed:', error);
      throw new Error(this.getErrorMessage(error));
    }
  }

  async resendConfirmationCode(username: string) {
    try {
      await resendSignUpCode({
        username,
      });

      return {
        success: true,
        message: 'Confirmation code sent successfully',
      };
    } catch (error) {
      console.error('Resend confirmation code failed:', error);
      throw new Error(this.getErrorMessage(error));
    }
  }

  async signIn({ username, password }: SignInParams): Promise<User> {
    try {
      const { nextStep } = await signIn({
        username,
        password,
      });

      if (nextStep.signInStep === 'DONE') {
        return await this.getCurrentUser();
      } else {
        throw new Error(`Additional sign-in step required: ${nextStep.signInStep}`);
      }
    } catch (error) {
      console.error('Sign in failed:', error);
      throw new Error(this.getErrorMessage(error));
    }
  }

  async signOut(): Promise<void> {
    try {
      await signOut();
    } catch (error) {
      console.error('Sign out failed:', error);
      throw new Error(this.getErrorMessage(error));
    }
  }

  async getCurrentUser(): Promise<User> {
    try {
      const user = await getCurrentUser();
      const session = await fetchAuthSession();
      
      return {
        id: user.userId || user.username,
        email: user.username, // In Cognito, username is often the email
        name: user.username,
        groups: session.tokens?.accessToken?.payload?.['cognito:groups'] as string[] || [],
        isAuthenticated: true,
      };
    } catch (error) {
      console.error('Get current user failed:', error);
      throw new Error('User not authenticated');
    }
  }

  async getAuthSession() {
    try {
      return await fetchAuthSession();
    } catch (error) {
      console.error('Get auth session failed:', error);
      return null;
    }
  }

  async isAuthenticated(): Promise<boolean> {
    try {
      const session = await fetchAuthSession();
      return !!session.tokens?.idToken;
    } catch (error) {
      return false;
    }
  }

  async getAccessToken(): Promise<string | null> {
    try {
      const session = await fetchAuthSession();
      return session.tokens?.idToken?.toString() || null;
    } catch (error) {
      console.error('Get access token failed:', error);
      return null;
    }
  }

  private getErrorMessage(error: any): string {
    if (error?.message) {
      return error.message;
    }
    
    if (typeof error === 'string') {
      return error;
    }
    
    // Handle common Cognito errors
    if (error?.name) {
      switch (error.name) {
        case 'UserNotConfirmedException':
          return 'Please verify your email address before signing in';
        case 'NotAuthorizedException':
          return 'Invalid username or password';
        case 'UserNotFoundException':
          return 'User not found';
        case 'InvalidPasswordException':
          return 'Password does not meet requirements';
        case 'UsernameExistsException':
          return 'An account with this email already exists';
        case 'CodeMismatchException':
          return 'Invalid verification code';
        case 'ExpiredCodeException':
          return 'Verification code has expired';
        case 'LimitExceededException':
          return 'Too many attempts. Please try again later';
        default:
          return error.name;
      }
    }
    
    return 'An unknown error occurred';
  }
}

export const authService = new AuthService();
export default authService;