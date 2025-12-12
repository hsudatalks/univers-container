#!/usr/bin/env bash
#
# Tmux Agents Manager
# 管理 Univers Ark Agents 服务的 tmux 会话
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
SESSION_NAME="univers-agents"
WINDOW_NAME="agents"
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
AGENTS_DIR="$PROJECT_ROOT/apps/server/univers-ark-agents"
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

# 检查 tmux 是否安装
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux 未安装"
        echo ""
        echo "请安装 tmux:"
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
is_server_running() {
    if session_exists; then
        local pane_pid=$(tmux list-panes -t "$SESSION_NAME:$WINDOW_NAME" -F "#{pane_pid}" 2>/dev/null | head -1)
        if [ -n "$pane_pid" ]; then
            if pgrep -P "$pane_pid" > /dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    return 1
}

# 启动服务
start_server() {
    check_tmux

    if session_exists; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        if is_server_running; then
            log_info "Agents 服务似乎正在运行"
            echo ""
            echo "使用以下命令:"
            echo "  $0 attach   - 连接到服务"
            echo "  $0 logs     - 查看日志"
            echo "  $0 stop     - 停止服务"
            return 1
        else
            log_warning "会话存在但服务未运行，将重新启动"
            tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
        fi
    fi

    # 检查 agents 目录是否存在
    if [ ! -d "$AGENTS_DIR" ]; then
        log_error "Agents 目录不存在: $AGENTS_DIR"
        exit 1
    fi

    log_info "创建 tmux 会话: $SESSION_NAME"

    # 创建 tmux 会话
    tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$AGENTS_DIR" zsh

    # 设置 tmux 选项
    tmux set-option -t "$SESSION_NAME" base-index 0
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on

    # 加载状态栏配置
    local statusbar_config="$STATUSBAR_DIR/agents-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            if [[ "$line" =~ ^(setw|set-window-option) ]]; then
                line="${line//__PROJECT_ROOT__/$PROJECT_ROOT}"
                if [[ "$line" =~ ^setw ]]; then
                    cmd="setw -t $SESSION_NAME:$WINDOW_NAME ${line#setw }"
                else
                    cmd="${line/set-window-option/set-window-option -t $SESSION_NAME:$WINDOW_NAME}"
                fi
                eval "tmux $cmd" 2>/dev/null || true
            elif [[ "$line" =~ ^set-option ]]; then
                line="${line//__PROJECT_ROOT__/$PROJECT_ROOT}"
                cmd="${line/set-option/set-option -t $SESSION_NAME}"
                eval "tmux $cmd" 2>/dev/null || true
            fi
        done < "$statusbar_config"
        log_info "已加载状态栏配置: agents-statusbar.conf"
    fi

    # 切换到 agents 目录并启动
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "cd '$AGENTS_DIR'" C-m
    sleep 0.5

    # 设置环境变量
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export ANTHROPIC_API_KEY='$ANTHROPIC_API_KEY'" C-m
    fi
    if [ -n "$OPENAI_API_KEY" ]; then
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export OPENAI_API_KEY='$OPENAI_API_KEY'" C-m
    fi
    sleep 0.3

    # 启动 agents 服务
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "pnpm dev" C-m

    log_success "Agents 服务已在 tmux 会话中启动"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到服务 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看日志"
    echo "  $0 stop     - 停止服务"
    echo "  $0 status   - 查看状态"
    echo ""
    log_info "服务端口: 3004"
    log_info "API 入口: http://localhost:3004/api/v1/query"
    echo ""

    # 等待启动并显示日志
    sleep 3
    show_logs 20

    echo ""
    log_info "💡 提示: 使用 '$0 logs' 查看完整日志"
}

# 停止服务
stop_server() {
    check_tmux

    if ! session_exists; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "停止 Agents 服务..."

    # 发送 Ctrl+C 停止服务
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" C-c
    sleep 2

    # 删除会话
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    log_success "Agents 服务已停止"
}

# 连接到会话
attach_server() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        echo ""
        echo "请先启动服务:"
        echo "  $0 start"
        return 1
    fi

    log_info "连接到 Agents 服务会话..."
    log_info "按 Ctrl+B 然后 D 退出会话（不会停止服务）"
    echo ""
    sleep 1

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
    echo "  Univers Ark Agents Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux 会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo "  窗口名: $WINDOW_NAME"

        if is_server_running; then
            log_success "Agents 服务: 运行中"

            # 检查端口
            if command -v netstat &> /dev/null; then
                echo ""
                echo "监听端口:"
                netstat -tuln | grep -E ":3004" || echo "  端口 3004 未检测到"
            fi

            # 尝试健康检查
            if command -v curl &> /dev/null; then
                echo ""
                echo "健康检查:"
                local health_response
                health_response=$(curl -s http://localhost:3004/health 2>/dev/null || echo "failed")
                if [ "$health_response" != "failed" ]; then
                    echo "  $health_response" | head -1
                else
                    echo "  无法连接到服务"
                fi
            fi
        else
            log_warning "Agents 服务: 未运行"
        fi

        echo ""
        echo "Tmux 会话信息:"
        tmux list-sessions | grep "$SESSION_NAME" || true

    else
        log_warning "Tmux 会话: 未运行"
        log_warning "Agents 服务: 未运行"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 重启服务
restart_server() {
    log_info "重启 Agents 服务..."

    stop_server
    sleep 2
    start_server
}

# 显示帮助
show_help() {
    cat << EOF
Univers Ark Agents Tmux Manager

用法:
  $0 <command> [options]

命令:
  start           启动 Agents 服务
  stop            停止服务
  restart         重启服务
  attach          连接到服务会话
  logs [lines]    显示最近的日志 (默认 50 行)
  tail            实时查看日志
  status          显示服务状态
  help            显示此帮助信息

示例:
  # 启动服务
  $0 start

  # 查看日志
  $0 logs

  # 连接到服务
  $0 attach

  # 查看状态
  $0 status

  # 停止服务
  $0 stop

Tmux 快捷键:
  Ctrl+B D        退出会话 (服务继续运行)
  Ctrl+B [        进入滚动模式 (q 退出)
  Ctrl+B ?        显示所有快捷键

端口:
  HTTP API: 3004

API 入口:
  Copilot:  POST /api/v1/query         {"prompt": "你好"}
  System:   GET  /health               健康检查
  Status:   GET  /api/v1/system/status 系统状态

EOF
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)
            start_server "$@"
            ;;
        stop)
            stop_server
            ;;
        restart)
            restart_server "$@"
            ;;
        attach)
            attach_server
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
