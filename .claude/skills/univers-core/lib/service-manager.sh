#!/usr/bin/env bash
#
# Univers Core - Service Manager
# 服务管理框架
#

# 防止重复加载
if [ -n "${_UNIVERS_SERVICE_MANAGER_LOADED:-}" ]; then
    return 0
fi
_UNIVERS_SERVICE_MANAGER_LOADED=1

# 加载依赖
SCRIPT_DIR_SVC_MGR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_SVC_MGR/common.sh"
source "$SCRIPT_DIR_SVC_MGR/tmux-utils.sh"

# ============================================
# 服务定义（兼容 Bash 3.2）
# ============================================

# 服务数据存储（使用全局变量）
_UNIVERS_SERVICE_COUNT=0

# 注册服务
register_service() {
    local name="$1"
    local script="$2"
    local session="${3:-univers-$name}"

    # 使用数组存储服务信息
    eval "_UNIVERS_SERVICE_${_UNIVERS_SERVICE_COUNT}_NAME=\"$name\""
    eval "_UNIVERS_SERVICE_${_UNIVERS_SERVICE_COUNT}_SCRIPT=\"$script\""
    eval "_UNIVERS_SERVICE_${_UNIVERS_SERVICE_COUNT}_SESSION=\"$session\""
    eval "_UNIVERS_SERVICE_${_UNIVERS_SERVICE_COUNT}_INDEX=$_UNIVERS_SERVICE_COUNT"

    _UNIVERS_SERVICE_COUNT=$((_UNIVERS_SERVICE_COUNT + 1))

    log_debug "注册服务: $name -> $script (session: $session)"
}

# 获取服务脚本路径
get_service_script() {
    local name="$1"
    local i
    for i in $(seq 0 $((_UNIVERS_SERVICE_COUNT - 1))); do
        eval "local svc_name=\"\${_UNIVERS_SERVICE_${i}_NAME}\""
        if [ "$svc_name" = "$name" ]; then
            eval "echo \"\${_UNIVERS_SERVICE_${i}_SCRIPT}\""
            return 0
        fi
    done
}

# 获取服务会话名
get_service_session() {
    local name="$1"
    local i
    for i in $(seq 0 $((_UNIVERS_SERVICE_COUNT - 1))); do
        eval "local svc_name=\"\${_UNIVERS_SERVICE_${i}_NAME}\""
        if [ "$svc_name" = "$name" ]; then
            eval "echo \"\${_UNIVERS_SERVICE_${i}_SESSION}\""
            return 0
        fi
    done
}

# 检查服务是否已注册
is_service_registered() {
    local name="$1"
    local i
    for i in $(seq 0 $((_UNIVERS_SERVICE_COUNT - 1))); do
        eval "local svc_name=\"\${_UNIVERS_SERVICE_${i}_NAME}\""
        if [ "$svc_name" = "$name" ]; then
            return 0
        fi
    done
    return 1
}

# 列出所有注册的服务
list_services() {
    local i
    local names=""
    for i in $(seq 0 $((_UNIVERS_SERVICE_COUNT - 1))); do
        eval "local svc_name=\"\${_UNIVERS_SERVICE_${i}_NAME}\""
        names="$names $svc_name"
    done
    echo "$names" | tr ' ' '\n' | grep -v '^$' | sort
}

# ============================================
# 服务操作
# ============================================

# 启动服务
start_service() {
    local name="$1"
    shift
    local args="$*"

    if ! is_service_registered "$name"; then
        log_error "未知服务: $name"
        return 1
    fi

    local script
    script="$(get_service_script "$name")"

    if [ ! -x "$script" ]; then
        log_error "服务脚本不可执行: $script"
        return 1
    fi

    log_service "启动服务: $name"
    "$script" start $args
}

# 停止服务
stop_service() {
    local name="$1"

    if ! is_service_registered "$name"; then
        log_error "未知服务: $name"
        return 1
    fi

    local script
    script="$(get_service_script "$name")"

    if [ ! -x "$script" ]; then
        log_error "服务脚本不可执行: $script"
        return 1
    fi

    log_service "停止服务: $name"
    "$script" stop
}

# 重启服务
restart_service() {
    local name="$1"
    shift
    local args="$*"

    log_service "重启服务: $name"
    stop_service "$name"
    sleep 2
    start_service "$name" $args
}

# 获取服务状态
status_service() {
    local name="$1"

    if ! is_service_registered "$name"; then
        log_error "未知服务: $name"
        return 1
    fi

    local script
    script="$(get_service_script "$name")"

    if [ -x "$script" ]; then
        "$script" status
    else
        local session
        session="$(get_service_session "$name")"
        local status
        status="$(get_session_status "$session")"
        echo -e "${CYAN}$name${NC}: $status"
    fi
}

# 显示服务日志
logs_service() {
    local name="$1"
    local lines="${2:-50}"

    if ! is_service_registered "$name"; then
        log_error "未知服务: $name"
        return 1
    fi

    local script
    script="$(get_service_script "$name")"

    if [ -x "$script" ]; then
        "$script" logs "$lines"
    else
        local session
        session="$(get_service_session "$name")"
        show_session_logs "$session" "" "$lines"
    fi
}

# 连接到服务会话
attach_service() {
    local name="$1"

    if ! is_service_registered "$name"; then
        log_error "未知服务: $name"
        return 1
    fi

    local script
    script="$(get_service_script "$name")"

    if [ -x "$script" ]; then
        "$script" attach
    else
        local session
        session="$(get_service_session "$name")"
        attach_session "$session"
    fi
}

# ============================================
# 批量操作
# ============================================

# 显示所有服务状态
status_all_services() {
    log_info "检查所有服务状态..."
    echo ""

    for name in $(list_services); do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        status_service "$name" || true
        echo ""
    done
}

# 停止所有服务
stop_all_services() {
    log_warning "停止所有服务..."

    local stopped=()
    local failed=()

    for name in $(list_services); do
        if stop_service "$name" 2>/dev/null; then
            stopped+=("$name")
        else
            failed+=("$name")
        fi
    done

    echo ""
    if [ ${#stopped[@]} -gt 0 ]; then
        log_success "已停止: ${stopped[*]}"
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        log_warning "未运行/失败: ${failed[*]}"
    fi
}

# ============================================
# 服务脚本生成器
# ============================================

# 生成标准服务脚本框架
generate_service_script() {
    local session_name="$1"
    local service_name="$2"
    local project_root="$3"
    local start_command="$4"

    cat << 'TEMPLATE'
#!/usr/bin/env bash
#
# Service: SESSION_NAME
# Auto-generated by univers-core
#

set -e

# 加载核心库
UNIVERS_CORE_LIB="CORE_LIB_PATH"
source "$UNIVERS_CORE_LIB/common.sh"
source "$UNIVERS_CORE_LIB/tmux-utils.sh"

# 确保非 root 运行
ensure_non_root "$@"

# 配置
SESSION_NAME="SESSION_NAME_VALUE"
SERVICE_NAME="SERVICE_NAME_VALUE"
PROJECT_ROOT="PROJECT_ROOT_VALUE"

# 启动服务
do_start() {
    local mode="${1:-default}"

    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "会话已存在: $SESSION_NAME"
        return 0
    fi

    log_service "启动 $SERVICE_NAME..."
    create_session "$SESSION_NAME" "main" "$PROJECT_ROOT"

    # 发送启动命令
    send_command "$SESSION_NAME:main" "START_COMMAND"

    log_success "$SERVICE_NAME 已启动"
}

# 停止服务
do_stop() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "会话不存在: $SESSION_NAME"
        return 0
    fi

    kill_session "$SESSION_NAME"
    log_success "$SERVICE_NAME 已停止"
}

# 查看状态
do_status() {
    check_tmux

    local status
    status="$(get_session_status "$SESSION_NAME")"

    case "$status" in
        running)
            log_success "$SERVICE_NAME: 运行中"
            ;;
        idle)
            log_warning "$SERVICE_NAME: 空闲"
            ;;
        stopped)
            log_info "$SERVICE_NAME: 已停止"
            ;;
    esac
}

# 查看日志
do_logs() {
    local lines="${1:-50}"
    show_session_logs "$SESSION_NAME" "" "$lines"
}

# 连接会话
do_attach() {
    attach_session "$SESSION_NAME"
}

# 重启服务
do_restart() {
    do_stop
    sleep 2
    do_start "$@"
}

# 主入口
case "${1:-help}" in
    start)
        shift
        do_start "$@"
        ;;
    stop)
        do_stop
        ;;
    restart)
        shift
        do_restart "$@"
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
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|attach}"
        exit 1
        ;;
esac
TEMPLATE
}
