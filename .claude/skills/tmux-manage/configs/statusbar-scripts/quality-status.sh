#!/usr/bin/env bash
# 质量检查状态 - 用于 developer 状态栏

UNIVERS_DIR="$HOME/repos/hvac-workbench/.univers"
CHECK_DIR="$UNIVERS_DIR/check"

# 检查最新结果
if [ -f "$CHECK_DIR/summary.txt" ]; then
    # 读取摘要的第一行
    result=$(head -1 "$CHECK_DIR/summary.txt" 2>/dev/null)
    if echo "$result" | grep -qi "pass\|success\|ok"; then
        echo "QA:OK"
    elif echo "$result" | grep -qi "fail\|error"; then
        echo "QA:FAIL"
    else
        echo "QA:?"
    fi
elif tmux has-session -t univers-check 2>/dev/null; then
    echo "QA:..."
else
    echo "QA:-"
fi
