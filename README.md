# Research Project Template

A project template for shared Claude Code and Codex research workflows. Runs as a **VS Code DevContainer** with GPU support, Claude Code, and all tools pre-installed.

[日本語](README-ja.md) | [中文](README-zh.md)

## Features

- **VS Code DevContainer**: One-click setup with CPU/GPU switching, Claude Code, GitHub CLI, and autoclaude pre-installed
- **Issue-Driven Development**: GitHub Issue-centered workflow with `/task-run` for batch processing
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

After installation, edit `AGENTS.md` to set project-specific information.

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
2. Select "Reopen in Container" (choose CPU or GPU variant)
3. Start Claude Code: `claude-san` (auto-resumes on rate limit via tmux + [autoclaude](https://github.com/henryaj/autoclaude))

> **CPU/GPU switching**: Configurations are in `.devcontainer/cpu/` and `.devcontainer/gpu/`. Select your environment from the Dev Container picker. Shared settings are in `docker-compose.yml` and `post-create.sh`.

> See [docs/claude-san.md](docs/claude-san.md) for details. You can also use `claude` directly for a plain session.

---

## Directory Structure

```
my-project/
├── AGENTS.md                  # Shared project instructions
├── .codex/                    # Codex-only adapter; local.md is preserved
├── .agents/skills/            # Generated relative links (not tracked)
├── .claude/
│   ├── CLAUDE.md              # Imports shared AGENTS.md
│   ├── skills/                # Custom skills (slash commands)
│   ├── rules/                 # Workflow rules (template/ is synced)
│   └── agents/                # Subagent definitions
├── .spec/                     # Required context (core-rules / invariants / known-issues)
├── scripts/                   # Standalone scripts
├── .devcontainer/
│   ├── Dockerfile                # Shared image (CPU/GPU)
│   ├── docker-compose.yml        # Shared service definition
│   ├── post-create.sh            # Shared lifecycle setup
│   ├── cpu/                      # CPU configuration
│   │   ├── devcontainer.json
│   │   └── docker-compose.override.yml
│   └── gpu/                      # GPU configuration
│       ├── devcontainer.json
│       └── docker-compose.override.yml
├── data/
│   └── shared/                # Shared data (across worktrees)
│       └── ollama_models/     # Ollama models (optional)
└── worktrees/                 # Worktree directory (.gitignore)
```

---

## Quick Start

```bash
# 1. Start a task
/issue-start Implement data preprocessing

# 2. Work and save progress
/commit-push

# 3. Complete task
/issue-finish
```

**Full skill list**: [`.claude/rules/template/skills.md`](.claude/rules/template/skills.md)
(epic / task / issue layers, commit, review, QA, template management, worktree, spec).
The list lives there only — this README does not duplicate it.

---

## Customization

You can customize the following:

- **`AGENTS.md`**: Shared project-specific rules and workflow; `.claude/CLAUDE.md` imports it
- **`.devcontainer/Dockerfile`**: Base image, packages, tools (e.g., Ollama)
- **`.devcontainer/devcontainer.json`**: VS Code extensions, environment variables

See `AGENTS.md` for shared customization and `.codex/instructions.md` for Codex-only instructions.

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

## Claude Code and Codex coexistence

Project facts and common instructions live in `AGENTS.md`. Claude imports that file;
Codex reads it directly and then reads `.codex/instructions.md`. Shared rules and skill
bodies stay in `.claude/`; `.agents/skills/` contains generated relative links to those
same skill directories. Edit the originals once to improve both agents.

After cloning, creating a worktree, or selecting a template update:

```bash
bash scripts/configure-agent-workflow.sh
```

Claude uses `/task-start`. Install Codex CLI separately, start a new Codex session,
check `/skills`, and use `$task-start`. Review both project-layer trust and the hook
definitions in `/hooks`. Registration does not mean the hook is trusted or active.
Personal authentication, permissions and terminal preferences are never distributed.

Codex-specific template instructions live in `.codex/instructions/template.md`;
project overrides live in `.codex/instructions/local.md` and are preserved by sync.
Rule selection uses existing `paths:` metadata via `scripts/agent-rules.py`. Delegation
uses the shared runtime contract: required independent reviewers, gates and stop rules
remain mandatory. Environments without required worker/resume/nesting capabilities
stop explicitly; nested `task-run` compatibility must be checked in that environment.

For existing Claude projects, installation preserves the original instructions and
writes `.template` references. `MIGRATION_REQUIRED` means compare these references,
move project facts to AGENTS, connect Claude's `@../AGENTS.md`, and add the Codex entry
read instruction. A non-force install stops before adding Codex files if existing
skills have not been upgraded. Review/select the common harness updates with
`/template-sync` or use the installer with `--force` after reviewing changes.

Install/sync/contribute path selection is defined once in `scripts/template-targets.sh`.
AGENTS and CLAUDE are reference-only during sync. Local rules, Codex local instructions,
generated links and personal configuration are excluded from contribution. General
file deletions remain manual; automatic cleanup is limited to template rules and
previously owned skill links.
