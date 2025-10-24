#!/usr/bin/env bash
#
# Tmux Desktop View Manager
# 管理桌面聚合视图 - 分屏布局
#

set -e

# 配置
SESSION_NAME="univers-desktop-view"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="/home/davidxu/repos"

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

log_view() {
    echo -e "${CYAN}🖥️  $1${NC}"
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

# 检查依赖会话是否运行
check_dependencies() {
    local missing=()

    for dep in univers-developer univers-server univers-ui univers-web univers-operator univers-manager; do
        if ! tmux has-session -t "$dep" 2>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_warning "以下依赖会话未运行: ${missing[*]}"
        log_info "desktop-view 仍然可以启动，但某些面板可能无法显示"
        return 1
    fi

    return 0
}

# 自动启动缺失的依赖会话
auto_start_dependencies() {
    log_info "检查并启动缺失的依赖会话..."
    local started=()
    local failed=()

    # 检查 univers-developer
    if ! tmux has-session -t "univers-developer" 2>/dev/null; then
        log_info "启动 univers-developer..."
        local developer_script="$PROJECT_ROOT/hvac-workspace/.claude/skills/univers-dev/scripts/tmux-developer.sh"
        if [ -f "$developer_script" ]; then
            "$developer_script" start && started+=("univers-developer") || failed+=("univers-developer")
        else
            log_warning "univers-developer 脚本未找到，跳过"
            failed+=("univers-developer")
        fi
    fi

    # 检查 univers-server
    if ! tmux has-session -t "univers-server" 2>/dev/null; then
        log_info "启动 univers-server..."
        if command -v univers-dev &> /dev/null; then
            univers-dev server start socket && started+=("univers-server") || failed+=("univers-server")
        else
            log_warning "univers-dev 命令未找到，跳过 univers-server"
            failed+=("univers-server")
        fi
    fi

    # 检查 univers-ui
    if ! tmux has-session -t "univers-ui" 2>/dev/null; then
        log_info "启动 univers-ui..."
        if command -v univers-dev &> /dev/null; then
            univers-dev ui start && started+=("univers-ui") || failed+=("univers-ui")
        else
            log_warning "univers-dev 命令未找到，跳过 univers-ui"
            failed+=("univers-ui")
        fi
    fi

    # 检查 univers-web
    if ! tmux has-session -t "univers-web" 2>/dev/null; then
        log_info "启动 univers-web..."
        if command -v univers-dev &> /dev/null; then
            univers-dev web start && started+=("univers-web") || failed+=("univers-web")
        else
            log_warning "univers-dev 命令未找到，跳过 univers-web"
            failed+=("univers-web")
        fi
    fi

    # 检查 univers-operator
    if ! tmux has-session -t "univers-operator" 2>/dev/null; then
        log_info "启动 univers-operator..."
        local operator_script="$PROJECT_ROOT/hvac-operation/.claude/skills/univers-ops/scripts/univers-ops"
        if [ -f "$operator_script" ]; then
            "$operator_script" operator start && started+=("univers-operator") || failed+=("univers-operator")
        else
            log_warning "univers-ops 脚本未找到，跳过 univers-operator"
            failed+=("univers-operator")
        fi
    fi

    # 检查 univers-manager
    if ! tmux has-session -t "univers-manager" 2>/dev/null; then
        log_info "启动 univers-manager..."
        if command -v tmux-manager &> /dev/null; then
            tmux-manager start && started+=("univers-manager") || failed+=("univers-manager")
        else
            log_warning "tmux-manager 命令未找到，跳过 univers-manager"
            failed+=("univers-manager")
        fi
    fi

    # 报告结果
    echo ""
    if [ ${#started[@]} -gt 0 ]; then
        log_success "已启动以下会话: ${started[*]}"
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        log_warning "以下会话启动失败或跳过: ${failed[*]}"
    fi
    if [ ${#started[@]} -eq 0 ] && [ ${#failed[@]} -eq 0 ]; then
        log_success "所有依赖会话已在运行"
    fi
    echo ""
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

    log_view "创建 Desktop View 分屏会话: $SESSION_NAME"

    # 自动启动缺失的依赖会话
    auto_start_dependencies

    # 检查依赖会话
    check_dependencies || true

    # ========================================
    # Window 1: workbench (4个pane)
    # ========================================
    log_info "创建 Window 1: workbench (4 panes)"

    # 创建会话和第一个窗口
    tmux new-session -d -s "$SESSION_NAME" -n "workbench" -c "$PROJECT_ROOT"

    # 设置基本选项
    tmux set-option -t "$SESSION_NAME" base-index 1
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on
    tmux set-option -t "$SESSION_NAME" history-limit 50000

    # 执行分割操作
    # 水平分割 (左右) - 左边 developer, 右边 server/ui/web
    tmux split-window -h -t "$SESSION_NAME:workbench"

    # 右侧第一次垂直分割 - pane 2 分成上下两部分
    tmux split-window -v -t "$SESSION_NAME:workbench.2"

    # 右侧第二次垂直分割 - 再分一次
    tmux split-window -v -t "$SESSION_NAME:workbench.3"

    # 调整 pane 大小比例（左侧占55%，右侧占45%）
    local win_width=$(tmux list-windows -t "$SESSION_NAME:workbench" -F "#{window_width}" | head -1)
    local left_width=$((win_width * 55 / 100))
    tmux resize-pane -t "$SESSION_NAME:workbench.1" -x "$left_width"

    # 现在有4个面板：
    # pane 1: 左侧 (developer) - 占整个左半边
    # pane 2: 右上 (server) - 占右半边的上半部
    # pane 3: 右中 (ui) - 占右半边的中间部分
    # pane 4: 右下 (web) - 占右半边的下半部

    # 为每个 pane 设置标题
    tmux select-pane -t "$SESSION_NAME:workbench.1" -T "Developer"
    tmux select-pane -t "$SESSION_NAME:workbench.2" -T "Server"
    tmux select-pane -t "$SESSION_NAME:workbench.3" -T "UI"
    tmux select-pane -t "$SESSION_NAME:workbench.4" -T "Web"

    # 设置连接命令（自动重连）
    tmux send-keys -t "$SESSION_NAME:workbench.1" "unset TMUX && while true; do tmux attach-session -t univers-developer 2>/dev/null || sleep 5; done" Enter
    tmux send-keys -t "$SESSION_NAME:workbench.2" "unset TMUX && while true; do tmux attach-session -t univers-server 2>/dev/null || sleep 5; done" Enter
    tmux send-keys -t "$SESSION_NAME:workbench.3" "unset TMUX && while true; do tmux attach-session -t univers-ui 2>/dev/null || sleep 5; done" Enter
    tmux send-keys -t "$SESSION_NAME:workbench.4" "unset TMUX && while true; do tmux attach-session -t univers-web 2>/dev/null || sleep 5; done" Enter

    # ========================================
    # Window 2: operation (1个pane)
    # ========================================
    log_info "创建 Window 2: operation"

    tmux new-window -t "$SESSION_NAME" -n "operation" -c "$PROJECT_ROOT"
    tmux send-keys -t "$SESSION_NAME:operation" "unset TMUX && while true; do tmux attach-session -t univers-operator 2>/dev/null || sleep 5; done" Enter

    # ========================================
    # Window 3: manager (1个pane)
    # ========================================
    log_info "创建 Window 3: manager"

    tmux new-window -t "$SESSION_NAME" -n "manager" -c "$PROJECT_ROOT"
    tmux send-keys -t "$SESSION_NAME:manager" "unset TMUX && while true; do tmux attach-session -t univers-manager 2>/dev/null || sleep 5; done" Enter

    # 选择 workbench 窗口
    tmux select-window -t "$SESSION_NAME:workbench"

    log_success "Desktop View 会话创建成功！"
    echo ""
    echo "会话包含 3 个窗口:"
    echo "  1. workbench  - 4个pane (developer, server, ui, web)"
    echo "  2. operation  - univers-operator"
    echo "  3. manager    - univers-manager"
    echo ""
    log_info "使用 '$0 attach' 连接到会话"
    echo ""
    echo "依赖会话:"
    echo "  - univers-developer (hvac-workspace)"
    echo "  - univers-server (hvac-workspace)"
    echo "  - univers-ui (hvac-workspace)"
    echo "  - univers-web (hvac-workspace)"
    echo "  - univers-operator (hvac-operation)"
    echo "  - univers-manager (univers-container)"
}

# 停止会话
stop_session() {
    check_tmux

    if ! session_exists; then
        log_warning "会话 '$SESSION_NAME' 不存在"
        return 0
    fi

    log_info "正在停止 Desktop View 会话..."
    tmux kill-session -t "$SESSION_NAME"
    log_success "Desktop View 会话已停止"
    log_info "注意: 其他独立会话仍在运行"
}

# 重启会话
restart_session() {
    log_info "正在重启 Desktop View 会话..."
    stop_session
    sleep 1
    start_session
}

# 连接到会话
attach_session() {
    check_tmux

    if ! session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        log_info "使用 '$0 start' 创建会话"
        exit 1
    fi

    log_view "连接到 Desktop View 会话..."
    tmux attach-session -t "$SESSION_NAME"
}

# 查看会话状态
show_status() {
    check_tmux

    echo "╔════════════════════════════════════════╗"
    echo "║  DESKTOP VIEW SESSION STATUS           ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    if session_exists; then
        log_success "Desktop View 会话: 运行中"

        echo ""
        echo "窗口列表:"
        tmux list-windows -t "$SESSION_NAME" -F "  #{window_index}: #{window_name} (#{window_panes} panes)" || true

        echo ""
        echo "依赖会话状态:"
        for dep in univers-developer univers-server univers-ui univers-web univers-operator univers-manager; do
            if tmux has-session -t "$dep" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $dep"
            else
                echo -e "  ${RED}✗${NC} $dep (未运行)"
            fi
        done

    else
        log_warning "Desktop View 会话: 未运行"
    fi

    echo ""
    echo "╚════════════════════════════════════════╝"
}

# 显示帮助
show_help() {
    cat << EOF
🖥️  Desktop View Tmux Manager

桌面聚合视图 - 分屏同时查看多个会话

用法:
  $0 <command> [options]

命令:
  start           启动 Desktop View 会话
  stop            停止会话
  restart         重启会话
  attach          连接到会话
  status          显示会话状态
  help            显示此帮助信息

窗口布局:

  Window 1: workbench (4 panes)
  ┌──────────────┬──────────────┐
  │              │  server      │
  │  developer   ├──────────────┤
  │              │  ui          │
  │              ├──────────────┤
  │              │  web         │
  └──────────────┴──────────────┘

  Window 2: operation (1 pane)
  - univers-operator

  Window 3: manager (1 pane)
  - univers-manager

依赖会话:
  - univers-developer: 启动命令 univers-dev developer start
  - univers-server:    启动命令 univers-dev server start
  - univers-ui:        启动命令 univers-dev ui start
  - univers-web:       启动命令 univers-dev web start
  - univers-operator:  启动命令 univers-ops operator start
  - univers-manager:   启动命令 tmux-manager start

示例:
  # 启动所有依赖会话
  univers-dev developer start
  univers-dev server start socket
  univers-dev ui start
  univers-dev web start
  univers-ops operator start
  tmux-manager start

  # 启动 desktop view
  $0 start

  # 连接到会话
  $0 attach

  # 查看状态
  $0 status

Tmux快捷键:
  Ctrl+B D        退出会话
  Ctrl+B 1-3      切换窗口
  Ctrl+B ←↑→↓     在pane间导航
  Ctrl+B [        进入滚动模式
  Ctrl+B ?        显示所有快捷键

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
