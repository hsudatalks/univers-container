#!/usr/bin/env bash
# Main Alert Command Interface
# User-friendly interface for the alerting system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERT_ENGINE="$SCRIPT_DIR/alert-engine.sh"

# Check if alert engine exists
if [ ! -f "$ALERT_ENGINE" ]; then
    echo -e "${RED}Error: Alert engine not found at $ALERT_ENGINE${NC}"
    exit 1
fi

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Print help
print_help() {
    cat << 'HELP'
Univers Alerting System

Usage: alert <command> [options]

Commands:

  System Operations:
    init                          Initialize alerting system
    check                         Check current system status
    status                        Show alert status summary
    start                         Start monitoring daemon
    stop                          Stop monitoring daemon

  Alert Management:
    rules list                     List all alert rules
    rules add <name>               Add new alert rule
    rules update <name>            Update existing rule
    rules remove <name>            Remove alert rule
    rules enable <name>            Enable alert rule
    rules disable <name>           Disable alert rule

  Configuration:
    config                         Show configuration
    config edit                    Edit configuration files
    channels list                  List notification channels
    channels test <channel>        Test notification channel

  Monitoring:
    monitor system                 Monitor system resources
    monitor services               Monitor Univers services
    monitor logs                   Monitor alert logs

  Testing:
    test alert <rule>              Test specific alert rule
    test notification <channel>    Test notification delivery

  History:
    history                        Show alert history
    history --last <duration>      Show recent alerts (e.g., 1h, 24h, 7d)

Examples:
  alert init                      # Initialize alerting
  alert check                     # Check current status
  alert start                     # Start monitoring
  alert rules list                # List all rules
  alert test notification email   # Test email notifications
  alert history --last 1h         # Show last hour of alerts

HELP
}

# Initialize alerting system
cmd_init() {
    echo -e "${CYAN}Initializing Univers Alerting System...${NC}"
    echo ""

    # Run alert engine init
    "$ALERT_ENGINE" init

    echo ""
    log_success "Alerting system initialized successfully!"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Configure notification channels: alert config edit"
    echo "  2. Review alert rules: alert rules list"
    echo "  3. Test notifications: alert test notification <channel>"
    echo "  4. Start monitoring: alert start"
}

# Check system status
cmd_check() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🔍 Univers System Alert Check${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    "$ALERT_ENGINE" check

    echo ""
    echo -e "${CYAN}Quick Actions:${NC}"
    echo "  • Start monitoring: alert start"
    echo "  • View rules: alert rules list"
    echo "  • Test notifications: alert test notification"
}

# Show alert status
cmd_status() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📊 Alert Status Overview${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    cmd_check
}

# List alert rules
cmd_rules_list() {
    local config_dir="${ALERT_CONFIG_DIR:-$HOME/.config/univers/alerting}"
    local rules_file="$config_dir/rules.yaml"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📋 Alert Rules${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ! -f "$rules_file" ]; then
        log_warning "Alert rules file not found. Run 'alert init' first."
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 -c "
import yaml
import sys

try:
    with open('$rules_file') as f:
        config = yaml.safe_load(f)

    rules = config.get('rules', [])

    if not rules:
        print('No alert rules configured.')
        sys.exit(0)

    for i, rule in enumerate(rules, 1):
        status = '✅' if rule.get('enabled', True) else '❌'
        severity = rule.get('severity', 'info').upper()

        print(f'{i:2d}. {status} {rule[\"name\"]}')
        print(f'     Type: {rule[\"type\"]} | Severity: {severity}')
        if rule['type'] == 'system':
            print(f'     Condition: {rule[\"metric\"]} {rule[\"condition\"]} {rule[\"threshold\"]}')
        elif rule['type'] == 'service':
            print(f'     Condition: {rule[\"target\"]} != {rule[\"threshold\"]}')

        print(f'     Duration: {rule.get(\"duration\", \"immediate\")}')
        if 'message' in rule:
            print(f'     Message: {rule[\"message\"]}')
        print()

except Exception as e:
    print(f'Error reading rules file: {e}')
    sys.exit(1)
"
    else
        log_warning "Python3 required to parse rules. Please install python3."
        echo "Rules file location: $rules_file"
    fi
}

# Monitor system resources
cmd_monitor_system() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🖥️  System Resource Monitoring${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # CPU Usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    echo -e "CPU Usage: ${cpu_usage:-N/A}%"

    # Memory Usage
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_usage=$((mem_used * 100 / mem_total))
    echo -e "Memory Usage: ${mem_usage}%"

    # Disk Usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    echo -e "Disk Usage: ${disk_usage}%"

    # Load Average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    echo -e "Load Average: ${load_avg}"

    echo ""

    # Alert thresholds
    echo -e "${CYAN}Alert Thresholds:${NC}"
    echo -e "  CPU > 80%  → Warning"
    echo -e "  Memory > 90% → Critical"
    echo -e "  Disk > 85%  → Warning"

    echo ""
    log_info "Press Ctrl+C to stop monitoring"

    # Continuous monitoring
    while true; do
        sleep 30
        echo -e "\n$(date '+%H:%M:%S') - Refreshing metrics..."
        cmd_monitor_system
    done
}

# Monitor Univers services
cmd_monitor_services() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🚀 Univers Service Monitoring${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check Univers services
    local services=(
        "univers-server:3003:Backend API"
        "univers-ui:6007:Storybook UI"
        "univers-web:5173:Vite Web Server"
    )

    echo -e "${CYAN}Service Status:${NC}"
    for service in "${services[@]}"; do
        local name=$(echo "$service" | cut -d: -f1)
        local port=$(echo "$service" | cut -d: -f2)
        local desc=$(echo "$service" | cut -d: -f3)

        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" | grep -q "200\|301\|302"; then
            echo -e "  ${GREEN}✅ $name ($port) - $desc${NC}"
        else
            echo -e "  ${RED}❌ $name ($port) - $desc${NC}"
        fi
    done

    echo ""

    # Check tmux sessions
    echo -e "${CYAN}Tmux Sessions:${NC}"
    local sessions=("univers-developer" "univers-server" "univers-ui" "univers-web")
    for session in "${sessions[@]}"; do
        if tmux has-session -t "$session" 2>/dev/null; then
            echo -e "  ${GREEN}✅ $session${NC}"
        else
            echo -e "  ${RED}❌ $session${NC}"
        fi
    done

    echo ""
    log_info "Press Ctrl+C to stop monitoring"

    # Continuous monitoring
    while true; do
        sleep 30
        echo -e "\n$(date '+%H:%M:%S') - Refreshing services..."
        cmd_monitor_services
    done
}

# Show alert history
cmd_history() {
    local duration="$1"
    local config_dir="${ALERT_CONFIG_DIR:-$HOME/.config/univers/alerting}"
    local history_file="$config_dir/state/alert_history.json"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📜 Alert History${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ! -f "$history_file" ]; then
        log_warning "Alert history file not found"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 -c "
import json
from datetime import datetime, timedelta

try:
    with open('$history_file') as f:
        history = json.load(f)

    if not history:
        print('No alert history available.')
        sys.exit(0)

    # Filter by duration if specified
    if '$duration':
        duration_map = {
            '1h': 1, '24h': 24, '7d': 24*7, '30d': 24*30
        }
        hours = duration_map.get('$duration', 24)
        cutoff = datetime.now() - timedelta(hours=hours)

        filtered = [
            alert for alert in history
            if datetime.fromisoformat(alert['timestamp']) > cutoff
        ]
    else:
        filtered = history

    print(f'Showing {len(filtered)} alerts (last {\"$duration\" or \"all\"})')
    print()

    for alert in reversed(filtered[-10:]):  # Show last 10
        timestamp = alert['timestamp']
        name = alert['alert_name']
        severity = alert['severity'].upper()
        message = alert['message']

        # Color by severity
        if severity == 'CRITICAL':
            color = '🔴'
        elif severity == 'ERROR':
            color = '🟠'
        elif severity == 'WARNING':
            color = '🟡'
        else:
            color = '🔵'

        print(f'{color} {timestamp}')
        print(f'   {severity}: {name}')
        print(f'   {message}')
        print()

except Exception as e:
    print(f'Error reading history: {e}')
    sys.exit(1)
"
    else
        log_warning "Python3 required to view history"
        echo "History file location: $history_file"
    fi
}

# Test notification channels
cmd_test_notification() {
    local channel="$1"

    if [ -z "$channel" ]; then
        echo -e "${RED}Error: Channel name required${NC}"
        echo "Available channels: console, file, email, slack"
        return 1
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🧪 Testing Notification Channel: $channel${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    case "$channel" in
        console)
            echo -e "${YELLOW}[WARNING] Test Alert${NC} [$(date '+%Y-%m-%d %H:%M:%S')] test-notification: This is a test alert from Univers Alerting System"
            log_success "Console notification test successful"
            ;;
        file)
            local config_dir="${ALERT_CONFIG_DIR:-$HOME/.config/univers/alerting}"
            local log_file="$config_dir/alerts.log"

            local test_entry='{
              "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
              "alert_name": "test-notification",
              "severity": "warning",
              "message": "This is a test alert from Univers Alerting System"
            }'

            echo "$test_entry" >> "$log_file"
            log_success "File notification test successful"
            echo "Logged to: $log_file"
            ;;
        email)
            log_warning "Email notification test not implemented yet"
            echo "Configure email settings in: $HOME/.config/univers/alerting/channels.yaml"
            ;;
        slack)
            log_warning "Slack notification test not implemented yet"
            echo "Configure Slack webhook in: $HOME/.config/univers/alerting/channels.yaml"
            ;;
        *)
            log_error "Unknown channel: $channel"
            echo "Available channels: console, file, email, slack"
            return 1
            ;;
    esac
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            cmd_init
            ;;
        check|status)
            cmd_status
            ;;
        start)
            log_info "Starting alert monitoring daemon..."
            "$ALERT_ENGINE" start
            ;;
        stop)
            log_warning "Alert daemon stop not implemented yet"
            ;;
        rules)
            local subcmd="${1:-list}"
            shift || true
            case "$subcmd" in
                list)
                    cmd_rules_list
                    ;;
                *)
                    echo -e "${RED}Error: Unknown rules command '$subcmd'${NC}"
                    echo "Available: list"
                    exit 1
                    ;;
            esac
            ;;
        monitor)
            local target="${1:-system}"
            case "$target" in
                system)
                    cmd_monitor_system
                    ;;
                services)
                    cmd_monitor_services
                    ;;
                *)
                    echo -e "${RED}Error: Unknown monitor target '$target'${NC}"
                    echo "Available: system, services"
                    exit 1
                    ;;
            esac
            ;;
        history)
            cmd_history "$1"
            ;;
        test)
            local subcmd="${1:-help}"
            case "$subcmd" in
                notification)
                    cmd_test_notification "$2"
                    ;;
                *)
                    echo -e "${RED}Error: Unknown test command '$subcmd'${NC}"
                    echo "Available: notification"
                    exit 1
                    ;;
            esac
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            print_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"