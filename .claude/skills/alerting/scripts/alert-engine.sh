#!/usr/bin/env bash
# Alert Engine for Univers Infrastructure
# Real-time monitoring and alerting system

set -e

# Import Univers core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
UNIVERS_CORE="$PROJECT_ROOT/.claude/skills/univers-core"

# Source core utilities
if [ -n "$UNIVERS_CORE" ] && [ -f "$UNIVERS_CORE/lib/common.sh" ]; then
    source "$UNIVERS_CORE/lib/common.sh"
else
    # Fallback logging functions
    log_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
    log_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
    log_warning() { echo -e "\033[1;33m⚠️  $1\033[0m"; }
    log_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
    log_step() { echo -e "\033[0;36m▶ $1\033[0m"; }
fi

# Configuration
ALERT_CONFIG_DIR="${ALERT_CONFIG_DIR:-$HOME/.config/univers/alerting}"
ALERT_RULES_FILE="$ALERT_CONFIG_DIR/rules.yaml"
ALERT_CHANNELS_FILE="$ALERT_CONFIG_DIR/channels.yaml"
ALERT_STATE_DIR="$ALERT_CONFIG_DIR/state"
ALERT_LOG_FILE="$ALERT_CONFIG_DIR/alerts.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Alert severity levels
# info=0, warning=1, error=2, critical=3

# Initialize alerting system
init_alerting() {
    log_info "Initializing alerting system..."

    # Create config directory
    mkdir -p "$ALERT_CONFIG_DIR"/{state,logs}

    # Create default configuration if not exists
    create_default_config

    # Initialize state tracking
    init_state_tracking

    log_success "Alerting system initialized"
}

# Create default configuration files
create_default_config() {
    if [ ! -f "$ALERT_RULES_FILE" ]; then
        cat > "$ALERT_RULES_FILE" << 'EOF'
# Univers Alerting Rules
# Configure monitoring rules and thresholds

rules:
  # System Resource Alerts
  - name: cpu-usage-high
    type: system
    metric: cpu_usage
    condition: ">"
    threshold: 80
    duration: 5m
    severity: warning
    message: "CPU usage is {{cpu_usage}}% on {{hostname}}"
    enabled: true
    actions:
      - type: log
        level: warning

  - name: memory-usage-critical
    type: system
    metric: memory_usage
    condition: ">"
    threshold: 90
    duration: 2m
    severity: critical
    message: "Critical memory usage: {{memory_usage}}% on {{hostname}}"
    enabled: true
    actions:
      - type: log
        level: error

  - name: disk-space-low
    type: system
    metric: disk_usage
    condition: ">"
    threshold: 85
    duration: 1m
    severity: warning
    message: "Disk space low: {{disk_usage}}% used on {{hostname}}"
    enabled: true
    actions:
      - type: log
        level: warning

  # Service Health Alerts
  - name: univers-server-down
    type: service
    check: http_status
    target: "http://localhost:3003/health"
    condition: "!="
    threshold: 200
    duration: 1m
    severity: critical
    message: "Univers Server is down (HTTP {{http_status}})"
    enabled: true
    actions:
      - type: log
        level: error

  - name: univers-ui-down
    type: service
    check: http_status
    target: "http://localhost:6007"
    condition: "!="
    threshold: 200
    duration: 1m
    severity: warning
    message: "Univers UI is down (HTTP {{http_status}})"
    enabled: true
    actions:
      - type: log
        level: warning

  - name: univers-web-down
    type: service
    check: http_status
    target: "http://localhost:5173"
    condition: "!="
    threshold: 200
    duration: 1m
    severity: warning
    message: "Univers Web is down (HTTP {{http_status}})"
    enabled: true
    actions:
      - type: log
        level: warning

  # Process Alerts
  - name: univers-session-missing
    type: process
    check: tmux_session
    target: "univers-developer"
    condition: "not_exists"
    duration: 30s
    severity: info
    message: "Univers Developer session is not running"
    enabled: true
    actions:
      - type: log
        level: info
EOF
    fi

    if [ ! -f "$ALERT_CHANNELS_FILE" ]; then
        cat > "$ALERT_CHANNELS_FILE" << 'EOF'
# Alert Notification Channels
# Configure how alerts are delivered

channels:
  # Console logging (always enabled)
  console:
    enabled: true
    format: "timestamp"
    colors: true

  # File logging
  file:
    enabled: true
    path: "~/.config/univers/alerting/alerts.log"
    format: "json"
    rotation: daily
    max_size: "100MB"

  # Email notifications (configure SMTP settings)
  email:
    enabled: false
    smtp_host: "smtp.gmail.com"
    smtp_port: 587
    use_tls: true
    username: ""
    password: ""
    from: "alerts@univers.dev"
    to: ["admin@univers.dev"]

  # Slack notifications (configure webhook)
  slack:
    enabled: false
    webhook_url: ""
    channel: "#univers-alerts"
    username: "Univers Alert"
    icon_emoji: ":warning:"

  # Custom webhooks
  webhook:
    enabled: false
    url: ""
    method: "POST"
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer YOUR_TOKEN"
EOF
    fi
}

# Initialize state tracking
init_state_tracking() {
    mkdir -p "$ALERT_STATE_DIR"

    # Create active alerts file
    if [ ! -f "$ALERT_STATE_DIR/active_alerts.json" ]; then
        echo "{}" > "$ALERT_STATE_DIR/active_alerts.json"
    fi

    # Create alert history file
    if [ ! -f "$ALERT_STATE_DIR/alert_history.json" ]; then
        echo "[]" > "$ALERT_STATE_DIR/alert_history.json"
    fi
}

# Get system metrics
get_system_metrics() {
    local metrics={}

    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    metrics["cpu_usage"]="${cpu_usage:-0}"

    # Memory usage
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_usage=$((mem_used * 100 / mem_total))
    metrics["memory_usage"]="$mem_usage"

    # Disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    metrics["disk_usage"]="${disk_usage:-0}"

    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    metrics["load_average"]="${load_avg:-0}"

    # Network connections
    local connections=$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l)
    metrics["network_connections"]="${connections:-0}"

    # Hostname
    metrics["hostname"]="$(hostname)"

    # Timestamp
    metrics["timestamp"]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Output as JSON
    echo "{"
    local first=true
    for key in "${!metrics[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        echo "  \"$key\": \"${metrics[$key]}\""
    done
    echo "}"
}

# Check service health
check_service_health() {
    local target="$1"
    local timeout="${2:-10}"

    if [[ $target == http* ]]; then
        # HTTP/HTTPS check
        local response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$target" 2>/dev/null)
        echo "$response"
    else
        # Port check
        local host=$(echo "$target" | cut -d: -f1)
        local port=$(echo "$target" | cut -d: -f2)
        if nc -z -w3 "$host" "$port" 2>/dev/null; then
            echo "200"
        else
            echo "0"
        fi
    fi
}

# Check tmux session
check_tmux_session() {
    local session_name="$1"

    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "exists"
    else
        echo "not_exists"
    fi
}

# Evaluate alert condition
evaluate_condition() {
    local current_value="$1"
    local operator="$2"
    local threshold="$3"

    # Convert to float for comparison
    local current=$(echo "$current_value" | sed 's/[^0-9.]//g')
    local thresh=$(echo "$threshold" | sed 's/[^0-9.]//g')

    case "$operator" in
        ">")   [ "$(echo "$current > $thresh" | bc 2>/dev/null || echo 0)" -eq 1 ] ;;
        "<")   [ "$(echo "$current < $thresh" | bc 2>/dev/null || echo 0)" -eq 1 ] ;;
        ">=")  [ "$(echo "$current >= $thresh" | bc 2>/dev/null || echo 0)" -eq 1 ] ;;
        "<=")  [ "$(echo "$current <= $thresh" | bc 2>/dev/null || echo 0)" -eq 1 ] ;;
        "==")  [ "$current" = "$threshold" ] ;;
        "!=")  [ "$current" != "$threshold" ] ;;
        "exists") [ "$current_value" = "exists" ] ;;
        "not_exists") [ "$current_value" = "not_exists" ] ;;
        *) return 1 ;;
    esac
}

# Send alert notification
send_alert() {
    local alert_name="$1"
    local severity="$2"
    local message="$3"
    local rule_data="$4"

    # Parse channel configuration
    if [ -f "$ALERT_CHANNELS_FILE" ]; then
        # Console output
        if grep -q "console:" "$ALERT_CHANNELS_FILE" && grep -A1 "console:" "$ALERT_CHANNELS_FILE" | grep -q "enabled: true"; then
            output_to_console "$severity" "$alert_name" "$message"
        fi

        # File logging
        if grep -A2 "file:" "$ALERT_CHANNELS_FILE" | grep -q "enabled: true"; then
            log_to_file "$alert_name" "$severity" "$message" "$rule_data"
        fi

        # Email notification (if configured)
        if grep -A2 "email:" "$ALERT_CHANNELS_FILE" | grep -q "enabled: true"; then
            send_email_alert "$alert_name" "$severity" "$message"
        fi

        # Slack notification (if configured)
        if grep -A2 "slack:" "$ALERT_CHANNELS_FILE" | grep -q "enabled: true"; then
            send_slack_alert "$alert_name" "$severity" "$message"
        fi
    fi
}

# Output to console with colors
output_to_console() {
    local severity="$1"
    local name="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$severity" in
        critical) echo -e "${RED}[CRITICAL]${NC} [$timestamp] $name: $message" ;;
        error)    echo -e "${RED}[ERROR]${NC} [$timestamp] $name: $message" ;;
        warning)  echo -e "${YELLOW}[WARNING]${NC} [$timestamp] $name: $message" ;;
        info)     echo -e "${BLUE}[INFO]${NC} [$timestamp] $name: $message" ;;
        *)        echo -e "[${severity^^}] [$timestamp] $name: $message" ;;
    esac
}

# Log to file
log_to_file() {
    local name="$1"
    local severity="$2"
    local message="$3"
    local rule_data="$4"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local log_entry="{
      \"timestamp\": \"$timestamp\",
      \"alert_name\": \"$name\",
      \"severity\": \"$severity\",
      \"message\": \"$message\",
      \"rule\": $rule_data
    }"

    echo "$log_entry" >> "$ALERT_LOG_FILE"
}

# Main monitoring loop
run_monitoring() {
    log_info "Starting alert monitoring loop..."

    while true; do
        # Get current system metrics
        local metrics_json=$(get_system_metrics)

        # Parse rules and evaluate
        if command -v python3 &> /dev/null; then
            python3 -c "
import json
import yaml
import sys
from datetime import datetime, timedelta

# Load rules
with open('$ALERT_RULES_FILE') as f:
    config = yaml.safe_load(f)

# Load metrics
metrics = json.loads('''$metrics_json''')

# Load active alerts
try:
    with open('$ALERT_STATE_DIR/active_alerts.json') as f:
        active_alerts = json.load(f)
except:
    active_alerts = {}

# Evaluate rules
for rule in config.get('rules', []):
    if not rule.get('enabled', True):
        continue

    name = rule['name']
    alert_key = name

    # Get current value based on rule type
    if rule['type'] == 'system':
        current_value = metrics.get(rule['metric'], 0)
    elif rule['type'] == 'service':
        # Service health check would be implemented here
        continue  # Skip for now
    elif rule['type'] == 'process':
        # Process check would be implemented here
        continue  # Skip for now
    else:
        continue

    # Evaluate condition
    operator = rule['condition']
    threshold = rule['threshold']

    # Simple numeric comparison
    alert_triggered = False
    try:
        current_val = float(str(current_value).replace('%', '').strip())
        threshold_val = float(str(threshold).replace('%', '').strip())

        if operator == '>':
            alert_triggered = current_val > threshold_val
        elif operator == '<':
            alert_triggered = current_val < threshold_val
    except ValueError:
        # Fallback for non-numeric comparisons
        if operator == '!=':
            alert_triggered = str(current_value) != str(threshold)
        elif operator == '==':
            alert_triggered = str(current_value) == str(threshold)

    if alert_triggered:
        # Alert is triggered
        if alert_key not in active_alerts:
            # New alert
            print(f'ALERT:{name}:{rule[\"severity\"]}:{rule[\"message\"]}:{json.dumps(rule)}')
            active_alerts[alert_key] = {
                'started_at': datetime.now().isoformat(),
                'severity': rule['severity'],
                'count': 1
            }
        else:
            # Update existing alert
            active_alerts[alert_key]['count'] += 1
    else:
        # Alert condition cleared
        if alert_key in active_alerts:
            print(f'CLEARED:{name}')
            del active_alerts[alert_key]

# Save active alerts
with open('$ALERT_STATE_DIR/active_alerts.json', 'w') as f:
    json.dump(active_alerts, f, indent=2)
"
        fi

        sleep 30  # Check every 30 seconds
    done
}

# Check system alerts manually
check_alerts() {
    echo -e "${BLUE}=== System Alert Check ===${NC}"
    echo ""

    # Get current metrics
    local metrics=$(get_system_metrics)
    echo -e "${CYAN}Current System Metrics:${NC}"
    echo "$metrics" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
for key, value in data.items():
    if key != 'timestamp':
        print(f'  {key}: {value}')
"
    echo ""

    # Check for active alerts
    echo -e "${CYAN}Active Alerts:${NC}"
    if [ -f "$ALERT_STATE_DIR/active_alerts.json" ]; then
        local alert_count=$(python3 -c "
import json
with open('$ALERT_STATE_DIR/active_alerts.json') as f:
    alerts = json.load(f)
print(len(alerts))
")

        if [ "$alert_count" -gt 0 ]; then
            echo -e "${YELLOW}$alert_count active alert(s):${NC}"
            python3 -c "
import json
from datetime import datetime
with open('$ALERT_STATE_DIR/active_alerts.json') as f:
    alerts = json.load(f)
for name, data in alerts.items():
    print(f'  • {name} ({data[\"severity\"]}) - started: {data[\"started_at\"]}')
"
        else
            echo -e "${GREEN}No active alerts${NC}"
        fi
    else
        echo -e "${YELLOW}Alert state not initialized${NC}"
    fi
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            init_alerting
            ;;
        start)
            init_alerting
            run_monitoring
            ;;
        check)
            check_alerts
            ;;
        status)
            check_alerts
            ;;
        help|--help|-h)
            cat << 'HELP'
Univers Alert Engine

Usage: alert-engine <command> [options]

Commands:
    init                Initialize alerting system
    start               Start monitoring loop
    check, status       Check current system status and alerts
    help, --help        Show this help message

HELP
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            echo "Run 'alert-engine help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"