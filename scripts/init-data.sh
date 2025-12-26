#!/usr/bin/env bash
# Initialize data directory configuration
# Usage:
#   ./scripts/init-data.sh [PROJECT_ROOT]
#   SHARED_DATA_PATH=/path/to/data ./scripts/init-data.sh  # Non-interactive

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect language from environment
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
                "title") echo "データディレクトリの初期化" ;;
                "project_root") echo "プロジェクトルート" ;;
                "config_exists") echo "設定ファイルが既に存在します" ;;
                "reconfigure") echo "再設定しますか？ [y/N]" ;;
                "keeping") echo "既存の設定を保持します" ;;
                "select_location") echo "共有データの保存場所を選択してください" ;;
                "option1") echo "デフォルト（リポジトリ内）" ;;
                "option1_desc") echo "シンプル、同じドライブ" ;;
                "option2") echo "カスタムパス（外部ドライブ、NFSなど）" ;;
                "option2_desc") echo "大容量ストレージ、ネットワークドライブ" ;;
                "choice") echo "選択 [1/2]" ;;
                "enter_path") echo "カスタムパスを入力（絶対パス）" ;;
                "examples") echo "例" ;;
                "path_prompt") echo "パス" ;;
                "path_error") echo "パスは絶対パス（/で始まる）である必要があります" ;;
                "invalid_choice") echo "無効な選択です" ;;
                "creating_dirs") echo "データディレクトリを作成中..." ;;
                "created") echo "作成完了" ;;
                "complete") echo "初期化完了！" ;;
                "shared_path") echo "共有データパス" ;;
                "usage_title") echo "使い方" ;;
                "usage_shared") echo "重要なデータはこちらに保存" ;;
                "usage_local") echo "一時ファイルはこちら（Worktree削除時に消えます）" ;;
                "using_env") echo "環境変数を使用" ;;
                "using_default") echo "非インタラクティブモード：デフォルト設定を使用" ;;
            esac
            ;;
        zh)
            case "$key" in
                "title") echo "数据目录初始化" ;;
                "project_root") echo "项目根目录" ;;
                "config_exists") echo "配置文件已存在" ;;
                "reconfigure") echo "是否重新配置？ [y/N]" ;;
                "keeping") echo "保留现有配置" ;;
                "select_location") echo "请选择共享数据存储位置" ;;
                "option1") echo "默认（仓库内）" ;;
                "option1_desc") echo "简单设置，同一驱动器" ;;
                "option2") echo "自定义路径（外部驱动器、NFS等）" ;;
                "option2_desc") echo "大容量存储、网络驱动器" ;;
                "choice") echo "选择 [1/2]" ;;
                "enter_path") echo "输入自定义路径（绝对路径）" ;;
                "examples") echo "示例" ;;
                "path_prompt") echo "路径" ;;
                "path_error") echo "路径必须是绝对路径（以/开头）" ;;
                "invalid_choice") echo "无效的选择" ;;
                "creating_dirs") echo "正在创建数据目录..." ;;
                "created") echo "创建完成" ;;
                "complete") echo "初始化完成！" ;;
                "shared_path") echo "共享数据路径" ;;
                "usage_title") echo "使用方法" ;;
                "usage_shared") echo "重要数据保存在这里" ;;
                "usage_local") echo "临时文件放这里（删除Worktree时会被删除）" ;;
                "using_env") echo "使用环境变量" ;;
                "using_default") echo "非交互模式：使用默认设置" ;;
            esac
            ;;
        *)  # English (default)
            case "$key" in
                "title") echo "Data Directory Initialization" ;;
                "project_root") echo "Project root" ;;
                "config_exists") echo "Configuration file already exists" ;;
                "reconfigure") echo "Reconfigure? [y/N]" ;;
                "keeping") echo "Keeping existing configuration" ;;
                "select_location") echo "Select shared data storage location" ;;
                "option1") echo "Default (inside repository)" ;;
                "option1_desc") echo "Simple setup, same drive" ;;
                "option2") echo "Custom path (external drive, NFS, etc.)" ;;
                "option2_desc") echo "Large storage, network drives" ;;
                "choice") echo "Choice [1/2]" ;;
                "enter_path") echo "Enter custom path (absolute)" ;;
                "examples") echo "Examples" ;;
                "path_prompt") echo "Path" ;;
                "path_error") echo "Path must be absolute (start with /)" ;;
                "invalid_choice") echo "Invalid choice" ;;
                "creating_dirs") echo "Creating data directories..." ;;
                "created") echo "Created" ;;
                "complete") echo "Initialization Complete!" ;;
                "shared_path") echo "Shared data path" ;;
                "usage_title") echo "Usage" ;;
                "usage_shared") echo "Save important data here" ;;
                "usage_local") echo "Temporary files here (deleted with worktree)" ;;
                "using_env") echo "Using environment variable" ;;
                "using_default") echo "Non-interactive mode: using default configuration" ;;
            esac
            ;;
    esac
}

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Determine project root
if [[ -n "${1:-}" ]]; then
    PROJECT_ROOT="$1"
elif git rev-parse --show-toplevel &>/dev/null; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    PROJECT_ROOT="$(pwd)"
fi

cd "$PROJECT_ROOT"
REPO_NAME=$(basename "$PROJECT_ROOT")

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  $(msg title)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
info "$(msg project_root): $PROJECT_ROOT"
echo ""

CONFIG_FILE=".claude/worktree-config.json"

# Check if already configured
if [[ -f "$CONFIG_FILE" ]]; then
    warn "$(msg config_exists):"
    cat "$CONFIG_FILE"
    echo ""

    if [[ -t 0 ]]; then
        read -p "$(msg reconfigure): " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            echo "$(msg keeping)"
            exit 0
        fi
    else
        warn "$(msg keeping)"
        exit 0
    fi
fi

# Non-interactive mode (environment variables)
if [[ -n "${SHARED_DATA_PATH:-}" ]]; then
    info "$(msg using_env): SHARED_DATA_PATH=$SHARED_DATA_PATH"

    if [[ "$SHARED_DATA_PATH" = /* ]]; then
        PATH_TYPE="absolute"
        SHARED_DATA_PATH_ABSOLUTE="$SHARED_DATA_PATH"
    else
        PATH_TYPE="relative"
        SHARED_DATA_PATH_ABSOLUTE="$PROJECT_ROOT/$SHARED_DATA_PATH"
    fi

    STORAGE_TYPE="${STORAGE_TYPE:-custom}"
    NOTE="${DATA_NOTE:-Configured via environment variable}"

# Interactive mode
elif [[ -t 0 ]]; then
    echo -e "${GREEN}$(msg select_location):${NC}"
    echo ""
    echo "  1. $(msg option1)"
    echo "     Path: data/shared"
    echo "     $(msg option1_desc)"
    echo ""
    echo "  2. $(msg option2)"
    echo "     $(msg option2_desc)"
    echo ""

    read -p "$(msg choice): " choice

    case "$choice" in
        1)
            SHARED_DATA_PATH="data/shared"
            SHARED_DATA_PATH_ABSOLUTE="$PROJECT_ROOT/data/shared"
            PATH_TYPE="relative"
            STORAGE_TYPE="local"
            NOTE="Default configuration"
            ;;
        2)
            echo ""
            echo "$(msg enter_path):"
            echo "$(msg examples):"
            echo "  /mnt/research-data/$REPO_NAME/shared"
            echo "  /Volumes/ExternalSSD/$REPO_NAME/shared"
            echo ""
            read -p "$(msg path_prompt): " CUSTOM_PATH

            CUSTOM_PATH="${CUSTOM_PATH/#\~/$HOME}"

            if [[ ! "$CUSTOM_PATH" = /* ]]; then
                error "$(msg path_error)"
            fi

            SHARED_DATA_PATH="$CUSTOM_PATH"
            SHARED_DATA_PATH_ABSOLUTE="$CUSTOM_PATH"
            PATH_TYPE="absolute"
            STORAGE_TYPE="external"
            NOTE="Custom storage configuration"
            ;;
        *)
            error "$(msg invalid_choice)"
            ;;
    esac

# Default (non-interactive, no env vars)
else
    info "$(msg using_default)"
    SHARED_DATA_PATH="data/shared"
    SHARED_DATA_PATH_ABSOLUTE="$PROJECT_ROOT/data/shared"
    PATH_TYPE="relative"
    STORAGE_TYPE="local"
    NOTE="Default configuration (auto-initialized)"
fi

# Create directories
info "$(msg creating_dirs)"
mkdir -p "$SHARED_DATA_PATH_ABSOLUTE"/{datasets,results,models}
touch "$SHARED_DATA_PATH_ABSOLUTE"/{datasets,results,models}/.gitkeep

success "$(msg created): $SHARED_DATA_PATH_ABSOLUTE/"
echo "         ├── datasets/"
echo "         ├── results/"
echo "         └── models/"

# Create configuration file
mkdir -p .claude
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$CONFIG_FILE" <<EOF
{
  "version": "1.1",
  "shared_data_path": "$SHARED_DATA_PATH",
  "path_type": "$PATH_TYPE",
  "created_at": "$TIMESTAMP",
  "updated_at": "$TIMESTAMP",
  "storage_type": "$STORAGE_TYPE",
  "note": "$NOTE"
}
EOF

success "$(msg created): $CONFIG_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  $(msg complete)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "$(msg shared_path): $SHARED_DATA_PATH"
echo ""
echo "$(msg usage_title):"
echo "  data/shared/ - $(msg usage_shared)"
echo "  data/local/  - $(msg usage_local)"
echo ""
