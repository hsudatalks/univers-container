#!/usr/bin/env bash
#
# EnOS Skill Sync Script
# 同步 .claude/skills/enos/ 从 hvac-operation 到 hvac-workbench
#

set -e

# 配置
SOURCE_REPO="/home/davidxu/repos/hvac-operation"
TARGET_REPO="/home/davidxu/repos/hvac-workbench"
SKILL_PATH=".claude/skills/enos"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印带颜色的消息
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

log_sync() {
    echo -e "${CYAN}🔄 $1${NC}"
}

# 检查仓库是否存在
check_repos() {
    log_info "检查仓库..."

    if [ ! -d "$SOURCE_REPO" ]; then
        log_error "源仓库不存在: $SOURCE_REPO"
        exit 1
    fi

    if [ ! -d "$TARGET_REPO" ]; then
        log_error "目标仓库不存在: $TARGET_REPO"
        exit 1
    fi

    if [ ! -d "$SOURCE_REPO/$SKILL_PATH" ]; then
        log_error "源 EnOS skill 不存在: $SOURCE_REPO/$SKILL_PATH"
        exit 1
    fi

    log_success "仓库检查通过"
}

# 同步 skill
sync_skill() {
    log_sync "开始同步 EnOS skill..."
    echo ""
    log_info "源: $SOURCE_REPO/$SKILL_PATH"
    log_info "目标: $TARGET_REPO/$SKILL_PATH"
    echo ""

    # 确保目标目录存在
    mkdir -p "$TARGET_REPO/$SKILL_PATH"

    # 使用 rsync 同步
    rsync -av --delete \
        --exclude '__pycache__' \
        --exclude '*.pyc' \
        --exclude '*.pyo' \
        --exclude '.pytest_cache' \
        --exclude '.mypy_cache' \
        "$SOURCE_REPO/$SKILL_PATH/" \
        "$TARGET_REPO/$SKILL_PATH/"

    log_success "同步完成！"
}

# 检查变更
check_changes() {
    log_info "检查 hvac-workbench 变更..."
    echo ""

    cd "$TARGET_REPO"

    # 检查是否有变更
    if git diff --quiet "$SKILL_PATH" && git diff --cached --quiet "$SKILL_PATH"; then
        log_info "没有检测到变更"
        return 0
    fi

    # 显示变更
    log_warning "检测到以下变更:"
    echo ""
    git status "$SKILL_PATH" --short
    echo ""

    # 显示详细差异
    log_info "详细差异:"
    echo ""
    git diff "$SKILL_PATH" | head -50

    if [ $(git diff "$SKILL_PATH" | wc -l) -gt 50 ]; then
        echo ""
        log_info "... (差异内容过长，仅显示前50行)"
    fi

    echo ""
    log_sync "建议提交变更:"
    echo ""
    echo "  cd $TARGET_REPO"
    echo "  git add $SKILL_PATH"
    echo "  git commit -m \"Sync EnOS skill from hvac-operation\""
    echo "  git push"
    echo ""
}

# 显示帮助
show_help() {
    cat << EOF
📋 EnOS Skill 同步工具

功能:
  单向同步 .claude/skills/enos/ 目录
  从 hvac-operation → hvac-workbench

用法:
  $0 [选项]

选项:
  -h, --help     显示此帮助信息
  -d, --dry-run  试运行模式（仅显示将要同步的内容）

工作流:
  1. 在 hvac-operation 开发新功能
  2. 提交并推送到 git
  3. 运行此脚本同步到 hvac-workbench
  4. 在 hvac-workbench 提交同步变更
  5. 团队成员 git pull 自动获取更新

示例:
  # 执行同步
  $0

  # 试运行（不实际同步）
  $0 --dry-run

EOF
}

# 试运行模式
dry_run() {
    log_sync "试运行模式 - 显示将要同步的内容"
    echo ""

    rsync -av --delete --dry-run \
        --exclude '__pycache__' \
        --exclude '*.pyc' \
        --exclude '*.pyo' \
        --exclude '.pytest_cache' \
        --exclude '.mypy_cache' \
        "$SOURCE_REPO/$SKILL_PATH/" \
        "$TARGET_REPO/$SKILL_PATH/"

    echo ""
    log_info "以上是试运行结果，没有实际修改文件"
}

# 主函数
main() {
    local dry_run_mode=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                dry_run_mode=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            EnOS Skill Sync Tool                        ║"
    echo "║            同步工具：hvac-operation → hvac-workbench    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # 检查仓库
    check_repos
    echo ""

    # 同步或试运行
    if [ "$dry_run_mode" = true ]; then
        dry_run
    else
        sync_skill
        echo ""
        check_changes
    fi

    echo ""
    log_success "完成！"
}

# 运行主函数
main "$@"
