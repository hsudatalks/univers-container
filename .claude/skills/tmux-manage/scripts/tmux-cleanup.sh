#!/usr/bin/env bash
#
# Tmux Session Cleanup
# Removes old or unwanted tmux sessions
#

set -e

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

# Check if any sessions exist
if ! tmux list-sessions &>/dev/null; then
    echo -e "${YELLOW}No tmux sessions to clean up${NC}"
    exit 0
fi

show_help() {
    cat << EOF
Tmux Session Cleanup

Usage:
  $0 [options]

Options:
  -a, --all         Kill all sessions
  -d, --detached    Kill only detached sessions
  -p, --pattern     Kill sessions matching pattern
  -i, --interactive Interactive cleanup (default)
  -h, --help        Show this help

Examples:
  $0                     # Interactive mode
  $0 --detached          # Kill all detached sessions
  $0 --pattern "test-*"  # Kill sessions starting with "test-"

EOF
}

kill_all_sessions() {
    echo -e "${YELLOW}⚠️  This will kill ALL tmux sessions${NC}"
    read -p "Are you sure? (yes/no) " -r
    echo
    if [ "$REPLY" = "yes" ]; then
        tmux kill-server
        echo -e "${GREEN}✅ All sessions killed${NC}"
    else
        echo "Cancelled"
    fi
}

kill_detached_sessions() {
    detached=$(tmux list-sessions -F "#{session_name}:#{session_attached}" | grep ":0$" | cut -d: -f1)

    if [ -z "$detached" ]; then
        echo -e "${YELLOW}No detached sessions found${NC}"
        return
    fi

    echo "Detached sessions:"
    echo "$detached" | while read -r session; do
        echo "  - $session"
    done
    echo ""

    read -p "Kill all detached sessions? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$detached" | while read -r session; do
            tmux kill-session -t "$session"
            echo -e "${GREEN}✅ Killed: $session${NC}"
        done
    else
        echo "Cancelled"
    fi
}

kill_by_pattern() {
    pattern="$1"

    if [ -z "$pattern" ]; then
        echo -e "${RED}❌ Pattern cannot be empty${NC}"
        exit 1
    fi

    matching=$(tmux list-sessions -F "#{session_name}" | grep "$pattern" || true)

    if [ -z "$matching" ]; then
        echo -e "${YELLOW}No sessions matching pattern: $pattern${NC}"
        return
    fi

    echo "Sessions matching pattern '$pattern':"
    echo "$matching" | while read -r session; do
        echo "  - $session"
    done
    echo ""

    read -p "Kill these sessions? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$matching" | while read -r session; do
            tmux kill-session -t "$session"
            echo -e "${GREEN}✅ Killed: $session${NC}"
        done
    else
        echo "Cancelled"
    fi
}

interactive_cleanup() {
    echo "Tmux Session Cleanup"
    echo "════════════════════════════════════════"
    echo ""

    # List sessions with selection
    sessions=()
    index=1

    while IFS= read -r line; do
        sessions+=("$line")
        session_name=$(echo "$line" | cut -d'|' -f1)
        windows=$(echo "$line" | cut -d'|' -f2)
        attached=$(echo "$line" | cut -d'|' -f3)

        if [ "$attached" = "1" ]; then
            status="${GREEN}[attached]${NC}"
        else
            status="${YELLOW}[detached]${NC}"
        fi

        echo -e "  $index) $session_name ($windows windows) $status"
        ((index++))
    done < <(tmux list-sessions -F "#{session_name}|#{session_windows}|#{session_attached}")

    echo ""
    echo "Select sessions to kill (space-separated numbers, 'a' for all, 'q' to quit):"
    read -p "> " -r selection

    case $selection in
        q|Q)
            echo "Cancelled"
            exit 0
            ;;
        a|A)
            kill_all_sessions
            ;;
        *)
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -le "${#sessions[@]}" ]; then
                    session_name=$(echo "${sessions[$((num-1))]}" | cut -d'|' -f1)

                    # Don't kill current session if inside tmux
                    if [ -n "$TMUX" ]; then
                        current_session=$(tmux display-message -p '#S')
                        if [ "$session_name" = "$current_session" ]; then
                            echo -e "${YELLOW}⚠️  Skipping current session: $session_name${NC}"
                            continue
                        fi
                    fi

                    tmux kill-session -t "$session_name"
                    echo -e "${GREEN}✅ Killed: $session_name${NC}"
                else
                    echo -e "${RED}❌ Invalid selection: $num${NC}"
                fi
            done
            ;;
    esac
}

# Parse arguments
case "${1:-}" in
    -a|--all)
        kill_all_sessions
        ;;
    -d|--detached)
        kill_detached_sessions
        ;;
    -p|--pattern)
        kill_by_pattern "$2"
        ;;
    -h|--help)
        show_help
        ;;
    "")
        interactive_cleanup
        ;;
    *)
        echo -e "${RED}❌ Unknown option: $1${NC}"
        show_help
        exit 1
        ;;
esac
