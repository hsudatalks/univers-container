#!/usr/bin/env bash
#
# Tmux Mobile View Manager
# 管理移动聚合视图 - 多窗口切换布局
#

set -e

# 配置
SESSION_NAME="univers-mobile-view"
# 解析符号链接获取真实脚本路径
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# 动态获取项目根目录（univers-container 的上级目录）
PROJECT_ROOT="$(cd "$SKILL_DIR/../../../../" && pwd)"

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
    echo -e "${CYAN}📱 $1${NC}"
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

    for dep in univers-developer univers-server univers-ui univers-web univers-operator; do
        if ! tmux has-session -t "$dep" 2>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_warning "以下依赖会话未运行: ${missing[*]}"
        log_info "mobile-view 仍然可以启动，但某些窗口可能无法显示"
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
        local developer_script="$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-developer.sh"
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
        local server_script="$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-server.sh"
        if [ -f "$server_script" ]; then
            "$server_script" start socket && started+=("univers-server") || failed+=("univers-server")
        else
            log_warning "univers-server 脚本未找到，跳过"
            failed+=("univers-server")
        fi
    fi

    # 检查 univers-ui
    if ! tmux has-session -t "univers-ui" 2>/dev/null; then
        log_info "启动 univers-ui..."
        local ui_script="$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-ui.sh"
        if [ -f "$ui_script" ]; then
            "$ui_script" start && started+=("univers-ui") || failed+=("univers-ui")
        else
            log_warning "univers-ui 脚本未找到，跳过"
            failed+=("univers-ui")
        fi
    fi

    # 检查 univers-web
    if ! tmux has-session -t "univers-web" 2>/dev/null; then
        log_info "启动 univers-web..."
        local web_script="$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-web.sh"
        if [ -f "$web_script" ]; then
            "$web_script" start && started+=("univers-web") || failed+=("univers-web")
        else
            log_warning "univers-web 脚本未找到，跳过"
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
            tmux-manager start mobile && started+=("univers-manager") || failed+=("univers-manager")
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

    log_view "创建 Mobile View 多窗口会话: $SESSION_NAME"

    # 自动启动缺失的依赖会话
    auto_start_dependencies

    # 检查依赖会话
    check_dependencies || true

    # 设置基本选项
    # 创建会话（使用 bash）
    tmux new-session -d -s "$SESSION_NAME" -n "dev" -c "$PROJECT_ROOT" bash

    tmux set-option -t "$SESSION_NAME" base-index 1
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on
    tmux set-option -t "$SESSION_NAME" history-limit 50000

    # 设置快捷键：Alt+数字 直接切换窗口
    tmux bind-key -n M-1 select-window -t "$SESSION_NAME:1"
    tmux bind-key -n M-2 select-window -t "$SESSION_NAME:2"
    tmux bind-key -n M-3 select-window -t "$SESSION_NAME:3"
    tmux bind-key -n M-4 select-window -t "$SESSION_NAME:4"

    # 设置快捷键：Ctrl+Y/U 切换窗口
    tmux bind-key -n C-y previous-window
    tmux bind-key -n C-u next-window

    # ========================================
    # Window 1: dev (1个pane)
    # ========================================
    log_info "创建 Window 1: dev"

    # dev 窗口已经创建（new-session时），连接到 univers-developer
    tmux send-keys -t "$SESSION_NAME:dev" "unset TMUX && while true; do tmux attach-session -t univers-developer 2>/dev/null || sleep 5; done" Enter

    # ========================================
    # Window 2: service (3个pane竖向排列)
    # ========================================
    log_info "创建 Window 2: service (3 panes)"

    tmux new-window -t "$SESSION_NAME" -n "service" -c "$PROJECT_ROOT"

    # 第一次垂直分割 - 创建上中两个pane
    tmux split-window -v -t "$SESSION_NAME:service"

    # 第二次垂直分割 - 中下两个pane
    tmux split-window -v -t "$SESSION_NAME:service.1"

    # 现在有3个 pane（从上到下）:
    # pane 1: server (因为 base-index=1)
    # pane 2: ui
    # pane 3: web

    # 等待一下确保所有panes都创建完成
    sleep 0.5

    # 设置连接命令（注意：使用 pane 1、2、3 而不是 0、1、2，因为 base-index=1）
    tmux send-keys -t "$SESSION_NAME:service.1" "unset TMUX && while true; do tmux attach-session -t univers-server 2>/dev/null || sleep 5; done" Enter
    tmux send-keys -t "$SESSION_NAME:service.2" "unset TMUX && while true; do tmux attach-session -t univers-ui 2>/dev/null || sleep 5; done" Enter
    tmux send-keys -t "$SESSION_NAME:service.3" "unset TMUX && while true; do tmux attach-session -t univers-web 2>/dev/null || sleep 5; done" Enter

    # ========================================
    # Window 3: ops (1个pane)
    # ========================================
    log_info "创建 Window 3: ops"

    tmux new-window -t "$SESSION_NAME" -n "ops" -c "$PROJECT_ROOT"
    tmux send-keys -t "$SESSION_NAME:ops" "unset TMUX && while true; do tmux attach-session -t univers-operator 2>/dev/null || sleep 5; done" Enter

    # ========================================
    # Window 4: manager (1个pane)
    # ========================================
    log_info "创建 Window 4: manager"
#
    tmux new-window -t "$SESSION_NAME" -n "manager" -c "$PROJECT_ROOT"
    tmux send-keys -t "$SESSION_NAME:manager" "unset TMUX && while true; do tmux attach-session -t univers-manager 2>/dev/null || sleep 5; done" Enter

    # ========================================
    # 加载状态栏配置（所有窗口创建完成后）
    # ========================================
    log_info "应用状态栏配置到所有窗口..."

    local statusbar_config="$SKILL_DIR/configs/mobile-view-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        # 对每个窗口应用配置
        for window in dev service ops manager; do
            while IFS= read -r line || [ -n "$line" ]; do
                # Skip comments and empty lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "$line" ]] && continue

                # Apply the command to each window
                if [[ "$line" =~ ^set-option ]]; then
                    # Session-level options only need to be set once
                    if [ "$window" = "dev" ]; then
                        eval "tmux set-option -t $SESSION_NAME ${line#set-option }" 2>/dev/null || true
                    fi
                elif [[ "$line" =~ ^setw ]]; then
                    # Window-level options need to be set for each window
                    eval "tmux set-window-option -t $SESSION_NAME:$window ${line#setw }" 2>/dev/null || true
                fi
            done < "$statusbar_config"
        done
        log_info "已加载状态栏配置: mobile-view-statusbar.conf"
    else
        log_warning "状态栏配置文件不存在: $statusbar_config"
    fi

    # 选择 dev 窗口
    tmux select-window -t "$SESSION_NAME:dev"

    log_success "Mobile View 会话创建成功！"
    echo ""
    echo "会话包含 4 个窗口:"
    echo "  1. dev      - univers-developer"
    echo "  2. service  - 3个pane (server, ui, web)"
    echo "  3. ops      - univers-operator"
    echo "  4. manager  - univers-manager"

    echo ""
    log_info "使用 '$0 attach' 连接到会话"
    echo "使用 Ctrl+B 1-4 或 Alt+1-4 切换窗口"
    echo ""
    echo "依赖会话:"
    echo "  - univers-developer (hvac-workbench)"
    echo "  - univers-server (hvac-workbench)"
    echo "  - univers-ui (hvac-workbench)"
    echo "  - univers-web (hvac-workbench)"
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

    log_info "正在停止 Mobile View 会话..."
    tmux kill-session -t "$SESSION_NAME"
    log_success "Mobile View 会话已停止"
    log_info "注意: 其他独立会话仍在运行"
}

# 重启会话
restart_session() {
    log_info "正在重启 Mobile View 会话..."
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

    log_view "连接到 Mobile View 会话..."
    tmux attach-session -t "$SESSION_NAME"
}

# 查看会话状态
show_status() {
    check_tmux

    echo "╔════════════════════════════════════════╗"
    echo "║  MOBILE VIEW SESSION STATUS            ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    if session_exists; then
        log_success "Mobile View 会话: 运行中"

        echo ""
        echo "窗口列表:"
        tmux list-windows -t "$SESSION_NAME" -F "  #{window_index}: #{window_name} (#{window_panes} panes)" || true

        echo ""
        echo "依赖会话状态:"
        for dep in univers-developer univers-server univers-ui univers-web univers-operator; do
            if tmux has-session -t "$dep" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $dep"
            else
                echo -e "  ${RED}✗${NC} $dep (未运行)"
            fi
        done

    else
        log_warning "Mobile View 会话: 未运行"
    fi

    echo ""
    echo "╚════════════════════════════════════════╝"
}

# 显示帮助
show_help() {
    cat << EOF
📱 Mobile View Tmux Manager

移动聚合视图 - 多窗口切换查看

用法:
  $0 <command> [options]

命令:
  start           启动 Mobile View 会话
  stop            停止会话
  restart         重启会话
  attach          连接到会话
  status          显示会话状态
  help            显示此帮助信息

窗口布局:

  Window 1: dev (1 pane)
  - univers-developer

  Window 2: service (3 panes 竖向排列)
  ┌──────────────┐
  │  server      │
  ├──────────────┤
  │  ui          │
  ├──────────────┤
  │  web         │
  └──────────────┘

  Window 3: ops (1 pane)
  - univers-operator

  Window 4: manager (1 pane)
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

  # 启动 mobile view
  $0 start

  # 连接到会话
  $0 attach

  # 查看状态
  $0 status

Tmux快捷键:
  Ctrl+Y, Ctrl+U               上一个/下一个窗口（推荐）
  Alt+1, Alt+2, Alt+3, Alt+4  快速切换到指定窗口
  Ctrl+B D                     退出会话
  Ctrl+B 1-4                   切换窗口
  Ctrl+B ←↑→↓                  在pane间导航（service窗口）
  Ctrl+B [                     进入滚动模式
  Ctrl+B ?                     显示所有快捷键

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
