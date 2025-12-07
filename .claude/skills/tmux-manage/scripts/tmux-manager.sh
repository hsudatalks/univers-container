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
# 动态获取 univers-container 根目录
# SKILL_DIR = .../univers-container/.claude/skills/tmux-manage
# 需要向上2级到 univers-container
CONTAINER_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
# 项目根目录（univers-container 的上级目录，包含所有项目）
PROJECT_ROOT="$(cd "$CONTAINER_ROOT/.." && pwd)"

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

# 验证服务是否就绪（检查会话是否有活动进程）
verify_service_ready() {
    local session_name="$1"
    local max_attempts="${2:-6}"  # 最多尝试6次，每次等待0.5秒 = 3秒

    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        # 检查会话是否存在
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            return 1
        fi

        # 检查会话是否有活动的panes
        local pane_count=$(tmux list-panes -t "$session_name" 2>/dev/null | wc -l)
        if [ "$pane_count" -gt 0 ]; then
            # 检查至少有一个pane有活动进程
            local pane_pid=$(tmux list-panes -t "$session_name" -F "#{pane_pid}" 2>/dev/null | head -1)
            if [ -n "$pane_pid" ]; then
                # 检查是否有子进程（实际的服务进程）
                if pgrep -P "$pane_pid" > /dev/null 2>&1; then
                    return 0  # 服务就绪
                fi
            fi
        fi

        sleep 0.5
        attempt=$((attempt + 1))
    done

    return 1  # 超时，服务未就绪
}

# 启动基础服务会话（不包括视图）
start_base_services() {
    log_info "启动基础服务会话..."
    local started=()
    local failed=()
    local already_running=()

    # 定义服务及其启动脚本（按依赖顺序）
    local services=(
        "univers-developer:$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-developer.sh:start"
        "univers-server:$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-server.sh:start socket"
        "univers-ui:$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-ui.sh:start"
        "univers-web:$PROJECT_ROOT/hvac-workbench/.claude/skills/univers-dev/scripts/tmux-web.sh:start"
        "univers-operator:$PROJECT_ROOT/hvac-operation/.claude/skills/univers-ops/scripts/univers-ops:operator start"
        "univers-agents:$PROJECT_ROOT/univers-container/.claude/skills/univers-core/ops/tmux-agents.sh:start"
        "univers-check:$PROJECT_ROOT/univers-container/.claude/skills/univers-core/dev/tmux-check.sh:start"
        "univers-e2e:$PROJECT_ROOT/univers-container/.claude/skills/univers-core/dev/tmux-e2e.sh:start"
        "univers-bench:$PROJECT_ROOT/univers-container/.claude/skills/univers-core/dev/tmux-bench.sh:start"
    )

    for service_info in "${services[@]}"; do
        IFS=':' read -r session_name script args <<< "$service_info"

        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            log_info "启动 $session_name..."
            if [ -f "$script" ]; then
                # 临时禁用 set -e
                set +e
                $script $args >/dev/null 2>&1
                local exit_code=$?
                set -e

                # 给服务一点时间启动，然后验证
                sleep 0.5

                # 验证会话是否真的创建了
                if tmux has-session -t "$session_name" 2>/dev/null; then
                    # 进一步验证服务是否就绪（有活动进程）
                    if verify_service_ready "$session_name" 3; then
                        started+=("$session_name")
                    else
                        log_warning "$session_name 会话已创建但服务未就绪"
                        started+=("$session_name")  # 仍然算作启动成功
                    fi
                else
                    log_warning "$session_name 启动失败（会话未创建）"
                    failed+=("$session_name")
                fi
            else
                log_warning "$script 未找到，跳过 $session_name"
                failed+=("$session_name")
            fi
        else
            already_running+=("$session_name")
        fi
    done

    echo ""
    if [ ${#started[@]} -gt 0 ]; then
        log_success "已启动: ${started[*]}"
    fi
    if [ ${#already_running[@]} -gt 0 ]; then
        log_info "已在运行: ${already_running[*]}"
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        log_warning "启动失败或跳过: ${failed[*]}"
    fi
    echo ""
}

# 启动单个视图（带存在性检查）
start_view_if_needed() {
    local view_name="$1"
    local view_session="$2"
    local view_command="$3"

    # 检查视图会话是否已存在
    if tmux has-session -t "$view_session" 2>/dev/null; then
        log_info "$view_name 会话已存在，跳过启动"
        return 0
    fi

    # 检查命令是否存在
    if ! command -v "$view_command" &> /dev/null; then
        log_warning "$view_command 命令未找到，跳过 $view_name"
        return 1
    fi

    # 启动视图
    log_info "启动 $view_name..."
    set +e
    $view_command start --skip-deps >/dev/null 2>&1
    local exit_code=$?
    set -e

    # 给视图一点时间启动
    sleep 0.3

    # 验证会话是否真的创建了
    if tmux has-session -t "$view_session" 2>/dev/null; then
        log_success "$view_name 启动成功"
        return 0
    else
        log_warning "$view_name 启动失败（会话未创建）"
        return 1
    fi
}

# 后台启动所有依赖会话和视图
auto_start_all() {
    local view_type="${1:-both}"  # desktop, mobile, both, none

    log_info "正在后台启动所有依赖会话..."
    echo ""

    # 先启动基础服务会话（不包括 manager）
    start_base_services

    # 然后启动视图会话（它们只连接到服务，不创建服务）
    case "$view_type" in
        desktop)
            start_view_if_needed "桌面视图" "container-desktop-view" "tmux-desktop-view"
            ;;
        mobile)
            start_view_if_needed "移动视图" "container-mobile-view" "tmux-mobile-view"
            ;;
        both)
            start_view_if_needed "桌面视图" "container-desktop-view" "tmux-desktop-view"
            start_view_if_needed "移动视图" "container-mobile-view" "tmux-mobile-view"
            ;;
        none)
            log_info "跳过视图启动"
            ;;
    esac

    echo ""
    log_success "后台启动完成！"
    echo ""
    log_info "查看所有会话状态: cm tmux list"
    if [ "$view_type" != "none" ]; then
        log_info "连接到 desktop-view: tmux-desktop-view attach"
        log_info "连接到 mobile-view: tmux-mobile-view attach"
    fi
    echo ""
}

# 启动会话
start_session() {
    local view_type="${1:-both}"  # 视图类型: desktop, mobile, both, none

    check_tmux

    local manager_existed=false
    if session_exists; then
        log_info "Manager 会话已存在，跳过创建"
        manager_existed=true
    fi

    # 仅当 manager 不存在时才创建
    if [ "$manager_existed" = false ]; then
        log_manager "创建 Container Manager 会话: $SESSION_NAME"

        # 创建tmux会话
        tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$CONTAINER_ROOT"

        # 设置tmux选项（会话级别）
        tmux set-option -t "$SESSION_NAME" remain-on-exit off
        tmux set-option -t "$SESSION_NAME" mouse on
        tmux set-option -t "$SESSION_NAME" history-limit 50000

        # 加载状态栏配置
        local statusbar_config="$SKILL_DIR/configs/manager-statusbar.conf"
        if [ -f "$statusbar_config" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                # Skip comments and empty lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "$line" ]] && continue

                # Apply the command to the session
                # Replace 'set-option' with 'set-option -t $SESSION_NAME'
                # Replace 'setw' with 'set-window-option -t $SESSION_NAME'
                if [[ "$line" =~ ^set-option ]]; then
                    eval "tmux set-option -t $SESSION_NAME ${line#set-option }" 2>/dev/null || true
                elif [[ "$line" =~ ^setw ]]; then
                    eval "tmux set-window-option -t $SESSION_NAME ${line#setw }" 2>/dev/null || true
                fi
            done < "$statusbar_config"
            log_info "已加载状态栏配置: manager-statusbar.conf"
        else
            log_warning "状态栏配置文件不存在: $statusbar_config"
        fi

        # 发送欢迎信息（先清屏，然后打印欢迎信息）
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'clear' C-m
        sleep 0.2
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" 'printf "╔════════════════════════════════════════════════════════════╗\n║        Univers Container Manager                         ║\n║        容器管理终端                                        ║\n╚════════════════════════════════════════════════════════════╝\n\n📂 Working directory: '"$CONTAINER_ROOT"'\n\n🔧 Available commands:\n  - tmux-manager start/stop/attach    # 管理此会话\n  - tmux-desktop-view start/attach    # 桌面聚合视图\n  - tmux-mobile-view start/attach     # 移动聚合视图\n  - tmux list-sessions                # 列出所有会话\n\n💡 提示: 使用 claude 启动 Claude Code\n\n"' C-m

        log_success "Container Manager 会话已创建"
        echo ""
    fi

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

# 停止所有会话
stop_all_sessions() {
    check_tmux

    log_warning "即将停止所有 Univers 相关会话（保留 manager）..."
    echo ""

    # 定义所有会话（不包括 univers-manager，保持管理会话运行）
    local sessions=(
        "container-desktop-view"
        "container-mobile-view"
        "container-manager"
        "univers-desktop-view"
        "univers-mobile-view"
        "univers-developer"
        "univers-server"
        "univers-ui"
        "univers-web"
        "univers-operator"
        "univers-check"
        "univers-e2e"
        "univers-bench"
    )

    local stopped=()
    local failed=()
    local not_found=()

    # 遍历并停止每个会话
    for session in "${sessions[@]}"; do
        if tmux has-session -t "$session" 2>/dev/null; then
            log_info "停止 $session..."
            if tmux kill-session -t "$session" 2>/dev/null; then
                # 验证会话确实被停止
                sleep 0.2
                if ! tmux has-session -t "$session" 2>/dev/null; then
                    stopped+=("$session")
                else
                    log_error "$session 停止失败（会话仍存在）"
                    failed+=("$session")
                fi
            else
                log_error "$session 停止失败"
                failed+=("$session")
            fi
        else
            not_found+=("$session")
        fi
    done

    # 报告结果
    echo ""
    if [ ${#stopped[@]} -gt 0 ]; then
        log_success "已停止 ${#stopped[@]} 个会话:"
        for session in "${stopped[@]}"; do
            echo "  ✓ $session"
        done
    fi

    if [ ${#failed[@]} -gt 0 ]; then
        echo ""
        log_error "以下 ${#failed[@]} 个会话停止失败:"
        for session in "${failed[@]}"; do
            echo "  ✗ $session"
        done
        echo ""
        log_info "提示: 尝试运行 'cm tmux cleanup' 强制清理"
    fi

    if [ ${#not_found[@]} -gt 0 ]; then
        echo ""
        log_info "${#not_found[@]} 个会话未运行（已跳过）"
    fi

    echo ""
    if [ ${#failed[@]} -eq 0 ]; then
        log_success "所有会话已成功停止！"
        if tmux has-session -t "univers-manager" 2>/dev/null; then
            log_info "univers-manager 会话保持运行中"
        fi
        return 0
    else
        log_warning "部分会话停止失败，请检查"
        return 1
    fi
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

# 诊断所有会话状态
diagnose_sessions() {
    check_tmux

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Tmux Sessions Diagnostic                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "检查所有 Univers 会话状态..."
    echo ""

    local all_sessions=(
        "container-desktop-view:桌面视图"
        "container-mobile-view:移动视图"
        "univers-manager:管理终端"
        "univers-developer:开发终端"
        "univers-server:服务器"
        "univers-ui:前端UI"
        "univers-web:前端Web"
        "univers-operator:运维终端"
    )

    local running=0
    local zombie=0
    local not_running=0

    for session_info in "${all_sessions[@]}"; do
        IFS=':' read -r session desc <<< "$session_info"
        printf "  %-27s " "$session ($desc):"

        if tmux has-session -t "$session" 2>/dev/null; then
            # 检查会话是否有pane
            local pane_count=$(tmux list-panes -t "$session" 2>/dev/null | wc -l)
            if [ "$pane_count" -eq 0 ]; then
                echo -e "${RED}僵死${NC} (无pane)"
                zombie=$((zombie + 1))
            else
                local window_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l)
                echo -e "${GREEN}运行中${NC} ($window_count windows, $pane_count panes)"
                running=$((running + 1))
            fi
        else
            echo -e "${YELLOW}未运行${NC}"
            not_running=$((not_running + 1))
        fi
    done

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  总结:"
    echo "    运行中:   $running"
    echo "    僵死:     $zombie"
    echo "    未运行:   $not_running"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if [ $zombie -gt 0 ]; then
        log_warning "发现僵死会话，建议运行 'cm tmux cleanup' 强制清理"
    fi

    if [ $running -eq 0 ] && [ $zombie -eq 0 ]; then
        log_info "没有会话运行。使用 'cm tmux start' 启动会话"
    fi
}

# 强制清理所有会话
force_cleanup() {
    check_tmux

    log_warning "强制清理所有 Univers 会话..."
    echo ""

    # 获取所有匹配的会话
    local all_sessions=$(tmux list-sessions 2>/dev/null | grep -E "(container-|univers-)" | cut -d: -f1)

    if [ -z "$all_sessions" ]; then
        log_info "没有发现相关会话，无需清理"
        return 0
    fi

    echo "将要清理的会话:"
    echo "$all_sessions" | sed 's/^/  - /'
    echo ""

    read -p "确认清理？(y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local cleaned=0
        local failed=0

        for session in $all_sessions; do
            log_info "强制杀死 $session..."
            if tmux kill-session -t "$session" 2>/dev/null; then
                cleaned=$((cleaned + 1))
            else
                failed=$((failed + 1))
            fi
        done

        # 再次验证
        sleep 0.5
        local remaining=$(tmux list-sessions 2>/dev/null | grep -E "(container-|univers-)" | wc -l)

        echo ""
        if [ "$remaining" -eq 0 ]; then
            log_success "清理完成！已清理 $cleaned 个会话"
        else
            log_warning "部分清理完成：$cleaned 个成功，$failed 个失败，仍有 $remaining 个会话残留"
            echo ""
            log_info "残留会话:"
            tmux list-sessions 2>/dev/null | grep -E "(container-|univers-)" | sed 's/^/  - /'
        fi
    else
        log_info "已取消清理"
    fi
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
  stop            停止 manager 会话
  stop-all        停止所有 Univers 相关会话（推荐）
  restart [view]  重启会话
  attach          连接到会话
  logs [lines]    显示最近的输出 (默认50行)
  status          显示会话状态
  diagnose        诊断所有会话状态（检查僵死会话）
  cleanup         强制清理所有 Univers 相关会话
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

  # 停止 manager 会话
  $0 stop

  # 停止所有会话
  $0 stop-all

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
        stop-all)
            stop_all_sessions
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
        diagnose)
            diagnose_sessions
            ;;
        cleanup)
            force_cleanup
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
