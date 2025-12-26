# Research Project Template

A project template for Claude Code integration with research workflows.

[日本語](README-ja.md)

## Features

- **Issue-Driven Development**: GitHub Issue-centered workflow
- **Git Worktree Management**: Parallel tasks in isolated directories
- **Data Protection**: Separation of important data and worktrees
- **Claude Code Integration**: Custom skills for automation

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
gh repo create my-project --public
git remote add origin https://github.com/YOUR_USERNAME/my-project.git
git push -u origin main
```

### 3. Start Development

With VS Code Dev Container:
1. Open project in VS Code
2. Select "Reopen in Container"
3. Start Claude Code: `claude`

---

## Directory Structure

```
my-project/
├── .claude/
│   ├── CLAUDE.md              # Project config & workflow
│   ├── commands/              # Custom skills (commands)
│   │   ├── start-task.md
│   │   ├── commit.md
│   │   ├── commit-push.md
│   │   ├── commit-merge.md
│   │   ├── finish-task.md
│   │   ├── report-progress.md
│   │   └── branch-task.md
│   └── skills/                # Worktree management skills
├── scripts/                   # Standalone scripts
│   ├── init-data.sh
│   ├── setup-worktree.sh
│   └── safe-remove-worktree.sh
├── .devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile
├── data/
│   └── shared/                # Shared data (across worktrees)
└── worktrees/                 # Worktree directory (.gitignore)
```

---

## Workflow

### Start a New Task

```bash
claude
/start-task Implement data preprocessing
```

This will:
1. Create GitHub Issue
2. Create branch (e.g., `feature/1-implement-data-preprocessing`)
3. Create worktree (e.g., `worktrees/issue1`)

### Save Progress (Intermediate)

```bash
/commit push
```

- Commit & push
- Issue stays **open**
- Worktree **remains**

### Complete Task

```bash
/finish-task
```

This will:
1. Quality review
2. Create PR & merge
3. **Close Issue**
4. **Delete worktree**

---

## Available Skills

| Skill | Purpose |
|-------|---------|
| `/start-task [desc]` | Start new task (Issue + Branch + Worktree) |
| `/branch-task [desc]` | Create child task (same worktree) |
| `/report-progress` | Report progress to Issue |
| `/commit` | Local commit only |
| `/commit push` | Commit & push (save progress) |
| `/commit merge` | Commit & merge (complete task) |
| `/finish-task` | Complete task (= `/commit merge`) |

---

## Data Management

### Important Data (Protected)

Save to `data/shared/`:
- Datasets
- Experiment results
- Trained models

### Temporary Data (Deleted with Worktree)

Save to `data/local/`:
- Cache
- Debug output
- Temp files

---

## Customization

### Project-Specific Settings

Edit `.claude/CLAUDE.md` to add project-specific rules.

### Dev Container

Edit `.devcontainer/` to customize:
- Base image
- Additional packages
- VS Code extensions

---

## License

MIT License
