#!/usr/bin/env bash
#
# Univers Core - Tmux Utilities
# Tmux 会话管理工具库
#

# 防止重复加载
if [ -n "${_UNIVERS_TMUX_UTILS_LOADED:-}" ]; then
    return 0
fi
_UNIVERS_TMUX_UTILS_LOADED=1

# 加载依赖
SCRIPT_DIR_TMUX_UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_TMUX_UTILS/common.sh"

# ============================================
# Tmux 基础检查
# ============================================

# 检查 tmux 是否安装
check_tmux() {
    if ! command_exists tmux; then
        log_error "tmux 未安装"
        echo ""
        echo "请安装 tmux:"
        echo "  Ubuntu/Debian: sudo apt install tmux"
        echo "  macOS: brew install tmux"
        echo "  Arch: sudo pacman -S tmux"
        exit 1
    fi
}

# ============================================
# 会话管理
# ============================================

# 检查会话是否存在
session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

# 创建新会话（后台）
create_session() {
    local session_name="$1"
    local window_name="${2:-main}"
    local working_dir="${3:-$HOME}"

    if session_exists "$session_name"; then
        log_warning "会话 '$session_name' 已存在"
        return 1
    fi

    tmux new-session -d -s "$session_name" -n "$window_name" -c "$working_dir"
    log_success "创建会话: $session_name"
}

# 销毁会话
kill_session() {
    local session_name="$1"

    if ! session_exists "$session_name"; then
        log_warning "会话 '$session_name' 不存在"
        return 1
    fi

    tmux kill-session -t "$session_name" 2>/dev/null
    log_success "停止会话: $session_name"
}

# 连接到会话
attach_session() {
    local session_name="$1"

    if ! session_exists "$session_name"; then
        log_error "会话 '$session_name' 不存在"
        return 1
    fi

    # 检查是否在 tmux 内部
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$session_name"
    else
        tmux attach-session -t "$session_name"
    fi
}

# ============================================
# 窗口管理
# ============================================

# 创建新窗口
create_window() {
    local session_name="$1"
    local window_name="$2"
    local working_dir="${3:-}"

    if [ -n "$working_dir" ]; then
        tmux new-window -t "$session_name" -n "$window_name" -c "$working_dir"
    else
        tmux new-window -t "$session_name" -n "$window_name"
    fi
}

# 选择窗口
select_window() {
    local session_name="$1"
    local window="$2"
    tmux select-window -t "$session_name:$window"
}

# ============================================
# Pane 管理
# ============================================

# 水平分割 pane
split_horizontal() {
    local target="$1"
    local percentage="${2:-50}"
    tmux split-window -h -t "$target" -p "$percentage"
}

# 垂直分割 pane
split_vertical() {
    local target="$1"
    local percentage="${2:-50}"
    tmux split-window -v -t "$target" -p "$percentage"
}

# 选择 pane
select_pane() {
    local target="$1"
    tmux select-pane -t "$target"
}

# ============================================
# 命令发送
# ============================================

# 向 pane 发送命令
send_command() {
    local target="$1"
    shift
    local command="$*"
    tmux send-keys -t "$target" "$command" Enter
}

# 向 pane 发送按键
send_keys() {
    local target="$1"
    shift
    tmux send-keys -t "$target" "$@"
}

# 清屏并发送欢迎消息
send_welcome() {
    local target="$1"
    local title="$2"
    local subtitle="${3:-}"

    tmux send-keys -t "$target" "clear" Enter
    sleep 0.1

    local message="$title"
    if [ -n "$subtitle" ]; then
        message="$title\n$subtitle"
    fi

    tmux send-keys -t "$target" "printf '\\n  $message\\n\\n'" Enter
}

# ============================================
# 配置加载
# ============================================

# 加载状态栏配置到指定会话
load_statusbar_config() {
    local session_name="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ]; then
        log_warning "状态栏配置不存在: $config_file"
        return 1
    fi

    # 读取配置文件，为每个 set-option/setw 命令添加 -t 参数
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 处理 set-option 命令 (使用 eval 正确处理引号)
        if [[ "$line" =~ ^set-option[[:space:]] ]]; then
            local opts="${line#set-option }"
            eval "tmux set-option -t '$session_name' $opts" 2>/dev/null || true
        # 处理 setw (set-window-option) 命令
        elif [[ "$line" =~ ^setw[[:space:]] ]]; then
            local opts="${line#setw }"
            eval "tmux set-window-option -t '$session_name' $opts" 2>/dev/null || true
        fi
    done < "$config_file"

    log_debug "加载状态栏配置: $config_file -> $session_name"
}

# ============================================
# 快捷键绑定
# ============================================

# 设置窗口切换快捷键
setup_window_shortcuts() {
    local session_name="$1"
    local max_windows="${2:-4}"

    # Alt+数字 直接切换窗口
    for i in $(seq 1 "$max_windows"); do
        tmux bind-key -n "M-$i" select-window -t "$session_name:$i"
    done

    # Ctrl+Y/U 切换上/下一个窗口
    tmux bind-key -n C-y previous-window
    tmux bind-key -n C-u next-window

    log_debug "设置窗口快捷键: Alt+1-$max_windows, Ctrl+Y/U"
}

# ============================================
# 服务状态检查
# ============================================

# 检查会话中是否有进程在运行
is_session_running() {
    local session_name="$1"
    local window_name="${2:-}"

    if ! session_exists "$session_name"; then
        return 1
    fi

    local target="$session_name"
    if [ -n "$window_name" ]; then
        target="$session_name:$window_name"
    fi

    local pane_pid
    pane_pid=$(tmux list-panes -t "$target" -F "#{pane_pid}" 2>/dev/null | head -1)

    if [ -n "$pane_pid" ]; then
        if pgrep -P "$pane_pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 获取会话状态描述
get_session_status() {
    local session_name="$1"

    if ! session_exists "$session_name"; then
        echo "stopped"
    elif is_session_running "$session_name"; then
        echo "running"
    else
        echo "idle"
    fi
}

# ============================================
# 日志查看
# ============================================

# 捕获 pane 内容
capture_pane() {
    local target="$1"
    local lines="${2:-100}"

    tmux capture-pane -t "$target" -p -S "-$lines"
}

# 显示会话日志
show_session_logs() {
    local session_name="$1"
    local window_name="${2:-}"
    local lines="${3:-50}"

    local target="$session_name"
    if [ -n "$window_name" ]; then
        target="$session_name:$window_name"
    fi

    if ! session_exists "$session_name"; then
        log_error "会话 '$session_name' 不存在"
        return 1
    fi

    log_info "显示最近 $lines 行日志: $target"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    capture_pane "$target" "$lines"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
