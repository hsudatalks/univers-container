#!/usr/bin/env bash
#
# Tmux User Manager
# 管理 Univers Ark CLI 用户交互会话
#

set -e

# 确保脚本不以 root 身份运行
if [ "$EUID" -eq 0 ]; then
    if [ -n "$SUDO_USER" ]; then
        TARGET_USER="$SUDO_USER"
    else
        TARGET_USER=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1; exit}' /etc/passwd)
        if [ -z "$TARGET_USER" ]; then
            echo "错误：找不到非 root 用户"
            exit 1
        fi
    fi
    exec sudo -u "$TARGET_USER" "$0" "$@"
fi

# 配置
SESSION_NAME="univers-user"
WINDOW_NAME="ark"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# 获取项目根目录
REPOS_ROOT="${REPOS_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
CONTAINER_ROOT="$REPOS_ROOT/univers-container"
CLI_DIR="$PROJECT_ROOT/apps/cli/univers-ark-cli"
STATUSBAR_DIR="$CONTAINER_ROOT/.claude/skills/tmux-manage/configs"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印带颜色的消息
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

# 检查 tmux 是否运行
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux 未安装"
        exit 1
    fi
}

# 检查会话是否存在
session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

# 获取会话状态
get_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Univers Ark CLI User Session Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux 会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo "  窗口名: $WINDOW_NAME"

        # 检查 ark CLI 是否在运行
        local pane_pid=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
        if [ -n "$pane_pid" ]; then
            local child_count=$(pgrep -P "$pane_pid" 2>/dev/null | wc -l)
            if [ "$child_count" -gt 0 ]; then
                log_success "Ark CLI: 运行中"
            else
                log_warning "Ark CLI: 等待输入"
            fi
        fi
    else
        log_warning "Tmux 会话: 未运行"
        echo ""
        echo "使用 '$0 start' 启动会话"
        return 1
    fi

    echo ""
    echo "Tmux 会话信息:"
    tmux list-sessions -F '#{session_name}: #{session_windows} windows (created #{session_created_string})' 2>/dev/null | grep "$SESSION_NAME" || true
    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 启动会话
start_session() {
    check_tmux

    if session_exists; then
        log_warning "会话已存在: $SESSION_NAME"
        log_info "使用 'attach' 连接到会话"
        return 0
    fi

    # 检查 CLI 目录
    if [ ! -d "$CLI_DIR" ]; then
        log_error "CLI 目录不存在: $CLI_DIR"
        exit 1
    fi

    log_info "创建 tmux 会话: $SESSION_NAME"

    # 创建新会话
    tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$CLI_DIR" zsh

    # 设置会话选项
    tmux set-option -t "$SESSION_NAME" base-index 0
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on

    # 加载状态栏配置
    local statusbar_config="$STATUSBAR_DIR/user-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            if [[ "$line" =~ ^set-option ]]; then
                local option_args="${line#set-option }"
                tmux set-option -t "$SESSION_NAME" $option_args 2>/dev/null || true
            elif [[ "$line" =~ ^set ]]; then
                local set_args="${line#set }"
                tmux set -t "$SESSION_NAME" $set_args 2>/dev/null || true
            fi
        done < "$statusbar_config"
        log_info "已加载状态栏配置: user-statusbar.conf"
    fi

    # 启动 ark CLI
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "cd '$CLI_DIR' && clear && npx tsx src/main.tsx" C-m

    log_success "Ark CLI 会话已启动"

    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到会话 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看日志"
    echo "  $0 stop     - 停止会话"
    echo "  $0 status   - 查看状态"
    echo ""
}

# 停止会话
stop_session() {
    if ! session_exists; then
        log_warning "会话未运行"
        return 0
    fi

    log_info "停止 Ark CLI 会话..."

    # 发送退出命令
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "exit" C-m 2>/dev/null || true
    sleep 1

    # 终止会话
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    log_success "Ark CLI 会话已停止"
}

# 重启会话
restart_session() {
    stop_session
    sleep 1
    start_session
}

# 连接到会话
attach_session() {
    if ! session_exists; then
        log_error "会话未运行，请先使用 'start' 启动"
        exit 1
    fi

    tmux attach-session -t "$SESSION_NAME"
}

# 查看日志
show_logs() {
    local lines=${1:-50}

    if ! session_exists; then
        log_error "会话未运行"
        exit 1
    fi

    log_info "最近 $lines 行输出:"
    echo ""
    tmux capture-pane -t "$SESSION_NAME:$WINDOW_NAME" -p -S -"$lines"
}

# 发送命令
send_command() {
    if ! session_exists; then
        log_error "会话未运行"
        exit 1
    fi

    local cmd="$*"
    if [ -z "$cmd" ]; then
        log_error "请提供要发送的命令"
        exit 1
    fi

    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "$cmd" C-m
    log_success "已发送命令: $cmd"
}

# 显示帮助
show_help() {
    echo "Univers Ark CLI User Session Manager"
    echo ""
    echo "用法: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start       启动 Ark CLI 交互会话"
    echo "  stop        停止会话"
    echo "  restart     重启会话"
    echo "  status      查看会话状态"
    echo "  attach      连接到会话 (Ctrl+B D 退出)"
    echo "  logs [n]    查看最近 n 行输出 (默认 50)"
    echo "  send <cmd>  发送命令到会话"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start           # 启动会话"
    echo "  $0 attach          # 连接到会话"
    echo "  $0 logs 100        # 查看最近 100 行"
    echo "  $0 send '你好'      # 发送消息给 Copilot"
    echo ""
}

# 主入口
main() {
    local command="${1:-status}"
    shift || true

    case "$command" in
        start)
            start_session
            ;;
        stop)
            stop_session
            ;;
        restart)
            restart_session
            ;;
        status)
            get_status
            ;;
        attach)
            attach_session
            ;;
        logs|log)
            show_logs "$@"
            ;;
        send)
            send_command "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
