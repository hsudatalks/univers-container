#!/usr/bin/env bash
# 容器资源监控 - 用于 manager 状态栏

# CPU 使用率 (1分钟平均负载 / CPU核心数 * 100)
cpu_usage() {
    local load cores pct
    load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    cores=$(nproc 2>/dev/null || echo 1)
    pct=$(echo "$load $cores" | awk '{printf "%.0f", ($1/$2)*100}')
    echo "${pct}%"
}

# 内存使用 (已用/总量)
mem_usage() {
    free -h 2>/dev/null | awk '/^Mem:/ {gsub(/i/,"",$3); gsub(/i/,"",$2); printf "%s/%s", $3, $2}'
}

# 磁盘使用率 (根目录)
disk_usage() {
    df -h / 2>/dev/null | awk 'NR==2 {print $5}'
}

# 活跃 tmux 会话数
tmux_sessions() {
    tmux list-sessions 2>/dev/null | wc -l
}

# 输出格式化的资源信息
case "${1:-all}" in
    cpu)  cpu_usage ;;
    mem)  mem_usage ;;
    disk) disk_usage ;;
    sessions) tmux_sessions ;;
    all)
        echo "CPU:$(cpu_usage) MEM:$(mem_usage) DISK:$(disk_usage)"
        ;;
esac
