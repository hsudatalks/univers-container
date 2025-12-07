#!/usr/bin/env bash
#
# Univers Ops Manager
# hvac-operation 项目运维服务管理 - 核心实现
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
# 项目配置
# ============================================
REPOS_ROOT="$(get_repos_root)"
PROJECT_ROOT="$REPOS_ROOT/hvac-operation"
AGENTS_DIR="$PROJECT_ROOT/univers-ark-agents"

# 验证项目存在
if [ ! -d "$PROJECT_ROOT" ]; then
    log_error "hvac-operation 项目不存在: $PROJECT_ROOT"
    exit 1
fi

# ============================================
# Agents 服务管理
# ============================================
SESSION_NAME="univers-agents"
WINDOW_NAME="agents"

start_agents() {
    local mode="${1:-dev}"

    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        return 1
    fi

    if [ ! -d "$AGENTS_DIR" ]; then
        log_error "Agents 目录不存在: $AGENTS_DIR"
        return 1
    fi

    log_service "启动 Agents 服务: $SESSION_NAME (模式: $mode)"
    create_session "$SESSION_NAME" "$WINDOW_NAME" "$AGENTS_DIR"

    case "$mode" in
        dev|development)
            send_command "$SESSION_NAME:$WINDOW_NAME" "pnpm dev"
            ;;
        serve)
            send_command "$SESSION_NAME:$WINDOW_NAME" "pnpm serve"
            ;;
        start|prod|production)
            send_command "$SESSION_NAME:$WINDOW_NAME" "pnpm start"
            ;;
        build)
            send_command "$SESSION_NAME:$WINDOW_NAME" "pnpm build && pnpm start"
            ;;
        *)
            log_warning "未知模式: $mode，使用默认 dev 模式"
            send_command "$SESSION_NAME:$WINDOW_NAME" "pnpm dev"
            ;;
    esac

    log_success "Agents 服务已启动"
}

stop_agents() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 0
    fi

    send_keys "$SESSION_NAME:$WINDOW_NAME" C-c
    sleep 1
    kill_session "$SESSION_NAME"
    log_success "Agents 服务已停止"
}

restart_agents() {
    local mode="${1:-dev}"
    log_service "重启 Agents 服务..."
    stop_agents
    sleep 2
    start_agents "$mode"
}

status_agents() {
    check_tmux

    local status
    status="$(get_session_status "$SESSION_NAME")"

    echo -e "${CYAN}Agents 服务状态${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "会话名: $SESSION_NAME"
    echo "目录: $AGENTS_DIR"

    case "$status" in
        running) echo -e "状态: ${GREEN}运行中${NC}" ;;
        idle)    echo -e "状态: ${YELLOW}空闲${NC}" ;;
        stopped) echo -e "状态: ${RED}已停止${NC}" ;;
    esac
}

logs_agents() {
    local lines="${1:-50}"
    show_session_logs "$SESSION_NAME" "$WINDOW_NAME" "$lines"
}

attach_agents() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_error "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "连接到 Agents 会话..."
    attach_session "$SESSION_NAME"
}

# ============================================
# 帮助信息
# ============================================
show_help() {
    cat << EOF
Univers Ops Manager - hvac-operation 运维服务管理

用法:
    univers ops <command> [args...]

服务管理:
    agents start [mode]     启动 AI Agents 服务
                            模式: dev (默认), serve, prod, build
    agents stop             停止 Agents 服务
    agents restart [mode]   重启 Agents 服务
    agents status           查看状态
    agents logs [N]         查看日志 (默认 50 行)
    agents attach           连接到会话

其他命令:
    status                  显示服务状态
    help                    显示此帮助

示例:
    univers ops agents start
    univers ops agents start serve
    univers ops agents logs 100
    univers ops status

注意: 运维终端请使用 'univers work operator'

项目路径: $PROJECT_ROOT
EOF
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
        help|--help|-h)
            show_help
            ;;

        agents)
            local action="${1:-status}"
            shift || true

            case "$action" in
                start)   start_agents "$@" ;;
                stop)    stop_agents ;;
                restart) restart_agents "$@" ;;
                status)  status_agents ;;
                logs)    logs_agents "${1:-50}" ;;
                attach)  attach_agents ;;
                *)
                    log_error "未知操作: $action"
                    echo "可用操作: start, stop, restart, status, logs, attach"
                    exit 1
                    ;;
            esac
            ;;

        status)
            status_agents
            ;;

        # 提示 operator 已移到 work
        operator)
            log_warning "operator 已移动到 'univers work operator'"
            echo ""
            echo "请使用: univers work operator $*"
            exit 1
            ;;

        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
