#!/usr/bin/env bash
#
# Quick Tmux Session Attach
# Provides interactive session selection or creates new session
#

set -e

SESSION_NAME="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}❌ tmux is not installed${NC}"
    exit 1
fi

# If session name provided, try to attach or create
if [ -n "$SESSION_NAME" ]; then
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo -e "${GREEN}✅ Attaching to existing session: $SESSION_NAME${NC}"
        tmux attach-session -t "$SESSION_NAME"
    else
        echo -e "${BLUE}ℹ️  Creating new session: $SESSION_NAME${NC}"
        tmux new-session -s "$SESSION_NAME"
    fi
    exit 0
fi

# Check if any sessions exist
if ! tmux list-sessions &>/dev/null; then
    echo -e "${YELLOW}No tmux sessions found${NC}"
    read -p "Create new session? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Session name: " new_session
        if [ -n "$new_session" ]; then
            tmux new-session -s "$new_session"
        else
            echo -e "${RED}❌ Session name cannot be empty${NC}"
            exit 1
        fi
    fi
    exit 0
fi

# If inside tmux, show switch menu
if [ -n "$TMUX" ]; then
    echo -e "${BLUE}ℹ️  You are already in a tmux session${NC}"
    echo "Choose an action:"
    echo "  1) Switch to another session"
    echo "  2) Detach current session"
    echo "  3) Create new session"
    read -p "Enter choice [1-3]: " -n 1 -r
    echo

    case $REPLY in
        1)
            tmux choose-tree -Zs
            ;;
        2)
            tmux detach-client
            ;;
        3)
            read -p "New session name: " new_session
            if [ -n "$new_session" ]; then
                tmux new-session -d -s "$new_session"
                tmux switch-client -t "$new_session"
            fi
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
    exit 0
fi

# Show session list and prompt for selection
echo "Available tmux sessions:"
echo ""

sessions=()
index=1

while IFS= read -r line; do
    sessions+=("$line")
    session_name=$(echo "$line" | cut -d: -f1)
    attached=$(echo "$line" | grep -o "attached" || echo "detached")

    if [ "$attached" = "attached" ]; then
        echo -e "  ${GREEN}$index)${NC} $session_name ${GREEN}[attached]${NC}"
    else
        echo -e "  $index) $session_name"
    fi

    ((index++))
done < <(tmux list-sessions -F "#{session_name}:#{session_attached}")

echo ""
echo "  n) Create new session"
echo "  q) Quit"
echo ""

read -p "Select session [1-${#sessions[@]}/n/q]: " choice

case $choice in
    [1-9]|[1-9][0-9])
        if [ "$choice" -le "${#sessions[@]}" ]; then
            session_name=$(echo "${sessions[$((choice-1))]}" | cut -d: -f1)
            echo -e "${GREEN}✅ Attaching to: $session_name${NC}"
            tmux attach-session -t "$session_name"
        else
            echo -e "${RED}❌ Invalid selection${NC}"
            exit 1
        fi
        ;;
    n|N)
        read -p "New session name: " new_session
        if [ -n "$new_session" ]; then
            echo -e "${BLUE}ℹ️  Creating session: $new_session${NC}"
            tmux new-session -s "$new_session"
        else
            echo -e "${RED}❌ Session name cannot be empty${NC}"
            exit 1
        fi
        ;;
    q|Q)
        echo "Bye!"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ Invalid choice${NC}"
        exit 1
        ;;
esac
