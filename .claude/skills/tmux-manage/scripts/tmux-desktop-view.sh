#!/usr/bin/env bash
#
# Tmux Desktop View Manager
# 管理桌面聚合视图 - 分屏布局
#

set -e

# 配置
SESSION_NAME="container-desktop-view"
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
            tmux-manager start none && started+=("univers-manager") || failed+=("univers-manager")
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
    local skip_deps=false

    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-deps)
                skip_deps=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

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

    if [ "$skip_deps" != "true" ]; then
        # 暂时禁用 set -e，避免依赖启动失败导致脚本退出
        set +e
        # 自动启动缺失的依赖会话
        auto_start_dependencies
        # 恢复 set -e
        set -e
    else
        log_info "跳过依赖启动（由 manager 统一管理）"
    fi

    # 检查依赖会话
    check_dependencies || true

    # ========================================
    # Window 1: workbench (4个pane)
    # ========================================
    log_info "创建 Window 1: workbench (4 panes)"

    # 临时清除 TMUX 环境变量，确保新 session 独立创建
    local saved_tmux="$TMUX"
    unset TMUX

    # 创建会话和第一个窗口
    tmux new-session -d -s "$SESSION_NAME" -n "workbench" -c "$PROJECT_ROOT"

    # 恢复 TMUX 环境变量
    export TMUX="$saved_tmux"

    # 关键：设置 window-size 为 manual，然后强制 resize 到足够大的尺寸
    # 这样即使有小 client attach，窗口大小也不会被自动缩小
    # 保证能容纳完整的 4 pane 布局
    tmux set-window-option -t "$SESSION_NAME:workbench" window-size manual
    tmux resize-window -t "$SESSION_NAME:workbench" -x 200 -y 50

    # 设置基本选项
    tmux set-option -t "$SESSION_NAME" base-index 1
    tmux set-option -t "$SESSION_NAME" remain-on-exit off
    tmux set-option -t "$SESSION_NAME" mouse on
    tmux set-option -t "$SESSION_NAME" history-limit 50000

    # 设置快捷键：Alt+数字 直接切换窗口
    tmux bind-key -n M-1 select-window -t "$SESSION_NAME:1"
    tmux bind-key -n M-2 select-window -t "$SESSION_NAME:2"
    tmux bind-key -n M-3 select-window -t "$SESSION_NAME:3"

    # 设置快捷键：Ctrl+H/L 切换窗口
    tmux bind-key -n C-y previous-window
    tmux bind-key -n C-u next-window

    # 检查实际创建的窗口大小
    local actual_width=$(tmux list-windows -t "$SESSION_NAME:workbench" -F "#{window_width}" | head -1)
    local actual_height=$(tmux list-windows -t "$SESSION_NAME:workbench" -F "#{window_height}" | head -1)

    if [ "$actual_width" -lt 160 ] || [ "$actual_height" -lt 40 ]; then
        log_warning "窗口大小不足 (${actual_width}x${actual_height})，可能无法创建完整的4pane布局"
        log_info "建议：在真实终端中运行此脚本，或使用 tmux attach 后手动调整窗口大小"
    fi

    # 执行分割操作
    # 水平分割 (左右) - 左边 developer, 右边 server/ui/web
    tmux split-window -h -t "$SESSION_NAME:workbench" || log_warning "水平分割失败（窗口可能太小），继续创建..."

    # 右侧第一次垂直分割 - pane 2 分成上下两部分
    tmux split-window -v -t "$SESSION_NAME:workbench.2" || log_warning "第一次垂直分割失败（窗口可能太小），继续创建..."

    # 右侧第二次垂直分割 - 再分一次
    tmux split-window -v -t "$SESSION_NAME:workbench.3" || log_warning "第二次垂直分割失败（窗口可能太小），继续创建..."

    # 等待一下确保所有panes都创建完成
    sleep 0.5

    # 调整 pane 大小比例（左右各占 50%）
    local win_width=$(tmux list-windows -t "$SESSION_NAME:workbench" -F "#{window_width}" | head -1)
    local left_width=$((win_width * 50 / 100))
    tmux resize-pane -t "$SESSION_NAME:workbench.1" -x "$left_width" 2>/dev/null || true

    # 现在有4个面板：
    # pane 1: 左侧 (developer) - 占整个左半边
    # pane 2: 右上 (server) - 占右半边的上半部
    # pane 3: 右中 (ui) - 占右半边的中间部分
    # pane 4: 右下 (web) - 占右半边的下半部

    # 为每个 pane 设置标题（只设置存在的pane）
    tmux select-pane -t "$SESSION_NAME:workbench.1" -T "Developer" 2>/dev/null || true
    tmux select-pane -t "$SESSION_NAME:workbench.2" -T "Server" 2>/dev/null || true
    tmux select-pane -t "$SESSION_NAME:workbench.3" -T "UI" 2>/dev/null || true
    tmux select-pane -t "$SESSION_NAME:workbench.4" -T "Web" 2>/dev/null || true

    # 设置连接命令（自动重连，只连接存在的pane）
    tmux send-keys -t "$SESSION_NAME:workbench.1" "unset TMUX && while true; do tmux attach-session -t univers-developer 2>/dev/null || sleep 5; done" Enter 2>/dev/null || true
    tmux send-keys -t "$SESSION_NAME:workbench.2" "unset TMUX && while true; do tmux attach-session -t univers-server 2>/dev/null || sleep 5; done" Enter 2>/dev/null || true
    tmux send-keys -t "$SESSION_NAME:workbench.3" "unset TMUX && while true; do tmux attach-session -t univers-ui 2>/dev/null || sleep 5; done" Enter 2>/dev/null || true
    tmux send-keys -t "$SESSION_NAME:workbench.4" "unset TMUX && while true; do tmux attach-session -t univers-web 2>/dev/null || sleep 5; done" Enter 2>/dev/null || true

    # 布局创建完成后，将 window-size 改为 largest，允许跟随终端大小调整
    # 这样 attach 时窗口会自动适应终端大小
    tmux set-window-option -t "$SESSION_NAME:workbench" aggressive-resize on

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

    # ========================================
    # 加载状态栏配置（所有窗口创建完成后）
    # ========================================
    log_info "应用状态栏配置到所有窗口..."

    local statusbar_config="$SKILL_DIR/configs/desktop-view-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        # 对每个窗口应用配置
        for window in workbench operation manager; do
            while IFS= read -r line || [ -n "$line" ]; do
                # Skip comments and empty lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "$line" ]] && continue

                # Apply the command to each window
                if [[ "$line" =~ ^set-option ]]; then
                    # Session-level options only need to be set once
                    if [ "$window" = "workbench" ]; then
                        eval "tmux set-option -t $SESSION_NAME ${line#set-option }" 2>/dev/null || true
                    fi
                elif [[ "$line" =~ ^setw ]]; then
                    # Window-level options need to be set for each window
                    eval "tmux set-window-option -t $SESSION_NAME:$window ${line#setw }" 2>/dev/null || true
                fi
            done < "$statusbar_config"
        done
        log_info "已加载状态栏配置: desktop-view-statusbar.conf"
    else
        log_warning "状态栏配置文件不存在: $statusbar_config"
    fi

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
  Ctrl+H, Ctrl+L       上一个/下一个窗口（推荐）
  Alt+1, Alt+2, Alt+3  快速切换到指定窗口
  Ctrl+B D             退出会话
  Ctrl+B 1-3           切换窗口
  Ctrl+B ←↑→↓          在pane间导航
  Ctrl+B [             进入滚动模式
  Ctrl+B ?             显示所有快捷键

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
