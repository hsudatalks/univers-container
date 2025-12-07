#!/usr/bin/env bash
#
# Tmux Check Service
# univers-quick-check 质量检查服务
#

set -euo pipefail

# 加载核心库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$CORE_LIB/common.sh"
source "$CORE_LIB/tmux-utils.sh"

# 配置
SESSION_NAME="univers-check"
WINDOW_NAME="check"
REPOS_ROOT="$(get_repos_root)"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
UNIVERS_DIR="$PROJECT_ROOT/.univers"
RESULTS_DIR="$UNIVERS_DIR/check"

# 确保结果目录存在
mkdir -p "$RESULTS_DIR"

# 启动检查
start_check() {
    local check_type="${1:-all}"

    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "检查会话已存在"
        log_info "使用 'univers dev check status' 查看状态"
        return 1
    fi

    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "项目目录不存在: $PROJECT_ROOT"
        return 1
    fi

    log_service "启动质量检查: $check_type"

    # 创建会话
    create_session "$SESSION_NAME" "$WINDOW_NAME" "$PROJECT_ROOT"

    # 加载状态栏配置
    local statusbar_config="$REPOS_ROOT/univers-container/.claude/skills/tmux-manage/configs/check-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        load_statusbar_config "$SESSION_NAME" "$statusbar_config"
    fi

    # 记录开始时间和类型
    echo "check_type=$check_type" > "$RESULTS_DIR/metadata.txt"
    echo "start_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/metadata.txt"
    echo "status=running" >> "$RESULTS_DIR/metadata.txt"

    # 构建检查命令
    local check_cmd
    case "$check_type" in
        all|rust)
            check_cmd="cargo run --bin univers-quick-check 2>&1 | tee $RESULTS_DIR/check.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/metadata.txt"
            ;;
        frontend|ui)
            check_cmd="pnpm dev check $check_type 2>&1 | tee $RESULTS_DIR/check.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/metadata.txt"
            ;;
        clippy)
            check_cmd="./scripts/fast-clippy.sh 2>&1 | tee $RESULTS_DIR/check.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/metadata.txt"
            ;;
        clippy-parallel)
            check_cmd="./scripts/parallel-clippy.sh 2>&1 | tee $RESULTS_DIR/check.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/metadata.txt"
            ;;
        *)
            log_warning "未知检查类型: $check_type，使用默认"
            check_cmd="cargo run --bin univers-quick-check 2>&1 | tee $RESULTS_DIR/check.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/metadata.txt"
            ;;
    esac

    # 发送命令
    send_command "$SESSION_NAME:$WINDOW_NAME" "$check_cmd"

    log_success "检查已在后台启动"
    echo ""
    echo "使用以下命令:"
    echo "  univers dev check status  - 查看检查状态"
    echo "  univers dev check logs    - 查看检查日志"
    echo "  univers dev check attach  - 连接到检查会话"
}

# 停止检查
stop_check() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "检查会话不存在"
        return 0
    fi

    send_keys "$SESSION_NAME:$WINDOW_NAME" C-c
    sleep 1
    kill_session "$SESSION_NAME"

    # 更新状态
    if [ -f "$RESULTS_DIR/metadata.txt" ]; then
        sed -i 's/status=running/status=cancelled/' "$RESULTS_DIR/metadata.txt"
        echo "end_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/metadata.txt"
    fi

    log_success "检查已停止"
}

# 查看状态
status_check() {
    check_tmux

    echo -e "${CYAN}质量检查状态${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "会话名: $SESSION_NAME"
    echo "结果目录: $RESULTS_DIR"
    echo ""

    # 检查会话状态
    if session_exists "$SESSION_NAME"; then
        echo -e "会话状态: ${GREEN}运行中${NC}"
    else
        echo -e "会话状态: ${YELLOW}已停止${NC}"
    fi

    # 读取元数据
    if [ -f "$RESULTS_DIR/metadata.txt" ]; then
        echo ""
        echo "最近检查:"
        while IFS='=' read -r key value; do
            case "$key" in
                check_type)  echo "  类型: $value" ;;
                start_time)  echo "  开始: $value" ;;
                end_time)    echo "  结束: $value" ;;
                status)
                    case "$value" in
                        running)   echo -e "  状态: ${YELLOW}运行中${NC}" ;;
                        completed) echo -e "  状态: ${GREEN}已完成${NC}" ;;
                        cancelled) echo -e "  状态: ${RED}已取消${NC}" ;;
                    esac
                    ;;
                exit_code)
                    if [ "$value" = "0" ]; then
                        echo -e "  结果: ${GREEN}通过${NC}"
                    else
                        echo -e "  结果: ${RED}失败 (exit: $value)${NC}"
                    fi
                    ;;
            esac
        done < "$RESULTS_DIR/metadata.txt"
    else
        echo ""
        echo "暂无检查记录"
    fi
}

# 查看日志
logs_check() {
    local lines="${1:-50}"

    # 优先从文件读取
    if [ -f "$RESULTS_DIR/check.log" ]; then
        log_info "检查日志 (最后 $lines 行):"
        echo ""
        tail -n "$lines" "$RESULTS_DIR/check.log"
    elif session_exists "$SESSION_NAME"; then
        log_info "会话日志 (最后 $lines 行):"
        echo ""
        show_session_logs "$SESSION_NAME" "$WINDOW_NAME" "$lines"
    else
        log_warning "没有可用的日志"
    fi
}

# 连接到会话
attach_check() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_error "检查会话不存在"
        return 1
    fi

    log_info "连接到检查会话..."
    attach_session "$SESSION_NAME"
}

# 查看结果摘要
result_check() {
    if [ ! -f "$RESULTS_DIR/check.log" ]; then
        log_warning "没有检查结果"
        return 1
    fi

    log_info "检查结果摘要:"
    echo ""

    # 显示错误和警告统计
    local errors=$(grep -c -i "error" "$RESULTS_DIR/check.log" 2>/dev/null || echo "0")
    local warnings=$(grep -c -i "warning" "$RESULTS_DIR/check.log" 2>/dev/null || echo "0")

    echo "错误数: $errors"
    echo "警告数: $warnings"
    echo ""

    # 显示错误行
    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}错误:${NC}"
        grep -i "error" "$RESULTS_DIR/check.log" | head -20
    fi
}

# 清理结果
clean_check() {
    log_info "清理检查结果..."
    rm -rf "$RESULTS_DIR"
    mkdir -p "$RESULTS_DIR"
    log_success "检查结果已清理"
}

# 帮助
show_help() {
    cat << EOF
Tmux Check Service - 质量检查服务

用法:
    $0 <command> [args...]

命令:
    start [type]    启动检查 (类型: all, rust, frontend, clippy, clippy-parallel)
    stop            停止检查
    status          查看状态
    logs [N]        查看日志 (默认 50 行)
    attach          连接到会话
    result          查看结果摘要
    clean           清理结果

示例:
    $0 start              # 启动默认检查 (univers-quick-check)
    $0 start clippy       # 启动 clippy 检查
    $0 status             # 查看检查状态
    $0 logs 100           # 查看最后 100 行日志

EOF
}

# 主入口
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)   start_check "$@" ;;
        stop)    stop_check ;;
        status)  status_check ;;
        logs)    logs_check "$@" ;;
        attach)  attach_check ;;
        result)  result_check ;;
        clean)   clean_check ;;
        help|--help|-h) show_help ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
