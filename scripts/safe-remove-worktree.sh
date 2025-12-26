#!/usr/bin/env bash

# Worktree Data Protection - Safe Worktree Removal
# Check for important files before removing worktree

set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Worktree Data Protection - Safe Remove${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get worktree to remove (current directory by default)
if [ $# -eq 0 ]; then
    WORKTREE_PATH=$(pwd)
else
    WORKTREE_PATH="$1"
fi

# Verify it's a worktree
if [ ! -d "$WORKTREE_PATH/.git" ] && [ ! -f "$WORKTREE_PATH/.git" ]; then
    echo -e "${RED}❌ Not a git worktree: $WORKTREE_PATH${NC}"
    exit 1
fi

cd "$WORKTREE_PATH"
WORKTREE_PATH=$(pwd)  # Get absolute path
WORKTREE_NAME=$(basename "$WORKTREE_PATH")

echo "Worktree to remove: $WORKTREE_PATH"
echo ""

# Find main repository
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
CONFIG_FILE="$MAIN_REPO/.claude/worktree-config.json"

# Read shared data path
if [ -f "$CONFIG_FILE" ]; then
    if command -v jq &> /dev/null; then
        SHARED_DATA_PATH=$(jq -r '.shared_data_path' "$CONFIG_FILE")
    else
        SHARED_DATA_PATH=$(grep '"shared_data_path"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
fi

# Check data/local for potentially important files
echo -e "${BLUE}Checking data/local for important files...${NC}"
echo ""

IMPORTANT_FILES=()
if [ -d "data/local" ]; then
    # Find large files (>10MB)
    while IFS= read -r -d '' file; do
        IMPORTANT_FILES+=("$file")
    done < <(find data/local -type f -size +10M -print0 2>/dev/null || true)

    # Find files with specific extensions (potentially important)
    IMPORTANT_EXTENSIONS=("*.json" "*.csv" "*.parquet" "*.pt" "*.pth" "*.h5" "*.hdf5")
    for ext in "${IMPORTANT_EXTENSIONS[@]}"; do
        while IFS= read -r -d '' file; do
            # Skip if already in list
            if [[ ! " ${IMPORTANT_FILES[@]} " =~ " ${file} " ]]; then
                IMPORTANT_FILES+=("$file")
            fi
        done < <(find data/local -type f -name "$ext" -print0 2>/dev/null || true)
    done
fi

if [ ${#IMPORTANT_FILES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found potentially important files in data/local:${NC}"
    echo ""
    for file in "${IMPORTANT_FILES[@]}"; do
        SIZE=$(du -h "$file" | cut -f1)
        echo "  - $file ($SIZE)"
    done
    echo ""
    echo -e "${YELLOW}These files will be DELETED when the worktree is removed.${NC}"
    echo ""
    echo "Options:"
    echo "  1. Move files to data/shared (preserve)"
    echo "  2. Continue with removal (delete files)"
    echo "  3. Cancel"
    echo ""
    read -p "Choice [1/2/3]: " choice

    case "$choice" in
        1)
            # Move files to shared
            if [ -z "${SHARED_DATA_PATH:-}" ]; then
                echo -e "${RED}❌ Shared data path not configured${NC}"
                exit 1
            fi

            echo ""
            echo -e "${BLUE}Moving files to shared data...${NC}"
            BACKUP_DIR="$SHARED_DATA_PATH/backup_from_$WORKTREE_NAME"
            mkdir -p "$BACKUP_DIR"

            for file in "${IMPORTANT_FILES[@]}"; do
                RELATIVE_PATH="${file#data/local/}"
                DEST_DIR="$BACKUP_DIR/$(dirname "$RELATIVE_PATH")"
                mkdir -p "$DEST_DIR"
                mv "$file" "$DEST_DIR/"
                echo -e "${GREEN}✅ Moved: $file${NC}"
            done

            echo ""
            echo -e "${GREEN}Files saved to: $BACKUP_DIR${NC}"
            echo ""
            ;;
        2)
            echo ""
            echo -e "${YELLOW}Proceeding with deletion...${NC}"
            ;;
        3)
            echo "Removal cancelled."
            exit 0
            ;;
        *)
            echo "Invalid choice. Removal cancelled."
            exit 1
            ;;
    esac
else
    echo -e "${GREEN}✅ No potentially important files found in data/local${NC}"
    echo ""
fi

# Final confirmation
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  FINAL CONFIRMATION${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Worktree to remove: $WORKTREE_PATH"
echo ""
echo -e "${GREEN}Will be preserved:${NC}"
echo "  - data/shared (symlink will be deleted, data preserved)"
if [ -d "$SHARED_DATA_PATH" ]; then
    echo "    → $SHARED_DATA_PATH"
fi
echo ""
echo -e "${RED}Will be DELETED:${NC}"
echo "  - data/local (all temporary files)"
echo "  - All uncommitted code changes"
echo "  - Entire worktree directory"
echo ""

read -p "Are you sure you want to remove this worktree? [y/N]: " final_confirm
if [[ ! "$final_confirm" =~ ^[Yy]$ ]]; then
    echo "Removal cancelled."
    exit 0
fi

# Remove worktree
echo ""
echo -e "${BLUE}Removing worktree...${NC}"

cd "$MAIN_REPO"
git worktree remove "$WORKTREE_PATH"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Worktree Removed Successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Removed: $WORKTREE_PATH"
if [ -d "$SHARED_DATA_PATH" ]; then
    echo "Shared data preserved: $SHARED_DATA_PATH"
fi
echo ""
