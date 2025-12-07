#!/usr/bin/env bash
#
# 质量指示器脚本
# 从 univers-quick-check 的缓存结果中读取代码质量状态
#
# 设计：完全路径无关，支持克隆到任意目录
#

# 符号定义
CHECK_PASS="✓"
CHECK_FAIL="✗"
CHECK_UNKNOWN="?"

# 方法1：优先使用传入的路径参数
CURRENT_DIR="${1:-$(pwd)}"

# 方法2：从脚本自身位置推断项目根目录
if [ ! -d "$CURRENT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CURRENT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

# 尝试从当前路径找到 Git 根目录
WORKSPACE=$(cd "$CURRENT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$WORKSPACE" ]; then
    # Fallback：使用脚本所在的项目目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WORKSPACE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

# 获取容器名/主机名
# FIX: 如果 HOSTNAME 环境变量为空，使用 hostname 命令
HOST_NAME="${HOSTNAME:-$(hostname)}"

# 查找quick-check结果文件
# 优先级: 1. 项目内 .univers/check 2. /tmp 临时目录
UNIVERS_CHECK_DIR="$WORKSPACE/.univers/check"
RESULT_FILE=""

# 优先使用项目内的结果
if [ -f "$UNIVERS_CHECK_DIR/result.json" ]; then
    RESULT_FILE="$UNIVERS_CHECK_DIR/result.json"
elif [ -f "/tmp/univers-quick-check-${HOST_NAME}.json" ]; then
    RESULT_FILE="/tmp/univers-quick-check-${HOST_NAME}.json"
fi

# 如果结果文件不存在，检查 metadata.txt 获取简单状态
if [ -z "$RESULT_FILE" ] || [ ! -f "$RESULT_FILE" ]; then
    # 尝试从 metadata.txt 读取状态
    if [ -f "$UNIVERS_CHECK_DIR/metadata.txt" ]; then
        status=$(grep "^status=" "$UNIVERS_CHECK_DIR/metadata.txt" | cut -d= -f2)
        exit_code=$(grep "^exit_code=" "$UNIVERS_CHECK_DIR/metadata.txt" | cut -d= -f2)
        case "$status" in
            running)   echo "C⏳ L? T?" ;;
            completed)
                if [ "$exit_code" = "0" ]; then
                    echo "C$CHECK_PASS L? T?"
                else
                    echo "C$CHECK_FAIL L? T?"
                fi
                ;;
            *)         echo "C$CHECK_UNKNOWN L$CHECK_UNKNOWN T$CHECK_UNKNOWN" ;;
        esac
        exit 0
    fi
    echo "C$CHECK_UNKNOWN L$CHECK_UNKNOWN T$CHECK_UNKNOWN"
    exit 0
fi

# 读取JSON结果（支持新旧两种格式）
# 新格式（v2.0+）: .summary.check_result
# 旧格式: .check_result
CHECK_RESULT=$(jq -r '.summary.check_result // .check_result // ""' "$RESULT_FILE" 2>/dev/null)

# 如果读取失败或为空，显示未知状态
if [ -z "$CHECK_RESULT" ] || [ "$CHECK_RESULT" = "null" ]; then
    echo "C$CHECK_UNKNOWN L$CHECK_UNKNOWN T$CHECK_UNKNOWN"
    exit 0
fi

# 解析结果字符串 Q:C✓F✓L✓T✓WC✓WL✓WT✓
# 提取 C(check), F(format), L(lint/clippy), T(test), WC(web check), WL(web lint), WT(web test) 的状态
parse_status() {
    local status_str="$1"
    local key="$2"

    # 查找key后面的字符（✓ 或 ✗ 或 ⏭）
    if echo "$status_str" | grep -q "${key}✓"; then
        echo "$CHECK_PASS"
    elif echo "$status_str" | grep -q "${key}✗"; then
        echo "$CHECK_FAIL"
    elif echo "$status_str" | grep -q "${key}⏭"; then
        echo "⏭"  # 跳过
    else
        echo "$CHECK_UNKNOWN"
    fi
}

CHECK_STATUS=$(parse_status "$CHECK_RESULT" "C")
FORMAT_STATUS=$(parse_status "$CHECK_RESULT" "F")
LINT_STATUS=$(parse_status "$CHECK_RESULT" "L")
TEST_STATUS=$(parse_status "$CHECK_RESULT" "T")
WEB_CHECK_STATUS=$(parse_status "$CHECK_RESULT" "WC")
WEB_LINT_STATUS=$(parse_status "$CHECK_RESULT" "WL")
WEB_TEST_STATUS=$(parse_status "$CHECK_RESULT" "WT")

# 输出结果（格式：C✓ F✓ L✓ T✓ WC✓ WL✓ WT✓）
echo "C$CHECK_STATUS F$FORMAT_STATUS L$LINT_STATUS T$TEST_STATUS WC$WEB_CHECK_STATUS WL$WEB_LINT_STATUS WT$WEB_TEST_STATUS"
