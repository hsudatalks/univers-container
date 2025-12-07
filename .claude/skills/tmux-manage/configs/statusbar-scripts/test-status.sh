#!/usr/bin/env bash
# 测试状态 - 用于 check/e2e 状态栏

UNIVERS_DIR="$HOME/repos/hvac-workbench/.univers"

case "${1:-check}" in
    check)
        CHECK_DIR="$UNIVERS_DIR/check"
        if tmux has-session -t univers-check 2>/dev/null; then
            # 检查是否有进程在运行
            if pgrep -f "univers-quick-check" >/dev/null 2>&1; then
                echo "Running..."
            else
                echo "Idle"
            fi
        elif [ -f "$CHECK_DIR/summary.txt" ]; then
            # 显示最后结果时间
            mtime=$(stat -c %Y "$CHECK_DIR/summary.txt" 2>/dev/null)
            now=$(date +%s)
            diff=$((now - mtime))
            if [ $diff -lt 60 ]; then
                echo "Done <1m"
            elif [ $diff -lt 3600 ]; then
                echo "Done $((diff/60))m"
            else
                echo "Done $((diff/3600))h"
            fi
        else
            echo "No result"
        fi
        ;;
    e2e)
        TEST_DIR="$UNIVERS_DIR/test"
        if tmux has-session -t univers-e2e 2>/dev/null; then
            if pgrep -f "test-e2e" >/dev/null 2>&1; then
                echo "Running..."
            else
                echo "Idle"
            fi
        elif [ -f "$TEST_DIR/summary.txt" ]; then
            # 显示通过/失败数
            pass=$(grep -c "PASS" "$TEST_DIR/summary.txt" 2>/dev/null || echo 0)
            fail=$(grep -c "FAIL" "$TEST_DIR/summary.txt" 2>/dev/null || echo 0)
            echo "P:$pass F:$fail"
        else
            echo "No result"
        fi
        ;;
    bench)
        BENCH_DIR="$UNIVERS_DIR/bench"
        if tmux has-session -t univers-bench 2>/dev/null; then
            echo "Running..."
        elif [ -d "$BENCH_DIR" ]; then
            echo "Done"
        else
            echo "No result"
        fi
        ;;
esac
