#!/bin/bash
# Container Manage Skill Installation Script
# Sets up cm as an alias for container-manage

set -e

# Color codes
GREEN='\\033[0;32m'
BLUE='\\033[0;34m'
YELLOW='\\033[1;33m'
NC='\\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CM_SCRIPT="$SCRIPT_DIR/bin/cm"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

echo "=== Container Manage Skill Installation ==="
echo

# Verify cm script exists
if [ ! -f "$CM_SCRIPT" ]; then
    echo "❌ Error: cm script not found at $CM_SCRIPT"
    exit 1
fi

print_success "Found cm script at $CM_SCRIPT"
echo

# Setup zsh alias
if [ -f "$ZSHRC" ]; then
    print_info "Configuring zsh alias..."
    
    CM_ALIAS="alias cm='$CM_SCRIPT'"
    
    if grep -qF "alias cm=" "$ZSHRC"; then
        print_warning "cm alias already exists in ~/.zshrc"
    else
        echo "" >> "$ZSHRC"
        echo "# Container Manage Skill alias" >> "$ZSHRC"
        echo "$CM_ALIAS" >> "$ZSHRC"
        print_success "Added cm alias to ~/.zshrc"
    fi
else
    print_warning "~/.zshrc not found, skipping zsh setup"
fi

echo

# Setup bash alias (optional)
if [ -f "$BASHRC" ]; then
    print_info "Configuring bash alias..."
    
    CM_ALIAS="alias cm='$CM_SCRIPT'"
    
    if grep -qF "alias cm=" "$BASHRC"; then
        print_warning "cm alias already exists in ~/.bashrc"
    else
        echo "" >> "$BASHRC"
        echo "# Container Manage Skill alias" >> "$BASHRC"
        echo "$CM_ALIAS" >> "$BASHRC"
        print_success "Added cm alias to ~/.bashrc"
    fi
fi

echo
echo "=== Installation Complete ==="
echo
print_success "cm alias configured!"
echo
print_warning "To use cm immediately, reload your shell:"
echo "  source ~/.zshrc"
echo
print_info "Usage examples:"
echo "  cm tmux list                    # List tmux sessions"
echo "  cm tmux attach univers-mobile-view  # Attach to session"
echo "  cm tmux kill-all                # Kill all sessions"
echo "  cm --help                       # Show full help"
echo
