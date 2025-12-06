# CM Dev Command Reference

## Overview

The `cm dev` command provides management for the **univers-developer** session - a dedicated development terminal for working with the Univers HVAC system. This session runs in a tmux environment that persists even when you disconnect.

**Important:** This command specifically manages only the `univers-developer` session, not all univers-* sessions.

## Commands

### cm dev restart
Restart the univers-developer session.

**Usage:**
```bash
cm dev restart
```

**What it does:**
- Stops the current univers-developer session if running
- Waits for cleanup
- Starts a fresh univers-developer session

### cm dev start
Start the univers-developer session.

**Usage:**
```bash
cm dev start
```

### cm dev stop
Stop the univers-developer session.

**Usage:**
```bash
cm dev stop
```

### cm dev status
Show the current status of the univers-developer session.

**Usage:**
```bash
cm dev status
```

**Output includes:**
- Session running status
- Window and pane information
- Session creation time
- Project directory

### cm dev attach
Attach to the running univers-developer session.

**Usage:**
```bash
cm dev attach
```

**Tmux Navigation:**
- `Ctrl+B D` - Detach from session (session continues running)
- `Ctrl+B [` - Enter scroll mode (press `q` to exit)
- `Ctrl+B ?` - Show all tmux shortcuts

## About the Univers Developer Session

The `univers-developer` session is a persistent tmux session that provides:

1. **Dedicated Development Terminal** - A consistent development environment
2. **Persistent Environment** - Continues running even when you disconnect
3. **Project Context** - Automatically set to the hvac-workbench directory
4. **Custom Status Bar** - Shows relevant development information

## Examples

### Basic Session Management
```bash
# Check if session is running
cm dev status

# Start the development session
cm dev start

# Attach to work in the session
cm dev attach

# When done, detach with Ctrl+B D (don't stop!)

# Restart if needed (e.g., after configuration changes)
cm dev restart

# Stop when completely done
cm dev stop
```

### Development Workflow
```bash
# Start your day - check status
cm dev status

# If not running, start it
cm dev start

# Attach to work
cm dev attach

# Work in the development terminal...
# When done for now, detach: Ctrl+B D

# Later, reattach to continue working
cm dev attach

# At end of day, you can leave it running or stop
cm dev stop
```

## Integration with Other CM Commands

The dev command works alongside other cm functionality:

```bash
# Initialize environment
cm init

# Start tmux management sessions (different from dev session)
cm tmux start

# Check system health
cm doctor

# Manage the developer session
cm dev start
cm dev attach
```

## Differences from Other Sessions

**Important Distinction:**

- **`cm dev` commands** - Manage ONLY the `univers-developer` session (development terminal)
- **`cm tmux` commands** - Manage desktop/mobile view sessions (container-desktop-view, container-mobile-view)
- **Other univers-* sessions** - Managed separately (univers-server, univers-ui, univers-web, etc.)

## Path Resolution

The `cm dev` command automatically discovers the tmux-developer.sh script:

1. **Primary location:** `/home/$(whoami)/repos/hvac-workbench/.claude/skills/univers-dev/scripts/`
2. **Alternative locations:** 
   - `/home/ubuntu/repos/hvac-workbench/.claude/skills/univers-dev/scripts/`
   - `$HOME/repos/hvac-workbench/.claude/skills/univers-dev/scripts/`
   - `./hvac-workbench/.claude/skills/univers-dev/scripts/`
   - `../hvac-workbench/.claude/skills/univers-dev/scripts/`

## Troubleshooting

### Session Not Found
If the session is not found:
1. Check if hvac-workbench is properly initialized: `cm init`
2. Verify session status: `cm dev status`
3. Try starting the session: `cm dev start`

### Path Issues
If the script cannot find tmux-developer.sh:
1. Ensure hvac-workbench is cloned in the expected location
2. Check that the .claude/skills/univers-dev/scripts/ directory exists
3. Verify the tmux-developer.sh script is executable

### Cannot Attach
If you cannot attach to the session:
1. Check if session is running: `cm dev status`
2. If not running, start it: `cm dev start`
3. Check for existing tmux sessions: `tmux list-sessions`
4. Ensure no conflicts with other tmux sessions

## Best Practices

1. **Leave it running** - The session is designed to persist, so leave it running between work sessions
2. **Detach, don't stop** - Use `Ctrl+B D` to detach, don't stop the session unless done for the day
3. **Check status first** - Always run `cm dev status` to see current state
4. **Use attach/restart** - Attach to work, restart only if needed
5. **Monitor resources** - Be aware that tmux sessions use system resources