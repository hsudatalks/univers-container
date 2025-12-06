# CM Dev Command - Complete Univers Session Management

## Overview

The `cm dev` command now provides **complete management** for all Univers development sessions. It supports individual session control, group operations, and comprehensive status monitoring.

## 🎯 What's New

### ✅ **Complete Session Coverage**
- **Core Sessions**: `univers-server`, `univers-ui`, `univers-web`, `univers-claude`
- **Development Views**: `univers-desktop-dev`, `univers-mobile-dev`
- **Developer Session**: `univers-developer`

### ✅ **Smart Session Groups**
- **`all`**: All univers-* sessions
- **`core`**: Core development sessions (server, ui, web, claude)
- **`dev-views`**: Development view sessions (desktop-dev, mobile-dev)
- **`developer`**: Developer terminal only

### ✅ **Flexible Targeting**
- Restart all sessions: `cm dev restart`
- Restart core only: `cm dev restart core`
- Restart specific: `cm dev restart univers-server`
- Individual control: `cm dev restart ui`

## 🚀 Quick Start

```bash
# List all available sessions
cm dev list

# Check current status
cm dev status

# Restart all development sessions
cm dev restart

# Restart just the core development stack
cm dev restart core

# Attach to specific session
cm dev attach univers-server
```

## 📋 Available Sessions

### Core Development Sessions
| Session | Purpose | Port/Feature |
|---------|---------|--------------|
| `univers-server` | Backend API server | HTTP: 3003, Socket: /tmp/univers-server.sock |
| `univers-ui` | Storybook UI development | Port: 6007 |
| `univers-web` | Vite web development | Port: 5173 |
| `univers-claude` | Claude Code terminal | Persistent development terminal |

### Development View Sessions
| Session | Purpose | Layout |
|---------|---------|---------|
| `univers-desktop-dev` | Desktop development view | Split-screen layout |
| `univers-mobile-dev` | Mobile development view | Window-switching layout |

### Developer Session
| Session | Purpose | Feature |
|---------|---------|---------|
| `univers-developer` | Developer terminal | Persistent tmux session |

## 🎯 Command Reference

### Session Management

#### `cm dev restart [target]`
Restart sessions with flexible targeting.

```bash
cm dev restart                    # Restart ALL sessions
cm dev restart all                # Same as above (explicit)
cm dev restart core               # Restart core sessions only
cm dev restart dev-views          # Restart development views only
cm dev restart developer          # Restart developer session only
cm dev restart server             # Restart univers-server only
cm dev restart ui                 # Restart univers-ui only
cm dev restart web                # Restart univers-web only
cm dev restart claude             # Restart univers-claude only
cm dev restart desktop-dev        # Restart univers-desktop-dev only
cm dev restart mobile-dev         # Restart univers-mobile-dev only
```

#### `cm dev start [target]`
Start sessions (same targeting as restart).

```bash
cm dev start                      # Start ALL sessions
cm dev start core                 # Start core sessions only
cm dev start server               # Start univers-server only
```

#### `cm dev stop [target]`
Stop sessions (same targeting as restart).

```bash
cm dev stop                       # Stop ALL sessions
cm dev stop core                  # Stop core sessions only
cm dev stop server                # Stop univers-server only
```

### Status and Monitoring

#### `cm dev status`
Show comprehensive status of all sessions.

**Features:**
- Categorized display (Core, Dev Views, Developer)
- Color-coded status indicators
- Usage tips and suggestions
- Real-time session information

#### `cm dev list`
List all available sessions and groups.

**Shows:**
- All individual sessions with descriptions
- Special groups and their contents
- Usage examples
- Quick reference guide

### Session Attachment

#### `cm dev attach [session]`
Attach to specific session.

```bash
cm dev attach                     # Default: attach to univers-developer
cm dev attach server              # Attach to univers-server
cm dev attach ui                  # Attach to univers-ui
cm dev attach web                 # Attach to univers-web
cm dev attach claude              # Attach to univers-claude
cm dev attach desktop-dev         # Attach to univers-desktop-dev
cm dev attach mobile-dev          # Attach to univers-mobile-dev
cm dev attach developer           # Attach to univers-developer
```

**Tmux Navigation:**
- `Ctrl+B D` - Detach (session continues running)
- `Ctrl+B [` - Enter scroll mode (q to exit)
- `Ctrl+B ?` - Show all shortcuts

## 🔄 Development Workflows

### Full Development Environment Setup
```bash
# 1. Initialize environment
cm init

# 2. Start container management views
cm tmux start

# 3. Start all development sessions
cm dev start

# 4. Check everything is running
cm dev status

# 5. Attach to work
cm dev attach server    # Monitor server logs
cm dev attach ui        # Work with Storybook
cm dev attach developer # General development
```

### Selective Development
```bash
# Start only core development stack
cm dev start core

# Work on frontend only
cm dev restart ui
cm dev attach ui

# Backend development
cm dev restart server
cm dev attach server

# AI-assisted development
cm dev attach claude
```

### Troubleshooting Workflow
```bash
# Check what's running
cm dev status

# Restart problematic session
cm dev restart server

# Check logs
cm dev attach server

# If needed, restart everything
cm dev restart
```

## 🎯 Smart Usage Patterns

### Development Session Priorities
1. **Always Running**: `univers-server` (backend API)
2. **Frontend Work**: `univers-ui` + `univers-web`
3. **AI Development**: `univers-claude`
4. **Overview Work**: `univers-desktop-dev`
5. **Mobile Focus**: `univers-mobile-dev`

### Resource Management
- **Development**: Keep core sessions running
- **Break Time**: Detach with `Ctrl+B D` (don't stop)
- **End of Day**: Can leave running or `cm dev stop`
- **System Restart**: Use `cm dev restart` to resume

### Quick Commands
```bash
# Daily startup
cm dev status && cm dev restart core

# Frontend focus
cm dev restart ui web && cm dev attach ui

# Backend focus  
cm dev restart server && cm dev attach server

# Full reset
cm dev restart && cm dev status
```

## 🔧 Integration with CM Tool

The dev commands work seamlessly with other cm functionality:

```bash
# Complete system check
cm doctor

# Environment setup
cm init

# Container views (separate from dev sessions)
cm tmux start desktop
cm tmux start mobile

# Development session management
cm dev restart core
cm dev attach server

# System monitoring
cm doctor
```

## 🚨 Important Distinctions

### Session Types
- **`cm dev`**: Manages **development sessions** (univers-*)
- **`cm tmux`**: Manages **container views** (container-desktop-view, container-mobile-view)
- **Direct tmux**: Manual session management

### Session Categories
- **Core**: Essential for development work
- **Dev Views**: Aggregated views for overview
- **Developer**: Individual development terminal

## 🎨 Visual Status

The status command provides color-coded information:
- ✅ **Green**: Session running
- ❌ **Red**: Session stopped  
- 📊 **Cyan**: Headers and categories
- 💡 **Yellow**: Tips and usage info

## 📚 Help System

### Built-in Help
```bash
cm dev help              # Complete command reference
cm dev list              # Available sessions and examples
```

### Main CM Help
```bash
cm help                  # Shows dev commands in main help
cm --help                # Same as above
```

## ✅ Summary

The enhanced `cm dev` command now provides:

1. **Complete Session Management** - All univers-* sessions
2. **Smart Grouping** - Logical session categories  
3. **Flexible Targeting** - Individual, group, or all sessions
4. **Rich Status Display** - Categorized, color-coded information
5. **Seamless Integration** - Works with existing cm commands
6. **User-Friendly** - Clear help, examples, and error messages

This creates a unified, powerful interface for managing the entire Univers development environment!