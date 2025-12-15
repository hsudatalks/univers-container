#!/usr/bin/env bash
# AI Agents 状态 - 用于 agents 状态栏

case "${1:-agents}" in
    agents)
        if tmux has-session -t univers-agents 2>/dev/null; then
            # 检查是否有AI代理进程在运行
            if pgrep -f "tsx.*ark-agents" >/dev/null 2>&1; then
                echo "Running"
            else
                echo "Idle"
            fi
        else
            echo "Offline"
        fi
        ;;
    *)
        echo "Unknown"
        ;;
esac
