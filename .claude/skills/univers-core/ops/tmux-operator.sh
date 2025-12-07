#!/usr/bin/env bash
#
# Tmux Operator Manager
# 管理Univers Operator操作控制台的tmux会话
#

set -e

# 确保脚本不以 root 身份运行
# 优先使用 SUDO_USER（通过 sudo 调用时）或获取第一个非 root 用户
if [ "$EUID" -eq 0 ]; then
    if [ -n "$SUDO_USER" ]; then
        # 从 sudo 调用时使用 SUDO_USER
        TARGET_USER="$SUDO_USER"
    else
        # 否则查找第一个非 root 用户
        TARGET_USER=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1; exit}' /etc/passwd)
        if [ -z "$TARGET_USER" ]; then
            echo "错误：找不到非 root 用户"
            exit 1
        fi
    fi
    exec sudo -u "$TARGET_USER" "$0" "$@"
fi




# 配置
SESSION_NAME="univers-operator"
WINDOW_NAME="operator"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 检查tmux是否安装
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux未安装"
        echo ""
        echo "请安装tmux:"
        echo "  Ubuntu/Debian: sudo apt install tmux"
        echo "  macOS: brew install tmux"
        echo "  Arch: sudo pacman -S tmux"
        exit 1
    fi
}

# 检查会话是否存在
session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

# 检查服务是否运行
is_service_running() {
    if session_exists; then
        # 检查窗口中是否有进程在运行
        local pane_pid=$(tmux list-panes -t "$SESSION_NAME:$WINDOW_NAME" -F "#{pane_pid}" 2>/dev/null | head -1)
        if [ -n "$pane_pid" ]; then
            # 检查是否有子进程（实际的shell进程）
            if pgrep -P "$pane_pid" > /dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    return 1
}

# 启动服务
start_service() {
    check_tmux

    if session_exists; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        if is_service_running; then
            log_info "Operator控制台似乎正在运行"
            echo ""
            echo "使用以下命令:"
            echo "  $0 attach   - 连接到会话"
            echo "  $0 logs     - 查看日志"
            echo "  $0 stop     - 停止服务"
            return 1
        else
            log_warning "会话存在但控制台未运行，将重新启动"
            tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
        fi
    fi

    log_info "创建tmux会话: $SESSION_NAME"

    # 创建tmux会话并启动shell
    tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$PROJECT_ROOT" bash

    # 设置tmux选项（会话级别，非全局）
    tmux set-option -t "$SESSION_NAME" base-index 0
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on

    # 加载会话专属状态栏配置
    local statusbar_config="$SKILL_DIR/configs/operator-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        # tmux 3.2a doesn't support 'source-file -t', so we apply commands line by line
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            # Apply the command to the session or window
            if [[ "$line" =~ ^setw|^set-window-option ]]; then
                # Replace PROJECT_ROOT placeholder with actual path
                line="${line//__PROJECT_ROOT__/$PROJECT_ROOT}"
                # For window options, add -t flag after setw/set-window-option
                if [[ "$line" =~ ^setw ]]; then
                    cmd="setw -t $SESSION_NAME:$WINDOW_NAME ${line#setw }"
                else
                    cmd="${line/set-window-option/set-window-option -t $SESSION_NAME:$WINDOW_NAME}"
                fi
                eval "tmux $cmd" 2>/dev/null || true
            elif [[ "$line" =~ ^set-option ]]; then
                # Replace PROJECT_ROOT placeholder with actual path
                line="${line//__PROJECT_ROOT__/$PROJECT_ROOT}"
                # Insert -t flag after set-option
                cmd="${line/set-option/set-option -t $SESSION_NAME}"
                eval "tmux $cmd" 2>/dev/null || true
            elif [[ "$line" =~ ^bind-key ]]; then
                # Execute bind-key commands directly
                eval "tmux $line" 2>/dev/null || true
            fi
        done < "$statusbar_config"
        log_info "已加载状态栏配置: operator-statusbar.conf"
    else
        log_warning "状态栏配置文件不存在: $statusbar_config"
    fi

    # 在会话中启动bash shell
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "cd '$PROJECT_ROOT' && bash" C-m

    log_success "Operator控制台已启动"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到会话 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看日志"
    echo "  $0 stop     - 停止服务"
    echo "  $0 status   - 查看状态"
    echo ""

    # 等待几秒让shell启动
    log_info "等待Operator控制台启动..."
    sleep 2

    # 显示初始日志
    show_logs 20
}

# 停止服务
stop_service() {
    check_tmux

    if ! session_exists; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "停止Operator控制台..."

    # 删除会话
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    log_success "Operator控制台已停止"
}

# 连接到会话
attach_service() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        echo ""
        echo "请先启动Operator控制台:"
        echo "  $0 start"
        return 1
    fi

    log_info "连接到Operator会话..."
    log_info "按 Ctrl+B 然后 D 退出会话（不会停止控制台）"
    echo ""
    sleep 1

    # 连接到会话
    tmux attach-session -t "$SESSION_NAME"
}

# 显示日志
show_logs() {
    local lines="${1:-50}"

    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "最近 $lines 行日志:"
    echo ""

    # 捕获tmux窗口内容
    tmux capture-pane -t "$SESSION_NAME:$WINDOW_NAME" -p -S -$lines
}

# 实时查看日志
tail_logs() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "实时查看日志 (按 Ctrl+C 退出)..."
    echo ""
    sleep 1

    # 使用tmux的pipe-pane功能实时显示输出
    while true; do
        clear
        tmux capture-pane -t "$SESSION_NAME:$WINDOW_NAME" -p -S -50
        sleep 2
    done
}

# 查看状态
show_status() {
    check_tmux

    echo "═══════════════════════════════════════════════════════════"
    echo "  Univers Operator Status (Control Console)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo "  窗口名: $WINDOW_NAME"

        if is_service_running; then
            log_success "Operator控制台: 运行中"
        else
            log_warning "Operator控制台: 未运行"
        fi

        # 显示会话信息
        echo ""
        echo "Tmux会话信息:"
        tmux list-sessions | grep "$SESSION_NAME" || true

    else
        log_warning "Tmux会话: 未运行"
        log_warning "Operator控制台: 未运行"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 重启服务
restart_service() {
    log_info "重启Operator控制台..."

    stop_service
    sleep 2
    start_service
}

# 显示帮助
show_help() {
    cat << EOF
Univers Operator Tmux Manager (Control Console)

用法:
  $0 <command> [options]

命令:
  start       启动Operator控制台
  stop        停止Operator控制台
  restart     重启Operator控制台
  attach      连接到会话
  logs [lines] 显示最近的日志 (默认50行)
  tail        实时查看日志
  status      显示服务状态
  help        显示此帮助信息

示例:
  # 启动Operator控制台
  $0 start

  # 查看日志
  $0 logs

  # 连接到会话
  $0 attach

  # 查看状态
  $0 status

  # 停止服务
  $0 stop

Tmux快捷键:
  Ctrl+B D        退出会话 (控制台继续运行)
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

提示:
  - Operator控制台在tmux后台运行，关闭终端也不会停止
  - 使用 'attach' 命令查看实时输出
  - 使用 'logs' 命令查看历史日志
  - 这是一个交互式控制台，可以运行运维命令

EOF
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)
            start_service "$@"
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service "$@"
            ;;
        attach)
            attach_service
            ;;
        logs)
            show_logs "$@"
            ;;
        tail)
            tail_logs
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
