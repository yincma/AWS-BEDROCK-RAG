import React, { useState } from 'react';
import {
  AppBar,
  Toolbar,
  Typography,
  Button,
  Box,
  Avatar,
  Menu,
  MenuItem,
  IconButton,
  Divider
} from '@mui/material';
import {
  Chat as ChatIcon,
  Description as DocumentsIcon,
  AccountCircle as AccountIcon,
  Logout as LogoutIcon
} from '@mui/icons-material';
import { useNavigate, useLocation } from 'react-router-dom';
import { signOut } from 'aws-amplify/auth';
import { User } from '../types';

interface NavigationProps {
  user: User;
  onLogout: () => void;
}

const Navigation: React.FC<NavigationProps> = ({ user, onLogout }) => {
  const navigate = useNavigate();
  const location = useLocation();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);

  const handleProfileClick = (event: React.MouseEvent<HTMLElement>) => {
    setAnchorEl(event.currentTarget);
  };

  const handleProfileClose = () => {
    setAnchorEl(null);
  };

  const handleLogout = async () => {
    try {
      await signOut();
      onLogout();
      handleProfileClose();
    } catch (error) {
      console.error('Logout error:', error);
      onLogout();
      handleProfileClose();
    }
  };

  const isCurrentPath = (path: string) => {
    return location.pathname === path;
  };

  return (
    <AppBar position="sticky" elevation={2}>
      <Toolbar>
        <Typography 
          variant="h6" 
          component="div" 
          sx={{ 
            flexGrow: 0, 
            mr: 4,
            fontWeight: 600,
            color: 'white'
          }}
        >
          Enterprise RAG
        </Typography>
        
        <Box sx={{ flexGrow: 1, display: 'flex', gap: 1 }}>
          <Button 
            color="inherit"
            startIcon={<ChatIcon />}
            onClick={() => navigate('/chat')}
            variant={isCurrentPath('/chat') ? 'outlined' : 'text'}
            sx={{ 
              color: 'white',
              borderColor: isCurrentPath('/chat') ? 'rgba(255,255,255,0.5)' : 'transparent',
              '&:hover': {
                backgroundColor: 'rgba(255,255,255,0.1)'
              }
            }}
          >
            Chat
          </Button>
          
          <Button 
            color="inherit"
            startIcon={<DocumentsIcon />}
            onClick={() => navigate('/documents')}
            variant={isCurrentPath('/documents') ? 'outlined' : 'text'}
            sx={{ 
              color: 'white',
              borderColor: isCurrentPath('/documents') ? 'rgba(255,255,255,0.5)' : 'transparent',
              '&:hover': {
                backgroundColor: 'rgba(255,255,255,0.1)'
              }
            }}
          >
            Documents
          </Button>
        </Box>
        
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Typography variant="body2" sx={{ color: 'rgba(255,255,255,0.9)' }}>
              {user.name || user.email}
            </Typography>
            
            <IconButton
              onClick={handleProfileClick}
              sx={{ p: 0 }}
            >
              <Avatar 
                sx={{ 
                  width: 32, 
                  height: 32, 
                  bgcolor: 'secondary.main',
                  fontSize: '14px'
                }}
              >
                {(user.name || user.email).charAt(0).toUpperCase()}
              </Avatar>
            </IconButton>
          </Box>
        </Box>
        
        <Menu
          anchorEl={anchorEl}
          open={Boolean(anchorEl)}
          onClose={handleProfileClose}
          onClick={handleProfileClose}
          PaperProps={{
            elevation: 3,
            sx: {
              overflow: 'visible',
              filter: 'drop-shadow(0px 2px 8px rgba(0,0,0,0.32))',
              mt: 1.5,
              minWidth: 200,
              '& .MuiAvatar-root': {
                width: 24,
                height: 24,
                ml: -0.5,
                mr: 1.5,
              },
            },
          }}
          transformOrigin={{ horizontal: 'right', vertical: 'top' }}
          anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
        >
          <Box sx={{ px: 2, py: 1 }}>
            <Typography variant="subtitle2" fontWeight={600}>
              {user.name || 'User'}
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {user.email}
            </Typography>
          </Box>
          
          <Divider />
          
          <MenuItem onClick={handleProfileClose}>
            <AccountIcon fontSize="small" sx={{ mr: 1.5 }} />
            Profile Settings
          </MenuItem>
          
          <Divider />
          
          <MenuItem onClick={handleLogout}>
            <LogoutIcon fontSize="small" sx={{ mr: 1.5 }} />
            Sign Out
          </MenuItem>
        </Menu>
      </Toolbar>
    </AppBar>
  );
};

export default Navigation;