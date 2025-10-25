#!/bin/bash
# Container Manage Skill Installation Script
# Sets up cm as an alias for container-manage in both bash and zsh

set -e

# Color codes
RED='\\033[0;31m'
GREEN='\\033[0;32m'
BLUE='\\033[0;34m'
YELLOW='\\033[1;33m'
NC='\\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CM_SCRIPT="$SCRIPT_DIR/bin/cm"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

echo "=== Container Manage Skill Installation ==="
echo

# Verify cm script exists
if [ ! -f "$CM_SCRIPT" ]; then
    print_error "cm script not found at $CM_SCRIPT"
    exit 1
fi

print_success "Found cm script: $CM_SCRIPT"
echo

# ============ Setup Zsh ============
if [ -f "$ZSHRC" ]; then
    print_info "Configuring zsh (~/.zshrc)..."
    
    CM_ALIAS="alias cm='$CM_SCRIPT'"
    
    if grep -qF "alias cm=" "$ZSHRC"; then
        print_warning "  cm alias already configured in ~/.zshrc"
    else
        {
            echo ""
            echo "# Container Manage Skill - cm alias"
            echo "$CM_ALIAS"
        } >> "$ZSHRC"
        print_success "  Added cm alias to ~/.zshrc"
    fi
else
    print_warning "~/.zshrc not found, creating..."
    {
        echo "# Zsh configuration"
        echo ""
        echo "# Container Manage Skill - cm alias"
        echo "alias cm='$CM_SCRIPT'"
    } > "$ZSHRC"
    print_success "  Created ~/.zshrc with cm alias"
fi

echo

# ============ Setup Bash ============
if [ -f "$BASHRC" ]; then
    print_info "Configuring bash (~/.bashrc)..."
    
    CM_ALIAS="alias cm='$CM_SCRIPT'"
    
    if grep -qF "alias cm=" "$BASHRC"; then
        print_warning "  cm alias already configured in ~/.bashrc"
    else
        {
            echo ""
            echo "# Container Manage Skill - cm alias"
            echo "$CM_ALIAS"
        } >> "$BASHRC"
        print_success "  Added cm alias to ~/.bashrc"
    fi
else
    print_warning "~/.bashrc not found, creating..."
    {
        echo "# Bash configuration"
        echo ""
        echo "# Container Manage Skill - cm alias"
        echo "alias cm='$CM_SCRIPT'"
    } > "$BASHRC"
    print_success "  Created ~/.bashrc with cm alias"
fi

echo

# ============ Make Script Executable ============
if [ ! -x "$CM_SCRIPT" ]; then
    chmod +x "$CM_SCRIPT"
    print_success "Made cm script executable"
fi

echo "=== Installation Complete ==="
echo
print_success "cm alias configured for bash and zsh!"
echo
print_info "Current shell: $SHELL"
print_warning "To activate cm in current session, run:"
echo "  source ~/.bashrc     # for bash"
echo "  source ~/.zshrc      # for zsh"
echo
print_info "Or open a new terminal window."
echo
print_info "Verify installation:"
echo "  which cm"
echo "  cm --help"
echo
