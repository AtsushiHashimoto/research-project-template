#!/usr/bin/env bash
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
                "init_later") echo "後で初期化する場合: ./scripts/init-data.sh または Claude Code で /worktree-init" ;;
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
                "init_later") echo "稍后初始化: ./scripts/init-data.sh 或在 Claude Code 中使用 /worktree-init" ;;
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
                "init_later") echo "To initialize later: ./scripts/init-data.sh or /worktree-init in Claude Code" ;;
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
trap 'rm -rf "$TMP_DIR"' EXIT

# Download template
info "$(msg downloading)"
git clone --depth 1 --branch "$TEMPLATE_BRANCH" "$TEMPLATE_REPO" "$TMP_DIR/template" 2>/dev/null || \
    error "$(msg download_failed)"

# Files to install
#
# ★ ITEMS と /template-sync の SYNC_TARGETS は**意図的に非対称**である。
#   `.dev` は install の配布対象（雛形を置く）だが、sync の差分対象には入れない。
#   backlog.md はユーザーデータであり、sync に載せると毎回「変更あり」の偽差分と
#   雛形での上書き提案を恒久生成してしまうため（#122 D9）。
ITEMS=(
    ".claude/skills"
    ".claude/agents"
    ".claude/rules"
    ".claude/worktree-config.json"
    ".claude/model-policy.json"
    ".devcontainer"
    "scripts"
    ".spec"
    ".dev"
)

cd "$PROJECT_ROOT"

# 既存設定の有無とユーザーデータを配置前に記録する。
# --force ではテンプレート（固定値入り）で上書きされるため、
# あとで復元できるようにここで控えておく。
#
# 復元対象（テンプレートの値で潰してはいけないもの）:
#   created_at        初回作成時刻
#   shared_data_path  共有データの保存先（silent reset するとデータを見失う。INV-D03）
#   path_type         上記が relative か absolute か
#   storage_type      local / external 等の保存形態
WORKTREE_CONFIG_EXISTED=false
PREV_CREATED_AT=""
PREV_SHARED_DATA_PATH=""
PREV_PATH_TYPE=""
PREV_STORAGE_TYPE=""
json_field() {
    # json_field <file> <key>
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1
}
if [[ -e ".claude/worktree-config.json" ]]; then
    WORKTREE_CONFIG_EXISTED=true
    PREV_CREATED_AT=$(json_field ".claude/worktree-config.json" created_at)
    PREV_SHARED_DATA_PATH=$(json_field ".claude/worktree-config.json" shared_data_path)
    PREV_PATH_TYPE=$(json_field ".claude/worktree-config.json" path_type)
    PREV_STORAGE_TYPE=$(json_field ".claude/worktree-config.json" storage_type)
fi

# `.dev/backlog.md` はユーザーデータ（バックログ本体）。
# --force のマージコピーでテンプレートの雛形に潰されないよう、配置前に退避しておく。
# 「存在しない場合のみ雛形を作る」を、ITEMS に含めたまま実現する（#122 D1）
DEV_BACKLOG_PRESERVED=""
if [[ -f ".dev/backlog.md" ]]; then
    DEV_BACKLOG_PRESERVED="$TMP_DIR/backlog.md.preserved"
    cp ".dev/backlog.md" "$DEV_BACKLOG_PRESERVED"
fi

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
        existed=false
        [[ -e "$dst" ]] && existed=true
        mkdir -p "$(dirname "$dst")"
        if [[ -d "$src" ]] && [[ -d "$dst" ]]; then
            # --force で既存ディレクトリを更新する場合は中身をマージコピーする。
            # `cp -r "$src" "$dst"` は dst の中へネストコピーしてしまう（例: .spec/.spec/）
            cp -r "$src/." "$dst/"
        else
            cp -r "$src" "$dst"
        fi
        # .spec/issues/ はテンプレート自身の仕様アーカイブ。新規プロジェクトには持ち込まない
        # （必読3ファイルとディレクトリ構造だけを残す）。既存 .spec がある場合は触らない
        if [[ "$item" == ".spec" ]] && [[ "$existed" != true ]]; then
            rm -f "$dst"/issues/*.md
        fi
        success "$(msg installed): $item"
    fi
done

# 退避しておいたバックログ（ユーザーデータ）を戻す
if [[ -n "$DEV_BACKLOG_PRESERVED" ]] && [[ -f "$DEV_BACKLOG_PRESERVED" ]]; then
    cp "$DEV_BACKLOG_PRESERVED" ".dev/backlog.md"
    info ".dev/backlog.md は既存の内容を保持しました（ユーザーデータのため上書きしません）"
fi

# sed -i は GNU と BSD(macOS) で引数解釈が異なる。`-i.bak` + rm が両者で動く唯一の形
sed_inplace() {
    local expr="$1" file="$2"
    sed -i.bak "$expr" "$file" && rm -f "$file.bak"
}

# Sanitize inputs for sed (escape & and | in replacement strings)
sanitize_sed() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

# Sanitize values for JSON (escape backslashes and double quotes)
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Handle CLAUDE.md
CLAUDE_MD_INSTALLED=false
if [[ -f ".claude/CLAUDE.md" ]]; then
    cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md.template"
    warn "$(msg preserved)"
else
    cp "$TMP_DIR/template/.claude/CLAUDE.md" ".claude/CLAUDE.md"
    CLAUDE_MD_INSTALLED=true
    success "$(msg installed): .claude/CLAUDE.md"
fi

# プロジェクト情報の収集（CLAUDE.md の有無に関わらず行う）。
# template-substitutions.json は /template-contribute の汚染チェックに使うため、
# 既存 CLAUDE.md があるプロジェクトでも必要になる
if [[ -t 0 ]]; then
    echo ""
    info "Setting up project info..."

    # Derive default project name from directory
    DEFAULT_PROJECT_NAME="$(basename "$PROJECT_ROOT")"

    read -r -p "Project name [$DEFAULT_PROJECT_NAME]: " PROJECT_NAME
    PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}"

    read -r -p "Project description (one line): " PROJECT_DESCRIPTION
    PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-TODO: Add project description}"

    read -r -p "Researcher name: " RESEARCHER_NAME
    RESEARCHER_NAME="${RESEARCHER_NAME:-TODO: Add researcher name}"

    START_DATE="$(date +%Y-%m-%d)"

    # 置換対象は今回インストールした CLAUDE.md のみ（既存は上書きしない）
    if [[ "$CLAUDE_MD_INSTALLED" == true ]]; then
        sed_inplace "s|{{PROJECT_NAME}}|$(sanitize_sed "$PROJECT_NAME")|g" ".claude/CLAUDE.md"
        sed_inplace "s|{{PROJECT_DESCRIPTION}}|$(sanitize_sed "$PROJECT_DESCRIPTION")|g" ".claude/CLAUDE.md"
        sed_inplace "s|{{RESEARCHER_NAME}}|$(sanitize_sed "$RESEARCHER_NAME")|g" ".claude/CLAUDE.md"
        sed_inplace "s|{{START_DATE}}|$(sanitize_sed "$START_DATE")|g" ".claude/CLAUDE.md"
        success "CLAUDE.md configured for: $PROJECT_NAME"
    fi
elif [[ "$CLAUDE_MD_INSTALLED" == true ]]; then
    # Non-interactive: leave placeholders, user edits manually
    info "Edit .claude/CLAUDE.md to replace {{...}} placeholders"
fi

# Save substitution log for /template-contribute contamination checks.
# 値が空のまま書き出すと「ファイルはあるのに汚染チェックが無効」という
# 気づきにくい状態になるため、値が取れたときだけ書き出す
if [[ -n "${PROJECT_NAME:-}" ]]; then
    cat > ".claude/template-substitutions.json" <<SUBST_EOF
{
  "PROJECT_NAME": "$(json_escape "${PROJECT_NAME:-}")",
  "PROJECT_DESCRIPTION": "$(json_escape "${PROJECT_DESCRIPTION:-}")",
  "RESEARCHER_NAME": "$(json_escape "${RESEARCHER_NAME:-}")",
  "START_DATE": "$(json_escape "${START_DATE:-}")",
  "PROJECT_SLUG": "$(json_escape "${PROJECT_NAME:-}")"
}
SUBST_EOF
    success "$(msg installed): .claude/template-substitutions.json"
else
    info "Skipped .claude/template-substitutions.json (プロジェクト情報が未入力)"
fi

# worktree-config.json をプロジェクトの実態に合わせる
# （テンプレートには固定値が入っているため、放置すると全プロジェクトが同じ値を持つ）
#
#   新規          : created_at / updated_at とも現在時刻
#   --force で上書 : ユーザーデータのフィールドを復元し、updated_at のみ現在時刻
#   保持（非force）: 触らない
#
# ★ --force はテンプレートで丸ごと上書きするので、**復元しないとデータ保存先が
#   silent reset される**（設定した外部ディスクのパスが data/shared に戻る）。
#   スキーマの更新（新フィールドの追加）はテンプレート側から届けたいので、
#   「上書きしない」ではなく「上書き後にユーザーデータだけ戻す」方式を採る（#122 D8）。
if [[ -f ".claude/worktree-config.json" ]]; then
    NOW_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # restore_field <key> <前回値>
    # 値はパス文字列でありうる（`&` `|` `\` を含む）ため、必ず sanitize_sed を通す。
    # 前回値が空（旧スキーマでフィールドが無い）ならテンプレートの既定値のままにする
    restore_field() {
        local key="$1" prev="$2"
        [[ -n "$prev" ]] || return 0
        sed_inplace "s|\"$key\": \"[^\"]*\"|\"$key\": \"$(sanitize_sed "$prev")\"|" \
            ".claude/worktree-config.json"
    }

    if [[ "$WORKTREE_CONFIG_EXISTED" != true ]]; then
        sed_inplace "s|\"created_at\": \"[^\"]*\"|\"created_at\": \"$NOW_UTC\"|" ".claude/worktree-config.json"
        sed_inplace "s|\"updated_at\": \"[^\"]*\"|\"updated_at\": \"$NOW_UTC\"|" ".claude/worktree-config.json"
    elif [[ "$FORCE" == true ]]; then
        restore_field created_at "${PREV_CREATED_AT:-$NOW_UTC}"
        restore_field shared_data_path "$PREV_SHARED_DATA_PATH"
        restore_field path_type "$PREV_PATH_TYPE"
        restore_field storage_type "$PREV_STORAGE_TYPE"
        sed_inplace "s|\"updated_at\": \"[^\"]*\"|\"updated_at\": \"$NOW_UTC\"|" ".claude/worktree-config.json"
        info "worktree-config.json: 既存の shared_data_path / path_type / storage_type を保持しました"
    fi
fi

# テンプレートの所在を記録する（読み取りは scripts/template-source.sh が単一情報源）。
# fork 運用ではこのファイルだけを書き換えれば sync / contribute の向き先が変わる（#122 D3）
# ★ --force でも上書きしない。fork 運用ではここが「テンプレートの所在」の正であり、
#   上書きすると fork 先 URL が黙って本家に戻る（worktree-config.json の
#   shared_data_path と同じクラスの silent reset）。
#   template-sync が同ファイルを同期対象から外しているのと同じ理由。
if [[ ! -f ".claude/template-source.json" ]]; then
    cat > ".claude/template-source.json" <<SRC_EOF
{
  "repo": "$(json_escape "$TEMPLATE_REPO")",
  "branch": "$(json_escape "$TEMPLATE_BRANCH")",
  "_comment": "テンプレートの所在の単一情報源。install.sh が書き出す。fork して運用する場合はここだけ書き換える（読み取りは scripts/template-source.sh 経由）"
}
SRC_EOF
    success "$(msg installed): .claude/template-source.json"
else
    info ".claude/template-source.json は既存の内容を保持しました（fork 先の設定を守るため）"
fi

# Handle .gitignore
# 必須エントリの一覧は scripts/ensure-gitignore.sh が単一情報源（install / sync の両方から呼ぶ）。
# ここで一覧を持つと sync 側に届かない（#122 O）ので、絶対に書き戻さないこと。
# ダウンロードしたテンプレート側のスクリプトを使う（--force 無しだと scripts/ の配置がスキップされ、
# インストール先に最新版が無いことがあるため）
if [[ -f ".gitignore" ]]; then
    ENSURE_GITIGNORE="$TMP_DIR/template/scripts/ensure-gitignore.sh"
    if [[ -f "$ENSURE_GITIGNORE" ]]; then
        bash "$ENSURE_GITIGNORE" --root "$PROJECT_ROOT" && success "$(msg updated_gitignore)"
    else
        warn "scripts/ensure-gitignore.sh が見つかりません（.gitignore の確認をスキップ）"
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
    msg init_desc
    echo ""
    read -r -p "[Y/n]: " do_init

    if [[ ! "$do_init" =~ ^[Nn]$ ]]; then
        echo ""
        # 初期化シーケンス（相対パス設定 → ラベル作成 → データディレクトリ）の
        # 単一情報源は worktree-init のラッパー。ここに手順を複製しないこと。
        #
        # ★ ダウンロードしたテンプレート側のラッパーを使う。
        #   プロジェクトに既存の .claude/skills があると ITEMS の配置がスキップされ、
        #   インストール先にラッパーが無い場合があるため（--force 無しの再インストール）。
        #   --root で対象を明示するのは、サブディレクトリ指定時に git のトップレベルが
        #   外側リポジトリを指してしまうのを避けるため
        # 初期化が失敗しても installer は落とさない（ファイル配置は完了しているため）。
        # 黙らせず警告と再実行方法を出す
        # 再実行の案内は「インストール先に実在するパス」を示す。
        # 既存 .claude/skills があるとラッパーは配置されないため、決め打ちにしない
        if [[ -f "$PROJECT_ROOT/.claude/skills/worktree-init/init.sh" ]]; then
            INIT_HINT="bash .claude/skills/worktree-init/init.sh"
        else
            INIT_HINT="bash scripts/init-data.sh && bash scripts/setup-labels.sh"
        fi

        INIT_WRAPPER="$TMP_DIR/template/.claude/skills/worktree-init/init.sh"
        if [[ -f "$INIT_WRAPPER" ]]; then
            bash "$INIT_WRAPPER" --root "$PROJECT_ROOT" "$PROJECT_ROOT" \
                || warn "初期化が完了しませんでした。後で実行: $INIT_HINT"
        elif [[ -x "$PROJECT_ROOT/scripts/init-data.sh" ]]; then
            warn "初期化ラッパーが見つかりません。データディレクトリのみ作成します"
            warn "  ラベル作成は後で: bash scripts/setup-labels.sh"
            "$PROJECT_ROOT/scripts/init-data.sh" "$PROJECT_ROOT" \
                || warn "初期化が完了しませんでした。後で実行: bash scripts/init-data.sh"
        else
            warn "初期化スクリプトが見つかりませんでした。手動で実行してください"
        fi
    else
        echo ""
        info "$(msg init_later)"
    fi
else
    msg init_later
fi

echo ""
echo -e "${BLUE}$(msg next_steps):${NC}"
echo "  1. $(msg step_edit)"
echo "  2. $(msg step_claude): claude"
echo "  3. $(msg step_start): /task-start <description>"
echo ""
echo -e "${BLUE}$(msg skills):${NC}"
echo "  /task-start     - Start new task (Issue + Branch + Worktree)"
echo "  /commit push    - Save progress"
echo "  /issue-finish    - Complete task (review + merge + close)"
echo ""
