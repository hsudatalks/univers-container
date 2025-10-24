#!/usr/bin/env bash
#
# Tmux Manage Skill Installation Script
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}🚀 Tmux Manage Skill Installation${NC}"
echo "======================================"
echo ""

# Check if tmux is installed
echo "📋 Checking prerequisites..."
if ! command -v tmux &> /dev/null; then
    echo -e "${YELLOW}⚠️  tmux not found, attempting to install...${NC}"

    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v brew &> /dev/null; then
        brew install tmux
    else
        echo -e "${RED}❌ Cannot install tmux automatically${NC}"
        echo "Please install manually:"
        echo "  Ubuntu/Debian: sudo apt install tmux"
        echo "  macOS: brew install tmux"
        exit 1
    fi
fi
echo -e "${GREEN}✅ tmux found: $(which tmux)${NC}"
echo ""

# Install commands (use symlinks for easier updates)
echo "📦 Installing tmux management commands..."
SUDO_CMD=""
if [ ! -w /usr/local/bin ]; then
    echo -e "${YELLOW}⚠️  /usr/local/bin is not writable, will use sudo${NC}"
    SUDO_CMD="sudo"
fi

# Remove old installations
$SUDO_CMD rm -f /usr/local/bin/tmux-manager
$SUDO_CMD rm -f /usr/local/bin/tmux-desktop-view
$SUDO_CMD rm -f /usr/local/bin/tmux-mobile-view
$SUDO_CMD rm -f /usr/local/bin/tmux-monitor

# Create symlinks
$SUDO_CMD ln -s "$SCRIPT_DIR/scripts/tmux-manager.sh" /usr/local/bin/tmux-manager
echo -e "${GREEN}✅ Installed: /usr/local/bin/tmux-manager${NC}"

$SUDO_CMD ln -s "$SCRIPT_DIR/scripts/tmux-desktop-view.sh" /usr/local/bin/tmux-desktop-view
echo -e "${GREEN}✅ Installed: /usr/local/bin/tmux-desktop-view${NC}"

$SUDO_CMD ln -s "$SCRIPT_DIR/scripts/tmux-mobile-view.sh" /usr/local/bin/tmux-mobile-view
echo -e "${GREEN}✅ Installed: /usr/local/bin/tmux-mobile-view${NC}"

$SUDO_CMD ln -s "$SCRIPT_DIR/scripts/tmux-monitor.sh" /usr/local/bin/tmux-monitor
echo -e "${GREEN}✅ Installed: /usr/local/bin/tmux-monitor${NC}"
echo ""

echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "======================================"
echo "🚀 Quick Start Guide"
echo "======================================"
echo ""
echo "1️⃣  Start container manager:"
echo "    tmux-manager start"
echo ""
echo "2️⃣  Start desktop view (split panes):"
echo "    tmux-desktop-view start"
echo ""
echo "3️⃣  Start mobile view (multiple windows):"
echo "    tmux-mobile-view start"
echo ""
echo "4️⃣  Start system monitor (4-pane layout):"
echo "    tmux-monitor start"
echo ""
echo "5️⃣  List all sessions:"
echo "    tmux list-sessions"
echo ""
echo "======================================"
echo "📚 Available Commands"
echo "======================================"
echo ""
echo "Container Manager:"
echo "  tmux-manager start      Start manager session"
echo "  tmux-manager attach     Attach to manager"
echo "  tmux-manager status     Check status"
echo "  tmux-manager stop       Stop manager"
echo ""
echo "Desktop View:"
echo "  tmux-desktop-view start   Start desktop view (3 windows)"
echo "  tmux-desktop-view attach  Attach to desktop view"
echo "  tmux-desktop-view status  Check status"
echo ""
echo "Mobile View:"
echo "  tmux-mobile-view start    Start mobile view (4 windows)"
echo "  tmux-mobile-view attach   Attach to mobile view"
echo "  tmux-mobile-view status   Check status"
echo ""
echo "System Monitor:"
echo "  tmux-monitor start        Start system monitor (4 panes)"
echo "  tmux-monitor attach       Attach to monitor"
echo "  tmux-monitor status       Check status"
echo "  tmux-monitor stop         Stop monitor"
echo ""
echo "======================================"
echo "📖 Dependencies"
echo "======================================"
echo ""
echo "View sessions depend on these services:"
echo ""
echo "From hvac-workbench (univers-dev):"
echo "  - univers-developer (developer terminal)"
echo "  - univers-server (backend API)"
echo "  - univers-ui (Storybook UI)"
echo "  - univers-web (Vite web server)"
echo ""
echo "From hvac-operation (univers-ops):"
echo "  - univers-operator (operations console)"
echo ""
echo "From univers-container (tmux-manage):"
echo "  - univers-manager (container manager)"
echo ""
echo "Start these before launching view sessions."
echo ""
echo "For more details, see:"
echo "  $SCRIPT_DIR/SKILL.md"
echo ""
