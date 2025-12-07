# Univers Core

Univers 核心工具库，为所有 Univers 项目提供统一的基础设施。

## 概述

univers-core 是一个共享的工具库，提供：

- **通用函数** (`lib/common.sh`): 日志、颜色、路径工具
- **Tmux 工具** (`lib/tmux-utils.sh`): 会话、窗口、pane 管理
- **服务管理** (`lib/service-manager.sh`): 服务注册、启停、状态管理
- **统一入口** (`bin/univers`): 跨项目的统一命令行入口

## 安装

```bash
# 创建全局命令链接
sudo ln -sf /home/davidxu/repos/univers-container/.claude/skills/univers-core/bin/univers /usr/local/bin/univers
```

## 使用

### 统一入口命令

```bash
univers <project> <command> [args...]

# 项目
univers dev ...      # hvac-workbench 开发
univers ops ...      # hvac-operation 运维
univers manage ...   # univers-container 管理

# 示例
univers dev server start socket   # 启动开发服务器
univers ops operator start        # 启动运维会话
univers manage start              # 启动所有管理视图
univers status                    # 查看所有项目状态
```

### 在其他项目中引用核心库

```bash
#!/usr/bin/env bash

# 加载核心库
UNIVERS_CORE="/home/davidxu/repos/univers-container/.claude/skills/univers-core/lib"
source "$UNIVERS_CORE/common.sh"
source "$UNIVERS_CORE/tmux-utils.sh"

# 使用日志函数
log_info "这是信息"
log_success "操作成功"
log_error "出错了"

# 使用 tmux 工具
check_tmux
create_session "my-session" "main" "/path/to/project"
send_command "my-session:main" "echo hello"
```

## 库 API

### common.sh

| 函数 | 说明 |
|------|------|
| `log_info`, `log_success`, `log_warning`, `log_error` | 带颜色的日志输出 |
| `get_real_script_path` | 获取脚本真实路径（解析符号链接） |
| `get_script_dir` | 获取脚本所在目录 |
| `find_project_root` | 查找项目根目录 |
| `ensure_non_root` | 确保非 root 运行 |
| `command_exists` | 检查命令是否存在 |
| `get_univers_core_dir` | 获取核心库目录 |
| `get_repos_root` | 获取 repos 根目录 |

### tmux-utils.sh

| 函数 | 说明 |
|------|------|
| `check_tmux` | 检查 tmux 是否安装 |
| `session_exists` | 检查会话是否存在 |
| `create_session` | 创建新会话 |
| `kill_session` | 销毁会话 |
| `attach_session` | 连接到会话 |
| `create_window` | 创建新窗口 |
| `split_horizontal`, `split_vertical` | 分割 pane |
| `send_command` | 向 pane 发送命令 |
| `send_welcome` | 发送欢迎消息 |
| `setup_window_shortcuts` | 设置窗口切换快捷键 |
| `is_session_running` | 检查会话是否有进程运行 |
| `get_session_status` | 获取会话状态 |
| `show_session_logs` | 显示会话日志 |

### service-manager.sh

| 函数 | 说明 |
|------|------|
| `register_service` | 注册服务 |
| `start_service`, `stop_service`, `restart_service` | 服务控制 |
| `status_service`, `logs_service`, `attach_service` | 服务查看 |
| `status_all_services`, `stop_all_services` | 批量操作 |

## 项目集成指南

### 为新项目添加 univers 支持

1. 在项目中创建 skill 目录：
   ```
   .claude/skills/univers-<name>/
   ├── SKILL.md
   ├── services.yaml      # 服务配置
   └── scripts/
       └── manager.sh     # 项目管理器
   ```

2. manager.sh 示例：
   ```bash
   #!/usr/bin/env bash
   UNIVERS_CORE="/home/davidxu/repos/univers-container/.claude/skills/univers-core/lib"
   source "$UNIVERS_CORE/common.sh"
   source "$UNIVERS_CORE/tmux-utils.sh"
   source "$UNIVERS_CORE/service-manager.sh"

   # 注册项目服务
   SCRIPT_DIR="$(get_script_dir)"
   register_service "server" "$SCRIPT_DIR/tmux-server.sh"
   register_service "worker" "$SCRIPT_DIR/tmux-worker.sh"

   # 处理命令
   case "${1:-help}" in
       server|worker)
           # 路由到服务
           ;;
       *)
           show_help
           ;;
   esac
   ```

3. 在 univers-core/bin/univers 中注册项目路径（可选，用于统一入口）

## 目录结构

```
univers-core/
├── SKILL.md              # 本文档
├── lib/
│   ├── common.sh         # 通用工具函数
│   ├── tmux-utils.sh     # Tmux 会话管理
│   └── service-manager.sh # 服务管理框架
├── bin/
│   └── univers           # 统一命令入口
└── templates/            # 脚本模板（待添加）
```
