#!/usr/bin/env bash
#
# Tmux Bench Service
# 性能基准测试服务
#

set -euo pipefail

# 加载核心库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$CORE_LIB/common.sh"
source "$CORE_LIB/tmux-utils.sh"

# 配置
SESSION_NAME="univers-bench"
WINDOW_NAME="bench"
REPOS_ROOT="$(get_repos_root)"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
UNIVERS_DIR="$PROJECT_ROOT/.univers"
RESULTS_DIR="$UNIVERS_DIR/bench"

# 确保结果目录存在
mkdir -p "$RESULTS_DIR"

# 启动基准测试
start_bench() {
    local suite="${1:-all}"

    check_tmux

    if session_exists "$SESSION_NAME"; then
        log_warning "基准测试会话已存在"
        log_info "使用 'univers dev bench status' 查看状态"
        return 1
    fi

    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "项目目录不存在: $PROJECT_ROOT"
        return 1
    fi

    log_service "启动基准测试: $suite"

    # 创建会话
    create_session "$SESSION_NAME" "$WINDOW_NAME" "$PROJECT_ROOT"

    # 加载状态栏配置
    local statusbar_config="$REPOS_ROOT/univers-container/.claude/skills/tmux-manage/configs/bench-statusbar.conf"
    if [ -f "$statusbar_config" ]; then
        load_statusbar_config "$SESSION_NAME" "$statusbar_config"
    fi

    # 记录开始时间和套件
    echo "suite=$suite" > "$RESULTS_DIR/metadata.txt"
    echo "start_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/metadata.txt"
    echo "status=running" >> "$RESULTS_DIR/metadata.txt"

    # 构建测试命令
    local bench_cmd
    bench_cmd="./scripts/test-benchmark.sh $suite 2>&1 | tee $RESULTS_DIR/bench.log; echo \"exit_code=\$?\" >> $RESULTS_DIR/metadata.txt; echo \"end_time=\$(date '+%Y-%m-%d %H:%M:%S')\" >> $RESULTS_DIR/metadata.txt; sed -i 's/status=running/status=completed/' $RESULTS_DIR/metadata.txt"

    # 发送命令
    send_command "$SESSION_NAME:$WINDOW_NAME" "$bench_cmd"

    log_success "基准测试已在后台启动"
    echo ""
    echo "使用以下命令:"
    echo "  univers dev bench status  - 查看测试状态"
    echo "  univers dev bench logs    - 查看测试日志"
    echo "  univers dev bench attach  - 连接到测试会话"
}

# 停止测试
stop_bench() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_warning "基准测试会话不存在"
        return 0
    fi

    send_keys "$SESSION_NAME:$WINDOW_NAME" C-c
    sleep 1
    kill_session "$SESSION_NAME"

    # 更新状态
    if [ -f "$RESULTS_DIR/metadata.txt" ]; then
        sed -i 's/status=running/status=completed/' "$RESULTS_DIR/metadata.txt"
        echo "end_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/metadata.txt"
    fi

    log_success "基准测试已停止"
}

# 查看状态
status_bench() {
    check_tmux

    echo -e "${CYAN}基准测试状态${NC}"
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
        echo "最近测试:"
        while IFS='=' read -r key value; do
            case "$key" in
                suite)       echo "  套件: $value" ;;
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
        echo "暂无测试记录"
    fi
}

# 查看日志
logs_bench() {
    local lines="${1:-50}"

    # 优先从文件读取
    if [ -f "$RESULTS_DIR/bench.log" ]; then
        log_info "基准测试日志 (最后 $lines 行):"
        echo ""
        tail -n "$lines" "$RESULTS_DIR/bench.log"
    elif session_exists "$SESSION_NAME"; then
        log_info "会话日志 (最后 $lines 行):"
        echo ""
        show_session_logs "$SESSION_NAME" "$WINDOW_NAME" "$lines"
    else
        log_warning "没有可用的日志"
    fi
}

# 连接到会话
attach_bench() {
    check_tmux

    if ! session_exists "$SESSION_NAME"; then
        log_error "基准测试会话不存在"
        return 1
    fi

    log_info "连接到基准测试会话..."
    attach_session "$SESSION_NAME"
}

# 查看结果
result_bench() {
    if [ ! -f "$RESULTS_DIR/bench.log" ]; then
        log_warning "没有基准测试结果"
        return 1
    fi

    log_info "基准测试结果:"
    echo ""

    # 提取性能数据
    grep -E "(time|ns/iter|benchmark|Benchmarking)" "$RESULTS_DIR/bench.log" | tail -30
}

# 清理结果
clean_bench() {
    log_info "清理基准测试结果..."
    rm -rf "$RESULTS_DIR"
    mkdir -p "$RESULTS_DIR"
    log_success "基准测试结果已清理"
}

# 帮助
show_help() {
    cat << EOF
Tmux Bench Service - 性能基准测试服务

用法:
    $0 <command> [args...]

命令:
    start [suite]   启动基准测试 (套件: all, core, api, db, ...)
    stop            停止测试
    status          查看状态
    logs [N]        查看日志 (默认 50 行)
    attach          连接到会话
    result          查看结果摘要
    clean           清理结果

示例:
    $0 start              # 运行所有基准测试
    $0 start core         # 只测试 core 模块
    $0 status             # 查看测试状态
    $0 logs 100           # 查看最后 100 行日志

EOF
}

# 主入口
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)   start_bench "$@" ;;
        stop)    stop_bench ;;
        status)  status_bench ;;
        logs)    logs_bench "$@" ;;
        attach)  attach_bench ;;
        result)  result_bench ;;
        clean)   clean_bench ;;
        help|--help|-h) show_help ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
