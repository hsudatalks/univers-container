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

# 后台启动所有依赖会话和视图
auto_start_all() {
    local view_type="${1:-both}"  # desktop, mobile, both, none

    log_info "正在后台启动所有依赖会话..."

    # 启动视图会话（它会自动启动所有依赖）
    case "$view_type" in
        desktop)
            log_info "启动桌面视图..."
            if command -v tmux-desktop-view &> /dev/null; then
                tmux-desktop-view start > /dev/null 2>&1 || log_warning "桌面视图启动失败"
            else
                log_warning "tmux-desktop-view 命令未找到"
            fi
            ;;
        mobile)
            log_info "启动移动视图..."
            if command -v tmux-mobile-view &> /dev/null; then
                tmux-mobile-view start > /dev/null 2>&1 || log_warning "移动视图启动失败"
            else
                log_warning "tmux-mobile-view 命令未找到"
            fi
            ;;
        both)
            log_info "启动桌面和移动视图..."
            if command -v tmux-desktop-view &> /dev/null; then
                tmux-desktop-view start > /dev/null 2>&1 || log_warning "桌面视图启动失败"
            fi
            if command -v tmux-mobile-view &> /dev/null; then
                tmux-mobile-view start > /dev/null 2>&1 || log_warning "移动视图启动失败"
            fi
            ;;
        none)
            log_info "跳过视图启动，仅启动基础会话..."
            # 直接调用 desktop-view 的 auto_start_dependencies 逻辑
            # 这里我们可以复用 view 脚本的逻辑，或者单独实现
            ;;
    esac

    log_success "后台启动完成！"
    echo ""
    log_info "查看所有会话状态: tmux list-sessions"
    log_info "连接到 desktop-view: tmux-desktop-view attach"
    log_info "连接到 mobile-view: tmux-mobile-view attach"
    echo ""
}

# 启动会话
start_session() {
    local view_type="${1:-both}"  # 视图类型: desktop, mobile, both, none

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

    # 发送欢迎信息（使用单个命令输出，然后再次清屏隐藏命令历史）
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'printf "╔════════════════════════════════════════════════════════════╗\n║        Univers Container Manager                         ║\n║        容器管理终端                                        ║\n╚════════════════════════════════════════════════════════════╝\n\n📂 Working directory: '"$CONTAINER_ROOT"'\n\n🔧 Available commands:\n  - tmux-manager start/stop/attach    # 管理此会话\n  - tmux-desktop-view start/attach    # 桌面聚合视图\n  - tmux-mobile-view start/attach     # 移动聚合视图\n  - tmux list-sessions                # 列出所有会话\n\n💡 提示: 使用 claude 启动 Claude Code\n\n"; history -d $(history 1 | awk "{print \$1}")' C-m
    sleep 0.5
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'clear' C-m

    log_success "Container Manager 会话已创建"
    echo ""

    # 自动启动所有依赖会话和视图
    auto_start_all "$view_type"

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
    local view_type="${1:-both}"
    log_info "重启 Container Manager 会话..."
    stop_session
    sleep 1
    start_session "$view_type"
}

# 显示帮助
show_help() {
    cat << EOF
📦 Container Manager Tmux Manager

这是容器管理终端，用于管理 univers-container 仓库的 skills。

用法:
  $0 <command> [options]

命令:
  start [view]    启动 Container Manager 会话并自动启动所有依赖
                  view: both (默认), desktop, mobile, none
  stop            停止会话
  restart [view]  重启会话
  attach          连接到会话
  logs [lines]    显示最近的输出 (默认50行)
  status          显示会话状态
  help            显示此帮助信息

示例:
  # 启动会话（默认同时启动两个视图）
  $0 start

  # 启动会话并只启动桌面视图
  $0 start desktop

  # 启动会话并只启动移动视图
  $0 start mobile

  # 启动会话但不启动任何视图
  $0 start none

  # 连接到会话
  $0 attach

  # 查看历史输出
  $0 logs 100

  # 查看状态
  $0 status

  # 停止会话
  $0 stop

自动启动功能:
  使用 'start' 命令时，会自动:
  1. 启动 univers-manager 会话
  2. 启动所有依赖会话 (developer, server, ui, web, operator)
  3. 启动视图会话 (默认同时启动 desktop 和 mobile 视图)

  视图会话会自动连接到所有依赖会话，提供统一的监控界面。
  - desktop-view: 3窗口分屏布局，适合大屏幕
  - mobile-view: 4窗口切换布局，适合小屏幕

Tmux快捷键:
  Ctrl+B D        退出会话 (会话继续运行)
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

特点:
  - 持久化会话，关闭终端也不会消失
  - 50000行历史记录缓冲
  - 鼠标支持（可以用鼠标滚动）
  - 默认打开 univers-container 目录
  - 一键启动所有开发和运维会话

EOF
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)
            local view_type="${1:-both}"
            start_session "$view_type"
            ;;
        stop)
            stop_session
            ;;
        restart)
            local view_type="${1:-both}"
            restart_session "$view_type"
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
