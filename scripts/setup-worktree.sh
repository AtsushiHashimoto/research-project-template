#!/usr/bin/env bash
# Setup data directories in a worktree
# Usage: ./scripts/setup-worktree.sh [WORKTREE_DIR]

set -euo pipefail

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

msg() {
    local key="$1"
    case "$LANG_CODE" in
        ja)
            case "$key" in
                "title") echo "Worktree データディレクトリのセットアップ" ;;
                "worktree") echo "Worktree" ;;
                "main_repo") echo "メインリポジトリ" ;;
                "not_worktree") echo "ここはWorktreeではないようです" ;;
                "run_in_worktree") echo "Worktreeディレクトリで実行してください" ;;
                "config_not_found") echo "設定ファイルが見つかりません" ;;
                "run_init_first") echo "先にメインリポジトリで初期化を実行してください" ;;
                "config") echo "設定" ;;
                "symlink_exists") echo "data/shared シンボリックリンクは既に存在します" ;;
                "dir_has_data") echo "data/shared がシンボリックリンクではなく実体のあるディレクトリで、中にデータがあります" ;;
                "stray_link_removed") echo "旧バージョンが作った不要なリンクを削除しました" ;;
                "dir_unreadable") echo "data/shared を読み取れません（権限を確認してください）" ;;
                "move_data_first") echo "そのままでは共有データにリンクできません。次のコマンドで中身をメインリポジトリへ移してから再実行してください:" ;;
                "dir_remove_failed") echo "data/shared ディレクトリを削除できませんでした" ;;
                "dir_replaced") echo "空の data/shared ディレクトリを削除しました（シンボリックリンクに置き換えます）" ;;
                "recreate") echo "再作成しますか？ [y/N]" ;;
                "cancelled") echo "キャンセルしました" ;;
                "local_exists") echo "data/local ディレクトリは既に存在します" ;;
                "creating_local") echo "data/local を作成中..." ;;
                "created") echo "作成完了" ;;
                "creating_symlink") echo "共有データへのシンボリックリンクを作成中..." ;;
                "complete") echo "セットアップ完了！" ;;
                "structure") echo "ディレクトリ構造" ;;
                "usage") echo "使い方" ;;
                "usage_shared") echo "重要なデータはこちらに保存（Worktree間で共有）" ;;
                "usage_local") echo "一時ファイルはこちら（Worktree削除時に消えます）" ;;
                "remember") echo "注意" ;;
                "use_safe_remove") echo "Worktree削除時は /worktree/safe-remove を使用してください" ;;
            esac
            ;;
        zh)
            case "$key" in
                "title") echo "Worktree 数据目录设置" ;;
                "worktree") echo "Worktree" ;;
                "main_repo") echo "主仓库" ;;
                "not_worktree") echo "这似乎不是一个 Worktree" ;;
                "run_in_worktree") echo "请在 Worktree 目录中运行" ;;
                "config_not_found") echo "找不到配置文件" ;;
                "run_init_first") echo "请先在主仓库中运行初始化" ;;
                "config") echo "配置" ;;
                "symlink_exists") echo "data/shared 符号链接已存在" ;;
                "dir_has_data") echo "data/shared 是真实目录（非符号链接）且其中包含数据" ;;
                "stray_link_removed") echo "已删除旧版本创建的多余链接" ;;
                "dir_unreadable") echo "无法读取 data/shared（请检查权限）" ;;
                "move_data_first") echo "当前状态无法链接到共享数据。请用以下命令将内容移动到主仓库后重新执行:" ;;
                "dir_remove_failed") echo "无法删除 data/shared 目录" ;;
                "dir_replaced") echo "已删除空的 data/shared 目录（将替换为符号链接）" ;;
                "recreate") echo "是否重新创建？ [y/N]" ;;
                "cancelled") echo "已取消" ;;
                "local_exists") echo "data/local 目录已存在" ;;
                "creating_local") echo "正在创建 data/local..." ;;
                "created") echo "创建完成" ;;
                "creating_symlink") echo "正在创建共享数据符号链接..." ;;
                "complete") echo "设置完成！" ;;
                "structure") echo "目录结构" ;;
                "usage") echo "使用方法" ;;
                "usage_shared") echo "重要数据保存在这里（Worktree 间共享）" ;;
                "usage_local") echo "临时文件放这里（删除 Worktree 时会被删除）" ;;
                "remember") echo "注意" ;;
                "use_safe_remove") echo "删除 Worktree 时请使用 /worktree/safe-remove" ;;
            esac
            ;;
        *)
            case "$key" in
                "title") echo "Worktree Data Directory Setup" ;;
                "worktree") echo "Worktree" ;;
                "main_repo") echo "Main repository" ;;
                "not_worktree") echo "This does not appear to be a worktree" ;;
                "run_in_worktree") echo "Run this in a worktree directory" ;;
                "config_not_found") echo "Configuration file not found" ;;
                "run_init_first") echo "Run initialization in main repository first" ;;
                "config") echo "Configuration" ;;
                "symlink_exists") echo "data/shared symlink already exists" ;;
                "dir_has_data") echo "data/shared is a real directory and contains data" ;;
                "stray_link_removed") echo "Removed a stray link left by an older version" ;;
                "dir_unreadable") echo "Cannot read data/shared (check permissions)" ;;
                "move_data_first") echo "Cannot link to the shared data as-is. Move the contents to the main repository with the command below, then re-run:" ;;
                "dir_remove_failed") echo "Failed to remove the data/shared directory" ;;
                "dir_replaced") echo "Removed empty data/shared directory (replacing it with a symlink)" ;;
                "recreate") echo "Recreate? [y/N]" ;;
                "cancelled") echo "Cancelled" ;;
                "local_exists") echo "data/local directory already exists" ;;
                "creating_local") echo "Creating data/local..." ;;
                "created") echo "Created" ;;
                "creating_symlink") echo "Creating symlink to shared data..." ;;
                "complete") echo "Setup Complete!" ;;
                "structure") echo "Directory structure" ;;
                "usage") echo "Usage" ;;
                "usage_shared") echo "Save important data here (shared across worktrees)" ;;
                "usage_local") echo "Temporary files here (deleted with worktree)" ;;
                "remember") echo "Remember" ;;
                "use_safe_remove") echo "Use /worktree/safe-remove when deleting this worktree" ;;
            esac
            ;;
    esac
}

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  $(msg title)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Determine worktree directory
if [[ -n "${1:-}" ]]; then
    CURRENT_DIR="$(cd "$1" && pwd)"
else
    CURRENT_DIR="$(pwd)"
fi

cd "$CURRENT_DIR"

# Check if in a worktree
if ! git worktree list 2>/dev/null | grep -q "$CURRENT_DIR"; then
    error "$(msg not_worktree): $CURRENT_DIR
$(msg run_in_worktree)"
fi

info "$(msg worktree): $CURRENT_DIR"

# Find main repository
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
CONFIG_FILE="$MAIN_REPO/.claude/worktree-config.json"

info "$(msg main_repo): $MAIN_REPO"
echo ""

# Check configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "$(msg config_not_found): $CONFIG_FILE
$(msg run_init_first): ./scripts/init-data.sh"
fi

# Read configuration
if command -v jq &>/dev/null; then
    SHARED_DATA_PATH=$(jq -r '.shared_data_path' "$CONFIG_FILE")
    PATH_TYPE=$(jq -r '.path_type // "absolute"' "$CONFIG_FILE")
else
    SHARED_DATA_PATH=$(grep '"shared_data_path"' "$CONFIG_FILE" | cut -d'"' -f4)
    PATH_TYPE=$(grep '"path_type"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "absolute")
fi

# Resolve relative path
if [[ "$PATH_TYPE" == "relative" ]]; then
    SHARED_DATA_PATH="$MAIN_REPO/$SHARED_DATA_PATH"
fi

echo -e "${GREEN}$(msg config):${NC}"
cat "$CONFIG_FILE"
echo ""

# Check existing symlink
if [[ -L "data/shared" ]]; then
    warn "$(msg symlink_exists):"
    ls -la data/shared
    echo ""

    if [[ -t 0 ]]; then
        read -p "$(msg recreate): " recreate
        if [[ ! "$recreate" =~ ^[Yy]$ ]]; then
            echo "$(msg cancelled)"
            exit 0
        fi
        rm data/shared
    else
        warn "$(msg cancelled)"
        exit 0
    fi

# data/shared exists as a real directory.
# `ln -sf TARGET DIR` would create DIR/$(basename TARGET) *inside* it instead of
# replacing it, silently leaving the worktree unlinked from the shared data.
# Remove it when it holds nothing of value, otherwise stop and let the user decide.
elif [[ -d "data/shared" ]]; then
    # An earlier version of this script ran `ln -sf` against the real directory and
    # so left a stray link at data/shared/<basename> pointing at the shared data.
    # That is this bug's own debris, not user data: drop it so the worktree can be
    # repaired by re-running. Only links that resolve to SHARED_DATA_PATH qualify.
    for stray in data/shared/* data/shared/.[!.]*; do
        [[ -L "$stray" ]] || continue
        [[ "$(readlink "$stray")" == "$SHARED_DATA_PATH" ]] || continue
        rm -f "$stray"
        info "$(msg stray_link_removed): $stray"
    done

    # Anything else that is not bookkeeping counts as user data. `find` may fail on
    # an unreadable directory, and under `set -e` a bare assignment would abort with
    # no explanation, so handle that case explicitly.
    LEFTOVER=$(find data/shared -mindepth 1 \
                   ! -name '.gitkeep' ! -name '.DS_Store' ! -name '._*' \
                   ! -name 'Thumbs.db' -print -quit 2>/dev/null) \
        || error "$(msg dir_unreadable): $(pwd)/data/shared"

    if [[ -n "$LEFTOVER" ]]; then
        warn "$(msg dir_has_data): $(pwd)/data/shared"
        ls -la data/shared | head -20
        error "$(msg move_data_first)
    mv \"$(pwd)/data/shared/\"* \"$SHARED_DATA_PATH/\" && rmdir \"$(pwd)/data/shared\""
    fi

    rm -f data/shared/.gitkeep data/shared/.DS_Store data/shared/Thumbs.db
    rmdir data/shared || error "$(msg dir_remove_failed): $(pwd)/data/shared"
    warn "$(msg dir_replaced)"
fi

# Check existing local directory
if [[ -d "data/local" ]]; then
    warn "$(msg local_exists)"
else
    # Create data/local
    info "$(msg creating_local)"
    mkdir -p data/local/{cache,temp,debug}
    touch data/local/{cache,temp,debug}/.gitkeep

    success "$(msg created):"
    echo "   data/local/cache/"
    echo "   data/local/temp/"
    echo "   data/local/debug/"
fi

# Create symlink
info "$(msg creating_symlink)"
mkdir -p data
# -n: never dereference an existing symlink target, so a stale link is replaced
# rather than followed into the shared directory
ln -sfn "$SHARED_DATA_PATH" data/shared

success "$(msg created): data/shared -> $SHARED_DATA_PATH"
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  $(msg complete)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "$(msg structure):"
ls -la data/
echo ""
echo "$(msg usage):"
echo "  data/shared/ - $(msg usage_shared)"
echo "  data/local/  - $(msg usage_local)"
echo ""
echo -e "${YELLOW}$(msg remember):${NC}"
echo "  $(msg use_safe_remove)"
echo ""
