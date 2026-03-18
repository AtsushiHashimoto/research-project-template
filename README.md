# Research Project Template

A project template for Claude Code integration with research workflows. Runs as a **VS Code DevContainer** with GPU support, Claude Code, and all tools pre-installed.

[日本語](README-ja.md) | [中文](README-zh.md)

## Features

- **VS Code DevContainer**: One-click setup with GPU support, Claude Code, GitHub CLI, and autoclaude pre-installed
- **Issue-Driven Development**: GitHub Issue-centered workflow with `/issue/auto` for batch processing
- **Git Worktree Management**: Parallel tasks in isolated directories
- **Data Protection**: Separation of important data and worktrees
- **Claude Code Integration**: Custom skills for automation, rate-limit auto-resume via `claude-san`
- **Human-in-the-Loop QA**: Ask questions to humans via Slack/Discord during task execution

---

## Installation for Existing Projects

Add template skills to an existing project:

```bash
# Run inside your project (auto-detects git root)
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash

# Or specify path explicitly
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash -s -- /path/to/project

# Force overwrite existing files
curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash -s -- --force
```

After installation, edit `.claude/CLAUDE.md` to set project-specific information.

---

## New Project Setup

### 1. Clone Template

```bash
git clone https://github.com/AtsushiHashimoto/research-project-template.git my-project
cd my-project
chmod +x setup.sh
./setup.sh "My Project Name" "Project description" "Your Name"
```

### 2. Create GitHub Repository

```bash
# If your repository URL is https://github.com/YOUR_ORG/my-project,
# YOUR_ORG and my-project are the parts you need to replace.

# Public
gh repo create YOUR_ORG/my-project --source=. --push --public

# Private
gh repo create YOUR_ORG/my-project --source=. --push --private

```

### 3. Start Development

With VS Code Dev Container:
1. Open project in VS Code
2. Select "Reopen in Container"
3. Start Claude Code: `claude-san` (auto-resumes on rate limit via tmux + [autoclaude](https://github.com/henryaj/autoclaude))

> See [docs/claude-san.md](docs/claude-san.md) for details. You can also use `claude` directly for a plain session.

---

## Directory Structure

```
my-project/
├── .claude/
│   ├── CLAUDE.md              # Project config & workflow
│   ├── commands/              # Custom skills (commands)
│   └── skills/                # Additional skills
├── scripts/                   # Standalone scripts
├── .devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile
├── data/
│   └── shared/                # Shared data (across worktrees)
│       └── ollama_models/     # Ollama models (optional)
└── worktrees/                 # Worktree directory (.gitignore)
```

---

## Quick Start

```bash
# 1. Start a task
/issue/start Implement data preprocessing

# 2. Work and save progress
/commit/push

# 3. Complete task
/issue/finish
```

---

## Available Skills

| Skill | Purpose |
|-------|---------|
| `/issue/start [desc]` | Start new task (Issue + Branch + Worktree) |
| `/issue/branch [desc]` | Create child task in current worktree |
| `/issue/report` | Report progress to Issue |
| `/issue/finish` | Complete task (review + merge + cleanup) |
| `/issue/auto [ids...]` | Auto-process multiple Issues in sequence (with snapshot) |
| `/commit` | Local commit only |
| `/commit/push` | Commit & push (save progress) |
| `/commit/merge` | Commit & merge (complete task) |
| `/review` | Multi-perspective code review |
| `/review-spec` | Review and validate specification before implementation |
| `/qa/setup` | Set up QA system (Slack/Discord) |
| `/qa/ask` | Ask a question to humans |
| `/qa/check` | Check for unanswered questions |
| `/template/sync` | Sync updates from template |
| `/template/contribute` | Contribute improvements to template |

---

## Customization

You can customize the following:

- **`.claude/CLAUDE.md`**: Project-specific rules and workflow
- **`.devcontainer/Dockerfile`**: Base image, packages, tools (e.g., Ollama)
- **`.devcontainer/devcontainer.json`**: VS Code extensions, environment variables

See `.claude/CLAUDE.md` for detailed customization instructions.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/claude-san.md](docs/claude-san.md) | claude-san usage guide (tmux + autoclaude) |
| [docs/devcontainer-internals.md](docs/devcontainer-internals.md) | DevContainer automation internals |
| [docs/security.md](docs/security.md) | Security analysis of automation features |

---

## License

MIT License
