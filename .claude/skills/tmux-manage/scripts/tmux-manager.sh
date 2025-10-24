#!/usr/bin/env bash
#
# Tmux Manager
# 管理 Univers Container 管理终端的tmux会话
#

set -e

# 配置
SESSION_NAME="univers-manager"
WINDOW_NAME="manager"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTAINER_ROOT="/home/davidxu/repos/univers-container"

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

log_manager() {
    echo -e "${CYAN}📦 $1${NC}"
}

# 检查tmux是否安装
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux未安装"
        echo ""
        echo "请安装tmux:"
        echo "  Ubuntu/Debian: sudo apt install tmux"
        echo "  macOS: brew install tmux"
        exit 1
    fi
}

# 检查会话是否存在
session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

# 启动会话
start_session() {
    check_tmux

    if session_exists; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        log_info "使用以下命令:"
        echo "  $0 attach   - 连接到会话"
        echo "  $0 status   - 查看状态"
        echo "  $0 stop     - 停止会话"
        return 1
    fi

    log_manager "创建 Container Manager 会话: $SESSION_NAME"

    # 创建tmux会话
    tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$CONTAINER_ROOT"

    # 设置tmux选项（会话级别）
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on
    tmux set-option -t "$SESSION_NAME" history-limit 50000

    # 发送欢迎信息
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'clear' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "╔════════════════════════════════════════════════════════════╗"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "║        Univers Container Manager                         ║"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "║        容器管理终端                                        ║"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "╚════════════════════════════════════════════════════════════╝"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo ""' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "📂 Working directory: $(pwd)"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo ""' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "🔧 Available commands:"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "  - tmux-manager start/stop/attach    # 管理此会话"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "  - tmux-desktop-view start/attach    # 桌面聚合视图"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "  - tmux-mobile-view start/attach     # 移动聚合视图"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "  - tmux list-sessions                # 列出所有会话"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo ""' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo "💡 提示: 使用 claude 启动 Claude Code"' C-m
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'echo ""' C-m

    log_success "Container Manager 会话已创建"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到会话 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看历史输出"
    echo "  $0 stop     - 停止会话"
    echo "  $0 status   - 查看状态"
    echo ""
}

# 停止会话
stop_session() {
    check_tmux

    if ! session_exists; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "停止 Container Manager 会话..."
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    log_success "Container Manager 会话已停止"
}

# 连接到会话
attach_session() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        echo ""
        echo "请先启动会话:"
        echo "  $0 start"
        return 1
    fi

    log_manager "连接到 Container Manager 会话..."
    log_info "按 Ctrl+B 然后 D 退出会话（不会停止）"
    echo ""
    sleep 1

    # 连接到会话
    tmux attach-session -t "$SESSION_NAME"
}

# 显示历史输出
show_logs() {
    local lines="${1:-50}"

    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "最近 $lines 行输出:"
    echo ""

    # 捕获tmux窗口内容
    tmux capture-pane -t "$SESSION_NAME:$WINDOW_NAME" -p -S -$lines
}

# 查看状态
show_status() {
    check_tmux

    echo "═══════════════════════════════════════════════════════════"
    echo "  📦 Container Manager Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo "  窗口名: $WINDOW_NAME"
        echo "  工作目录: $CONTAINER_ROOT"

        # 显示会话信息
        echo ""
        echo "Tmux会话信息:"
        tmux list-sessions | grep "$SESSION_NAME" || true

    else
        log_warning "Tmux会话: 未运行"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 重启会话
restart_session() {
    log_info "重启 Container Manager 会话..."
    stop_session
    sleep 1
    start_session
}

# 显示帮助
show_help() {
    cat << EOF
📦 Container Manager Tmux Manager

这是容器管理终端，用于管理 univers-container 仓库的 skills。

用法:
  $0 <command> [options]

命令:
  start           启动 Container Manager 会话
  stop            停止会话
  restart         重启会话
  attach          连接到会话
  logs [lines]    显示最近的输出 (默认50行)
  status          显示会话状态
  help            显示此帮助信息

示例:
  # 启动会话
  $0 start

  # 连接到会话
  $0 attach

  # 查看历史输出
  $0 logs 100

  # 查看状态
  $0 status

  # 停止会话
  $0 stop

Tmux快捷键:
  Ctrl+B D        退出会话 (会话继续运行)
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

特点:
  - 持久化会话，关闭终端也不会消失
  - 50000行历史记录缓冲
  - 鼠标支持（可以用鼠标滚动）
  - 默认打开 univers-container 目录

EOF
}

# 主函数
main() {
    local command="${1:-help}"
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
        attach)
            attach_session
            ;;
        logs)
            show_logs "$@"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
