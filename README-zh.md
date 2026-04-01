# Research Project Template

基于 Claude Code 的研究项目模板。以 **VS Code DevContainer** 运行，内置 GPU 支持、Claude Code 及所有工具。

[English](README.md) | [日本語](README-ja.md)

## 特性

- **VS Code DevContainer**: 一键启动，CPU/GPU 切换支持，内置 Claude Code、GitHub CLI、autoclaude
- **Issue 驱动开发**: 以 GitHub Issue 为中心的工作流，支持 `/issue/auto` 批量处理
- **Git Worktree 管理**: 在隔离目录中并行处理多个任务
- **数据保护**: 重要数据与 Worktree 分离管理
- **Claude Code 集成**: 自定义技能实现自动化，`claude-san` 支持速率限制自动恢复
- **Human-in-the-Loop QA**: 任务执行中通过 Slack/Discord 向人类提问

---

## 在现有项目中安装

将模板技能添加到现有项目：

```bash
# 在项目目录内运行（自动检测 Git 根目录）
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash

# 或显式指定路径
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash -s -- /path/to/project

# 强制覆盖现有文件
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash -s -- --force
```

安装后，编辑 `.claude/CLAUDE.md` 设置项目特定信息。

---

## 新项目设置

### 1. 克隆模板

```bash
git clone https://github.com/AtsushiHashimoto/research-project-template.git my-project
cd my-project
chmod +x setup.sh
./setup.sh "My Project Name" "Project description" "Your Name"
```

### 2. 创建 GitHub 仓库

```bash
# 如果仓库 URL 为 https://github.com/YOUR_ORG/my-project，
# YOUR_ORG 和 my-project 是需要替换的部分。

# 公开仓库
gh repo create YOUR_ORG/my-project --source=. --push --public

# 私有仓库
gh repo create YOUR_ORG/my-project --source=. --push --private

```

### 3. 开始开发

使用 VS Code Dev Container：
1. 在 VS Code 中打开项目
2. 选择 "Reopen in Container"（选择 CPU 或 GPU 版本）
3. 启动 Claude Code：`claude-san`（通过 tmux + [autoclaude](https://github.com/henryaj/autoclaude) 实现速率限制自动恢复）

> **CPU/GPU 切换**: 配置文件位于 `.devcontainer/cpu/` 和 `.devcontainer/gpu/`。在 Dev Container 选择器中选择环境。共享设置集中在 `docker-compose.yml` 和 `post-create.sh` 中。

> 详见 [docs/claude-san.md](docs/claude-san.md)。也可以直接使用 `claude` 进行普通会话。

---

## 目录结构

```
my-project/
├── .claude/
│   ├── CLAUDE.md              # 项目配置与工作流
│   ├── commands/              # 自定义技能（命令）
│   └── skills/                # 附加技能
├── scripts/                   # 独立脚本
├── .devcontainer/
│   ├── Dockerfile                # 共享镜像（CPU/GPU）
│   ├── docker-compose.yml        # 共享服务定义
│   ├── post-create.sh            # 共享生命周期设置
│   ├── cpu/                      # CPU 配置
│   │   ├── devcontainer.json
│   │   └── docker-compose.override.yml
│   └── gpu/                      # GPU 配置
│       ├── devcontainer.json
│       └── docker-compose.override.yml
├── data/
│   └── shared/                # 共享数据（跨 Worktree）
│       └── ollama_models/     # Ollama 模型（可选）
└── worktrees/                 # Worktree 目录（.gitignore）
```

---

## 快速开始

```bash
# 1. 开始任务
/issue/start 实现数据预处理

# 2. 工作并保存进度
/commit/push

# 3. 完成任务
/issue/finish
```

---

## 可用技能

| 技能 | 用途 |
|------|------|
| `/issue/start [描述]` | 开始新任务（Issue + 分支 + Worktree） |
| `/issue/branch [描述]` | 在当前 Worktree 中创建子任务 |
| `/issue/report` | 向 Issue 报告进度 |
| `/issue/finish` | 完成任务（审查 + 合并 + 清理） |
| `/issue/auto [ids...]` | 自动按顺序处理多个 Issue（含快照） |
| `/commit` | 仅本地提交 |
| `/commit/push` | 提交并推送（保存进度） |
| `/commit/merge` | 提交并合并（完成任务） |
| `/review` | 多角度代码审查 |
| `/review-spec` | 实现前的规格审查与验证 |
| `/qa/setup` | 设置 QA 系统（Slack/Discord） |
| `/qa/ask` | 向人类提问 |
| `/qa/check` | 检查未回答的问题 |
| `/template/sync` | 同步模板最新更新 |
| `/template/contribute` | 向模板贡献改进 |

---

## 自定义

可以自定义以下内容：

- **`.claude/CLAUDE.md`**: 项目特定的规则和工作流
- **`.devcontainer/Dockerfile`**: 基础镜像、软件包、工具（如 Ollama）
- **`.devcontainer/devcontainer.json`**: VS Code 扩展、环境变量

详细自定义说明请参阅 `.claude/CLAUDE.md`。

---

## 文档

| 文档 | 说明 |
|------|------|
| [docs/claude-san.md](docs/claude-san.md) | claude-san 使用指南（tmux + autoclaude） |
| [docs/devcontainer-internals.md](docs/devcontainer-internals.md) | DevContainer 自动化机制 |
| [docs/security.md](docs/security.md) | 自动化功能的安全性分析 |

---

## 许可证

MIT License
