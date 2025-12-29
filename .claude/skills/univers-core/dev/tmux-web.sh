#!/usr/bin/env bash
#
# Tmux Web Manager
# 管理Univers Web开发服务器的tmux会话
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
SESSION_NAME="univers-web"
# Dev server port
DEV_PORT=3432
# Preview server port (fixed)
PREVIEW_PORT=4173
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

# 检查服务是否运行 (接受 pane 索引: 0=dev, 1=preview)
is_service_running() {
    local pane="${1:-0}"
    if session_exists; then
        # 检查指定 pane 中是否有进程在运行
        local pane_pid=$(tmux list-panes -t "$SESSION_NAME:web.$pane" -F "#{pane_pid}" 2>/dev/null | head -1)
        if [ -n "$pane_pid" ]; then
            # 检查是否有子进程（实际的服务进程）
            if pgrep -P "$pane_pid" > /dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    return 1
}

# 启动服务
start_service() {
    local mode="${1:-dev}"

    check_tmux

    if session_exists; then
        log_warning "会话 '$SESSION_NAME' 已存在"
        if is_service_running "0"; then
            log_info "Web服务似乎正在运行"
            echo ""
            echo "使用以下命令:"
            echo "  $0 attach   - 连接到会话"
            echo "  $0 logs     - 查看日志"
            echo "  $0 stop     - 停止服务"
            return 1
        else
            log_warning "会话存在但服务未运行，将重新启动"
            tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
        fi
    fi

    log_info "创建tmux会话: $SESSION_NAME"
    log_info "启动 Dev Server (端口 $DEV_PORT) + Preview Server (端口 $PREVIEW_PORT)"

    # 创建tmux会话，单窗口分屏模式
    tmux new-session -d -s "$SESSION_NAME" -n "web" -c "$PROJECT_ROOT" zsh

    # 设置tmux选项（会话级别，非全局）- 在 split 前设置确保 pane-base-index 生效
    tmux set-option -t "$SESSION_NAME" base-index 0
    tmux set-window-option -t "$SESSION_NAME:web" pane-base-index 0
    tmux set-option -t "$SESSION_NAME" remain-on-exit off

    # 水平分屏：左边 dev，右边 preview
    tmux split-window -h -t "$SESSION_NAME:web" -c "$PROJECT_ROOT/apps/univers-ark-web" zsh
    # 完全禁用鼠标 - 防止鼠标事件导致 Vite 崩溃
    tmux set-option -t "$SESSION_NAME" mouse off

    # 加载会话专属状态栏配置
    local statusbar_config="$STATUSBAR_DIR/web-statusbar.conf"
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
                if [[ "$line" =~ ^setw ]]; then
                    cmd="setw -t $SESSION_NAME:web ${line#setw }"
                else
                    cmd="${line/set-window-option/set-window-option -t $SESSION_NAME:web}"
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
        log_info "已加载状态栏配置: web-statusbar.conf"
    else
        log_warning "状态栏配置文件不存在: $statusbar_config"
    fi

    # 左边 pane (pane 0): Dev Server
    tmux send-keys -t "$SESSION_NAME:web.0" "cd '$PROJECT_ROOT'" C-m
    sleep 0.3
    tmux send-keys -t "$SESSION_NAME:web.0" "pnpm web:dev || true" C-m

    # 右边 pane (pane 1): Preview Server (先 build 再 preview)
    tmux send-keys -t "$SESSION_NAME:web.1" "cd '$PROJECT_ROOT/apps/univers-ark-web'" C-m
    sleep 0.3
    # 延迟启动 preview，等待 build 完成
    tmux send-keys -t "$SESSION_NAME:web.1" "echo '等待构建...' && sleep 5 && pnpm build && pnpm preview --host 0.0.0.0 --port $PREVIEW_PORT || true" C-m

    # 选中左边 pane (dev)
    tmux select-pane -t "$SESSION_NAME:web.0"

    log_success "Web服务已在tmux会话中启动"
    echo ""
    echo "  Dev Server:     http://localhost:$DEV_PORT"
    echo "  Preview Server: http://localhost:$PREVIEW_PORT (构建中...)"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach          - 连接到会话 (按 Ctrl+B 然后 D 退出)"
    echo "  $0 logs [dev|preview] - 查看日志"
    echo "  $0 stop            - 停止服务"
    echo "  $0 status          - 查看状态"
    echo ""

    # 等待几秒让服务启动
    log_info "等待Web服务启动..."
    sleep 3

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

    log_info "停止Web服务..."

    # 发送 Ctrl+C 停止两个 pane 中的服务
    tmux send-keys -t "$SESSION_NAME:web.0" C-c 2>/dev/null || true
    tmux send-keys -t "$SESSION_NAME:web.1" C-c 2>/dev/null || true

    # 等待进程结束
    sleep 2

    # 删除会话
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    log_success "Web服务已停止"
}

# 连接到会话
attach_service() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        echo ""
        echo "请先启动Web服务:"
        echo "  $0 start"
        return 1
    fi

    log_info "连接到Web会话..."
    log_info "按 Ctrl+B 然后 D 退出会话（不会停止服务）"
    echo ""
    sleep 1

    # 连接到会话
    tmux attach-session -t "$SESSION_NAME"
}

# 显示日志
show_logs() {
    local target="${1:-dev}"
    local lines="${2:-50}"

    # 如果第一个参数是数字，则作为行数处理
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        lines="$target"
        target="dev"
    fi

    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        return 1
    fi

    # 现在使用单窗口双 pane 布局: pane 0 = dev, pane 1 = preview
    local pane
    case "$target" in
        dev)     pane="0" ;;
        preview) pane="1" ;;
        *)       pane="0" ;;
    esac

    log_info "[$target] 最近 $lines 行日志:"
    echo ""

    # 捕获 pane 内容
    tmux capture-pane -t "$SESSION_NAME:web.$pane" -p -S -$lines
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

    # 使用tmux的pipe-pane功能实时显示输出 (默认显示 dev pane)
    while true; do
        clear
        tmux capture-pane -t "$SESSION_NAME:web.0" -p -S -50
        sleep 2
    done
}

# 查看状态
show_status() {
    check_tmux

    echo "═══════════════════════════════════════════════════════════"
    echo "  Univers Web Status (Dev + Preview Servers)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo ""

        # Dev Server 状态 (pane 0)
        echo "Dev Server (端口 $DEV_PORT):"
        if is_service_running "0"; then
            log_success "  状态: 运行中"
        else
            log_warning "  状态: 未运行"
        fi

        # Preview Server 状态 (pane 1)
        echo ""
        echo "Preview Server (端口 $PREVIEW_PORT):"
        if is_service_running "1"; then
            log_success "  状态: 运行中"
        else
            log_warning "  状态: 未运行"
        fi

        # 尝试检查端口
        if command -v ss &> /dev/null; then
            echo ""
            echo "监听端口:"
            ss -tlnp 2>/dev/null | grep -E ":($DEV_PORT|$PREVIEW_PORT)" | awk '{print "  " $4}' || echo "  未检测到端口"
        fi

        # 显示会话信息
        echo ""
        echo "Tmux窗口:"
        tmux list-windows -t "$SESSION_NAME" -F "  #{window_index}: #{window_name}" 2>/dev/null || true

    else
        log_warning "Tmux会话: 未运行"
        log_warning "Web服务: 未运行"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 重启服务
restart_service() {
    local mode="${1:-dev}"

    log_info "重启Web服务..."

    stop_service
    sleep 2
    start_service "$mode"
}

# 显示帮助
show_help() {
    cat << EOF
Univers Web Tmux Manager (Dev + Preview Servers)

用法:
  $0 <command> [options]

命令:
  start           启动Web服务 (同时启动 Dev + Preview)
  stop            停止Web服务
  restart         重启Web服务
  attach          连接到会话
  logs [target] [lines]   显示日志 (target: dev|preview, 默认dev)
  tail            实时查看日志
  status          显示服务状态
  help            显示此帮助信息

服务端口:
  Dev Server:     http://localhost:$DEV_PORT (快速热更新，适合本地开发)
  Preview Server: http://localhost:$PREVIEW_PORT (打包后，适合远程访问)

示例:
  # 启动Web服务
  $0 start

  # 查看 dev 日志
  $0 logs
  $0 logs dev 100

  # 查看 preview 日志
  $0 logs preview

  # 连接到会话
  $0 attach

  # 查看状态
  $0 status

  # 停止服务
  $0 stop

Tmux快捷键:
  Ctrl+B D        退出会话 (服务继续运行)
  Ctrl+B n/p      切换窗口 (dev/preview)
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

提示:
  - start 会同时启动 Dev Server 和 Preview Server
  - Dev Server 适合本地开发（HMR 热更新快）
  - Preview Server 适合远程访问（打包后加载快，端口固定）
  - 通过 Tailscale 访问推荐用 Preview Server

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
