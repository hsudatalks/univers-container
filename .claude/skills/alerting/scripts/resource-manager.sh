#!/usr/bin/env bash
# Univers Resource Manager
# Resource-centric management and automation platform

set -e

# Configuration
RESOURCE_CONFIG_DIR="${RESOURCE_CONFIG_DIR:-$HOME/.config/univers/resources}"
RESOURCE_STATE_DIR="$RESOURCE_CONFIG_DIR/state"
RESOURCE_POLICIES_FILE="$RESOURCE_CONFIG_DIR/policies.yaml"
RESOURCE_REGISTRY_FILE="$RESOURCE_STATE_DIR/registry.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Initialize resource manager
init_resource_manager() {
    echo -e "${CYAN}Initializing Univers Resource Manager...${NC}"

    # Create directories
    mkdir -p "$RESOURCE_CONFIG_DIR"/{state,policies,schemas}

    # Create resource registry
    if [ ! -f "$RESOURCE_REGISTRY_FILE" ]; then
        echo "{}" > "$RESOURCE_REGISTRY_FILE"
    fi

    # Create default policies
    create_default_policies

    echo -e "${GREEN}✅ Resource Manager initialized${NC}"
}

# Create default resource policies
create_default_policies() {
    if [ ! -f "$RESOURCE_POLICIES_FILE" ]; then
        cat > "$RESOURCE_POLICIES_FILE" << 'EOF'
# Univers Resource Management Policies

policies:
  # System Resource Policies
  - name: "cpu-high-monitoring"
    resource_type: "cpu"
    condition: "usage_percent > 80"
    actions:
      - type: "monitor"
        interval: "30s"
      - type: "alert"
        threshold: 90
        severity: "warning"

  - name: "memory-cleanup"
    resource_type: "memory"
    condition: "usage_percent > 85"
    actions:
      - type: "cleanup"
        target: "cache"
      - type: "alert"
        threshold: 95
        severity: "critical"

  - name: "disk-space-monitoring"
    resource_type: "disk"
    condition: "usage_percent > 85"
    actions:
      - type: "cleanup"
        target: "temp_files"
        age: "7d"
      - type: "alert"
        threshold: 90
        severity: "warning"

  # Service Resource Policies
  - name: "univers-service-auto-restart"
    resource_type: "univers_service"
    condition: "status == error"
    actions:
      - type: "restart"
        delay: "30s"
        max_attempts: 3
      - type: "alert"
        if: "restart_attempts > 2"

  - name: "univers-session-monitoring"
    resource_type: "tmux_session"
    condition: "name in ['univers-developer', 'univers-server', 'univers-ui', 'univers-web']"
    actions:
      - type: "monitor"
        check_interval: "60s"
      - type: "alert"
        condition: "status == missing"
        severity: "info"

  # Network Resource Policies
  - name: "port-monitoring"
    resource_type: "port"
    condition: "number in [3003, 6007, 5173]"
    actions:
      - type: "monitor"
        check_interval: "30s"
      - type: "alert"
        condition: "status == closed"
        severity: "warning"
EOF
    fi
}

# Resource discovery
discover_resources() {
    echo -e "${BLUE}🔍 Discovering resources...${NC}"

    local discovery_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local resources="{}"

    # Discover system resources
    resources=$(echo "$resources" | python3 -c "
import json
import sys
import subprocess
import psutil

data = json.load(sys.stdin)

# CPU Resource
cpu_info = {
    'resource_id': 'cpu:system',
    'type': 'cpu',
    'attributes': {
        'usage_percent': psutil.cpu_percent(interval=1),
        'core_count': psutil.cpu_count(),
        'load_average': psutil.getloadavg()[0] if hasattr(psutil, 'getloadavg') else 0
    },
    'status': 'healthy',
    'last_updated': '$discovery_time',
    'actions_available': ['monitor', 'throttle', 'optimize', 'alert']
}
data['cpu:system'] = cpu_info

# Memory Resource
memory = psutil.virtual_memory()
mem_info = {
    'resource_id': 'memory:system',
    'type': 'memory',
    'attributes': {
        'usage_percent': memory.percent,
        'available_gb': round(memory.available / (1024**3), 2),
        'total_gb': round(memory.total / (1024**3), 2)
    },
    'status': 'healthy' if memory.percent < 85 else 'warning',
    'last_updated': '$discovery_time',
    'actions_available': ['monitor', 'cleanup', 'optimize', 'alert']
}
data['memory:system'] = mem_info

# Disk Resource
disk = psutil.disk_usage('/')
disk_info = {
    'resource_id': 'disk:root',
    'type': 'disk',
    'attributes': {
        'usage_percent': round((disk.used / disk.total) * 100, 1),
        'available_gb': round(disk.free / (1024**3), 2),
        'total_gb': round(disk.total / (1024**3), 2)
    },
    'status': 'healthy' if disk.used / disk.total < 0.85 else 'warning',
    'last_updated': '$discovery_time',
    'actions_available': ['monitor', 'cleanup', 'optimize', 'alert', 'expand']
}
data['disk:root'] = disk_info

print(json.dumps(data, indent=2))
" 2>/dev/null || echo "$resources")

    # Discover Univers services
    services=("univers-server:3003:Backend API" "univers-ui:6007:Storybook UI" "univers-web:5173:Vite Web")
    for service_info in "${services[@]}"; do
        local name=$(echo "$service_info" | cut -d: -f1)
        local port=$(echo "$service_info" | cut -d: -f2)
        local desc=$(echo "$service_info" | cut -d: -f3)
        local resource_id="univers_service:$name"

        local status="stopped"
        local response_time=0

        if curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$port" 2>/dev/null | grep -q "200\|301\|302"; then
            status="running"
            response_time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 3 "http://localhost:$port" 2>/dev/null || echo "0")
        fi

        resources=$(echo "$resources" | python3 -c "
import json
import sys

data = json.load(sys.stdin)

service_info = {
    'resource_id': '$resource_id',
    'type': 'univers_service',
    'attributes': {
        'name': '$name',
        'port': $port,
        'description': '$desc',
        'response_time': round(float('$response_time'), 3)
    },
    'status': '$status',
    'last_updated': '$discovery_time',
    'actions_available': ['monitor', 'start', 'stop', 'restart', 'debug', 'logs', 'alert']
}

data['$resource_id'] = service_info
print(json.dumps(data, indent=2))
")
    done

    # Discover tmux sessions
    if command -v tmux &> /dev/null; then
        local tmux_sessions=$(tmux list-sessions 2>/dev/null | cut -d: -f1)
        while IFS= read -r session; do
            [ -z "$session" ] && continue

            local resource_id="tmux_session:$session"
            resources=$(echo "$resources" | python3 -c "
import json
import sys

data = json.load(sys.stdin)

session_info = {
    'resource_id': '$resource_id',
    'type': 'tmux_session',
    'attributes': {
        'name': '$session',
        'windows_count': len([w for w in '$(tmux list-windows -t "$session" 2>/dev/null | wc -l)'.split()])
    },
    'status': 'active',
    'last_updated': '$discovery_time',
    'actions_available': ['monitor', 'attach', 'detach', 'kill', 'restart', 'optimize', 'alert']
}

data['$resource_id'] = session_info
print(json.dumps(data, indent=2))
")
        done <<< "$tmux_sessions"
    fi

    # Save to registry
    echo "$resources" > "$RESOURCE_REGISTRY_FILE"

    # Count resources
    local resource_count=$(echo "$resources" | python3 -c "import json, sys; print(len(json.load(sys.stdin)))")
    echo -e "${GREEN}✅ Discovered $resource_count resources${NC}"
}

# List resources by type
list_resources() {
    local type_filter="$1"

    if [ ! -f "$RESOURCE_REGISTRY_FILE" ]; then
        echo -e "${YELLOW}No resources found. Run 'resource discover' first.${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📋 Resource Inventory${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if command -v python3 &> /dev/null; then
        python3 -c "
import json
from datetime import datetime

with open('$RESOURCE_REGISTRY_FILE') as f:
    resources = json.load(f)

# Filter by type if specified
if '$type_filter':
    filtered = {k: v for k, v in resources.items() if v['type'] == '$type_filter'}
else:
    filtered = resources

# Group by type
by_type = {}
for resource_id, resource in filtered.items():
    resource_type = resource['type']
    if resource_type not in by_type:
        by_type[resource_type] = []
    by_type[resource_type].append(resource)

# Display by type
for resource_type, type_resources in sorted(by_type.items()):
    print(f'{resource_type.upper()} Resources ({len(type_resources)}):')
    print()

    for resource in type_resources:
        resource_id = resource['resource_id']
        status = resource['status']
        last_updated = resource['last_updated']

        # Status color indicators
        if status == 'healthy' or status == 'running' or status == 'active':
            status_icon = '✅'
        elif status == 'warning':
            status_icon = '⚠️ '
        elif status == 'error' or status == 'stopped':
            status_icon = '❌'
        else:
            status_icon = '❓'

        print(f'  {status_icon} {resource_id} - {status}')

        # Show key attributes
        attrs = resource['attributes']
        if 'usage_percent' in attrs:
            print(f'     Usage: {attrs[\"usage_percent\"]}%')
        if 'port' in attrs:
            print(f'     Port: {attrs[\"port\"]} ({attrs.get(\"description\", \"\")})')
        if 'name' in attrs and resource_type == 'tmux_session':
            print(f'     Session: {attrs[\"name\"]}')

        print()
"
    else
        echo "Python3 required for detailed resource listing"
        cat "$RESOURCE_REGISTRY_FILE"
    fi
}

# Show resource details
show_resource_info() {
    local resource_id="$1"

    if [ -z "$resource_id" ]; then
        echo -e "${RED}Error: Resource ID required${NC}"
        return 1
    fi

    if [ ! -f "$RESOURCE_REGISTRY_FILE" ]; then
        echo -e "${RED}Error: No resources found. Run 'resource discover' first.${NC}"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 -c "
import json
from datetime import datetime

with open('$RESOURCE_REGISTRY_FILE') as f:
    resources = json.load(f)

if '$resource_id' not in resources:
    print(f'Resource not found: {$resource_id}')
    sys.exit(1)

resource = resources['$resource_id']

print(f'Resource ID: {resource[\"resource_id\"]}')
print(f'Type: {resource[\"type\"]}')
print(f'Status: {resource[\"status\"]}')
print(f'Last Updated: {resource[\"last_updated\"]}')
print()

print('Attributes:')
for key, value in resource['attributes'].items():
    print(f'  {key}: {value}')

print()
print('Available Actions:')
for action in resource['actions_available']:
    print(f'  • {action}')
"
    else
        echo "Python3 required for detailed resource information"
    fi
}

# Execute action on resource
execute_resource_action() {
    local action="$1"
    local resource_id="$2"
    shift 2
    local options="$@"

    if [ -z "$action" ] || [ -z "$resource_id" ]; then
        echo -e "${RED}Error: Action and resource ID required${NC}"
        echo "Usage: resource <action> <resource_id> [options]"
        return 1
    fi

    # Extract resource type from resource_id
    local resource_type=$(echo "$resource_id" | cut -d: -f1)

    echo -e "${BLUE}🎬 Executing '$action' on '$resource_id'${NC}"

    case "$resource_type" in
        "univers_service")
            execute_service_action "$action" "$resource_id" "$options"
            ;;
        "tmux_session")
            execute_session_action "$action" "$resource_id" "$options"
            ;;
        "memory"|"cpu"|"disk")
            execute_system_action "$action" "$resource_type" "$options"
            ;;
        *)
            echo -e "${YELLOW}Action not implemented for resource type: $resource_type${NC}"
            return 1
            ;;
    esac
}

# Execute service actions
execute_service_action() {
    local action="$1"
    local resource_id="$2"
    local service_name=$(echo "$resource_id" | cut -d: -f2)

    case "$action" in
        "start"|"restart")
            echo -e "${CYAN}Starting $service_name...${NC}"
            # Try multiple script locations
            local script_paths=(
                "/home/ubuntu/repos/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-${service_name}.sh"
                "/home/ubuntu/repos/univers-container/.claude/skills/univers-core/dev/tmux-${service_name}.sh"
                "/home/ubuntu/repos/hvac-workbench/apps/dev-tools/scripts/tmux-${service_name}.sh"
            )

            # Special handling for univers services
            if [[ "$service_name" == univers-* ]]; then
                script_paths+=(
                    "/home/ubuntu/repos/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-${service_name#univers-}.sh"
                    "/home/ubuntu/repos/univers-container/.claude/skills/univers-core/dev/tmux-${service_name#univers-}.sh"
                )
            fi

            for script_path in "${script_paths[@]}"; do
                if [ -f "$script_path" ]; then
                    bash "$script_path" start
                    echo -e "${GREEN}✅ $service_name started${NC}"
                    return 0
                fi
            done
            echo -e "${RED}Service script not found for $service_name${NC}"
            echo -e "${YELLOW}Tried paths:${NC}"
            printf '  %s\n' "${script_paths[@]}"
            ;;
        "stop")
            echo -e "${CYAN}Stopping $service_name...${NC}"
            local script_paths=(
                "/home/ubuntu/repos/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-${service_name}.sh"
                "/home/ubuntu/repos/univers-container/.claude/skills/univers-core/dev/tmux-${service_name}.sh"
                "/home/ubuntu/repos/hvac-workbench/apps/dev-tools/scripts/tmux-${service_name}.sh"
            )

            for script_path in "${script_paths[@]}"; do
                if [ -f "$script_path" ]; then
                    bash "$script_path" stop
                    echo -e "${GREEN}✅ $service_name stopped${NC}"
                    return 0
                fi
            done
            echo -e "${RED}Service script not found for $service_name${NC}"
            ;;
        "status")
            echo -e "${CYAN}Checking $service_name status...${NC}"
            local script_paths=(
                "/home/ubuntu/repos/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-${service_name}.sh"
                "/home/ubuntu/repos/univers-container/.claude/skills/univers-core/dev/tmux-${service_name}.sh"
                "/home/ubuntu/repos/hvac-workbench/apps/dev-tools/scripts/tmux-${service_name}.sh"
            )

            for script_path in "${script_paths[@]}"; do
                if [ -f "$script_path" ]; then
                    bash "$script_path" status
                    return 0
                fi
            done
            echo -e "${RED}Service script not found for $service_name${NC}"
            ;;
        *)
            echo -e "${YELLOW}Action '$action' not implemented for services${NC}"
            ;;
    esac
}

# Execute session actions
execute_session_action() {
    local action="$1"
    local resource_id="$2"
    local session_name=$(echo "$resource_id" | cut -d: -f2)

    case "$action" in
        "attach")
            echo -e "${CYAN}Attaching to tmux session: $session_name${NC}"
            tmux attach-session -t "$session_name"
            ;;
        "detach")
            echo -e "${CYAN}Detaching from tmux session: $session_name${NC}"
            tmux detach-client -s "$session_name" 2>/dev/null || echo -e "${YELLOW}Session not attached or not found${NC}"
            ;;
        "kill")
            echo -e "${CYAN}Killing tmux session: $session_name${NC}"
            tmux kill-session -t "$session_name" 2>/dev/null && echo -e "${GREEN}✅ Session killed${NC}" || echo -e "${YELLOW}Session not found${NC}"
            ;;
        *)
            echo -e "${YELLOW}Action '$action' not implemented for tmux sessions${NC}"
            ;;
    esac
}

# Execute system actions
execute_system_action() {
    local action="$1"
    local resource_type="$2"

    case "$action" in
        "monitor")
            echo -e "${CYAN}Monitoring $resource_type resources...${NC}"
            # This would integrate with the monitoring system
            echo -e "${BLUE}📊 Current $resource_type status:${NC}"
            if [ "$resource_type" = "memory" ]; then
                free -h
                echo ""
                echo -e "${YELLOW}Available actions: cleanup, optimize${NC}"
            elif [ "$resource_type" = "cpu" ]; then
                top -bn1 | head -10
                echo ""
                echo -e "${YELLOW}Available actions: throttle, optimize${NC}"
            elif [ "$resource_type" = "disk" ]; then
                df -h
                echo ""
                echo -e "${YELLOW}Available actions: cleanup, expand${NC}"
            fi
            ;;
        "cleanup")
            echo -e "${CYAN}Cleaning up $resource_type resources...${NC}"
            if [ "$resource_type" = "memory" ]; then
                echo "Clearing system cache..."
                sudo sync && sudo sysctl vm.drop_caches=3 2>/dev/null || echo -e "${YELLOW}Cache cleanup requires sudo privileges${NC}"
                echo -e "${GREEN}✅ Memory cleanup initiated${NC}"
            elif [ "$resource_type" = "disk" ]; then
                echo "Cleaning temporary files..."
                find /tmp -type f -atime +7 -delete 2>/dev/null || true
                echo -e "${GREEN}✅ Disk cleanup completed${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}Action '$action' not implemented for $resource_type${NC}"
            ;;
    esac
}

# Show policies
show_policies() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📋 Resource Management Policies${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ! -f "$RESOURCE_POLICIES_FILE" ]; then
        echo -e "${YELLOW}No policies configured. Run 'resource init' first.${NC}"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 -c "
import yaml

with open('$RESOURCE_POLICIES_FILE') as f:
    config = yaml.safe_load(f)

policies = config.get('policies', [])

if not policies:
    print('No policies configured.')
    sys.exit(0)

for i, policy in enumerate(policies, 1):
    print(f'{i}. {policy[\"name\"]}')
    print(f'   Resource Type: {policy[\"resource_type\"]}')
    print(f'   Condition: {policy[\"condition\"]}')

    actions = policy.get('actions', [])
    if actions:
        print('   Actions:')
        for action in actions:
            action_type = action['type']
            if action_type in ['restart', 'cleanup', 'alert']:
                print(f'     • {action_type}')
                if 'max_attempts' in action:
                    print(f'       Max attempts: {action[\"max_attempts\"]}')
                if 'threshold' in action:
                    print(f'       Threshold: {action[\"threshold\"]}')
    print()
"
    else
        echo "Python3 required for policy parsing"
        cat "$RESOURCE_POLICIES_FILE"
    fi
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            init_resource_manager
            ;;
        discover)
            discover_resources
            ;;
        list)
            list_resources "$1"
            ;;
        info)
            show_resource_info "$1"
            ;;
        start|stop|restart|monitor|cleanup|attach|detach|kill|status)
            execute_resource_action "$command" "$@"
            ;;
        policies)
            show_policies
            ;;
        help|--help|-h)
            cat << 'HELP'
Univers Resource Manager - Resource-centric management and automation

Usage: resource <command> [options]

Discovery and Status:
    discover                  Discover all available resources
    list [type]              List resources (filter by type: cpu, memory, disk, univers_service, tmux_session)
    info <resource_id>       Show detailed resource information
    policies                 Show configured management policies

Resource Actions:
    start <resource_id>      Start a resource (services)
    stop <resource_id>       Stop a resource (services)
    restart <resource_id>    Restart a resource (services)
    status <resource_id>     Check resource status (services)

    attach <resource_id>     Attach to tmux session
    detach <resource_id>     Detach from tmux session
    kill <resource_id>       Kill tmux session

    monitor <resource_type>  Monitor system resources (cpu, memory, disk)
    cleanup <resource_type>  Clean up system resources (memory, disk)

Examples:
    resource discover                           # Find all resources
    resource list univers_service              # List all Univers services
    resource info univers_service:univers-server  # Service details
    resource start univers_service:univers-server  # Start service
    resource attach tmux_session:univers-developer  # Connect to session
    resource monitor memory                    # Monitor memory usage
    resource cleanup memory                    # Clean up memory

Resource IDs format:
    - cpu:system
    - memory:system
    - disk:root
    - univers_service:<name>
    - tmux_session:<name>

HELP
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}"
            echo "Run 'resource help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"