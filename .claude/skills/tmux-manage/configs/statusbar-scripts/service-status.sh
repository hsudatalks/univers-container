#!/usr/bin/env bash
# 服务状态检测 - 用于 server/ui/web 状态栏

check_port() {
    local port=$1
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        echo "ON"
    else
        echo "OFF"
    fi
}

check_session() {
    local session=$1
    if tmux has-session -t "$session" 2>/dev/null; then
        echo "ON"
    else
        echo "OFF"
    fi
}

case "${1:-}" in
    server)
        # 检查 3003 端口
        status=$(check_port 3003)
        [ "$status" = "ON" ] && echo ":3003" || echo ":3003?"
        ;;
    ui)
        # 检查 6007 端口
        status=$(check_port 6007)
        [ "$status" = "ON" ] && echo ":6007" || echo ":6007?"
        ;;
    web)
        # 检查 3432 端口
        status=$(check_port 3432)
        [ "$status" = "ON" ] && echo ":3432" || echo ":3432?"
        ;;
    socket)
        # WebSocket 状态 (简化检测)
        status=$(check_port 3003)
        [ "$status" = "ON" ] && echo "sock:ON" || echo "sock:OFF"
        ;;
    hmr)
        # HMR 状态
        local port=${2:-3432}
        status=$(check_port "$port")
        [ "$status" = "ON" ] && echo "HMR:ON" || echo "HMR:OFF"
        ;;
    *)
        echo "Usage: $0 {server|ui|web|socket|hmr}"
        ;;
esac
