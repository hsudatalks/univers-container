#!/usr/bin/env bash
#
# Univers Work Manager
# 管理 AI Agent 工作会话 (developer, operator 等)
#

set -euo pipefail

# ============================================
# 加载核心库
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$CORE_LIB/common.sh"
source "$CORE_LIB/tmux-utils.sh"
source "$CORE_LIB/service-manager.sh"

# ============================================
# 项目路径
# ============================================
REPOS_ROOT="$(get_repos_root)"
WORKBENCH_ROOT="$REPOS_ROOT/hvac-workbench"
OPERATION_ROOT="$REPOS_ROOT/hvac-operation"

# ============================================
# 注册工作会话
# ============================================
register_service "developer" "$SCRIPT_DIR/tmux-developer.sh" "univers-developer"
register_service "operator" "$SCRIPT_DIR/tmux-operator.sh" "univers-operator"

# ============================================
# 帮助信息
# ============================================
show_help() {
    cat << EOF
Univers Work Manager - AI Agent 工作会话管理

用法:
    univers work <session> <action> [options]

工作会话:
    developer       开发终端 (hvac-workbench)
    operator        运维终端 (hvac-operation)

操作:
    start           启动会话
    stop            停止会话
    restart         重启会话
    status          查看状态
    logs [N]        查看日志 (默认 50 行)
    attach          连接到会话

其他命令:
    status          显示所有工作会话状态
    start-all       启动所有工作会话
    stop-all        停止所有工作会话
    help            显示此帮助

示例:
    univers work developer start
    univers work operator start
    univers work status
    univers work start-all

会话说明:
    developer - 用于 hvac-workbench 项目的 AI 开发终端
    operator  - 用于 hvac-operation 项目的 AI 运维终端
EOF
}

# ============================================
# 批量操作
# ============================================
start_all_sessions() {
    log_info "启动所有工作会话..."
    echo ""

    for session in developer operator; do
        start_service "$session" || true
        echo ""
    done

    log_success "所有工作会话已启动"
}

stop_all_sessions() {
    log_warning "停止所有工作会话..."
    echo ""

    for session in developer operator; do
        stop_service "$session" || true
    done

    log_success "所有工作会话已停止"
}

# ============================================
# 处理服务命令
# ============================================
handle_service() {
    local service="$1"
    local action="${2:-status}"
    shift 2 || shift || true

    case "$action" in
        start)
            start_service "$service" "$@"
            ;;
        stop)
            stop_service "$service"
            ;;
        restart)
            restart_service "$service" "$@"
            ;;
        status)
            status_service "$service"
            ;;
        logs)
            logs_service "$service" "${1:-50}"
            ;;
        attach)
            attach_service "$service"
            ;;
        *)
            log_error "未知操作: $action"
            echo "可用操作: start, stop, restart, status, logs, attach"
            exit 1
            ;;
    esac
}

# ============================================
# 主入口
# ============================================
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        # 帮助
        help|--help|-h)
            show_help
            ;;

        # 工作会话
        developer|dev)
            handle_service "developer" "$@"
            ;;

        operator|op)
            handle_service "operator" "$@"
            ;;

        # 批量操作
        status)
            status_all_services
            ;;

        start-all)
            start_all_sessions
            ;;

        stop-all)
            stop_all_sessions
            ;;

        # 未知命令
        *)
            log_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
