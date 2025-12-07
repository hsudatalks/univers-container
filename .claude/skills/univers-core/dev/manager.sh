#!/usr/bin/env bash
#
# Univers Dev Manager
# hvac-workbench 项目开发管理 - 核心实现
#

set -euo pipefail

# ============================================
# 加载核心库
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_LIB="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$CORE_LIB/common.sh"
source "$CORE_LIB/tmux-utils.sh"
source "$CORE_LIB/service-manager.sh"

# ============================================
# 项目配置
# ============================================
REPOS_ROOT="$(get_repos_root)"
PROJECT_ROOT="$REPOS_ROOT/hvac-workbench"
# 服务脚本现在统一管理在 univers-core/dev 目录
SCRIPTS_DIR="$SCRIPT_DIR"
PROJECT_SCRIPTS="$PROJECT_ROOT/scripts"

# Univers 本地数据目录
UNIVERS_DIR="$PROJECT_ROOT/.univers"
mkdir -p "$UNIVERS_DIR"

# 验证项目存在
if [ ! -d "$PROJECT_ROOT" ]; then
    log_error "hvac-workbench 项目不存在: $PROJECT_ROOT"
    exit 1
fi

# ============================================
# 注册服务
# ============================================
register_service "server" "$SCRIPTS_DIR/tmux-server.sh" "univers-server"
register_service "ui" "$SCRIPTS_DIR/tmux-ui.sh" "univers-ui"
register_service "web" "$SCRIPTS_DIR/tmux-web.sh" "univers-web"

# ============================================
# 测试命令
# ============================================
run_test() {
    local test_type=${1:-}
    if [ -z "$test_type" ]; then
        log_error "Test type required"
        echo "Valid types: unit, e2e, fast, all, live"
        return 1
    fi
    shift

    cd "$PROJECT_ROOT" || exit 1

    case "$test_type" in
        unit)
            log_info "Running unit tests..."
            pnpm dev test unit "$@"
            ;;
        e2e)
            local module=${1:-all}
            log_info "Running E2E tests for: $module"
            ./scripts/test-e2e-socket.sh "$module"
            ;;
        fast)
            log_info "Running fast tests..."
            ./scripts/fast-test.sh
            ;;
        benchmark)
            local suite=${1:-all}
            log_info "Running benchmark tests for: $suite"
            ./scripts/test-benchmark.sh "$suite"
            ;;
        all)
            log_info "Running all tests..."
            pnpm dev test all "$@"
            ;;
        live)
            local live_test=${1:-enos}
            case "$live_test" in
                enos)
                    log_info "Running EnOS Live tests..."
                    pnpm test:live:enos
                    ;;
                enos:connection)
                    log_info "Running EnOS connection health tests..."
                    pnpm test:live:enos:connection
                    ;;
                enos:data)
                    log_info "Running EnOS data validation tests..."
                    pnpm test:live:enos:data
                    ;;
                enos:device)
                    log_info "Running EnOS device tests..."
                    pnpm test:live:enos:device
                    ;;
                enos:sync)
                    log_info "Running EnOS sync tests..."
                    pnpm test:live:enos:sync
                    ;;
                *)
                    log_error "Unknown live test type: $live_test"
                    echo "Valid types: enos, enos:connection, enos:data, enos:device, enos:sync"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error "Unknown test type: $test_type"
            echo "Valid types: unit, e2e, fast, benchmark, all, live"
            return 1
            ;;
    esac
}

# ============================================
# 测试结果命令
# ============================================
run_test_result() {
    local action=${1:-summary}
    local TEST_RESULTS_DIR="$UNIVERS_DIR/test"

    if [ ! -d "$TEST_RESULTS_DIR" ]; then
        log_warning "No test results found at: $TEST_RESULTS_DIR"
        echo "Run 'univers dev test e2e all' to generate results"
        return 1
    fi

    case "$action" in
        summary|status)
            log_info "Test Results Summary"
            echo ""
            [ -f "$TEST_RESULTS_DIR/metadata.txt" ] && cat "$TEST_RESULTS_DIR/metadata.txt" && echo ""
            [ -f "$TEST_RESULTS_DIR/summary.txt" ] && cat "$TEST_RESULTS_DIR/summary.txt" || log_warning "Summary not found"
            ;;
        list)
            log_info "Available test logs:"
            ls -lh "$TEST_RESULTS_DIR"/*.log 2>/dev/null | awk '{print $9, "(" $5 ")"}' || echo "No logs found"
            ;;
        show)
            local module=${2:-}
            [ -z "$module" ] && { log_error "Module name required"; return 1; }
            local log_file="$TEST_RESULTS_DIR/${module}.log"
            [ -f "$log_file" ] && cat "$log_file" || { log_error "Log not found: $log_file"; return 1; }
            ;;
        failed)
            log_info "Failed tests:"
            grep -h "FAIL" "$TEST_RESULTS_DIR"/*.log 2>/dev/null | head -50 || echo "No failures found"
            ;;
        path)
            echo "$TEST_RESULTS_DIR"
            ;;
        clean)
            log_info "Cleaning test results..."
            rm -rf "$TEST_RESULTS_DIR" "$TEST_RESULTS_DIR.backup"
            log_success "Test results cleaned"
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Valid actions: summary, list, show <module>, failed, path, clean"
            return 1
            ;;
    esac
}

# ============================================
# 数据库命令
# ============================================
run_db() {
    local db_action=${1:-}
    [ -z "$db_action" ] && { log_error "Database action required"; echo "Valid: clear, explore, switch, stop"; return 1; }
    shift

    cd "$PROJECT_ROOT" || exit 1

    case "$db_action" in
        clear)   log_info "Clearing database..."; ./scripts/clear-database.sh "$@" ;;
        explore) log_info "Exploring database..."; ./scripts/explore-db.sh "$@" ;;
        switch)  local mode=${1:-memory}; log_info "Switching database to: $mode"; ./scripts/switch-db.sh "$mode" ;;
        stop)    log_info "Stopping SurrealDB..."; ./scripts/stop-surrealdb.sh ;;
        *)       log_error "Unknown db action: $db_action"; return 1 ;;
    esac
}

# ============================================
# QA 服务脚本路径
# ============================================
CHECK_SCRIPT="$SCRIPT_DIR/tmux-check.sh"
E2E_SCRIPT="$SCRIPT_DIR/tmux-e2e.sh"
BENCH_SCRIPT="$SCRIPT_DIR/tmux-bench.sh"

# ============================================
# 质量检查命令 (tmux 托管)
# ============================================

handle_check() {
    local action="${1:-status}"
    shift || true

    if [ ! -f "$CHECK_SCRIPT" ]; then
        log_error "检查脚本不存在: $CHECK_SCRIPT"
        return 1
    fi

    exec "$CHECK_SCRIPT" "$action" "$@"
}

# 保留旧的同步检查函数用于直接运行
run_check_sync() {
    local check_type=${1:-all}
    shift || true

    cd "$PROJECT_ROOT" || exit 1

    case "$check_type" in
        all)         log_info "Running univers-quick-check"; cargo run --bin univers-quick-check ;;
        rust)        log_info "Running Rust checks"; cargo run --bin univers-quick-check ;;
        frontend|ui) log_info "Running quick check: $check_type"; pnpm dev check "$check_type" "$@" ;;
        *)           log_error "Unknown check type: $check_type"; return 1 ;;
    esac
}

# ============================================
# E2E 测试命令 (tmux 托管)
# ============================================
handle_e2e() {
    local action="${1:-status}"
    shift || true

    if [ ! -f "$E2E_SCRIPT" ]; then
        log_error "E2E 脚本不存在: $E2E_SCRIPT"
        return 1
    fi

    exec "$E2E_SCRIPT" "$action" "$@"
}

# ============================================
# 基准测试命令 (tmux 托管)
# ============================================
handle_bench() {
    local action="${1:-status}"
    shift || true

    if [ ! -f "$BENCH_SCRIPT" ]; then
        log_error "基准测试脚本不存在: $BENCH_SCRIPT"
        return 1
    fi

    exec "$BENCH_SCRIPT" "$action" "$@"
}

run_validate() {
    local validate_type=${1:-all}
    shift || true
    cd "$PROJECT_ROOT" || exit 1
    log_info "Running validation: $validate_type"
    pnpm dev validate "$validate_type" "$@"
}

run_clippy() {
    local clippy_mode=${1:-fast}
    cd "$PROJECT_ROOT" || exit 1

    case "$clippy_mode" in
        fast)     log_info "Running fast clippy..."; ./scripts/fast-clippy.sh ;;
        parallel) log_info "Running parallel clippy..."; ./scripts/parallel-clippy.sh ;;
        *)        log_error "Unknown clippy mode: $clippy_mode"; return 1 ;;
    esac
}

# ============================================
# EnOS 命令
# ============================================
run_enos() {
    local enos_action=${1:-}
    [ -z "$enos_action" ] && { log_error "ENOS action required"; echo "Valid: switch, validate"; return 1; }
    shift

    cd "$PROJECT_ROOT" || exit 1

    case "$enos_action" in
        switch)   local env=${1:-dev}; log_info "Switching ENOS to: $env"; ./scripts/enos-switch-env.sh "$env" ;;
        validate) log_info "Validating ENOS data..."; ./scripts/enos_data_validation.sh ;;
        *)        log_error "Unknown enos action: $enos_action"; return 1 ;;
    esac
}

# ============================================
# 组织命令
# ============================================
run_org() {
    local org_action=${1:-}
    [ -z "$org_action" ] && { log_error "Organization action required"; echo "Valid: switch, manage"; return 1; }
    shift

    cd "$PROJECT_ROOT" || exit 1

    case "$org_action" in
        switch)
            local org_id=${1:-}
            [ -z "$org_id" ] && { log_error "Organization ID required"; return 1; }
            log_info "Switching organization to: $org_id"
            ./scripts/switch-org.sh "$org_id"
            ;;
        manage)
            log_info "Managing organizations..."
            ./scripts/org-manager.sh "$@"
            ;;
        *)
            log_error "Unknown org action: $org_action"
            return 1
            ;;
    esac
}

# ============================================
# 代码生成命令
# ============================================
run_codegen() {
    local codegen_action=${1:-}
    [ -z "$codegen_action" ] && { log_error "Codegen action required"; echo "Valid: api-clients"; return 1; }
    shift

    cd "$PROJECT_ROOT" || exit 1

    case "$codegen_action" in
        api-clients|api|clients)
            log_info "Generating API clients..."
            local script="$PROJECT_ROOT/scripts/codegen/generate-api-clients.sh"
            [ -f "$script" ] && "$script" "$@" || { log_error "Script not found: $script"; return 1; }
            ;;
        *)
            log_error "Unknown codegen action: $codegen_action"
            return 1
            ;;
    esac
}

# ============================================
# 处理服务命令
# ============================================
handle_service() {
    local service="$1"
    local action="${2:-status}"
    shift 2 || shift || true

    check_tmux

    case "$action" in
        start)   start_service "$service" "$@" ;;
        stop)    stop_service "$service" ;;
        restart) restart_service "$service" "$@" ;;
        status)  status_service "$service" ;;
        logs)    logs_service "$service" "${1:-50}" ;;
        attach)  attach_service "$service" ;;
        *)       log_error "Unknown action: $action"; echo "Valid: start, stop, restart, status, logs, attach"; return 1 ;;
    esac
}

# ============================================
# 帮助信息
# ============================================
show_help() {
    cat << EOF
Univers Dev Manager - hvac-workbench 开发管理

用法:
    univers dev <command> [args...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
服务管理 (tmux)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    server start/stop/restart/status/logs/attach
    ui start/stop/restart/status/logs/attach
    web start/stop/restart/status/logs/attach
    all status              查看所有服务状态

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
测试
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    test unit               单元测试
    test e2e [module]       E2E 测试
    test fast               快速测试
    test all                全部测试
    test live [type]        EnOS 实时测试

    result [action]         查看测试结果

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QA 质量检查 (tmux 托管)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    check start [type]      后台启动检查 (all, rust, clippy, frontend)
    check stop/status/logs/attach/result/clean

    e2e start [module]      后台启动 E2E 测试 (all, twin, data, ...)
    e2e stop/status/logs/attach/result/clean

    bench start [suite]     后台启动基准测试
    bench stop/status/logs/attach/result/clean

    check-sync [type]       同步运行检查 (阻塞)
    validate [type]         验证
    clippy [mode]           Clippy 检查

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
数据库
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    db clear/explore/switch/stop

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
其他
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    enos switch/validate    EnOS 环境
    org switch/manage       组织管理
    codegen api-clients     代码生成

项目路径: $PROJECT_ROOT
EOF
}

# ============================================
# 主入口
# ============================================
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        help|--help|-h)
            show_help
            ;;

        # 服务管理
        server|ui|web)
            handle_service "$command" "$@"
            ;;

        all)
            local action=${1:-status}
            [ "$action" == "status" ] && { check_tmux; status_all_services; } || { log_error "Only 'status' supported"; exit 1; }
            ;;

        # 测试
        test)
            run_test "$@"
            ;;

        result|test-result)
            run_test_result "$@"
            ;;

        # 质量检查 (tmux 托管)
        check)
            handle_check "$@"
            ;;

        # 同步检查 (阻塞)
        check-sync)
            run_check_sync "$@"
            ;;

        # E2E 测试 (tmux 托管)
        e2e)
            handle_e2e "$@"
            ;;

        # 基准测试 (tmux 托管)
        bench)
            handle_bench "$@"
            ;;

        validate)
            run_validate "$@"
            ;;

        clippy)
            run_clippy "$@"
            ;;

        # 数据库
        db)
            run_db "$@"
            ;;

        # EnOS
        enos)
            run_enos "$@"
            ;;

        # 组织
        org)
            run_org "$@"
            ;;

        # 代码生成
        codegen)
            run_codegen "$@"
            ;;

        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
