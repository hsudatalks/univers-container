#!/usr/bin/env bash
#
# Tmux System Monitor
# 系统监控的 tmux 会话
#

set -e

# 配置
SESSION_NAME="univers-monitor"
WINDOW_NAME="monitor"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_monitor() {
    echo -e "${MAGENTA}📊 $1${NC}"
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

    log_monitor "创建系统监控会话: $SESSION_NAME"

    # 创建tmux会话（4窗格布局）
    tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME"

    # 设置tmux选项
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on
    tmux set-option -t "$SESSION_NAME" history-limit 50000

    # 创建4窗格布局
    # 布局:
    # ┌──────────────┬──────────────┐
    # │   系统资源    │   进程监控    │
    # │   (htop)     │   (watch ps)  │
    # ├──────────────┼──────────────┤
    # │   磁盘监控    │   网络监控    │
    # │   (watch df) │   (watch ss)  │
    # └──────────────┴──────────────┘

    # 水平分割
    tmux split-window -h -t "$SESSION_NAME:$WINDOW_NAME"
    # 左侧垂直分割
    tmux split-window -v -t "$SESSION_NAME:$WINDOW_NAME.0"
    # 右侧垂直分割
    tmux split-window -v -t "$SESSION_NAME:$WINDOW_NAME.1"

    # 窗格0（左上）：系统资源监控 - htop
    if command -v htop &> /dev/null; then
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME.0" "htop" C-m
    else
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME.0" "top" C-m
    fi

    # 窗格1（右上）：进程监控 - watch ps
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME.1" "watch -n 2 'ps aux --sort=-%cpu | head -20'" C-m

    # 窗格2（左下）：磁盘监控 - watch df
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME.2" "watch -n 5 'df -h; echo; echo \"Top 10 Largest Directories:\"; du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10'" C-m

    # 窗格3（右下）：网络监控 - watch ss
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME.3" "watch -n 2 'echo \"=== Network Connections ===\"; ss -tunap 2>/dev/null | head -20; echo; echo \"=== Network Interfaces ===\"; ip -s link'" C-m

    log_success "系统监控会话已创建"
    echo ""
    echo "监控布局:"
    echo "  ┌──────────────┬──────────────┐"
    echo "  │   系统资源    │   进程监控    │"
    echo "  │   (htop)     │   (top CPU)   │"
    echo "  ├──────────────┼──────────────┤"
    echo "  │   磁盘监控    │   网络监控    │"
    echo "  │   (df/du)    │   (ss/ip)     │"
    echo "  └──────────────┴──────────────┘"
    echo ""
    echo "使用以下命令:"
    echo "  $0 attach   - 连接到会话 (按 Ctrl+B 然后 D 退出)"
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

    log_info "停止系统监控会话..."
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    log_success "系统监控会话已停止"
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

    log_monitor "连接到系统监控会话..."
    log_info "按 Ctrl+B 然后 D 退出会话（不会停止）"
    log_info "使用 Ctrl+B + 方向键 在窗格间切换"
    echo ""
    sleep 1

    # 连接到会话
    tmux attach-session -t "$SESSION_NAME"
}

# 查看状态
show_status() {
    check_tmux

    echo "═══════════════════════════════════════════════════════════"
    echo "  📊 System Monitor Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if session_exists; then
        log_success "Tmux会话: 运行中"
        echo "  会话名: $SESSION_NAME"
        echo "  窗口名: $WINDOW_NAME"

        # 显示会话信息
        echo ""
        echo "Tmux会话信息:"
        tmux list-sessions | grep "$SESSION_NAME" || true

        # 显示窗格信息
        echo ""
        echo "监控窗格:"
        echo "  窗格 0 (左上): 系统资源 (htop/top)"
        echo "  窗格 1 (右上): 进程监控 (CPU排序)"
        echo "  窗格 2 (左下): 磁盘监控 (df/du)"
        echo "  窗格 3 (右下): 网络监控 (ss/ip)"

    else
        log_warning "Tmux会话: 未运行"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# 重启会话
restart_session() {
    log_info "重启系统监控会话..."
    stop_session
    sleep 1
    start_session
}

# 显示帮助
show_help() {
    cat << EOF
📊 System Monitor Tmux Manager

系统监控会话，使用4窗格布局实时监控系统状态。

用法:
  $0 <command>

命令:
  start      启动系统监控会话
  stop       停止会话
  restart    重启会话
  attach     连接到会话
  status     显示会话状态
  help       显示此帮助信息

监控内容:
  ┌──────────────┬──────────────┐
  │ 窗格0 (左上)  │ 窗格1 (右上)  │
  │ 系统资源      │ 进程监控      │
  │ htop/top     │ top CPU进程   │
  ├──────────────┼──────────────┤
  │ 窗格2 (左下)  │ 窗格3 (右下)  │
  │ 磁盘监控      │ 网络监控      │
  │ df/du        │ ss/ip link   │
  └──────────────┴──────────────┘

示例:
  # 启动监控会话
  $0 start

  # 连接到会话
  $0 attach

  # 查看状态
  $0 status

  # 停止会话
  $0 stop

Tmux快捷键:
  Ctrl+B D        退出会话 (会话继续运行)
  Ctrl+B ←↑→↓     在窗格间切换
  Ctrl+B Z        放大/缩小当前窗格
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

特点:
  - 持久化会话，关闭终端也不会消失
  - 50000行历史记录缓冲
  - 鼠标支持（可以用鼠标点击切换窗格和滚动）
  - 自动刷新监控数据
  - 4窗格分屏布局

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
