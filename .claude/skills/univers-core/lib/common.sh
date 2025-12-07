#!/usr/bin/env bash
#
# Univers Core - Common Utilities
# 通用工具函数库
#

# 防止重复加载
if [ -n "${_UNIVERS_COMMON_LOADED:-}" ]; then
    return 0
fi
_UNIVERS_COMMON_LOADED=1

# ============================================
# 颜色定义
# ============================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# ============================================
# 日志函数
# ============================================
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_service() {
    echo -e "${CYAN}🔧 $1${NC}"
}

log_debug() {
    if [ "${UNIVERS_DEBUG:-0}" = "1" ]; then
        echo -e "${MAGENTA}🐛 $1${NC}"
    fi
}

# ============================================
# 路径工具
# ============================================

# 获取脚本的真实路径（解析符号链接）
get_real_script_path() {
    local script_path="${1:-${BASH_SOURCE[1]}}"
    if [ -L "$script_path" ]; then
        script_path="$(readlink -f "$script_path")"
    fi
    echo "$script_path"
}

# 获取脚本所在目录
get_script_dir() {
    local script_path
    script_path="$(get_real_script_path "${1:-${BASH_SOURCE[1]}}")"
    cd "$(dirname "$script_path")" && pwd
}

# 查找项目根目录（向上查找包含特定文件的目录）
find_project_root() {
    local start_dir="${1:-$(pwd)}"
    local markers=("CLAUDE.md" ".git" "Cargo.toml" "package.json")
    local current_dir="$start_dir"

    while [ "$current_dir" != "/" ]; do
        for marker in "${markers[@]}"; do
            if [ -e "$current_dir/$marker" ]; then
                echo "$current_dir"
                return 0
            fi
        done
        current_dir="$(dirname "$current_dir")"
    done

    # 未找到，返回起始目录
    echo "$start_dir"
    return 1
}

# ============================================
# 用户权限处理
# ============================================

# 确保不以 root 身份运行，如果是则切换到普通用户
ensure_non_root() {
    if [ "$EUID" -eq 0 ]; then
        local target_user
        if [ -n "$SUDO_USER" ]; then
            target_user="$SUDO_USER"
        else
            target_user=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1; exit}' /etc/passwd)
            if [ -z "$target_user" ]; then
                log_error "找不到非 root 用户"
                exit 1
            fi
        fi
        exec sudo -u "$target_user" "$0" "$@"
    fi
}

# ============================================
# 工具函数
# ============================================

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 获取 univers-core 库目录
get_univers_core_dir() {
    local script_path
    script_path="$(get_real_script_path "${BASH_SOURCE[0]}")"
    cd "$(dirname "$script_path")/.." && pwd
}

# 获取 univers-container 项目根目录
get_univers_container_root() {
    local core_dir
    core_dir="$(get_univers_core_dir)"
    cd "$core_dir/../../.." && pwd
}

# 获取 repos 根目录（包含所有项目的目录）
get_repos_root() {
    local container_root
    container_root="$(get_univers_container_root)"
    dirname "$container_root"
}
