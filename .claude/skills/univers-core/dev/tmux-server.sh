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
# SurrealDB 配置
SURREALDB_SESSION="univers-surrealdb"
SURREALDB_PORT=8000
SURREALDB_USER="root"
SURREALDB_PASS="root"
SURREALDB_DATA_DIR="$HOME/.univers/db"
SURREALDB_DATA_FILE="$SURREALDB_DATA_DIR/univers-ark.db"

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

# ============================================================================
# SurrealDB 管理函数
# ============================================================================

# 检查 SurrealDB 是否已安装
check_surrealdb_installed() {
    # 检查默认安装路径
    if [ -f "$HOME/.surrealdb/surreal" ]; then
        export PATH="$HOME/.surrealdb:$PATH"
    fi
    if command -v surreal &> /dev/null; then
        return 0
    fi
    return 1
}

# 获取 SurrealDB 版本
get_surrealdb_version() {
    if check_surrealdb_installed; then
        surreal version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    fi
}

# 检查端口是否被占用
is_port_in_use() {
    local port="$1"
    if command -v lsof &> /dev/null; then
        lsof -i ":$port" -sTCP:LISTEN &> /dev/null
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":$port "
    elif command -v ss &> /dev/null; then
        ss -tuln | grep -q ":$port "
    else
        # 尝试连接端口
        (echo > /dev/tcp/localhost/$port) 2>/dev/null
    fi
}

# 检查 SurrealDB 健康状态
check_surrealdb_health() {
    local max_attempts="${1:-5}"
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:$SURREALDB_PORT/health" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    return 1
}

# 检查 SurrealDB 会话是否存在
surrealdb_session_exists() {
    tmux has-session -t "$SURREALDB_SESSION" 2>/dev/null
}

# 安装 SurrealDB
install_surrealdb() {
    log_info "📦 正在安装 SurrealDB..."

    local os_type=""
    case "$(uname -s)" in
        Linux*)  os_type="linux";;
        Darwin*) os_type="macos";;
        *)       log_error "不支持的操作系统"; return 1;;
    esac

    if [ "$os_type" = "macos" ]; then
        # macOS: 使用 Homebrew
        if command -v brew &> /dev/null; then
            log_info "使用 Homebrew 安装..."
            brew install surrealdb/tap/surreal
        else
            # 使用官方脚本作为备选
            log_info "使用官方安装脚本..."
            curl -sSf https://install.surrealdb.com | sh
        fi
    else
        # Linux: 使用官方脚本
        log_info "使用官方安装脚本..."
        curl -sSf https://install.surrealdb.com | sh
    fi

    # 确保在 PATH 中
    if [ -f "$HOME/.surrealdb/surreal" ]; then
        export PATH="$HOME/.surrealdb:$PATH"
    fi

    # 验证安装
    if check_surrealdb_installed; then
        local version=$(get_surrealdb_version)
        log_success "SurrealDB $version 安装成功"
        return 0
    else
        log_error "SurrealDB 安装失败"
        return 1
    fi
}

# 启动 SurrealDB
start_surrealdb() {
    log_info "🗄️  检查 SurrealDB 状态..."

    # 检查是否已安装
    if ! check_surrealdb_installed; then
        log_warning "SurrealDB 未安装，正在自动安装..."
        if ! install_surrealdb; then
            log_error "无法安装 SurrealDB"
            log_info "💡 手动安装: curl -sSf https://install.surrealdb.com | sh"
            return 1
        fi
    fi

    # 检查是否已在运行
    if is_port_in_use "$SURREALDB_PORT"; then
        if check_surrealdb_health 3; then
            local version=$(get_surrealdb_version)
            log_success "SurrealDB $version 已在端口 $SURREALDB_PORT 运行"
            return 0
        else
            log_warning "端口 $SURREALDB_PORT 被占用但非 SurrealDB"
            return 1
        fi
    fi

    # 确保数据目录存在
    if [ ! -d "$SURREALDB_DATA_DIR" ]; then
        mkdir -p "$SURREALDB_DATA_DIR"
        log_info "📁 创建数据目录: $SURREALDB_DATA_DIR"
    fi

    log_info "🚀 启动 SurrealDB (文件模式)..."
    log_info "   📍 数据文件: $SURREALDB_DATA_FILE"
    log_info "   🌐 端口: $SURREALDB_PORT"
    log_info "   👤 用户: $SURREALDB_USER"

    # 在 tmux 会话中启动 SurrealDB
    if surrealdb_session_exists; then
        tmux kill-session -t "$SURREALDB_SESSION" 2>/dev/null || true
    fi

    # 确保 PATH 包含 SurrealDB
    local surreal_cmd="surreal"
    if [ -f "$HOME/.surrealdb/surreal" ]; then
        surreal_cmd="$HOME/.surrealdb/surreal"
    fi

    tmux new-session -d -s "$SURREALDB_SESSION" -n "surrealdb" \
        "$surreal_cmd start --user $SURREALDB_USER --pass $SURREALDB_PASS --bind 0.0.0.0:$SURREALDB_PORT file:$SURREALDB_DATA_FILE"

    # 等待启动
    log_info "⏳ 等待 SurrealDB 启动..."
    if check_surrealdb_health 10; then
        local version=$(get_surrealdb_version)
        log_success "SurrealDB $version 启动成功"
        return 0
    else
        log_error "SurrealDB 启动超时"
        log_info "💡 查看日志: tmux attach -t $SURREALDB_SESSION"
        return 1
    fi
}

# 停止 SurrealDB
stop_surrealdb() {
    if surrealdb_session_exists; then
        log_info "🛑 停止 SurrealDB..."
        tmux kill-session -t "$SURREALDB_SESSION" 2>/dev/null || true
        log_success "SurrealDB 已停止"
    else
        log_info "SurrealDB 未运行"
    fi
}

# 显示 SurrealDB 状态
show_surrealdb_status() {
    echo ""
    echo "  SurrealDB 状态:"

    if check_surrealdb_installed; then
        local version=$(get_surrealdb_version)
        echo "    ✅ 已安装: v$version"
    else
        echo "    ❌ 未安装"
        return
    fi

    if is_port_in_use "$SURREALDB_PORT"; then
        if check_surrealdb_health 2; then
            echo "    ✅ 运行中: http://localhost:$SURREALDB_PORT"
            echo "    📍 数据文件: $SURREALDB_DATA_FILE"
        else
            echo "    ⚠️  端口占用但健康检查失败"
        fi
    else
        echo "    ⏹️  未运行"
    fi

    if surrealdb_session_exists; then
        echo "    📺 Tmux 会话: $SURREALDB_SESSION"
    fi
}

# ============================================================================

# 启动服务器
start_server() {
    local mode="${1:-default}"
    local skip_db="${2:-false}"

    check_tmux

    # 除非明确跳过，否则确保 SurrealDB 运行
    if [ "$skip_db" != "true" ] && [ "$skip_db" != "--memory" ]; then
        if ! start_surrealdb; then
            log_error "无法启动 SurrealDB，服务器启动已取消"
            log_info "💡 使用 --memory 参数可跳过数据库启动（使用内存模式）"
            return 1
        fi
        echo ""
    fi

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

    # SurrealDB 状态
    show_surrealdb_status

    echo ""
    echo "  Workbench Server 状态:"

    if session_exists; then
        echo "    ✅ Tmux 会话: $SESSION_NAME"

        if is_server_running; then
            echo "    ✅ 服务器: 运行中"

            # 尝试检查端口
            if command -v netstat &> /dev/null; then
                echo ""
                echo "  监听端口:"
                netstat -tuln 2>/dev/null | grep -E ":(3000|3001|3002|3003|8000|8080)" | awk '{print "    " $4}' || echo "    未检测到标准端口"
            fi

            # 检查Socket文件
            if [ -e "/tmp/univers-server.sock" ]; then
                echo "    ✅ Unix Socket: /tmp/univers-server.sock"
            fi
        else
            echo "    ⏹️  服务器: 未运行"
        fi

    else
        echo "    ⏹️  Tmux 会话: 未运行"
        echo "    ⏹️  服务器: 未运行"
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
  start [mode]    启动服务器 (自动启动 SurrealDB)
                  模式: default, socket, http, watch, release
  stop            停止服务器
  restart [mode]  重启服务器
  attach          连接到服务器会话
  logs [lines]    显示最近的日志 (默认50行)
  tail            实时查看日志
  status          显示服务器和数据库状态
  help            显示此帮助信息

SurrealDB 命令:
  db-start        仅启动 SurrealDB
  db-stop         停止 SurrealDB
  db-status       查看 SurrealDB 状态
  db-logs         查看 SurrealDB 日志
  db-attach       连接到 SurrealDB 会话

启动模式:
  default         HTTP + Socket (无热重载，推荐日常开发)
  socket          HTTP + Socket (等同于default)
  http            HTTP + Socket (等同于default)
  watch           HTTP + Socket + 热重载 (文件修改自动重启)
  release         HTTP + Socket Release编译 (优化构建，无热重载)

注意: 2025-11起，所有模式都启用 HTTP + Socket 双端点

SurrealDB 配置:
  数据目录:       $SURREALDB_DATA_DIR
  数据文件:       $SURREALDB_DATA_FILE
  端口:           $SURREALDB_PORT
  用户:           $SURREALDB_USER

示例:
  # 启动服务器 (自动启动 SurrealDB)
  $0 start

  # 仅启动 SurrealDB
  $0 db-start

  # 查看完整状态
  $0 status

  # 停止所有服务
  $0 stop && $0 db-stop

Tmux快捷键:
  Ctrl+B D        退出会话 (服务器继续运行)
  Ctrl+B [        进入滚动模式 (q退出)
  Ctrl+B ?        显示所有快捷键

提示:
  - 服务器启动时会自动检查并启动 SurrealDB
  - SurrealDB 使用文件模式，数据持久化到 ~/.univers/db/
  - 服务器在tmux后台运行，关闭终端也不会停止

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
        # SurrealDB 相关命令
        db-start)
            start_surrealdb
            ;;
        db-stop)
            stop_surrealdb
            ;;
        db-status)
            show_surrealdb_status
            ;;
        db-logs)
            if surrealdb_session_exists; then
                tmux capture-pane -t "$SURREALDB_SESSION:surrealdb" -p -S -50
            else
                log_warning "SurrealDB 会话不存在"
            fi
            ;;
        db-attach)
            if surrealdb_session_exists; then
                tmux attach-session -t "$SURREALDB_SESSION"
            else
                log_warning "SurrealDB 会话不存在"
            fi
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
