#!/bin/bash
# Research Project Template Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash
#   curl -fsSL ... | bash -s -- /path/to/project
#   curl -fsSL ... | bash -s -- --force

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect language
detect_lang() {
    local lang="${LANG:-${LC_ALL:-en}}"
    case "$lang" in
        ja*) echo "ja" ;;
        zh*) echo "zh" ;;
        *)   echo "en" ;;
    esac
}

LANG_CODE=$(detect_lang)

# Multilingual messages
msg() {
    local key="$1"
    case "$LANG_CODE" in
        ja)
            case "$key" in
                "installing") echo "インストール先" ;;
                "downloading") echo "テンプレートをダウンロード中..." ;;
                "download_failed") echo "テンプレートのダウンロードに失敗しました" ;;
                "skipping") echo "スキップ（既に存在）" ;;
                "use_force") echo "--force で上書き可能" ;;
                "installed") echo "インストール完了" ;;
                "preserved") echo "既存ファイルを保持。テンプレートは .template として保存" ;;
                "updated_gitignore") echo ".gitignore を更新しました" ;;
                "gitignore_ok") echo ".gitignore は既に必要なエントリを含んでいます" ;;
                "created_data") echo "data/shared ディレクトリを作成しました" ;;
                "complete") echo "インストール完了！" ;;
                "init_prompt") echo "データディレクトリを初期化しますか？" ;;
                "init_desc") echo "共有データの保存場所を設定します（デフォルト: data/shared）" ;;
                "init_later") echo "後で初期化する場合: ./scripts/init-data.sh または Claude Code で /worktree/init" ;;
                "next_steps") echo "次のステップ" ;;
                "step_edit") echo ".claude/CLAUDE.md を編集してプロジェクト情報を設定" ;;
                "step_claude") echo "Claude Code を起動" ;;
                "step_start") echo "最初のタスクを開始" ;;
                "skills") echo "利用可能なスキル" ;;
            esac
            ;;
        zh)
            case "$key" in
                "installing") echo "安装到" ;;
                "downloading") echo "正在下载模板..." ;;
                "download_failed") echo "模板下载失败" ;;
                "skipping") echo "跳过（已存在）" ;;
                "use_force") echo "使用 --force 覆盖" ;;
                "installed") echo "安装完成" ;;
                "preserved") echo "保留现有文件。模板已保存为 .template" ;;
                "updated_gitignore") echo "已更新 .gitignore" ;;
                "gitignore_ok") echo ".gitignore 已包含所需条目" ;;
                "created_data") echo "已创建 data/shared 目录" ;;
                "complete") echo "安装完成！" ;;
                "init_prompt") echo "是否初始化数据目录？" ;;
                "init_desc") echo "设置共享数据存储位置（默认: data/shared）" ;;
                "init_later") echo "稍后初始化: ./scripts/init-data.sh 或在 Claude Code 中使用 /worktree/init" ;;
                "next_steps") echo "下一步" ;;
                "step_edit") echo "编辑 .claude/CLAUDE.md 设置项目信息" ;;
                "step_claude") echo "启动 Claude Code" ;;
                "step_start") echo "开始第一个任务" ;;
                "skills") echo "可用技能" ;;
            esac
            ;;
        *)  # English
            case "$key" in
                "installing") echo "Installing to" ;;
                "downloading") echo "Downloading template..." ;;
                "download_failed") echo "Failed to download template" ;;
                "skipping") echo "Skipping (already exists)" ;;
                "use_force") echo "Use --force to overwrite" ;;
                "installed") echo "Installed" ;;
                "preserved") echo "Existing file preserved. Template saved as .template" ;;
                "updated_gitignore") echo "Updated .gitignore" ;;
                "gitignore_ok") echo ".gitignore already has required entries" ;;
                "created_data") echo "Created data/shared directory" ;;
                "complete") echo "Installation complete!" ;;
                "init_prompt") echo "Initialize data directory?" ;;
                "init_desc") echo "Configure shared data storage location (default: data/shared)" ;;
                "init_later") echo "To initialize later: ./scripts/init-data.sh or /worktree/init in Claude Code" ;;
                "next_steps") echo "Next steps" ;;
                "step_edit") echo "Edit .claude/CLAUDE.md to set project info" ;;
                "step_claude") echo "Start Claude Code" ;;
                "step_start") echo "Start your first task" ;;
                "skills") echo "Available skills" ;;
            esac
            ;;
    esac
}

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Default values
TEMPLATE_REPO="https://github.com/AtsushiHashimoto/research-project-template"
TEMPLATE_BRANCH="main"
FORCE=false
TARGET_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: install.sh [OPTIONS] [TARGET_DIR]"
            echo ""
            echo "Options:"
            echo "  --force, -f    Overwrite existing files"
            echo "  --help, -h     Show this help"
            exit 0
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# Determine target directory
if [[ -n "$TARGET_DIR" ]]; then
    if [[ ! -d "$TARGET_DIR" ]]; then
        error "Directory not found: $TARGET_DIR"
    fi
    PROJECT_ROOT="$(cd "$TARGET_DIR" && pwd)"
elif git rev-parse --show-toplevel &>/dev/null; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    PROJECT_ROOT="$(pwd)"
    warn "Not in a git repository. Using current directory: $PROJECT_ROOT"
fi

info "$(msg installing): $PROJECT_ROOT"

# Create temp directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Download template
info "$(msg downloading)"
git clone --depth 1 --branch "$TEMPLATE_BRANCH" "$TEMPLATE_REPO" "$TMP_DIR/template" 2>/dev/null || \
    error "$(msg download_failed)"

# Files to install
ITEMS=(
    ".claude/commands"
    ".claude/skills"
    "scripts"
)

cd "$PROJECT_ROOT"

# Create directories
mkdir -p .claude

# Install files
for item in "${ITEMS[@]}"; do
    src="$TMP_DIR/template/$item"
    dst="$PROJECT_ROOT/$item"

    if [[ -e "$dst" ]] && [[ "$FORCE" != true ]]; then
        warn "$(msg skipping): $item"
        warn "  $(msg use_force)"
    else
        mkdir -p "$(dirname "$dst")"
        cp -r "$src" "$dst"
        success "$(msg installed): $item"
    fi
done

# Handle CLAUDE.md
if [[ -f ".claude/CLAUDE.md" ]]; then
    cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md.template"
    warn "$(msg preserved)"
else
    cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md"
    success "$(msg installed): .claude/CLAUDE.md"
fi

# Handle .gitignore
if [[ -f ".gitignore" ]]; then
    GITIGNORE_ENTRIES=(
        "worktrees/"
        "data/shared/**"
        "!data/shared/.gitkeep"
        "data/local/"
    )

    ADDED=false
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
        if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
            echo "$entry" >> .gitignore
            ADDED=true
        fi
    done

    if [[ "$ADDED" == true ]]; then
        success "$(msg updated_gitignore)"
    else
        success "$(msg gitignore_ok)"
    fi
else
    cp "$TMP_DIR/template/.gitignore" ".gitignore"
    success "$(msg installed): .gitignore"
fi

# Create data directory
if [[ ! -d "data/shared" ]]; then
    mkdir -p data/shared
    touch data/.gitkeep data/shared/.gitkeep
    success "$(msg created_data)"
fi

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || true

echo ""
echo "=========================================="
success "$(msg complete)"
echo "=========================================="
echo ""

# Ask about initialization (only if interactive)
if [[ -t 0 ]]; then
    echo -e "${BLUE}$(msg init_prompt)${NC}"
    echo "$(msg init_desc)"
    echo ""
    read -p "[Y/n]: " do_init

    if [[ ! "$do_init" =~ ^[Nn]$ ]]; then
        echo ""
        "$PROJECT_ROOT/scripts/init-data.sh" "$PROJECT_ROOT"
    else
        echo ""
        info "$(msg init_later)"
    fi
else
    echo "$(msg init_later)"
fi

echo ""
echo -e "${BLUE}$(msg next_steps):${NC}"
echo "  1. $(msg step_edit)"
echo "  2. $(msg step_claude): claude"
echo "  3. $(msg step_start): /start-task <description>"
echo ""
echo -e "${BLUE}$(msg skills):${NC}"
echo "  /start-task     - Start new task (Issue + Branch + Worktree)"
echo "  /commit push    - Save progress"
echo "  /finish-task    - Complete task (review + merge + close)"
echo ""
