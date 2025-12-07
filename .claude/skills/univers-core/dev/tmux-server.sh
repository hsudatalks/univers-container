#!/usr/bin/env bash
#
# Tmux Server Manager
# 管理Univers服务器的tmux会话
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
SESSION_NAME="univers-server"
WINDOW_NAME="server"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
UNIVERS_CORE="$(cd "$SCRIPT_DIR/.." && pwd)"
# univers-core -> skills -> .claude -> univers-container (3 levels up)
CONTAINER_ROOT="$(cd "$UNIVERS_CORE/../../.." && pwd)"
# 项目路径 (hvac-workbench)
REPOS_ROOT="$(cd "$CONTAINER_ROOT/.." && pwd)"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
# 状态栏配置路径
STATUSBAR_DIR="$CONTAINER_ROOT/.claude/skills/tmux-manage/configs"

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

# 检查服务器是否运行
is_server_running() {
    if session_exists; then
        # 检查窗口中是否有进程在运行
        local pane_pid=$(tmux list-panes -t "$SESSION_NAME:$WINDOW_NAME" -F "#{pane_pid}" 2>/dev/null | head -1)
        if [ -n "$pane_pid" ]; then
            # 检查是否有子进程（实际的服务器进程）
            if pgrep -P "$pane_pid" > /dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    return 1
}

# 启动服务器
start_server() {
    local mode="${1:-default}"

    check_tmux

    if session_exists; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        if is_server_running; then
            log_info "服务器似乎正在运行"
            echo ""
            echo "使用以下命令:"
            echo "  $0 attach   - 连接到服务器"
            echo "  $0 logs     - 查看日志"
            echo "  $0 stop     - 停止服务器"
            return 1
        else
            log_warning "会话存在但服务器未运行，将重新启动"
            tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
        fi
    fi

    log_info "创建tmux会话: $SESSION_NAME"

    # 启动命令 - 始终使用 HTTP + Socket 双模式
    # 2025-11: 移除模式区分，统一使用 both 模式，简化开发体验
    local start_command
    case "$mode" in
        watch)
            start_command="pnpm server"
            log_info "启动模式: HTTP + Socket + 热重载"
            ;;
        release)
            start_command="pnpm server:release"
            log_info "启动模式: HTTP + Socket (Release构建)"
            ;;
        *)
            # socket, http, default 等所有其他模式都使用 both
            start_command="pnpm server:both"
            log_info "启动模式: HTTP + Socket"
            ;;
    esac

    # 创建tmux会话并启动服务器（使用 bash）
    tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$PROJECT_ROOT" zsh

    # 设置tmux选项（会话级别，非全局）
    tmux set-option -t "$SESSION_NAME" base-index 0
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on

    # 加载会话专属状态栏配置
    local statusbar_config="$STATUSBAR_DIR/server-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        # tmux 3.2a doesn't support 'source-file -t', so we apply commands line by line
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            # Apply the command to the session or window
            if [[ "$line" =~ ^(setw|set-window-option) ]]; then
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
            fi
        done < "$statusbar_config"
        log_info "已加载状态栏配置: server-statusbar.conf"
    else
        log_warning "状态栏配置文件不存在: $statusbar_config"
    fi

    # 确保在正确的目录
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "cd '$PROJECT_ROOT'" C-m
    sleep 0.5

    # 设置EnOS环境变量（如果在父shell中已设置）
    if [ -n "$ENOS_ORG_ID" ]; then
        log_info "传递EnOS凭据到tmux会话: $ENOS_ORG_ID"
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export ENOS_ORG_ID='$ENOS_ORG_ID'" C-m
    fi
    if [ -n "$ENOS_SYSTEM_ID" ]; then
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export ENOS_SYSTEM_ID='$ENOS_SYSTEM_ID'" C-m
    fi
    if [ -n "$ENOS_BASE_URL" ]; then
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export ENOS_BASE_URL='$ENOS_BASE_URL'" C-m
    fi

    # 设置自动化调度器扫描间隔（如果在父shell中已设置）
    if [ -n "$AUTOMATION_SCAN_INTERVAL_SECONDS" ]; then
        log_info "传递自动化调度器配置到tmux会话: ${AUTOMATION_SCAN_INTERVAL_SECONDS}s"
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export AUTOMATION_SCAN_INTERVAL_SECONDS='$AUTOMATION_SCAN_INTERVAL_SECONDS'" C-m
    fi

    # 设置仿真模式（如果在父shell中已设置）
    if [ -n "$SIMULATION_MODE" ]; then
        log_info "传递仿真模式配置到tmux会话: SIMULATION_MODE=$SIMULATION_MODE"
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "export SIMULATION_MODE='$SIMULATION_MODE'" C-m
    fi
    sleep 0.5

    # 运行服务器
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "$start_command" C-m

    log_success "服务器已在tmux会话中启动"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到服务器 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs     - 查看日志"
    echo "  $0 stop     - 停止服务器"
    echo "  $0 status   - 查看状态"
    echo ""

    # Rust 项目编译需要较长时间
    log_warning "⏱️  Rust 项目首次编译可能需要 10-15 分钟"
    log_info "服务器正在后台编译和启动..."
    log_info "可使用 '$0 logs' 或 '$0 attach' 查看进度"
    echo ""

    # 等待几秒让服务器启动
    sleep 3

    # 显示初始日志
    show_logs 20

    echo ""
    log_info "💡 提示: 服务器仍在启动中，完整日志请使用 '$0 logs' 查看"
}

# 停止服务器
stop_server() {
    check_tmux

    if ! session_exists; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    log_info "停止服务器..."

    # 发送Ctrl+C停止服务器
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" C-c

    # 等待进程结束
    sleep 2

    # 删除会话
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    log_success "服务器已停止"
}

# 连接到服务器会话
attach_server() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        echo ""
        echo "请先启动服务器:"
        echo "  $0 start"
        return 1
    fi

    log_info "连接到服务器会话..."
    log_info "按 Ctrl+B 然后 D 退出会话（不会停止服务器）"
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
    echo "  Univers Server Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo "  窗口名: $WINDOW_NAME"

        if is_server_running; then
            log_success "服务器: 运行中"

            # 尝试检查端口
            if command -v netstat &> /dev/null; then
                echo ""
                echo "监听端口:"
                netstat -tuln | grep -E ":(3000|3001|3002|3003|8000|8080)" || echo "  未检测到标准端口"
            fi

            # 检查Socket文件
            if [ -e "/tmp/univers-server.sock" ]; then
                log_success "Unix Socket: /tmp/univers-server.sock"
            fi
        else
            log_warning "服务器: 未运行"
        fi

        # 显示会话信息
        echo ""
        echo "Tmux会话信息:"
        tmux list-sessions | grep "$SESSION_NAME" || true

    else
        log_warning "Tmux会话: 未运行"
        log_warning "服务器: 未运行"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 重启服务器
restart_server() {
    local mode="${1:-default}"

    log_info "重启服务器..."

    stop_server
    sleep 2
    start_server "$mode"
}

# 显示帮助
show_help() {
    cat << EOF
Univers Server Tmux Manager

用法:
  $0 <command> [options]

命令:
  start [mode]    启动服务器 (默认模式)
                  模式: default, socket, http, watch, release
  stop            停止服务器
  restart [mode]  重启服务器
  attach          连接到服务器会话
  logs [lines]    显示最近的日志 (默认50行)
  tail            实时查看日志
  status          显示服务器状态
  help            显示此帮助信息

启动模式:
  default         HTTP + Socket (无热重载，推荐日常开发)
  socket          HTTP + Socket (等同于default)
  http            HTTP + Socket (等同于default)
  watch           HTTP + Socket + 热重载 (文件修改自动重启)
  release         HTTP + Socket Release编译 (优化构建，无热重载)

注意: 2025-11起，所有模式都启用 HTTP + Socket 双端点

示例:
  # 启动服务器 (默认模式)
  $0 start

  # 启动服务器 (HTTP + Socket - 所有模式相同)
  $0 start socket   # 等同于 $0 start

  # 启动服务器 (生产模式)
  $0 start release

  # 查看日志
  $0 logs

  # 连接到服务器
  $0 attach

  # 查看状态
  $0 status

  # 停止服务器
  $0 stop

Tmux快捷键:
  Ctrl+B D        退出会话 (服务器继续运行)
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

提示:
  - 服务器在tmux后台运行，关闭终端也不会停止
  - 使用 'attach' 命令查看实时输出
  - 使用 'logs' 命令查看历史日志
  - 使用 'tail' 命令实时跟踪日志

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
