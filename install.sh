#!/bin/bash
# Research Project Template Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AtsushiHashimoto/research-project-template/main/install.sh | bash
#   curl -fsSL ... | bash -s -- /path/to/project
#   curl -fsSL ... | bash -s -- --force  # 既存ファイルを上書き

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# デフォルト値
TEMPLATE_REPO="https://github.com/AtsushiHashimoto/research-project-template"
TEMPLATE_BRANCH="main"
FORCE=false
TARGET_DIR=""

# 引数解析
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
            echo "  --help, -h     Show this help message"
            echo ""
            echo "If TARGET_DIR is not specified, uses git root or current directory."
            exit 0
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# ターゲットディレクトリの決定
if [[ -n "$TARGET_DIR" ]]; then
    # 引数で指定された場合
    if [[ ! -d "$TARGET_DIR" ]]; then
        error "Directory not found: $TARGET_DIR"
    fi
    PROJECT_ROOT="$(cd "$TARGET_DIR" && pwd)"
elif git rev-parse --show-toplevel &>/dev/null; then
    # Gitリポジトリ内の場合
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    # それ以外はカレントディレクトリ
    PROJECT_ROOT="$(pwd)"
    warn "Not in a git repository. Using current directory: $PROJECT_ROOT"
fi

info "Installing to: $PROJECT_ROOT"

# 一時ディレクトリ
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# テンプレートをダウンロード
info "Downloading template..."
git clone --depth 1 --branch "$TEMPLATE_BRANCH" "$TEMPLATE_REPO" "$TMP_DIR/template" 2>/dev/null || \
    error "Failed to download template"

# インストールするファイル/ディレクトリ
ITEMS=(
    ".claude/commands"
    ".claude/skills"
    ".claude/worktree-config.json"
)

OPTIONAL_ITEMS=(
    ".devcontainer"
    "data"
)

# .claude/CLAUDE.md は特別扱い（マージが必要な場合がある）
# .gitignore も特別扱い

cd "$PROJECT_ROOT"

# .claude ディレクトリの作成
mkdir -p .claude

# 必須ファイルのインストール
for item in "${ITEMS[@]}"; do
    src="$TMP_DIR/template/$item"
    dst="$PROJECT_ROOT/$item"

    if [[ -e "$dst" ]] && [[ "$FORCE" != true ]]; then
        warn "Skipping (already exists): $item"
        warn "  Use --force to overwrite"
    else
        mkdir -p "$(dirname "$dst")"
        cp -r "$src" "$dst"
        success "Installed: $item"
    fi
done

# CLAUDE.md の処理
if [[ -f ".claude/CLAUDE.md" ]]; then
    if [[ "$FORCE" == true ]]; then
        cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md.template"
        warn "Existing CLAUDE.md found. Template saved as CLAUDE.md.template"
        warn "  Please merge manually if needed"
    else
        cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md.template"
        warn "Existing CLAUDE.md preserved. Template saved as CLAUDE.md.template"
    fi
else
    cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md"
    success "Installed: .claude/CLAUDE.md"
    warn "Please edit .claude/CLAUDE.md to customize for your project:"
    warn "  - Replace {{PROJECT_NAME}} with your project name"
    warn "  - Replace {{PROJECT_DESCRIPTION}} with your description"
    warn "  - Replace {{RESEARCHER_NAME}} with your name"
    warn "  - Replace {{START_DATE}} with today's date"
fi

# .gitignore の処理
if [[ -f ".gitignore" ]]; then
    info "Checking .gitignore..."

    # 追加が必要なエントリ
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
        success "Updated .gitignore with worktree/data entries"
    else
        success ".gitignore already has required entries"
    fi
else
    cp "$TMP_DIR/template/.gitignore" ".gitignore"
    success "Installed: .gitignore"
fi

# オプショナルファイルの確認
echo ""
info "Optional components:"
for item in "${OPTIONAL_ITEMS[@]}"; do
    dst="$PROJECT_ROOT/$item"
    if [[ -e "$dst" ]]; then
        echo "  [EXISTS] $item"
    else
        echo "  [MISSING] $item - copy from template if needed"
    fi
done

# data ディレクトリの作成
if [[ ! -d "data/shared" ]]; then
    mkdir -p data/shared
    touch data/.gitkeep data/shared/.gitkeep
    success "Created: data/shared directory"
fi

# 完了メッセージ
echo ""
echo "=========================================="
success "Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Edit .claude/CLAUDE.md to customize for your project"
echo "  2. Review .claude/commands/ for available skills"
echo "  3. Start Claude Code: claude"
echo "  4. Begin your first task: /start-task <description>"
echo ""
echo "Available skills:"
echo "  /start-task     - Start a new task (Issue + Branch + Worktree)"
echo "  /commit push    - Save progress (no merge)"
echo "  /finish-task    - Complete task (review + merge + close)"
echo "  /report-progress - Report progress to Issue"
echo ""

if [[ ! -d ".devcontainer" ]]; then
    echo "Optional: To add Dev Container support, run:"
    echo "  cp -r $TMP_DIR/template/.devcontainer ."
    echo "  (Run this before the installer exits, or re-run with template)"
fi
