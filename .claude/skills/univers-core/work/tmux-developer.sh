#!/usr/bin/env bash
#
# Tmux Developer Session
# AI 开发终端 - 用于 hvac-workbench 项目
#

set -e

# ============================================
# 加载核心库
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$CORE_LIB/common.sh"
source "$CORE_LIB/tmux-utils.sh"

# 确保非 root 运行
ensure_non_root "$@"

# ============================================
# 配置
# ============================================
SESSION_NAME="univers-developer"
WINDOW_NAME="developer"
REPOS_ROOT="$(get_repos_root)"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
STATUSBAR_CONFIG="$REPOS_ROOT/hvac-workbench/.claude/skills/univers-dev/configs/developer-statusbar.conf"

# ============================================
# 启动会话
# ============================================
do_start() {
    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        log_info "使用以下命令:"
        echo "  $0 attach   - 连接到会话"
        echo "  $0 status   - 查看状态"
        echo "  $0 stop     - 停止会话"
        return 1
    fi

    # 检查项目目录
    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "项目目录不存在: $PROJECT_ROOT"
        return 1
    fi

    log_service "创建 Developer 开发终端会话: $SESSION_NAME"

    # 创建会话
    create_session "$SESSION_NAME" "$WINDOW_NAME" "$PROJECT_ROOT"

    # 加载状态栏配置
    if [ -f "$STATUSBAR_CONFIG" ]; then
        load_statusbar_config "$SESSION_NAME" "$STATUSBAR_CONFIG"
        log_service "已加载状态栏配置: developer-statusbar.conf"
    fi

    # 发送欢迎消息
    send_welcome "$SESSION_NAME:$WINDOW_NAME" \
        "Developer Terminal - hvac-workbench" \
        "Project: $PROJECT_ROOT"

    log_success "Developer 开发终端已启动"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到会话 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看历史输出"
    echo "  $0 stop     - 停止会话"
    echo "  $0 status   - 查看状态"
    echo ""
    log_info "这是一个持久化的开发终端，关闭终端窗口也不会消失"
}

# ============================================
# 停止会话
# ============================================
do_stop() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 0
    fi

    kill_session "$SESSION_NAME"
    log_success "Developer 会话已停止"
}

# ============================================
# 重启会话
# ============================================
do_restart() {
    log_service "重启 Developer 会话..."
    do_stop
    sleep 1
    do_start
}

# ============================================
# 查看状态
# ============================================
do_status() {
    check_tmux

    local status
    status="$(get_session_status "$SESSION_NAME")"

    echo -e "${CYAN}Developer 终端状态${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "会话名: $SESSION_NAME"
    echo "项目: $PROJECT_ROOT"

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
}

# ============================================
# 查看日志
# ============================================
do_logs() {
    local lines="${1:-50}"
    show_session_logs "$SESSION_NAME" "$WINDOW_NAME" "$lines"
}

# ============================================
# 连接会话
# ============================================
do_attach() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_error "会话 '$SESSION_NAME' 不存在"
        log_info "使用 '$0 start' 启动会话"
        return 1
    fi

    log_info "连接到 Developer 会话... (按 Ctrl+B 然后 D 退出)"
    attach_session "$SESSION_NAME"
}

# ============================================
# 主入口
# ============================================
case "${1:-help}" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    logs)
        do_logs "${2:-50}"
        ;;
    attach)
        do_attach
        ;;
    help|--help|-h)
        echo "用法: $0 {start|stop|restart|status|logs|attach}"
        ;;
    *)
        log_error "未知命令: $1"
        echo "用法: $0 {start|stop|restart|status|logs|attach}"
        exit 1
        ;;
esac
