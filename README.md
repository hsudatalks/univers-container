# Univers Container Management

这个仓库用于管理开发和运营容器的日常操作。

## 用途

- 每个开发或运营容器都会克隆此仓库
- 使用 Claude Code 进行容器管理和配置
- 集中管理容器相关的脚本和配置文件

## 使用方法

1. 在容器中克隆此仓库：
   ```bash
   git clone <repository-url>
   cd univers-container
   ```

2. 使用 Claude Code 进行日常管理：
   ```bash
   claude
   ```

## 工具集

### Tmux 会话管理

一键启动/停止所有开发和运维会话：

```bash
# 启动所有会话（包括 desktop 和 mobile 视图）
tmux-manager start

# 停止所有会话
tmux-manager stop-all

# 启动桌面视图
tmux-desktop-view start

# 启动移动视图
tmux-mobile-view start
```

快捷键：
- `Ctrl+Y` / `Ctrl+U` - 上一个/下一个窗口
- `Alt+1~4` - 直接切换到指定窗口
- `Ctrl+B D` - 退出会话（不停止）

### EnOS Skill 同步

同步 `.claude/skills/enos/` 从 hvac-operation 到 hvac-workbench：

```bash
# 执行同步
sync-enos

# 试运行（不实际修改）
sync-enos --dry-run

# 查看帮助
sync-enos --help
```

工作流：
1. 在 hvac-operation 开发 EnOS skill 新功能
2. 提交并推送到 git
3. 运行 `sync-enos` 同步到 hvac-workbench
4. 在 hvac-workbench 提交同步变更
5. 团队成员 `git pull` 自动获取更新

## 目录结构

```
univers-container/
├── .claude/
│   └── skills/
│       ├── container-manage/  # 容器管理 skill
│       └── tmux-manage/       # Tmux 会话管理 skill
├── scripts/
│   └── sync-enos-skill.sh     # EnOS skill 同步脚本
└── README.md
```

## 注意事项

- 请勿提交敏感信息（密码、密钥等）
- 所有环境变量应使用 `.env` 文件并已在 `.gitignore` 中排除
