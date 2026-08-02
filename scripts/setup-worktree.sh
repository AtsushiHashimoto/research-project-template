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
                "stray_link_removed") echo "旧バージョンが作った不要なリンクを削除しました" ;;
                "gitkeep_tracked") echo "data/shared/.gitkeep が git 追跡下にあります。メインリポジトリで次を実行して移行してください:" ;;
                "is_shared_store") echo "data/shared は共有データストアそのものです。ここでリンクを張ると共有データを失います" ;;
                "gitkeep_worktree_note") echo "移行後、この worktree で git merge が .gitkeep で止まります。次も実行してください:" ;;
                "mv_n_note") echo "（-n は同名を上書きしません / 2行目は隠しファイル）" ;;
                "move_conflict_note") echo "同名ファイルがある場合は -n により移動されません。残ったものは中身を確認してから手動で統合してください。" ;;
                "dir_has_data") echo "data/shared がシンボリックリンクではなく実体のあるディレクトリで、中にデータがあります" ;;
                "move_data_first") echo "そのままではリンクできません。次のコマンドで中身をメインリポジトリへ移してから再実行してください:" ;;
                "dir_replaced") echo "空の data/shared ディレクトリを削除しました（シンボリックリンクに置き換えます）" ;;
                "dir_remove_failed") echo "data/shared ディレクトリを削除できませんでした" ;;
                "dir_unreadable") echo "data/shared を読み取れません（権限を確認してください）" ;;
                "not_dir_or_link") echo "data/shared がファイルとして存在します。リンクを張ると失われるため停止します" ;;
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
                "use_safe_remove") echo "Worktree削除時は /worktree-safe-remove を使用してください" ;;
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
                "stray_link_removed") echo "已删除旧版本创建的多余链接" ;;
                "gitkeep_tracked") echo "data/shared/.gitkeep 仍被 git 跟踪。请在主仓库中执行以下命令完成迁移:" ;;
                "is_shared_store") echo "data/shared 就是共享数据存储本身。在此创建链接会丢失共享数据" ;;
                "gitkeep_worktree_note") echo "迁移后该 worktree 的 git merge 会因 .gitkeep 失败。请同时执行:" ;;
                "mv_n_note") echo "（-n 不覆盖同名文件 / 第二行为隐藏文件）" ;;
                "move_conflict_note") echo "如有同名文件，-n 会跳过移动。请检查剩余文件后手动合并。" ;;
                "dir_has_data") echo "data/shared 是真实目录（非符号链接）且其中包含数据" ;;
                "move_data_first") echo "当前状态无法创建链接。请用以下命令将内容移动到主仓库后重新执行:" ;;
                "dir_replaced") echo "已删除空的 data/shared 目录（将替换为符号链接）" ;;
                "dir_remove_failed") echo "无法删除 data/shared 目录" ;;
                "dir_unreadable") echo "无法读取 data/shared（请检查权限）" ;;
                "not_dir_or_link") echo "data/shared 是一个文件。创建链接会丢失它，因此停止" ;;
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
                "use_safe_remove") echo "删除 Worktree 时请使用 /worktree-safe-remove" ;;
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
                "stray_link_removed") echo "Removed a stray link created by an older version" ;;
                "gitkeep_tracked") echo "data/shared/.gitkeep is still tracked by git. Run these in the main repository to migrate:" ;;
                "is_shared_store") echo "data/shared IS the shared data store. Linking here would destroy the shared data" ;;
                "gitkeep_worktree_note") echo "After migrating, git merge in this worktree will fail on .gitkeep. Also run:" ;;
                "mv_n_note") echo "(-n does not overwrite; the second line moves hidden files)" ;;
                "move_conflict_note") echo "Files with the same name are skipped by -n. Inspect what remains and merge manually." ;;
                "dir_has_data") echo "data/shared is a real directory (not a symlink) and contains data" ;;
                "move_data_first") echo "Cannot link as-is. Move its contents to the main repository and re-run:" ;;
                "dir_replaced") echo "Removed the empty data/shared directory (replacing it with a symlink)" ;;
                "dir_remove_failed") echo "Failed to remove the data/shared directory" ;;
                "dir_unreadable") echo "Cannot read data/shared (check permissions)" ;;
                "not_dir_or_link") echo "data/shared exists as a file. Linking would destroy it, so stopping" ;;
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
                "use_safe_remove") echo "Use /worktree-safe-remove when deleting this worktree" ;;
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
        read -r -p "$(msg recreate): " recreate
        if [[ ! "$recreate" =~ ^[Yy]$ ]]; then
            msg cancelled
            exit 0
        fi
        rm data/shared
    else
        warn "$(msg cancelled)"
        exit 0
    fi
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

# --- data/shared が symlink 以外で存在する場合のガード（#133） ---
#
# 以前は `-L`（symlink か）しか見ておらず、実ディレクトリのとき ln -sf が
# **リンクをその中に**作っていた（data/shared/<basename>）。共有が成立せず、
# worktree 削除でデータが失われる silent-wrong だった。
mkdir -p data

# ★ F-1: data/shared が**共有ストアそのもの**なら絶対に触らない。
#   メインリポジトリで実行された場合（git worktree list の第1行なので worktree 判定を通る）、
#   ここを消すと共有データを削除して自己参照 symlink を張り、
#   以後 "Too many levels of symbolic links" で復旧不能になる。
#   これは本 issue が塞ごうとしている silent-wrong と同型なので、最優先で止める
# ★ F-6: `-d` で門番してはいけない。.gitkeep を追跡から外した結果、
#   **clone 直後は data/shared が存在しないのが既定**になった。
#   存在しない場合も自己参照 symlink を張れてしまうので、パス比較は
#   「実在するか」に関係なく行う（親ディレクトリまで解決して比較する）
_resolve_path() {
    local q="${1%/}"; [ -n "$q" ] || q="/"
    if [ -d "$q" ]; then
        (cd "$q" && pwd -P)
    else
        local d; d=$(cd "$(dirname "$q")" 2>/dev/null && pwd -P) || return 1
        printf '%s\n' "${d%/}/$(basename "$q")"
    fi
}

if [ ! -L "data/shared" ]; then
    _here=$(_resolve_path "$(pwd -P)/data/shared" || echo "")
    _store=$(_resolve_path "$SHARED_DATA_PATH" || echo "")
    if [ -n "$_here" ] && [ "$_here" = "$_store" ]; then
        echo -e "${RED}[ERROR]${NC} $(msg is_shared_store)" >&2
        echo "  data/shared = $_here" >&2
        echo "  $(msg run_in_worktree)" >&2
        exit 1
    fi
fi

if [ -e "data/shared" ] && [ ! -L "data/shared" ]; then
    if [ ! -d "data/shared" ]; then
        # 実ファイル。ln -sf は黙って上書きするので必ず止める
        error_msg="$(msg not_dir_or_link)"
        echo -e "${RED}[ERROR]${NC} ${error_msg}: data/shared" >&2
        exit 1
    fi

    if [ ! -r "data/shared" ]; then
        echo -e "${RED}[ERROR]${NC} $(msg dir_unreadable)" >&2
        exit 1
    fi

    # 旧バージョンが中に作った stray link を先に片付ける。
    # 名前では判定しない（旧バグが作る名前は basename "$SHARED_DATA_PATH"）
    for entry in data/shared/* data/shared/.*; do
        [ -L "$entry" ] || continue
        target=$(readlink "$entry")
        if [ "$target" = "$SHARED_DATA_PATH" ]; then
            rm -f "$entry"
            warn "$(msg stray_link_removed): $entry"
        fi
    done

    # 残りが空かどうかで分岐する。
    # ★ .gitkeep はプレースホルダでありユーザーデータではない。
    #   旧ポリシー（data/shared/** + !data/shared/.gitkeep）の派生プロジェクトでは
    #   worktree 展開時に必ず .gitkeep が具現化するため、これをデータとして扱うと
    #   **sync した瞬間に全 worktree 作成が止まる**（実測）
    # find が失敗する（辿れない・未対応の find 等）場合に無言終了しないこと。
    # set -e 下では代入の失敗でそのまま落ち、理由が一切出なくなる
    if ! remaining=$(find data/shared -mindepth 1 \
        -not -name '.DS_Store' -not -name '.gitkeep' -print -quit 2>/dev/null); then
        echo -e "${RED}[ERROR]${NC} $(msg dir_unreadable)" >&2
        exit 1
    fi
    if [ -n "$remaining" ]; then
        echo -e "${RED}[ERROR]${NC} $(msg dir_has_data)" >&2
        echo "" >&2
        echo "  $(msg move_data_first)" >&2
        echo "    mkdir -p \"$SHARED_DATA_PATH\"" >&2
        echo "    mv -n data/shared/* \"$SHARED_DATA_PATH\"/" >&2
        echo "    mv -n data/shared/.[!.]* \"$SHARED_DATA_PATH\"/ 2>/dev/null || true" >&2
        echo "    $(msg mv_n_note)" >&2
        echo "    rmdir data/shared" >&2
        echo "" >&2
        echo "  $(msg move_conflict_note)" >&2
        echo "" >&2
        exit 1
    fi

    # 旧ポリシーからの移行案内。.gitkeep が追跡下にあると、ディレクトリを消した時点で
    # ` D data/shared/.gitkeep` が残り続ける。黙って汚さず、直し方を示す
    if git ls-files --error-unmatch data/shared/.gitkeep >/dev/null 2>&1; then
        warn "$(msg gitkeep_tracked)"
        echo "    cd \"$MAIN_REPO\" && git rm --cached data/shared/.gitkeep" >&2
        echo "    bash scripts/ensure-gitignore.sh" >&2
        echo "  $(msg gitkeep_worktree_note)" >&2
        echo "    git rm --cached data/shared/.gitkeep   # この worktree でも実行する" >&2
    fi

    if ! rm -rf data/shared; then
        echo -e "${RED}[ERROR]${NC} $(msg dir_remove_failed)" >&2
        exit 1
    fi
    info "$(msg dir_replaced)"
fi

# Create symlink
info "$(msg creating_symlink)"
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
