#!/usr/bin/env bash
#
# Tmux Agents Manager
# 管理 univers-ark-agents 服务的 tmux 会话
#

set -e

# ============================================
# 加载核心库
# ============================================
UNIVERS_CORE="/home/davidxu/repos/univers-container/.claude/skills/univers-core/lib"
source "$UNIVERS_CORE/common.sh"
source "$UNIVERS_CORE/tmux-utils.sh"

# 确保非 root 运行
ensure_non_root "$@"

# ============================================
# 配置
# ============================================
SESSION_NAME="univers-agents"
WINDOW_NAME="agents"
SCRIPT_DIR="$(get_script_dir)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
AGENTS_DIR="$PROJECT_ROOT/univers-ark-agents"

# ============================================
# 启动服务
# ============================================
start_agents() {
    local mode="${1:-dev}"

    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        log_info "使用以下命令:"
        echo "  $0 attach   - 连接到会话"
        echo "  $0 status   - 查看状态"
        echo "  $0 stop     - 停止会话"
        return 1
    fi

    # 检查目录
    if [ ! -d "$AGENTS_DIR" ]; then
        log_error "Agents 目录不存在: $AGENTS_DIR"
        return 1
    fi

    log_service "启动 Agents 服务: $SESSION_NAME (模式: $mode)"

    # 创建会话
    create_session "$SESSION_NAME" "$WINDOW_NAME" "$AGENTS_DIR"

    # 加载状态栏配置（如果有）
    local statusbar_config="$SCRIPT_DIR/../configs/agents-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        load_statusbar_config "$SESSION_NAME" "$statusbar_config"
    fi

    # 发送启动命令
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
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到会话 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看历史输出"
    echo "  $0 stop     - 停止会话"
    echo "  $0 status   - 查看状态"
    echo ""
    log_info "这是一个持久化的服务会话，关闭终端窗口也不会消失"
}

# ============================================
# 停止服务
# ============================================
stop_agents() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 0
    fi

    # 发送 Ctrl+C 停止进程
    send_keys "$SESSION_NAME:$WINDOW_NAME" C-c
    sleep 1

    # 销毁会话
    kill_session "$SESSION_NAME"
    log_success "Agents 服务已停止"
}

# ============================================
# 重启服务
# ============================================
restart_agents() {
    local mode="${1:-dev}"

    log_service "重启 Agents 服务..."
    stop_agents
    sleep 2
    start_agents "$mode"
}

# ============================================
# 查看状态
# ============================================
status_agents() {
    check_tmux

    local status
    status="$(get_session_status "$SESSION_NAME")"

    echo -e "${CYAN}Agents 服务状态${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "会话名: $SESSION_NAME"
    echo "目录: $AGENTS_DIR"

    case "$status" in
        running)
            echo -e "状态: ${GREEN}运行中${NC}"
            ;;
        idle)
            echo -e "状态: ${YELLOW}空闲${NC}"
            ;;
        stopped)
            echo -e "状态: ${RED}已停止${NC}"
            ;;
    esac

    # 显示端口信息（如果服务运行中）
    if [ "$status" = "running" ]; then
        local port=$(grep -E "PORT|port" "$AGENTS_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2)
        if [ -n "$port" ]; then
            echo "端口: $port"
        fi
    fi
}

# ============================================
# 查看日志
# ============================================
logs_agents() {
    local lines="${1:-50}"
    show_session_logs "$SESSION_NAME" "$WINDOW_NAME" "$lines"
}

# ============================================
# 连接会话
# ============================================
attach_agents() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_error "会话 '$SESSION_NAME' 不存在"
        log_info "使用 '$0 start' 启动服务"
        return 1
    fi

    log_info "连接到 Agents 会话... (按 Ctrl+B 然后 D 退出)"
    attach_session "$SESSION_NAME"
}

# ============================================
# 帮助
# ============================================
show_help() {
    cat << EOF
Tmux Agents Manager - univers-ark-agents 服务管理

用法:
    $0 <command> [options]

命令:
    start [mode]    启动服务
                    模式: dev (默认), serve, start/prod, build
    stop            停止服务
    restart [mode]  重启服务
    status          查看状态
    logs [N]        查看最近 N 行日志 (默认 50)
    attach          连接到会话

示例:
    $0 start              # 开发模式启动
    $0 start serve        # 服务模式启动
    $0 logs 100           # 查看最近 100 行日志
    $0 restart            # 重启服务

目录: $AGENTS_DIR
EOF
}

# ============================================
# 主入口
# ============================================
case "${1:-help}" in
    start)
        start_agents "${2:-dev}"
        ;;
    stop)
        stop_agents
        ;;
    restart)
        restart_agents "${2:-dev}"
        ;;
    status)
        status_agents
        ;;
    logs)
        logs_agents "${2:-50}"
        ;;
    attach)
        attach_agents
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "未知命令: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
