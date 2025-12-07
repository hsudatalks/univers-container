#!/usr/bin/env bash
#
# Tmux E2E Service
# E2E 端到端测试服务
#

set -euo pipefail

# 加载核心库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$CORE_LIB/common.sh"
source "$CORE_LIB/tmux-utils.sh"

# 配置
SESSION_NAME="univers-e2e"
WINDOW_NAME="e2e"
REPOS_ROOT="$(get_repos_root)"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
UNIVERS_DIR="$PROJECT_ROOT/.univers"
RESULTS_DIR="$UNIVERS_DIR/test"

# 确保结果目录存在
mkdir -p "$RESULTS_DIR"

# 启动 E2E 测试
start_e2e() {
    local module="${1:-all}"

    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "E2E 测试会话已存在"
        log_info "使用 'univers dev e2e status' 查看状态"
        return 1
    fi

    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "项目目录不存在: $PROJECT_ROOT"
        return 1
    fi

    log_service "启动 E2E 测试: $module"

    # 创建会话
    create_session "$SESSION_NAME" "$WINDOW_NAME" "$PROJECT_ROOT"

    # 加载状态栏配置
    local statusbar_config="$REPOS_ROOT/univers-container/.claude/skills/tmux-manage/configs/e2e-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        load_statusbar_config "$SESSION_NAME" "$statusbar_config"
    fi

    # 记录开始时间和模块
    echo "module=$module" > "$RESULTS_DIR/e2e-metadata.txt"
    echo "start_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/e2e-metadata.txt"
    echo "status=running" >> "$RESULTS_DIR/e2e-metadata.txt"

    # 构建测试命令
    local test_cmd
    test_cmd="./scripts/test-e2e-socket.sh $module 2>&1 | tee $RESULTS_DIR/e2e.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/e2e-metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/e2e-metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/e2e-metadata.txt"

    # 发送命令
    send_command "$SESSION_NAME:$WINDOW_NAME" "$test_cmd"

    log_success "E2E 测试已在后台启动"
    echo ""
    echo "使用以下命令:"
    echo "  univers dev e2e status  - 查看测试状态"
    echo "  univers dev e2e logs    - 查看测试日志"
    echo "  univers dev e2e attach  - 连接到测试会话"
}

# 停止测试
stop_e2e() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "E2E 测试会话不存在"
        return 0
    fi

    send_keys "$SESSION_NAME:$WINDOW_NAME" C-c
    sleep 1
    kill_session "$SESSION_NAME"

    # 更新状态
    if [ -f "$RESULTS_DIR/e2e-metadata.txt" ]; then
        sed -i 's/status=running/status=cancelled/' "$RESULTS_DIR/e2e-metadata.txt"
        echo "end_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/e2e-metadata.txt"
    fi

    log_success "E2E 测试已停止"
}

# 查看状态
status_e2e() {
    check_tmux

    echo -e "${CYAN}E2E 测试状态${NC}"
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
    if [ -f "$RESULTS_DIR/e2e-metadata.txt" ]; then
        echo ""
        echo "最近测试:"
        while IFS='=' read -r key value; do
            case "$key" in
                module)      echo "  模块: $value" ;;
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
        done < "$RESULTS_DIR/e2e-metadata.txt"
    else
        echo ""
        echo "暂无测试记录"
    fi
}

# 查看日志
logs_e2e() {
    local lines="${1:-50}"

    # 优先从文件读取
    if [ -f "$RESULTS_DIR/e2e.log" ]; then
        log_info "E2E 测试日志 (最后 $lines 行):"
        echo ""
        tail -n "$lines" "$RESULTS_DIR/e2e.log"
    elif session_exists "$SESSION_NAME"; then
        log_info "会话日志 (最后 $lines 行):"
        echo ""
        show_session_logs "$SESSION_NAME" "$WINDOW_NAME" "$lines"
    else
        log_warning "没有可用的日志"
    fi
}

# 连接到会话
attach_e2e() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_error "E2E 测试会话不存在"
        return 1
    fi

    log_info "连接到 E2E 测试会话..."
    attach_session "$SESSION_NAME"
}

# 查看结果摘要
result_e2e() {
    if [ ! -f "$RESULTS_DIR/summary.txt" ]; then
        log_warning "没有测试结果摘要"
        return 1
    fi

    log_info "E2E 测试结果摘要:"
    echo ""
    cat "$RESULTS_DIR/summary.txt"
}

# 清理结果
clean_e2e() {
    log_info "清理 E2E 测试结果..."
    rm -f "$RESULTS_DIR/e2e.log" "$RESULTS_DIR/e2e-metadata.txt"
    log_success "E2E 测试结果已清理"
}

# 帮助
show_help() {
    cat << EOF
Tmux E2E Service - E2E 端到端测试服务

用法:
    $0 <command> [args...]

命令:
    start [module]  启动 E2E 测试
                    模块: all (默认), twin, organization, data, control,
                          integration, hvac, resource, maintenance,
                          intelligence, validation, computation, relation, frontend
    stop            停止测试
    status          查看状态
    logs [N]        查看日志 (默认 50 行)
    attach          连接到会话
    result          查看结果摘要
    clean           清理结果

示例:
    $0 start              # 运行所有 E2E 测试
    $0 start twin         # 只测试 twin 模块
    $0 status             # 查看测试状态
    $0 logs 100           # 查看最后 100 行日志

EOF
}

# 主入口
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)   start_e2e "$@" ;;
        stop)    stop_e2e ;;
        status)  status_e2e ;;
        logs)    logs_e2e "$@" ;;
        attach)  attach_e2e ;;
        result)  result_e2e ;;
        clean)   clean_e2e ;;
        help|--help|-h) show_help ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
