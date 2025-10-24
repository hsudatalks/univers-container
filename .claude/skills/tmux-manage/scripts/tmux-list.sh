#!/usr/bin/env bash
#
# Enhanced Tmux Session Listing
# Displays tmux sessions with detailed information
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}❌ tmux is not installed${NC}"
    exit 1
fi

# Check if any sessions exist
if ! tmux list-sessions &>/dev/null; then
    echo -e "${YELLOW}No tmux sessions running${NC}"
    exit 0
fi

echo "════════════════════════════════════════════════════════════════"
echo "  Tmux Sessions"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Format string for session info
FORMAT="#{session_name}|#{session_windows}|#{session_attached}|#{session_created}"

# Get session list
tmux list-sessions -F "$FORMAT" | while IFS='|' read -r name windows attached created; do
    # Convert timestamp to readable format
    created_date=$(date -d "@$created" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$created" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

    # Status indicator
    if [ "$attached" -gt 0 ]; then
        status="${GREEN}●${NC} Attached"
    else
        status="${YELLOW}○${NC} Detached"
    fi

    # Session name with color
    echo -e "${BLUE}📋 ${CYAN}$name${NC}"
    echo -e "   Status: $status"
    echo -e "   Windows: $windows"
    echo -e "   Created: $created_date"

    # List windows in session
    echo -e "   ${YELLOW}Windows:${NC}"
    tmux list-windows -t "$name" -F "#{window_index}:#{window_name}|#{window_panes}|#{window_active}" | while IFS='|' read -r win_info panes active; do
        if [ "$active" = "1" ]; then
            echo -e "     ${GREEN}▸${NC} $win_info ($panes panes) ${GREEN}[active]${NC}"
        else
            echo -e "       $win_info ($panes panes)"
        fi
    done

    echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Usage:"
echo "  tmux attach -t <session-name>  # Attach to session"
echo "  tmux kill-session -t <name>    # Kill session"
echo ""
